import Foundation

/// How big a bird is drawn on the Listen and Journal pages.
///
/// Size means call count and nothing else (docs/design.md). It's a log scale from the style's
/// `smallestBirdFraction` at one call to full size at `fullSizeAtCalls`, so a chatty bird stands
/// out without taking over the page, and a bird heard once is clearly small.
public enum BirdSize {
    /// Size as a fraction of full size (`smallestBirdFraction`…1).
    public static func fraction(calls: Int, style: PageStyle = .standard) -> Double {
        guard calls > 1 else { return style.smallestBirdFraction }

        let fullAt = max(2, style.fullSizeAtCalls)
        let progress = log(Double(min(calls, fullAt))) / log(Double(fullAt))
        return style.smallestBirdFraction + (1 - style.smallestBirdFraction) * progress
    }
}
