import Foundation

/// Tunable rules for which BirdNET scores become reported birds.
public struct DetectionRules: Sendable, Hashable {
    /// Base confidence threshold: what a common species needs. Rarer species need more (see `bar`).
    public var minConfidence: Float
    /// Use the location: hide species too unlikely here and raise the bar for rarer ones.
    /// Off, every bird is judged by `minConfidence` alone (commonness is still reported).
    public var useLocationFilter: Bool
    public var bar: ConfidenceBar

    public init(minConfidence: Float = 0.5, useLocationFilter: Bool = true, bar: ConfidenceBar = .standard) {
        self.minConfidence = minConfidence
        self.useLocationFilter = useLocationFilter
        self.bar = bar
    }
}

/// Decides whether a label is reportable, and what bar it had to clear. The app and the eval
/// harness share this, so the rules are defined once:
/// - never a non-bird;
/// - with a known location and the filter on: hidden if too unlikely here, otherwise it needs
///   the base threshold plus its tier's extra (`ConfidenceBar`);
/// - otherwise just the base threshold.
public struct SpeciesFilter: Sendable {
    /// BirdNET labels that aren't birds: sounds (Engine, Siren, Human vocal, …), frogs, insects, mammals.
    public let nonBird: Set<Int>

    /// The highest confidence any tier can demand, so a rare bird is never unreachable.
    public static let maxRequiredConfidence: Float = 0.95

    public init(nonBird: Set<Int>) {
        self.nonBird = nonBird
    }

    public init(catalog: SpeciesCatalog) {
        self.init(nonBird: catalog.nonBird)
    }

    /// - Parameter local: species likelihoods for the current place and week, or nil when the
    ///   location is unknown.
    /// - Returns: nil if the label isn't reportable.
    public func assess(_ index: Int, confidence: Float, local: LocalSpecies?, rules: DetectionRules) -> Assessment? {
        guard !nonBird.contains(index) else { return nil }
        guard let local else {
            return confidence >= rules.minConfidence
                ? Assessment(requiredConfidence: rules.minConfidence, commonness: nil) : nil
        }
        let tier = rules.bar.tier(forOccurrence: local.occurrence(of: index))
        guard rules.useLocationFilter else {
            return confidence >= rules.minConfidence
                ? Assessment(requiredConfidence: rules.minConfidence, commonness: tier?.commonness ?? .unusual) : nil
        }
        guard let tier else { return nil }  // too unlikely here
        let required = min(rules.minConfidence + tier.extraConfidence, Self.maxRequiredConfidence)
        return confidence >= required ? Assessment(requiredConfidence: required, commonness: tier.commonness) : nil
    }

    /// BirdNET weeks run 1–48: four per month.
    public static func birdNETWeek(for date: Date) -> Int {
        let parts = Calendar(identifier: .gregorian).dateComponents([.month, .day], from: date)
        let month = parts.month ?? 1
        let day = parts.day ?? 1
        return (month - 1) * 4 + min(4, (day - 1) / 7 + 1)
    }
}
