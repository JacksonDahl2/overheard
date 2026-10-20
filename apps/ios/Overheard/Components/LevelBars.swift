import SwiftUI

/// The strip of bars under the walk title: one bar per clip, newest on the right.
/// Bars where a bird was heard are drawn in the accent color.
struct LevelBars: View {
    let history: LevelHistory

    @Environment(\.theme) private var theme

    /// Loudness that fills the strip. Birdsong close by is around 0.05–0.1.
    private static let fullScale: Float = 0.09
    private static let spacing: CGFloat = 8

    var body: some View {
        Canvas { context, size in
            let samples = history.samples
            let slots = LevelHistory.capacity

            for (i, sample) in samples.enumerated() {
                // Right-align, so the newest bar is always at the right edge.
                let slot = slots - samples.count + i
                let x = size.width - CGFloat(slots - slot) * Self.spacing + Self.spacing / 2
                let height = barHeight(sample.level, in: size.height)

                var bar = Path()
                bar.move(to: CGPoint(x: x, y: (size.height - height) / 2))
                bar.addLine(to: CGPoint(x: x, y: (size.height + height) / 2))

                let color = sample.heardBird ? theme.accent : theme.chromeSoft
                context.stroke(bar, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }
        .frame(height: 26)
        .accessibilityHidden(true)
    }

    private func barHeight(_ level: Float, in height: CGFloat) -> CGFloat {
        let fraction = CGFloat(min(1, level / Self.fullScale).squareRoot())
        return max(2, fraction * height)
    }
}
