import OverheardKit
import SwiftUI

/// A bird on the journal page: its drawing, and its handwritten label underneath.
/// The layout (`JournalPage`) decides where it goes and how big it is.
struct PageBirdView: View {
    let bird: PageBird
    let placement: PageLayout.Placement

    @Environment(\.theme) private var theme

    var body: some View {
        ZStack(alignment: .topLeading) {
            drawing
                .frame(width: placement.art.width, height: placement.art.height)
                .offset(x: placement.art.minX, y: placement.art.minY)

            label
                .frame(width: placement.label.width, height: placement.label.height, alignment: .top)
                .offset(x: placement.label.minX, y: placement.label.minY)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
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
                    .padding(placement.art.width * 0.06)
                    .opacity(0.55)
            }
        }
    }

    // MARK: - Label

    private var label: some View {
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
        .font(.hand(19))
        .multilineTextAlignment(.center)
        .lineSpacing(-4)
        .minimumScaleFactor(0.8)
    }

    /// "×3" after the name; a single call needs no count.
    private var callCount: String {
        bird.calls > 1 ? " ×\(bird.calls)" : ""
    }

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
