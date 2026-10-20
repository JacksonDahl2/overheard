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

    func testABirdHeardOftenIsMuchBigger() {
        XCTAssertGreaterThan(BirdSize.fraction(calls: 6) / BirdSize.fraction(calls: 1), 2.5)
    }

    func testEarlyCallsMatterMostOnALogScale() {
        let firstStep = BirdSize.fraction(calls: 2) - BirdSize.fraction(calls: 1)
        let laterStep = BirdSize.fraction(calls: 10) - BirdSize.fraction(calls: 9)
        XCTAssertGreaterThan(firstStep, laterStep * 3)
    }
}

final class PageLayoutTests: XCTestCase {
    let page = CGRect(x: 0, y: 0, width: 360, height: 480)

    func item(_ id: String, _ side: Double = 120) -> PageLayout.Item {
        PageLayout.Item(id: id, side: side, labelHeight: 40)
    }

    /// On the page, and no drawing or label covers another (drawings may tuck into margins).
    func assertValid(_ layout: PageLayout, file: StaticString = #filePath, line: UInt = #line) {
        let placements = Array(layout.placements.values)
        for (i, a) in placements.enumerated() {
            XCTAssertTrue(page.contains(a.frame), "off the page: \(a.frame)", file: file, line: line)
            for b in placements[(i + 1)...] {
                XCTAssertTrue(
                    PageLayout.fits(a, among: [b]), "overlap: \(a.frame) and \(b.frame)", file: file, line: line)
            }
        }
    }

    func testTheFirstBirdSitsNearTheTop() throws {
        let layout = PageLayout(items: [item("norcar")], in: page)
        let art = try XCTUnwrap(layout.placements["norcar"]).art
        XCTAssertLessThan(art.midY, page.midY)
        XCTAssertEqual(art.midX, page.midX, accuracy: page.width * 0.12)
        XCTAssertEqual(layout.scale, 1)
    }

    func testBirdsScatterWithoutCoveringEachOther() {
        let layout = PageLayout(items: [item("a", 150), item("b", 120), item("c", 100), item("d", 80)], in: page)
        XCTAssertEqual(layout.placements.count, 4)
        XCTAssertEqual(layout.scale, 1)
        assertValid(layout)
    }

    func testBirdsAreNotInAGrid() {
        let ids = ["whtspa", "blujay", "norcar", "rethaw", "scatan", "btbwar"]
        let layout = PageLayout(items: ids.map { item($0, 90) }, in: page)
        let rows = Set(layout.placements.values.map { Int($0.art.minY) })
        let columns = Set(layout.placements.values.map { Int($0.art.minX) })
        XCTAssertGreaterThan(rows.count, 3)
        XCTAssertGreaterThan(columns.count, 3)
    }

    func testEachBirdHasASmallSteadyTilt() throws {
        let first = try XCTUnwrap(PageLayout(items: [item("norcar")], in: page).placements["norcar"])
        let again = try XCTUnwrap(PageLayout(items: [item("norcar")], in: page).placements["norcar"])
        XCTAssertEqual(first.tilt, again.tilt)
        XCTAssertLessThanOrEqual(abs(first.tilt), PageLayout.maxTilt)
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

    func testAFewBirdsGrowToFillThePage() {
        let items = [item("a", 100), item("b", 80)]
        let grown = PageLayout(items: items, in: page, maxScale: 1.5)
        XCTAssertEqual(grown.scale, 1.5)
        assertValid(grown)
        XCTAssertEqual(PageLayout(items: items, in: page).scale, 1)  // no growing unless asked
    }

    func testGrowingStillShrinksWhenFull() {
        let items = (0..<14).map { item("bird\($0)", 130) }
        XCTAssertLessThan(PageLayout(items: items, in: page, maxScale: 1.5).scale, 1)
    }

    func testASmallBirdKeepsAReadableLabel() throws {
        let small = PageLayout.Item(id: "a", side: 60, labelHeight: 40, labelWidth: 110)
        let placement = try XCTUnwrap(PageLayout(items: [small], in: page).placements["a"])
        XCTAssertEqual(placement.label.width, 110)
        XCTAssertEqual(placement.label.minY, placement.art.maxY)
        XCTAssertEqual(placement.label.midX, placement.art.midX, accuracy: 0.001)  // centered under it
    }

    func testIsDeterministic() {
        let items = [item("a", 140), item("b", 100), item("c", 90), item("d", 120)]
        XCTAssertEqual(PageLayout(items: items, in: page), PageLayout(items: items, in: page))
    }

    func testStableHashIsTheSameOnEveryRun() {
        XCTAssertEqual(StableHash.of("a"), 0xAF63_DC4C_8601_EC8C)  // the published FNV-1a 64 value
        XCTAssertNotEqual(StableHash.of("norcar"), StableHash.of("blujay"))
    }
}
