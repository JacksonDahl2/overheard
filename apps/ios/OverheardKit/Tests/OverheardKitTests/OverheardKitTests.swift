import XCTest

@testable import OverheardKit

final class OverheardKitTests: XCTestCase {
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
    // Labels 0–2 are birds, 3 is "Engine". Label 2 isn't expected in October.
    let filter = SpeciesFilter(nonBird: [3], weeks: [39: [0, 1, 3]])
    let october = SpeciesFilter.birdNETWeek(for: Date(timeIntervalSince1970: 1_792_350_000))  // 2026-10-18

    func testNonBirdsAreNeverReported() {
        for rules in [DetectionRules(useLocationFilter: true), DetectionRules(useLocationFilter: false)] {
            XCTAssertFalse(filter.isReportable(3, confidence: 0.99, expected: filter.weeks[39], rules: rules))
        }
    }

    func testConfidenceThreshold() {
        let rules = DetectionRules(minConfidence: 0.5)
        XCTAssertTrue(filter.isReportable(0, confidence: 0.5, expected: filter.weeks[39], rules: rules))
        XCTAssertFalse(filter.isReportable(0, confidence: 0.49, expected: filter.weeks[39], rules: rules))
    }

    func testLocationFilter() {
        let expected = filter.weeks[39]
        XCTAssertFalse(filter.isReportable(2, confidence: 0.9, expected: expected, rules: DetectionRules()))
        XCTAssertTrue(
            filter.isReportable(2, confidence: 0.9, expected: expected, rules: DetectionRules(useLocationFilter: false))
        )
    }

    func testMissingWeekDoesNotFilter() {
        // No table for this week: fall back to reporting by confidence alone.
        XCTAssertTrue(filter.isReportable(2, confidence: 0.9, expected: nil, rules: DetectionRules()))
    }

    func testExpectedSpeciesUsesBirdNETWeek() {
        XCTAssertEqual(october, 39)
        XCTAssertEqual(
            filter.expectedSpecies(on: Date(timeIntervalSince1970: 1_792_350_000)), [0, 1, 3])
    }
}
