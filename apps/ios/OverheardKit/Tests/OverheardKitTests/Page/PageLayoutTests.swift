import CoreGraphics
import XCTest

@testable import OverheardKit

final class BirdSizeTests: XCTestCase {
    func testOneCallIsTheSmallest() {
        XCTAssertEqual(BirdSize.fraction(calls: 1), BirdSize.minFraction)
        XCTAssertEqual(BirdSize.fraction(calls: 0), BirdSize.minFraction)
    }

    func testGrowsWithCallsThenCaps() {
        let sizes = (1...BirdSize.fullAt).map(BirdSize.fraction(calls:))
        XCTAssertEqual(sizes, sizes.sorted())
        XCTAssertEqual(BirdSize.fraction(calls: BirdSize.fullAt), 1, accuracy: 1e-9)
        XCTAssertEqual(BirdSize.fraction(calls: 40), 1, accuracy: 1e-9)  // a chatty bird stops growing
    }

    func testEarlyCallsMatterMostOnALogScale() {
        let firstStep = BirdSize.fraction(calls: 2) - BirdSize.fraction(calls: 1)
        let laterStep = BirdSize.fraction(calls: 11) - BirdSize.fraction(calls: 10)
        XCTAssertGreaterThan(firstStep, laterStep * 3)
    }
}

final class PageLayoutTests: XCTestCase {
    let page = CGRect(x: 0, y: 0, width: 360, height: 480)

    func item(_ id: String, _ side: Double = 120) -> PageLayout.Item {
        PageLayout.Item(id: id, side: side, labelHeight: 40)
    }

    func assertValid(_ layout: PageLayout, file: StaticString = #filePath, line: UInt = #line) {
        let frames = Array(layout.placements.values.map(\.frame))
        for (i, a) in frames.enumerated() {
            XCTAssertTrue(page.contains(a), "off the page: \(a)", file: file, line: line)
            for b in frames[(i + 1)...] {
                XCTAssertFalse(a.intersects(b), "overlap: \(a) and \(b)", file: file, line: line)
            }
        }
    }

    func testOneBirdSitsNearTheFocalPoint() throws {
        let layout = PageLayout(items: [item("norcar")], in: page)
        let art = try XCTUnwrap(layout.placements["norcar"]).art
        XCTAssertEqual(art.midX, page.midX, accuracy: 0.5)
        XCTAssertEqual(layout.scale, 1)
    }

    func testBirdsClusterWithoutOverlapping() {
        let layout = PageLayout(items: [item("a", 150), item("b", 120), item("c", 100), item("d", 80)], in: page)
        XCTAssertEqual(layout.placements.count, 4)
        XCTAssertEqual(layout.scale, 1)
        assertValid(layout)
    }

    func testANewBirdDoesNotMoveTheOthers() {
        let before = PageLayout(items: [item("a"), item("b"), item("c", 90)], in: page)
        let after = PageLayout(items: [item("a"), item("b"), item("c", 90), item("d", 70)], in: page)
        for id in ["a", "b", "c"] {
            XCTAssertEqual(before.placements[id], after.placements[id])
        }
    }

    func testShrinksToFitMoreBirds() {
        let items = (0..<14).map { item("bird\($0)", 130) }
        let layout = PageLayout(items: items, in: page)
        XCTAssertEqual(layout.placements.count, 14)
        XCTAssertLessThan(layout.scale, 1)
        assertValid(layout)
    }

    func testTooManyBirdsShowsTheOnesThatFit() {
        let items = (0..<200).map { item("bird\($0)", 130) }
        let layout = PageLayout(items: items, in: page)
        XCTAssertGreaterThan(layout.placements.count, 0)
        XCTAssertLessThan(layout.placements.count, 200)
        XCTAssertNotNil(layout.placements["bird0"])  // the first heard always shows
        assertValid(layout)
    }

    func testLabelSitsUnderItsDrawing() throws {
        let placement = try XCTUnwrap(PageLayout(items: [item("a")], in: page).placements["a"])
        XCTAssertEqual(placement.label.minY, placement.art.maxY)
        XCTAssertEqual(placement.label.width, placement.art.width)
    }

    func testIsDeterministic() {
        let items = [item("a", 140), item("b", 100), item("c", 90), item("d", 120)]
        XCTAssertEqual(PageLayout(items: items, in: page), PageLayout(items: items, in: page))
    }
}
