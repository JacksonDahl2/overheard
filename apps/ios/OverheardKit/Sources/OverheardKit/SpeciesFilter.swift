import Foundation

/// Tunable rules for which BirdNET scores become reported birds.
public struct DetectionRules: Sendable, Equatable {
    public var minConfidence: Float
    /// Only report species expected at this place and week (when the location is known).
    public var useLocationFilter: Bool

    public init(minConfidence: Float = 0.5, useLocationFilter: Bool = true) {
        self.minConfidence = minConfidence
        self.useLocationFilter = useLocationFilter
    }
}

/// Decides whether a label is reportable: always a bird, confident enough, and, when the
/// location filter is on and the location is known, expected here this week. The app and
/// the eval harness share this, so the rules are defined once.
public struct SpeciesFilter: Sendable {
    /// BirdNET labels that aren't birds: sounds (Engine, Siren, Human vocal, …), frogs, insects, mammals.
    public let nonBird: Set<Int>

    public init(nonBird: Set<Int>) {
        self.nonBird = nonBird
    }

    public init(catalog: SpeciesCatalog) {
        self.init(nonBird: catalog.nonBird)
    }

    /// - Parameter local: species likelihoods for the current place and week, or nil when the
    ///   location is unknown (then only non-birds and low confidence are filtered).
    public func isReportable(_ index: Int, confidence: Float, local: LocalSpecies?, rules: DetectionRules) -> Bool {
        guard !nonBird.contains(index), confidence >= rules.minConfidence else { return false }
        if rules.useLocationFilter, let local { return local.isExpected(index) }
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
