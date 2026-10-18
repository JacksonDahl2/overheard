import XCTest

@testable import OverheardKit

final class OverheardKitTests: XCTestCase {
    func testBirdNETWeek() {
        let cal = Calendar(identifier: .gregorian)
        func week(_ month: Int, _ day: Int) -> Int {
            BirdClassifier.birdNETWeek(for: cal.date(from: DateComponents(year: 2026, month: month, day: day))!)
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
