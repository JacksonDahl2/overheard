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
    // Label occurrences here: 0 common, 1 uncommon, 2 unusual, 3 very unlikely; label 4 is "Engine".
    let filter = SpeciesFilter(nonBird: [4])
    let local = LocalSpecies(
        place: Place(latitude: 40.78, longitude: -73.97, week: 39), occurrence: [0.9, 0.05, 0.015, 0.005, 0.5])

    func required(_ index: Int, _ confidence: Float, rules: DetectionRules = DetectionRules()) -> Float? {
        filter.assess(index, confidence: confidence, local: local, rules: rules)?.requiredConfidence
    }

    func testNonBirdsAreNeverReported() {
        for rules in [DetectionRules(useLocationFilter: true), DetectionRules(useLocationFilter: false)] {
            XCTAssertNil(filter.assess(4, confidence: 0.99, local: local, rules: rules))
            XCTAssertNil(filter.assess(4, confidence: 0.99, local: nil, rules: rules))
        }
    }

    func testBarRisesAsSpeciesGetRarer() {
        XCTAssertEqual(required(0, 0.5), 0.5)  // common: base threshold
        XCTAssertNil(required(1, 0.65))  // uncommon needs 0.70
        XCTAssertEqual(required(1, 0.7)!, 0.7, accuracy: 1e-6)
        XCTAssertNil(required(2, 0.89))  // unusual needs 0.90
        XCTAssertEqual(required(2, 0.92)!, 0.9, accuracy: 1e-6)
        XCTAssertNil(required(3, 0.99))  // very unlikely: hidden
    }

    func testCommonnessIsReported() {
        let rules = DetectionRules()
        XCTAssertEqual(filter.assess(0, confidence: 0.9, local: local, rules: rules)?.commonness, .common)
        XCTAssertEqual(filter.assess(1, confidence: 0.9, local: local, rules: rules)?.commonness, .uncommon)
        XCTAssertEqual(filter.assess(2, confidence: 0.9, local: local, rules: rules)?.commonness, .unusual)
    }

    func testBaseThresholdShiftsEveryTier() {
        let strict = DetectionRules(minConfidence: 0.55)
        XCTAssertNil(required(0, 0.52, rules: strict))
        XCTAssertEqual(required(1, 0.8, rules: strict)!, 0.75, accuracy: 1e-6)
        XCTAssertNil(required(2, 0.9, rules: strict))  // unusual now needs 0.95
        // 0.6 + 0.40 would be 1.0: capped so a rare bird is still reachable.
        XCTAssertEqual(
            required(2, 0.97, rules: DetectionRules(minConfidence: 0.6)), SpeciesFilter.maxRequiredConfidence)
    }

    func testFilterOffJudgesByBaseButKeepsCommonness() {
        let off = DetectionRules(useLocationFilter: false)
        let veryUnlikely = filter.assess(3, confidence: 0.6, local: local, rules: off)
        XCTAssertEqual(veryUnlikely?.requiredConfidence, 0.5)
        XCTAssertEqual(veryUnlikely?.commonness, .unusual)
    }

    func testUnknownLocationUsesBaseThreshold() {
        let verdict = filter.assess(3, confidence: 0.6, local: nil, rules: DetectionRules())
        XCTAssertEqual(verdict?.requiredConfidence, 0.5)
        XCTAssertNil(verdict?.commonness)
        XCTAssertNil(filter.assess(3, confidence: 0.4, local: nil, rules: DetectionRules()))
    }

    func testHardCutoffPresetMatchesTheOldBehavior() {
        let old = DetectionRules(bar: .hardCutoff)
        XCTAssertEqual(required(1, 0.5, rules: old), 0.5)  // ≥ 3%: base threshold
        XCTAssertNil(required(2, 0.99, rules: old))  // < 3%: hidden however confident
    }
}

