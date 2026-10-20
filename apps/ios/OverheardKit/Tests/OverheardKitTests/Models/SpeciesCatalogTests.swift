import XCTest

@testable import OverheardKit

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

/// Checks the real catalog the app ships (ml/models/coreml/species.json, a plain file in git).
final class BundledCatalogTests: XCTestCase {
    func catalog() throws -> SpeciesCatalog {
        try SpeciesCatalog(contentsOf: XCTUnwrap(Self.shippedCatalog()))
    }

    /// species.json, found by walking up from this file to the repo root.
    static func shippedCatalog() -> URL? {
        var folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while folder.path != "/" {
            let candidate = folder.appendingPathComponent("ml/models/coreml/species.json")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            folder.deleteLastPathComponent()
        }
        return nil
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

final class CatalogLookupTests: XCTestCase {
    func testFindsByCodeAndLumpedCodesResolveToTheFirst() {
        let catalog = SpeciesCatalog(species: [
            Species(
                code: "norcar", commonName: "Northern Cardinal", scientificName: "Cardinalis cardinalis", isBird: true),
            Species(code: "lumped", commonName: "A", scientificName: "A a", isBird: true),
            Species(code: "lumped", commonName: "B", scientificName: "B b", isBird: true),
        ])
        XCTAssertEqual(catalog.species(code: "norcar")?.commonName, "Northern Cardinal")
        XCTAssertEqual(catalog.species(code: "lumped")?.commonName, "A")
        XCTAssertNil(catalog.species(code: "nope"))
    }
}
