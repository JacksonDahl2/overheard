import SwiftUI

/// The rare-bird "naturalist flourish" (docs/design.md): a red-ink handwritten note with a
/// hand-drawn arrow pointing up at the bird, tilted about -3°.
struct Flourish: View {
    let note: String

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 2) {
            ArrowUp()
                .stroke(theme.accentOnPage, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                .frame(width: 14, height: 18)

            Text(note)
                .font(.hand(16, bold: true))
                .foregroundStyle(theme.accentOnPage)
                .fixedSize(horizontal: false, vertical: true)
        }
        .rotationEffect(.degrees(-3))
    }
}

/// A loose, hand-drawn arrow curving up and to the left.
private struct ArrowUp: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let tip = CGPoint(x: rect.minX + rect.width * 0.3, y: rect.minY)

        // The shaft: a gentle curve from the bottom right up to the tip.
        p.move(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addQuadCurve(to: tip, control: CGPoint(x: rect.minX + rect.width * 0.2, y: rect.midY))

        // The head: two short strokes back from the tip.
        p.move(to: CGPoint(x: tip.x - rect.width * 0.25, y: tip.y + rect.height * 0.28))
        p.addLine(to: tip)
        p.addLine(to: CGPoint(x: tip.x + rect.width * 0.35, y: tip.y + rect.height * 0.2))
        return p
    }
}
