import Foundation

/// How big a bird is drawn on the Listen and Journal pages.
///
/// Size means call count and nothing else (docs/design.md). It's a log scale from
/// `minFraction` at one call to full size at `fullAt` calls, so a chatty bird stands out
/// without taking over the page, and a bird heard once is clearly small.
public enum BirdSize {
    /// Calls at which a bird reaches full size; more calls don't make it bigger.
    public static let fullAt = 10

    /// A one-call bird's size, as a fraction of full size.
    public static let minFraction = 0.3

    /// Size as a fraction of full size (`minFraction`…1).
    public static func fraction(calls: Int) -> Double {
        guard calls > 1 else { return minFraction }

        let progress = log(Double(min(calls, fullAt))) / log(Double(fullAt))
        return minFraction + (1 - minFraction) * progress
    }
}
