import XCTest

@testable import OverheardKit

final class AudioAndCalendarTests: XCTestCase {
    func testBirdNETWeek() {
        let cal = Calendar(identifier: .gregorian)
        func week(_ month: Int, _ day: Int) -> Int {
            SpeciesFilter.birdNETWeek(for: cal.date(from: DateComponents(year: 2026, month: month, day: day))!)
        }
        XCTAssertEqual(week(1, 1), 1)
        XCTAssertEqual(week(1, 8), 2)
        XCTAssertEqual(week(1, 31), 4)
        XCTAssertEqual(week(10, 18), 39)
        XCTAssertEqual(week(12, 31), 48)
    }

    func testClipsSplitsAndPadsTail() {
        let n = BirdClassifier.clipLength
        XCTAssertEqual(AudioDecoding.clips([Float](repeating: 1, count: n * 2)).count, 2)
        // Short tail (< half a clip) is dropped…
        XCTAssertEqual(AudioDecoding.clips([Float](repeating: 1, count: n * 2 + n / 4)).count, 2)
        // …a long one is padded.
        let padded = AudioDecoding.clips([Float](repeating: 1, count: n * 2 + n * 3 / 4))
        XCTAssertEqual(padded.count, 3)
        XCTAssertEqual(padded[2].count, n)
        XCTAssertEqual(padded[2].last, 0)
        // A recording shorter than one clip still yields one clip.
        XCTAssertEqual(AudioDecoding.clips([Float](repeating: 1, count: n / 3)).count, 1)
        // Overlapping hop: 6 s at 1 s hop → clips starting at 0,1,2,3 s, plus one padded tail.
        XCTAssertEqual(AudioDecoding.clips([Float](repeating: 1, count: n * 2), hop: n / 3).count, 5)
    }
}

final class SpeciesFilterTests: XCTestCase {
    // Labels 0–2 are birds, 3 is "Engine". Here, label 2 is unlikely (below the 0.03 cutoff).
    let filter = SpeciesFilter(nonBird: [3])
    let local = LocalSpecies(
        place: Place(latitude: 40.78, longitude: -73.97, week: 39), occurrence: [0.9, 0.05, 0.01, 0.5])

    func testNonBirdsAreNeverReported() {
        for rules in [DetectionRules(useLocationFilter: true), DetectionRules(useLocationFilter: false)] {
            XCTAssertFalse(filter.isReportable(3, confidence: 0.99, local: local, rules: rules))
            XCTAssertFalse(filter.isReportable(3, confidence: 0.99, local: nil, rules: rules))
        }
    }

    func testConfidenceThreshold() {
        let rules = DetectionRules(minConfidence: 0.5)
        XCTAssertTrue(filter.isReportable(0, confidence: 0.5, local: local, rules: rules))
        XCTAssertFalse(filter.isReportable(0, confidence: 0.49, local: local, rules: rules))
    }

    func testLocationFilter() {
        XCTAssertTrue(filter.isReportable(1, confidence: 0.9, local: local, rules: DetectionRules()))
        XCTAssertFalse(filter.isReportable(2, confidence: 0.9, local: local, rules: DetectionRules()))
        XCTAssertTrue(
            filter.isReportable(2, confidence: 0.9, local: local, rules: DetectionRules(useLocationFilter: false)))
    }

    func testUnknownLocationDoesNotFilterByPlace() {
        XCTAssertTrue(filter.isReportable(2, confidence: 0.9, local: nil, rules: DetectionRules()))
    }
}

final class PlaceTests: XCTestCase {
    let centralPark = Place(latitude: 40.7812, longitude: -73.9665, week: 39)

    func testDistance() {
        let prospectPark = Place(latitude: 40.6602, longitude: -73.9690, week: 39)
        XCTAssertEqual(centralPark.distance(to: prospectPark), 13.4, accuracy: 0.3)
        XCTAssertEqual(centralPark.distance(to: centralPark), 0, accuracy: 1e-9)
    }

    func testLocalSpeciesRecomputeRules() {
        let local = LocalSpecies(place: centralPark, occurrence: [])
        let nearby = Place(latitude: 40.80, longitude: -73.95, week: 39)  // ~2.5 km
        let brooklyn = Place(latitude: 40.66, longitude: -73.97, week: 39)  // ~13 km
        let nextWeek = Place(latitude: centralPark.latitude, longitude: centralPark.longitude, week: 40)
        XCTAssertTrue(local.covers(nearby))
        XCTAssertFalse(local.covers(brooklyn))
        XCTAssertFalse(local.covers(nextWeek))
    }
}

final class DetectionSessionTests: XCTestCase {
    let cardinal = Species(code: "norcar", commonName: "Northern Cardinal", scientificName: "C. c.", isBird: true)
    let jay = Species(code: "blujay", commonName: "Blue Jay", scientificName: "C. c.", isBird: true)
    let t0 = Date(timeIntervalSince1970: 0)

