import Foundation

/// How expected a species is at the current place and week, from BirdNET's location model.
/// Drives how much confidence a detection needs, and what the UI says about it (the rare-bird
/// flourish, sketch styling, life-list badges).
public enum Commonness: Int, Sendable, Codable, Comparable, CaseIterable {
    case common
    case uncommon
    /// Rarely here this week, but plausible: shown with the "naturalist flourish" when confirmed.
    case unusual

    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

/// How much confidence a detection needs, by how likely the species is here this week.
///
/// The bar is data, not code: a list of tiers, so it can be tuned, swapped per region, or
/// exposed as a setting without touching the filter logic. Tiers add to the base threshold
/// (`DetectionRules.minConfidence`), so the app's "Min confidence" slider moves every tier.
public struct ConfidenceBar: Sendable, Hashable {
    public struct Tier: Sendable, Hashable {
        /// Applies when the species' occurrence here is at least this (0–1).
        public let minOccurrence: Float
        /// Added to the base threshold.
        public let extraConfidence: Float
        public let commonness: Commonness

        public init(minOccurrence: Float, extraConfidence: Float, commonness: Commonness) {
            self.minOccurrence = minOccurrence
            self.extraConfidence = extraConfidence
            self.commonness = commonness
        }
    }

    /// Highest `minOccurrence` first. Below the last tier, a species is hidden.
    public let tiers: [Tier]

    public init(tiers: [Tier]) {
        self.tiers = tiers.sorted { $0.minOccurrence > $1.minOccurrence }
    }

    /// The tier for an occurrence value, or nil if the species is too unlikely here to report.
    public func tier(forOccurrence occurrence: Float) -> Tier? {
        tiers.first { occurrence >= $0.minOccurrence }
    }

    /// The app's default. The rarer a species is here, the more sure BirdNET has to be:
    /// common ≥ 10% occurrence (+0), uncommon ≥ 3% (+0.20), unusual ≥ 1% (+0.40), rarer hidden.
    ///
    /// Chosen with overheard-eval (2026-10-18) over gentler tiers: it's the only option that
    /// beat the old hard cutoff on precision (84.3% vs 83.7% at 0.50) while letting clearly
    /// heard rare birds through instead of hiding them.
    public static let standard = ConfidenceBar(tiers: [
        Tier(minOccurrence: 0.10, extraConfidence: 0, commonness: .common),
        Tier(minOccurrence: 0.03, extraConfidence: 0.20, commonness: .uncommon),
        Tier(minOccurrence: 0.01, extraConfidence: 0.40, commonness: .unusual),
    ])

    /// BirdNET-Analyzer's behavior (and ours before the tiered bar): expected (≥ 3%) or hidden,
    /// with no extra confidence. Kept as the eval baseline.
    public static let hardCutoff = ConfidenceBar(tiers: [
        Tier(minOccurrence: 0.03, extraConfidence: 0, commonness: .common)
    ])
}

/// The filter's verdict on one label in one clip.
public struct Assessment: Sendable, Hashable {
    /// The confidence this detection had to reach (base threshold plus its tier's extra).
    public let requiredConfidence: Float
    /// How expected the species is here; nil when the location is unknown.
    public let commonness: Commonness?

    public init(requiredConfidence: Float, commonness: Commonness?) {
        self.requiredConfidence = requiredConfidence
        self.commonness = commonness
    }
}
