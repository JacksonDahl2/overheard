import SwiftData
import XCTest

@testable import OverheardKit

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

/// A fix `north` meters north of Central Park's Great Lawn, `seconds` after t0.
private func fix(north: Double, at seconds: TimeInterval, accuracy: Double = 5) -> RoutePoint {
    RoutePoint(
        latitude: 40.7812 + north / 111_195, longitude: -73.9665, time: t0.addingTimeInterval(seconds),
        accuracy: accuracy)
}

final class RouteTests: XCTestCase {
    func testDistanceIsHaversine() {
        XCTAssertEqual(fix(north: 0, at: 0).distance(to: fix(north: 1000, at: 1)), 1000, accuracy: 1)
    }

    func testKeepsStepsAndAddsDistance() {
        var route = Route()
        XCTAssertTrue(route.add(fix(north: 0, at: 0)))
        XCTAssertTrue(route.add(fix(north: 15, at: 10)))
        XCTAssertTrue(route.add(fix(north: 40, at: 20)))
        XCTAssertEqual(route.points.count, 3)
        XCTAssertEqual(route.distance, 40, accuracy: 0.5)
    }

    func testStandingStillAddsNothing() {
        var route = Route()
        route.add(fix(north: 0, at: 0))
        for s in 1...30 { route.add(fix(north: Double(s % 3) * 2, at: TimeInterval(s))) }  // jitter
        XCTAssertEqual(route.points.count, 1)
        XCTAssertEqual(route.distance, 0)
    }

    func testDropsInaccurateAndOutOfOrderFixes() {
        var route = Route()
        XCTAssertFalse(route.add(fix(north: 0, at: 0, accuracy: 65)))  // a cell-tower fix
        XCTAssertFalse(route.add(fix(north: 0, at: 0, accuracy: -1)))  // invalid
        route.add(fix(north: 0, at: 10))
        XCTAssertFalse(route.add(fix(north: 50, at: 5)))  // older than the last point
    }

    func testJitterBoundGrowsWithUncertainty() {
        var route = Route()
        route.add(fix(north: 0, at: 0, accuracy: 30))
        XCTAssertFalse(route.add(fix(north: 20, at: 10, accuracy: 30)))  // within the uncertainty
        XCTAssertTrue(route.add(fix(north: 35, at: 20, accuracy: 30)))
    }

    func testRoundTripsThroughCodable() throws {
        var route = Route()
        route.add(fix(north: 0, at: 0))
        route.add(fix(north: 100, at: 60))
        let decoded = try JSONDecoder().decode(Route.self, from: JSONEncoder().encode(route))
        XCTAssertEqual(decoded, route)
    }
}

@MainActor
final class WalkStoreTests: XCTestCase {
    var container: ModelContainer!
    var store: WalkStore!

    override func setUp() async throws {
        container = try WalkStore.container(inMemory: true)
        store = WalkStore(context: container.mainContext)
    }

    func heard(_ code: String, calls: Int = 1, at seconds: TimeInterval = 10, _ commonness: Commonness? = .common)
        -> HeardBird
    {
        HeardBird(
            species: Species(code: code, commonName: code, scientificName: code, isBird: true), calls: calls,
            bestConfidence: 0.8, firstHeard: t0.addingTimeInterval(seconds), lastHeard: t0.addingTimeInterval(seconds),
            commonness: commonness)
    }

    /// What a fresh context (another launch) would read from the store.
    func reloaded() throws -> [Walk] {
        try WalkStore(context: ModelContext(container)).walks()
    }

    func testStartAndEnd() throws {
        let walk = try store.startWalk(at: t0)
        XCTAssertTrue(walk.isActive)
        try store.endWalk(walk, at: t0.addingTimeInterval(600))
        let saved = try XCTUnwrap(reloaded().first)
        XCTAssertFalse(saved.isActive)
        XCTAssertEqual(saved.duration, 600)
        XCTAssertFalse(saved.interrupted)
    }

