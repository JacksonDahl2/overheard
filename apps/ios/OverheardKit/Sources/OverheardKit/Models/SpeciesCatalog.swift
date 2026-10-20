import Foundation

/// A species as the app stores and shows it.
public struct Species: Hashable, Sendable, Codable {
    /// Stable ID: an eBird species code ("norcar"), or "birdnet:<scientific name>" for the few
    /// birds current eBird names differently. Store this, never a BirdNET output index.
    public let code: String
    public let commonName: String
    public let scientificName: String
    public let isBird: Bool
    /// When eBird has since split this species, the daughter species' codes. BirdNET can't tell
    /// them apart, so `code` names the whole group; a future version could pick the local one.
    public let splitInto: [String]

    public init(code: String, commonName: String, scientificName: String, isBird: Bool, splitInto: [String] = []) {
        self.code = code
        self.commonName = commonName
        self.scientificName = scientificName
        self.isBird = isBird
        self.splitInto = splitInto
    }
}

/// Maps BirdNET output indices to species (`species.json`, from ml/bird_labels.py).
public struct SpeciesCatalog: Sendable {
    public let species: [Species]  // index = BirdNET output index
    public let nonBird: Set<Int>
    private let indexByCode: [String: Int]

    public init(species: [Species]) {
        self.species = species
        nonBird = Set(species.indices.filter { !species[$0].isBird })
        // Lumped species share a code; the first label stands for both.
        indexByCode = Dictionary(species.indices.map { (species[$0].code, $0) }, uniquingKeysWith: { a, _ in a })
    }

    public init(contentsOf url: URL) throws {
        let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
        self.init(
            species: file.species.map {
                Species(
                    code: $0.code, commonName: $0.common, scientificName: $0.scientific, isBird: $0.bird,
                    splitInto: $0.split ?? [])
            })
    }

    public var count: Int { species.count }
    public subscript(index: Int) -> Species { species[index] }

    /// The species with this code (how walks store birds), or nil if this model doesn't know it.
    public func species(code: String) -> Species? {
        indexByCode[code].map { species[$0] }
    }

    /// Indices whose scientific name matches (eval manifests label recordings this way).
    public func indices(scientificName: String) -> [Int] {
        species.indices.filter { species[$0].scientificName == scientificName }
    }

    private struct File: Decodable {
        let species: [Entry]
        struct Entry: Decodable {
            let code: String
            let common: String
            let scientific: String
            let bird: Bool
            let split: [String]?
        }
    }
}