final class ConfidenceBarTests: XCTestCase {
    func testTiersAreSortedAndBoundariesInclusive() {
        let bar = ConfidenceBar(tiers: [
            .init(minOccurrence: 0.01, extraConfidence: 0.3, commonness: .unusual),
            .init(minOccurrence: 0.10, extraConfidence: 0, commonness: .common),
        ])
        XCTAssertEqual(bar.tiers.map(\.commonness), [.common, .unusual])
        XCTAssertEqual(bar.tier(forOccurrence: 0.10)?.commonness, .common)
        XCTAssertEqual(bar.tier(forOccurrence: 0.0999)?.commonness, .unusual)
        XCTAssertEqual(bar.tier(forOccurrence: 0.01)?.commonness, .unusual)
        XCTAssertNil(bar.tier(forOccurrence: 0.0099))
    }

    func testCommonnessOrdersFromCommonToUnusual() {
        XCTAssertLessThan(Commonness.common, .uncommon)
        XCTAssertLessThan(Commonness.uncommon, .unusual)
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
        var session = DetectionSession(confirmation: .none)
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
        var session = DetectionSession(confirmation: .none)
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
        var session = DetectionSession(confirmation: .none)
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

final class ConfirmationTests: XCTestCase {
    let warbler = Species(
        code: "btbwar", commonName: "Black-throated Blue Warbler", scientificName: "S. c.", isBird: true)
    let t0 = Date(timeIntervalSince1970: 0)

    func record(_ session: inout DetectionSession, _ confidence: Float?, at second: Double) {
        let scores = confidence.map { [BirdScore(index: 0, species: warbler, confidence: $0)] } ?? []
        session.record(scores, at: t0.addingTimeInterval(second))
    }

    func testSingleWeakClipIsOnlyPending() {
        var session = DetectionSession()
        record(&session, 0.6, at: 3)
        XCTAssertNil(session.byCode["btbwar"])
        XCTAssertEqual(session.pending.map(\.id), ["btbwar"])
        XCTAssertEqual(session.pending.first?.clips, 1)
    }

    func testUnconfirmedCallFadesAfterTheGap() {
        var session = DetectionSession()
        record(&session, 0.6, at: 3)
        for s in 4...6 { record(&session, nil, at: Double(s)) }  // quiet clips
        XCTAssertTrue(session.pending.isEmpty)
        XCTAssertNil(session.byCode["btbwar"])
    }

    func testTwoClipsConfirmAndCountFromTheFirst() {
        var session = DetectionSession()
        record(&session, 0.6, at: 3)
        record(&session, 0.55, at: 4)
        let bird = session.byCode["btbwar"]
        XCTAssertEqual(bird?.calls, 1)
        XCTAssertEqual(bird?.firstHeard, t0.addingTimeInterval(3))  // the sketch started at the first clip
        XCTAssertEqual(bird?.bestConfidence, 0.6)
        XCTAssertTrue(session.pending.isEmpty)
    }

    func testOneStrongClipConfirms() {
        var session = DetectionSession()
        record(&session, 0.85, at: 3)
        XCTAssertEqual(session.byCode["btbwar"]?.calls, 1)
    }

    func testLaterCallsNeedConfirmingToo() {
        var session = DetectionSession()
        record(&session, 0.85, at: 3)  // call 1, confirmed
        record(&session, 0.6, at: 10)  // a lone weak clip: not a second call
        XCTAssertEqual(session.byCode["btbwar"]?.calls, 1)
        XCTAssertTrue(session.pending.isEmpty)  // already on the page, so not "sketching"
        record(&session, 0.6, at: 11)  // …until it repeats
        XCTAssertEqual(session.byCode["btbwar"]?.calls, 2)
    }

    func testAdvanceClosesCallsDuringSilence() {
        var session = DetectionSession()
        record(&session, 0.6, at: 3)
        session.advance(to: t0.addingTimeInterval(10))
        record(&session, 0.6, at: 11)  // a new call, not the 2nd clip of the old one
        XCTAssertNil(session.byCode["btbwar"])
        XCTAssertEqual(session.pending.first?.clips, 1)
    }

    func testConfirmationNoneCountsEverything() {
        var session = DetectionSession(confirmation: .none)
        record(&session, 0.51, at: 3)
        XCTAssertEqual(session.byCode["btbwar"]?.calls, 1)
    }
}

final class RareConfirmationTests: XCTestCase {
    let warbler = Species(
        code: "btbwar", commonName: "Black-throated Blue Warbler", scientificName: "S. c.", isBird: true)
    let t0 = Date(timeIntervalSince1970: 0)

    func score(_ confidence: Float, required: Float, _ commonness: Commonness) -> BirdScore {
        BirdScore(
            index: 0, species: warbler, confidence: confidence, requiredConfidence: required, commonness: commonness)
    }

    func testOneClipJustOverARareBarIsNotEnough() {
        var session = DetectionSession()
        // An unusual bird needs 0.80 to be reported at all; one clip at 0.85 isn't 0.15 above that.
        session.record([score(0.85, required: 0.8, .unusual)], at: t0.addingTimeInterval(3))
        XCTAssertNil(session.byCode["btbwar"])
        XCTAssertEqual(session.pending.first?.commonness, .unusual)
    }

    func testOneVeryConfidentClipConfirmsARareBird() {
        var session = DetectionSession()
        session.record([score(0.96, required: 0.8, .unusual)], at: t0.addingTimeInterval(3))
        XCTAssertEqual(session.byCode["btbwar"]?.calls, 1)
        XCTAssertEqual(session.byCode["btbwar"]?.commonness, .unusual)
    }

    func testRareBirdConfirmsWithTwoClips() {
        var session = DetectionSession()
        session.record([score(0.82, required: 0.8, .unusual)], at: t0.addingTimeInterval(3))
        session.record([score(0.81, required: 0.8, .unusual)], at: t0.addingTimeInterval(4))
        XCTAssertEqual(session.byCode["btbwar"]?.calls, 1)
    }

    func testCommonnessKeepsTheRarestSeen() {
        var session = DetectionSession(confirmation: .none)
        session.record([score(0.9, required: 0.5, .common)], at: t0.addingTimeInterval(3))
        session.record([score(0.9, required: 0.8, .unusual)], at: t0.addingTimeInterval(20))
        session.record([score(0.9, required: 0.5, .common)], at: t0.addingTimeInterval(40))
        XCTAssertEqual(session.byCode["btbwar"]?.commonness, .unusual)
    }
}

/// Checks the real catalog the app ships (ml/models/coreml/species.json, a plain file in git).
final class BundledCatalogTests: XCTestCase {
    func catalog() throws -> SpeciesCatalog {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { root.deleteLastPathComponent() }  // apps/ios/OverheardKit/Tests/OverheardKitTests/<file>
        return try SpeciesCatalog(contentsOf: root.appendingPathComponent("ml/models/coreml/species.json"))
    }

    func testSplitSpeciesKeepBirdNETsConcept() throws {
        let species = try catalog().species
        func named(_ scientific: String) -> Species { species.first { $0.scientificName == scientific }! }
        // eBird split Yellow Warbler; BirdNET's label must not become the tropical Mangrove Yellow Warbler.
        let yellowWarbler = named("Setophaga petechia")
        XCTAssertEqual(yellowWarbler.code, "yelwar")
        XCTAssertEqual(yellowWarbler.commonName, "Yellow Warbler")
        XCTAssertEqual(yellowWarbler.splitInto, ["manwar1", "yelwar1"])
        XCTAssertEqual(named("Larus argentatus").commonName, "Herring Gull")  // not "European Herring Gull"
        XCTAssertEqual(named("Tyto alba").code, "birdnet:Tyto alba")  // no exact eBird group code
    }

    func testOrdinarySpeciesAreUnchanged() throws {
        let species = try catalog().species
        XCTAssertEqual(species.first { $0.scientificName == "Cardinalis cardinalis" }?.code, "norcar")
        XCTAssertEqual(species.count, 6522)
        XCTAssertEqual(species.filter { !$0.isBird }.count, 101)
    }

    func testCodesAreUniqueApartFromKnownLumps() throws {
        let codes = try catalog().species.map(\.code)
        let shared = Dictionary(grouping: codes, by: { $0 }).filter { $0.value.count > 1 }.keys
        XCTAssertEqual(Set(shared), ["sinbus6"])  // Singing Bushlark: two BirdNET labels, one species now
    }
}