    func testNewBirdIsSavedImmediately() throws {
        let walk = try store.startWalk(at: t0)
        try store.record([heard("norcar")], in: walk, at: t0.addingTimeInterval(5))
        let saved = try XCTUnwrap(reloaded().first)
        XCTAssertEqual(saved.birds.map(\.speciesCode), ["norcar"])
    }

    func testBirdsAreUpdatedNotDuplicated() throws {
        let walk = try store.startWalk(at: t0)
        try store.record([heard("norcar")], in: walk, at: t0.addingTimeInterval(5))
        try store.record(
            [heard("norcar", calls: 3, .uncommon), heard("blujay")], in: walk, at: t0.addingTimeInterval(9))
        let saved = try XCTUnwrap(reloaded().first)
        XCTAssertEqual(saved.birds.count, 2)
        let cardinal = try XCTUnwrap(saved.birds.first { $0.speciesCode == "norcar" })
        XCTAssertEqual(cardinal.calls, 3)
        XCTAssertEqual(cardinal.commonness, .uncommon)
        XCTAssertEqual(saved.sortedBirds.map(\.speciesCode), ["norcar", "blujay"])  // most calls first
    }

    func testRouteIsSavedOnAnInterval() throws {
        let walk = try store.startWalk(at: t0)
        try store.addRoutePoint(fix(north: 0, at: 1), to: walk)  // the start: saved right away
        try store.addRoutePoint(fix(north: 20, at: 10), to: walk)
        XCTAssertEqual(try reloaded().first?.route.points.count, 1)  // not saved again yet
        try store.addRoutePoint(fix(north: 40, at: 31), to: walk)  // 30 s since the last save
        XCTAssertEqual(try reloaded().first?.route.points.count, 3)
        XCTAssertEqual(try reloaded().first?.route.distance ?? 0, 40, accuracy: 0.5)
    }

    func testInterruptedWalkIsClosedAtItsLastSave() throws {
        let walk = try store.startWalk(at: t0)
        try store.record([heard("norcar")], in: walk, at: t0.addingTimeInterval(120))
        // The app is killed here. Next launch:
        let next = WalkStore(context: ModelContext(container))
        XCTAssertEqual(try next.closeInterruptedWalks(), 1)
        let saved = try XCTUnwrap(next.walks().first)
        XCTAssertTrue(saved.interrupted)
        XCTAssertEqual(saved.endedAt, t0.addingTimeInterval(120))
        XCTAssertEqual(saved.birds.count, 1)  // nothing heard is lost
        XCTAssertEqual(try next.closeInterruptedWalks(), 0)
    }

    func testPlaceNameBecomesTheTitle() throws {
        let walk = try store.startWalk(at: t0)
        XCTAssertEqual(walk.title, WalkTitle.default(for: t0))
        try store.name(walk, placeName: "The Ramble, Central Park")
        XCTAssertEqual(try reloaded().first?.title, "The Ramble, Central Park")
    }

    func testDeleteRemovesItsBirds() throws {
        let walk = try store.startWalk(at: t0)
        try store.record([heard("norcar"), heard("blujay")], in: walk, at: t0.addingTimeInterval(5))
        try store.delete(walk)
        XCTAssertTrue(try reloaded().isEmpty)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<WalkBird>()).isEmpty)
    }

    func testWalksAreNewestFirst() throws {
        let first = try store.startWalk(at: t0)
        try store.endWalk(first, at: t0.addingTimeInterval(60))
        let second = try store.startWalk(at: t0.addingTimeInterval(3600))
        XCTAssertEqual(try store.walks().map(\.id), [second.id, first.id])
    }
}

final class WalkTitleTests: XCTestCase {
    func testNamesTheTimeOfDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!

        func title(atHour hour: Int) -> String {
            let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: hour))!
            return WalkTitle.default(for: date, calendar: calendar)
        }

        XCTAssertEqual(title(atHour: 7), "Morning walk")
        XCTAssertEqual(title(atHour: 13), "Afternoon walk")
        XCTAssertEqual(title(atHour: 18), "Evening walk")
        XCTAssertEqual(title(atHour: 23), "Night walk")
        XCTAssertEqual(title(atHour: 3), "Night walk")
    }
}
