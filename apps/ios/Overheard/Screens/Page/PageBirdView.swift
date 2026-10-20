import OverheardKit
import SwiftUI

/// A bird on the journal page: its drawing and its handwritten name, tilted a little as if
/// sketched by hand. The name sits on whichever side the layout chose (below, above or beside),
/// sometimes a little apart with an arrow. `JournalPage` decides where, how big and how tilted.
struct PageBirdView: View {
    let bird: PageBird
    let placement: PageLayout.Placement

    @Environment(\.theme) private var theme

    var body: some View {
        ZStack(alignment: .topLeading) {
            // A rare bird's red-ink note already points at it; a second arrow would be clutter.
            if placement.hasArrow && !bird.hasFlourish { arrow }

            drawing
                .frame(width: art.width, height: art.height)
                .offset(x: art.minX, y: art.minY)

            // Handwriting may spill into the gap the layout keeps around every label, so long names
            // and glyph flourishes aren't clipped at the box's edge.
            labelText
                .padding(.horizontal, 4)  // Caveat's letters reach past their box; keep them uncut
                .frame(width: label.width + PageLayout.labelGap * 2, alignment: textAlignment.frame)
                .frame(width: label.width, height: label.height, alignment: textAlignment.frame)
                .offset(x: label.minX, y: label.minY)
        }
        .frame(width: placement.frame.width, height: placement.frame.height, alignment: .topLeading)
        .rotationEffect(.degrees(placement.tilt))
        .position(x: placement.frame.midX, y: placement.frame.midY)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: - Geometry, relative to this bird's footprint

    private var art: CGRect { local(placement.art) }
    private var label: CGRect { local(placement.label) }

    private func local(_ rect: CGRect) -> CGRect {
        rect.offsetBy(dx: -placement.frame.minX, dy: -placement.frame.minY)
    }

    /// Text leans toward the bird: right-aligned when it's written to the bird's left, and so on.
    private var textAlignment: (frame: Alignment, text: TextAlignment) {
        switch placement.labelSide {
        case .below: (.top, .center)
        case .above: (.bottom, .center)
        case .leading: (.trailing, .trailing)
        case .trailing: (.leading, .leading)
        }
    }

    // MARK: - Drawing

    @ViewBuilder
    private var drawing: some View {
        ZStack {
            if let image = BirdArt.image(for: bird.species.code) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .grayscale(bird.isSketching ? 1 : 0)
                    .opacity(bird.isSketching ? 0.38 : 1)
            } else {
                NoDrawingYet()
            }

            if bird.isSketching {
                Circle()
                    .strokeBorder(theme.accentOnPage, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .padding(art.width * 0.06)
                    .opacity(0.55)
            }
        }
    }

    // MARK: - Label

    private var labelText: some View {
        VStack(spacing: 2) {
            if bird.isSketching {
                Text("sketching…\n\(bird.species.commonName)")
                    .foregroundStyle(theme.accentOnPage)
            } else {
                (Text(bird.species.commonName) + Text(callCount).foregroundStyle(theme.pageSoft))
                    .foregroundStyle(theme.pageInk)
            }

            if bird.hasFlourish {
                Flourish(note: "unusual here this time of year")
            }
        }
        .font(.hand(18))
        .multilineTextAlignment(textAlignment.text)
        .fixedSize(horizontal: false, vertical: true)  // wrap fully; never cut a name short
    }

    /// "×3" after the name; a single call needs no count.
    private var callCount: String {
        bird.calls > 1 ? " ×\(bird.calls)" : ""
    }

    // MARK: - Arrow

    /// From the edge of the name to just inside the drawing (cutouts are cropped close to the bird).
    private var arrow: some View {
        let reach = art.width * 0.12
        let (start, end): (CGPoint, CGPoint) =
            switch placement.labelSide {
            case .below:
                (CGPoint(x: label.midX, y: label.minY - 2), CGPoint(x: art.midX, y: art.maxY - reach))
            case .above:
                (CGPoint(x: label.midX, y: label.maxY + 2), CGPoint(x: art.midX, y: art.minY + reach))
            case .leading:
                (CGPoint(x: label.maxX + 2, y: label.midY), CGPoint(x: art.minX + reach, y: art.midY))
            case .trailing:
                (CGPoint(x: label.minX - 2, y: label.midY), CGPoint(x: art.maxX - reach, y: art.midY))
            }

        return PointerArrow(start: start, end: end)
            .stroke(theme.pageInk.opacity(0.7), style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
    }

    // MARK: - Accessibility

    private var accessibilityText: String {
        let name = bird.species.commonName
        if bird.isSketching { return "\(name), still being sketched" }

        let times = bird.calls == 1 ? "once" : "\(bird.calls) times"
        return bird.hasFlourish ? "\(name), heard \(times), unusual here" : "\(name), heard \(times)"
    }
}

/// Stands in for a bird that hasn't been drawn yet: a faint pencil circle and a note.
private struct NoDrawingYet: View {
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(theme.pageSoft.opacity(0.4), lineWidth: 1)
                .padding(10)
            Text("drawing\nto come")
                .font(.hand(16))
                .multilineTextAlignment(.center)
                .foregroundStyle(theme.pageSoft)
        }
    }
}
