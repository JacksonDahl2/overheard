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
