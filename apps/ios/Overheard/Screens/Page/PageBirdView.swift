import OverheardKit
import SwiftUI

/// A bird on the journal page: its drawing, tilted a little as if sketched by hand. Tapping it
/// shows its name for a few seconds; on the live page a new bird shows its name once on arrival.
/// `JournalPage` decides where it goes, how big it is and how it's tilted.
struct PageBirdView: View {
    let bird: PageBird
    let placement: PageLayout.Placement
    /// The whole page, so a name near an edge stays on the page.
    let pageSize: CGSize
    /// Show the name when the bird is first drawn (and when a sketch is confirmed).
    let introducesItself: Bool

    @Environment(\.theme) private var theme
    @Environment(\.pageStyle) private var style
    @AppStorage("hasTappedABird") private var hasTappedABird = false

    @State private var isNameShown = false
    @State private var hideName: Task<Void, Never>?

    var body: some View {
        let tag = tagPlacement

        drawing
            .frame(width: art.width, height: art.height)
            .overlay(alignment: tag.anchor) {
                if isNameShown {
                    NameTag(bird: bird)
                        .fixedSize()
                        .alignmentGuide(tag.anchor.vertical) { tag.guide($0) }
                        .transition(.opacity)
                }
            }
            .rotationEffect(.degrees(placement.tilt))
            .position(x: art.midX, y: art.midY)
            .zIndex(isNameShown ? 1 : 0)  // a shown name sits over neighbors
            .contentShape(Rectangle())
            .onTapGesture { showName(tapped: true) }
            .onAppear { if introducesItself { showName() } }
            .onChange(of: bird.isSketching) { _, isSketching in
                if !isSketching && introducesItself { showName() }  // a sketch just became a bird
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            .accessibilityAddTraits(.isButton)
    }

    private var art: CGRect { placement.art }

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

    // MARK: - Name

    /// Shows the name, then fades it after the style's `nameShowsFor` seconds. Tapping again
    /// restarts the clock.
    private func showName(tapped: Bool = false) {
        if tapped { hasTappedABird = true }
        withAnimation(.easeOut(duration: 0.25)) { isNameShown = true }

        hideName?.cancel()
        hideName = Task {
            try? await Task.sleep(for: .seconds(style.nameShowsFor))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.6)) { isNameShown = false }
        }
    }

    /// Where the name hangs: under the bird, or above it when the bird is near the bottom; lined
    /// up with the bird's left or right edge when it's near a side of the page.
    private var tagPlacement: TagPlacement {
        let below = art.maxY + 70 < pageSize.height
        let horizontal: HorizontalAlignment =
            art.midX < 110 ? .leading : (art.midX > pageSize.width - 110 ? .trailing : .center)
        return TagPlacement(below: below, horizontal: horizontal)
    }

    private var accessibilityText: String {
        let name = bird.species.commonName
        if bird.isSketching { return "\(name), still being sketched" }

        let times = bird.calls == 1 ? "once" : "\(bird.calls) times"
        return bird.hasFlourish ? "\(name), heard \(times), unusual here" : "\(name), heard \(times)"
    }
}

/// How a name tag hangs off its bird's drawing.
private struct TagPlacement: Sendable {
    let below: Bool
    let horizontal: HorizontalAlignment

    /// The drawing's edge the tag attaches to.
    var anchor: Alignment { Alignment(horizontal: horizontal, vertical: below ? .bottom : .top) }

    /// Moves the tag's far edge onto that anchor, so it hangs outside the drawing, not over it.
    func guide(_ tag: ViewDimensions) -> CGFloat {
        below ? tag[.top] - 2 : tag[.bottom] + 2
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
