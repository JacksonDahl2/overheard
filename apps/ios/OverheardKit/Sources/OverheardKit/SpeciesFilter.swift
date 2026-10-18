import Foundation

/// Tunable rules for which BirdNET scores become reported birds.
public struct DetectionRules: Sendable, Equatable {
    public var minConfidence: Float
    /// Only report species expected at this place and week.
    public var useLocationFilter: Bool

    public init(minConfidence: Float = 0.5, useLocationFilter: Bool = true) {
        self.minConfidence = minConfidence
        self.useLocationFilter = useLocationFilter
    }
}

/// Decides whether a label is reportable: always a bird, confident enough, and, when the
/// location filter is on, expected this week. The app and the eval harness share this,
/// so the rules are defined once.
public struct SpeciesFilter: Sendable {
    /// BirdNET labels that aren't birds: sounds (Engine, Siren, Human vocal, …), frogs, insects, mammals.
    public let nonBird: Set<Int>
    /// Expected label indices per BirdNET week (1–48).
    public let weeks: [Int: Set<Int>]

    public init(nonBird: Set<Int>, weeks: [Int: Set<Int>]) {
        self.nonBird = nonBird
        self.weeks = weeks
    }

    /// Loads `non-birds.json` (ml/bird_labels.py) and a per-week species table (ml/species_list.py).
    public init(nonBirdURL: URL, speciesURL: URL) throws {
        let nonBird = try JSONDecoder().decode(NonBirdFile.self, from: Data(contentsOf: nonBirdURL))
        let table = try JSONDecoder().decode(SpeciesTable.self, from: Data(contentsOf: speciesURL))
        self.init(
            nonBird: Set(nonBird.indices),
            weeks: Dictionary(
                uniqueKeysWithValues: table.weeks.compactMap { key, value in Int(key).map { ($0, Set(value)) } }))
    }

    /// Label indices expected at this place in the BirdNET week containing `date`.
    public func expectedSpecies(on date: Date) -> Set<Int>? {
        weeks[Self.birdNETWeek(for: date)]
    }

    public func isReportable(_ index: Int, confidence: Float, expected: Set<Int>?, rules: DetectionRules) -> Bool {
        guard !nonBird.contains(index), confidence >= rules.minConfidence else { return false }
        if rules.useLocationFilter, let expected { return expected.contains(index) }
        return true
    }

    /// BirdNET weeks run 1–48: four per month.
    public static func birdNETWeek(for date: Date) -> Int {
        let parts = Calendar(identifier: .gregorian).dateComponents([.month, .day], from: date)
        let month = parts.month ?? 1
        let day = parts.day ?? 1
        return (month - 1) * 4 + min(4, (day - 1) / 7 + 1)
    }
}

private struct NonBirdFile: Decodable { let indices: [Int] }
private struct SpeciesTable: Decodable { let weeks: [String: [Int]] }
