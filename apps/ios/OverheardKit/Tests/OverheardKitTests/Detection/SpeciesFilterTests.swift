import XCTest

@testable import OverheardKit

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
