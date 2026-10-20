import XCTest

@testable import OverheardKit

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

final class BirdArrivalsTests: XCTestCase {
    func bird(_ code: String, calls: Int = 1) -> HeardBird {
        HeardBird(
            species: Species(code: code, commonName: code, scientificName: code, isBird: true), calls: calls,
            bestConfidence: 0.8, firstHeard: .now, lastHeard: .now, commonness: .common)
    }

    func testEachSpeciesArrivesOnce() {
        var arrivals = BirdArrivals()
        XCTAssertEqual(arrivals.newBirds(in: [bird("norcar")]).map(\.species.code), ["norcar"])
        XCTAssertEqual(arrivals.newBirds(in: [bird("norcar", calls: 2)]).count, 0)  // a repeat call
        XCTAssertEqual(
            arrivals.newBirds(in: [bird("norcar", calls: 3), bird("blujay")]).map(\.species.code), ["blujay"])
    }

    func testResetStartsANewWalk() {
        var arrivals = BirdArrivals()
        _ = arrivals.newBirds(in: [bird("norcar")])
        arrivals.reset()
        XCTAssertEqual(arrivals.newBirds(in: [bird("norcar")]).count, 1)
    }
}
