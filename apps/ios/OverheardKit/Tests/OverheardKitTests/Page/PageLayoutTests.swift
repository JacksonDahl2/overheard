import CoreGraphics
import XCTest

@testable import OverheardKit

final class BirdSizeTests: XCTestCase {
    let style = PageStyle.standard

    func testOneCallIsTheSmallest() {
        XCTAssertEqual(BirdSize.fraction(calls: 1), style.smallestBirdFraction)
        XCTAssertEqual(BirdSize.fraction(calls: 0), style.smallestBirdFraction)
    }

    func testGrowsWithCallsThenCaps() {
        let sizes = (1...style.fullSizeAtCalls).map { BirdSize.fraction(calls: $0) }
        XCTAssertEqual(sizes, sizes.sorted())
        XCTAssertEqual(BirdSize.fraction(calls: style.fullSizeAtCalls), 1, accuracy: 1e-9)
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

    func testTheStyleSetsTheRange() {
        var big = style
        big.smallestBirdFraction = 0.6
        XCTAssertEqual(BirdSize.fraction(calls: 1, style: big), 0.6)
    }
}

final class PageLayoutTests: XCTestCase {
    let page = CGRect(x: 0, y: 0, width: 360, height: 480)
    let ids = ["whtspa", "blujay", "norcar", "rethaw", "scatan", "btbwar"]

    func item(_ id: String, _ side: Double = 120) -> PageLayout.Item {
        PageLayout.Item(id: id, side: side)
    }

    /// On the page, and no drawing covers another (they may tuck into each other's margins).
    func assertValid(_ layout: PageLayout, file: StaticString = #filePath, line: UInt = #line) {
        let arts = layout.placements.values.map(\.art)
        for (i, a) in arts.enumerated() {
            XCTAssertTrue(page.contains(a), "off the page: \(a)", file: file, line: line)
            XCTAssertTrue(PageLayout.fits(a, among: Array(arts[(i + 1)...])), "overlap at \(a)", file: file, line: line)
        }
    }

    // MARK: - Placing

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
        assertValid(layout)
    }

    func testBirdsAreNotInAGrid() {
        let layout = PageLayout(items: ids.map { item($0, 90) }, in: page)
        XCTAssertGreaterThan(Set(layout.placements.values.map { Int($0.art.minY) }).count, 3)
        XCTAssertGreaterThan(Set(layout.placements.values.map { Int($0.art.minX) }).count, 3)
    }

    func testShrinksToFitMoreBirds() {
        let layout = PageLayout(items: (0..<20).map { item("bird\($0)", 130) }, in: page)
        XCTAssertEqual(layout.placements.count, 20)
        XCTAssertLessThan(layout.scale, 1)
        assertValid(layout)
    }

    func testTooManyBirdsShowsTheOnesThatFit() {
        var strict = PageStyle.standard
        (strict.nestle, strict.arrangementsPerSize) = (0, 1)  // no tucking in, so the page truly fills up
        let layout = PageLayout(items: (0..<200).map { item("bird\($0)", 130) }, in: page, style: strict)
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

    // MARK: - Each page its own

    func testEachBirdHasASmallSteadyTilt() throws {
        let first = try XCTUnwrap(PageLayout(items: [item("norcar")], in: page).placements["norcar"])
        let again = try XCTUnwrap(PageLayout(items: [item("norcar")], in: page).placements["norcar"])
        XCTAssertEqual(first.tilt, again.tilt)
        XCTAssertLessThanOrEqual(abs(first.tilt), PageStyle.standard.maxTilt)
    }

    func testEachWalkIsSketchedDifferently() {
        let items = ids.map { item($0, 90) }
        let monday = PageLayout(items: items, in: page, seed: "walk-1")
        let tuesday = PageLayout(items: items, in: page, seed: "walk-2")
        XCTAssertNotEqual(monday, tuesday)
        XCTAssertEqual(monday, PageLayout(items: items, in: page, seed: "walk-1"))  // the same walk redraws the same
    }

    func testStableHashIsTheSameOnEveryRun() {
        XCTAssertEqual(StableHash.of("a"), 0xAF63_DC4C_8601_EC8C)  // the published FNV-1a 64 value
        XCTAssertNotEqual(StableHash.of("norcar"), StableHash.of("blujay"))
    }

    // MARK: - The style's settings take effect

    func testNoTiltWhenTheStyleSaysNone() {
        var style = PageStyle.standard
        style.maxTilt = 0
        let layout = PageLayout(items: ids.map { item($0, 90) }, in: page, style: style)
        XCTAssertTrue(layout.placements.values.allSatisfy { $0.tilt == 0 })
    }

    func testMoreNestlingPacksBirdsCloser() {
        var tight = PageStyle.standard
        tight.nestle = 30
        let a = CGRect(x: 0, y: 0, width: 100, height: 100)
        let overlapping = CGRect(x: 60, y: 0, width: 100, height: 100)  // 40 pt overlap
        XCTAssertFalse(PageLayout.fits(overlapping, among: [a]))
        XCTAssertTrue(PageLayout.fits(overlapping, among: [a], style: tight))
    }

    func testStyleSurvivesSaving() throws {
        var style = PageStyle.standard
        style.nestle = 20
        let saved = try JSONEncoder().encode(style)
        XCTAssertEqual(try JSONDecoder().decode(PageStyle.self, from: saved), style)
    }
}