    func testTalliesCallsAndConfidence() {
        var session = DetectionSession()
        session.record([BirdScore(index: 1, species: cardinal, confidence: 0.6)], at: t0)
        session.record(
            [
                BirdScore(index: 1, species: cardinal, confidence: 0.9),
                BirdScore(index: 2, species: jay, confidence: 0.7),
            ], at: t0.addingTimeInterval(3))
        let cardinalTally = session.byCode["norcar"]!
        XCTAssertEqual(cardinalTally.calls, 2)
        XCTAssertEqual(cardinalTally.bestConfidence, 0.9)
        XCTAssertEqual(cardinalTally.firstHeard, t0)
        XCTAssertEqual(cardinalTally.lastHeard, t0.addingTimeInterval(3))
        XCTAssertEqual(session.birds.map(\.id), ["norcar", "blujay"])  // most calls first
    }

    func testLumpedLabelsCountOncePerClip() {
        var session = DetectionSession()
        // Two BirdNET labels that eBird now treats as one species share a code.
        session.record(
            [
                BirdScore(index: 7, species: cardinal, confidence: 0.6),
                BirdScore(index: 8, species: cardinal, confidence: 0.8),
            ], at: t0)
        XCTAssertEqual(session.byCode["norcar"]?.calls, 1)
        XCTAssertEqual(session.byCode["norcar"]?.bestConfidence, 0.8)
    }

    func testOrderingTiesBreakByFirstHeard() {
        var session = DetectionSession()
        session.record([BirdScore(index: 2, species: jay, confidence: 0.7)], at: t0)
        session.record([BirdScore(index: 1, species: cardinal, confidence: 0.7)], at: t0.addingTimeInterval(3))
        XCTAssertEqual(session.birds.map(\.id), ["blujay", "norcar"])
    }
}

final class SpeciesCatalogTests: XCTestCase {
    func testNonBirdsComeFromCatalog() {
        let catalog = SpeciesCatalog(species: [
            Species(
                code: "norcar", commonName: "Northern Cardinal", scientificName: "Cardinalis cardinalis", isBird: true),
            Species(code: "birdnet:Siren", commonName: "Siren", scientificName: "Siren", isBird: false),
        ])
        XCTAssertEqual(catalog.nonBird, [1])
        XCTAssertEqual(catalog.indices(scientificName: "Cardinalis cardinalis"), [0])
    }
}

final class SlidingWindowTests: XCTestCase {
    func testEmitsOverlappingClipsAcrossChunkedInput() {
        var window = SlidingWindow(length: 6, hop: 2)
        // Feed 0..<11 in uneven chunks, like mic buffers.
        var clips: [[Float]] = []
        for chunk in [0..<3, 3..<4, 4..<9, 9..<11] {
            clips += window.append(chunk.map(Float.init))
        }
        XCTAssertEqual(clips, [[0, 1, 2, 3, 4, 5], [2, 3, 4, 5, 6, 7], [4, 5, 6, 7, 8, 9]])
    }

    func testDefaultIsThreeSecondClipsEverySecond() {
        var window = SlidingWindow()
        let second = [Float](repeating: 0, count: SlidingWindow.defaultHop)
        XCTAssertEqual(window.append(second).count, 0)
        XCTAssertEqual(window.append(second).count, 0)
        XCTAssertEqual(window.append(second).count, 1)  // first clip after 3 s…
        XCTAssertEqual(window.append(second).count, 1)  // …then one more every second
        XCTAssertEqual(window.append(second).first?.count, BirdClassifier.clipLength)
    }

    func testResetDropsBufferedAudio() {
        var window = SlidingWindow(length: 4, hop: 4)
        _ = window.append([1, 2, 3])
        window.reset()
        XCTAssertEqual(window.append([4, 5, 6, 7]), [[4, 5, 6, 7]])
    }
}

final class CallMergingTests: XCTestCase {
    let wren = Species(code: "carwre", commonName: "Carolina Wren", scientificName: "T. l.", isBird: true)
    let t0 = Date(timeIntervalSince1970: 0)

    /// Records a detection of the wren at each of `seconds` (clip end times, 1 s apart when back to back).
    func calls(detectedAt seconds: [Double]) -> Int {
        var session = DetectionSession()
        for s in seconds {
            session.record([BirdScore(index: 0, species: wren, confidence: 0.8)], at: t0.addingTimeInterval(s))
        }
        return session.byCode["carwre"]?.calls ?? 0
    }

    func testOneSongAcrossOverlappingClipsIsOneCall() {
        XCTAssertEqual(calls(detectedAt: [3, 4, 5]), 1)
    }

    func testOneMissedClipStaysTheSameCall() {
        XCTAssertEqual(calls(detectedAt: [3, 4, 6, 7]), 1)
    }

    func testSilenceStartsANewCall() {
        // Two missed clips (3 s gap) → a second song.
        XCTAssertEqual(calls(detectedAt: [3, 4, 7]), 2)
        XCTAssertEqual(calls(detectedAt: [3, 4, 5, 20, 21, 40]), 3)
    }

    func testLastHeardTracksLatestClip() {
        var session = DetectionSession()
        for s in [3.0, 4, 5] {
            session.record([BirdScore(index: 0, species: wren, confidence: 0.8)], at: t0.addingTimeInterval(s))
        }
        XCTAssertEqual(session.byCode["carwre"]?.firstHeard, t0.addingTimeInterval(3))
        XCTAssertEqual(session.byCode["carwre"]?.lastHeard, t0.addingTimeInterval(5))
    }
}
