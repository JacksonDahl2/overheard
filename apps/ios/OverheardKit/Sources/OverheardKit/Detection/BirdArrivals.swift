import Foundation

/// Spots the moment a species joins the walk: confirmed for the first time, not just heard
/// again. The app taps or notifies once per new species (a repeat call never alerts).
public struct BirdArrivals: Sendable, Equatable {
    private var seen: Set<String> = []

    public init() {}

    /// The birds in `birds` that weren't there last time, in the order given.
    public mutating func newBirds(in birds: [HeardBird]) -> [HeardBird] {
        let arrivals = birds.filter { !seen.contains($0.species.code) }
        seen.formUnion(arrivals.map(\.species.code))
        return arrivals
    }

    /// Starts over for a new walk.
    public mutating func reset() {
        seen = []
    }
}
