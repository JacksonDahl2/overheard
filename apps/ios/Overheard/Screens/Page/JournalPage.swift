import OverheardKit
import SwiftUI

/// The journal page: paper, a handwritten date line, and the birds laid out by `PageLayout`.
/// Each bird's size is its call count (`BirdSize`); nothing else changes how big it is.
/// The page shows only the drawings; tapping a bird shows its name for a moment.
struct JournalPage: View {
    /// Which page this is (the walk's id): each walk's birds are arranged their own way.
    let seed: String
    let dateLine: String?
    let birds: [PageBird]
    /// Shown in the middle of an empty page.
    let emptyNote: String
    /// The live Listen page: a newly drawn bird shows its name for a moment.
    var isLive = false

    @Environment(\.theme) private var theme
    @Environment(\.pageStyle) private var style
    @AppStorage("hasTappedABird") private var hasTappedABird = false
    /// Birds already on the page when it opens don't introduce themselves; only new arrivals do.
    @State private var hasSettled = false

    // Page margins, in points.
    private static let margin: CGFloat = 14
    private static let dateLineHeight: CGFloat = 34

    var body: some View {
        GeometryReader { geometry in
            let bounds = birdArea(in: geometry.size)
            let items = birds.map { item(for: $0, pageWidth: bounds.width) }
            let layout = PageLayout(items: items, in: bounds, maxScale: style.fillScale, seed: seed, style: style)

            ZStack(alignment: .topLeading) {
                if let dateLine { dateText(dateLine) }

                ForEach(birds) { bird in
                    if let placement = layout.placements[bird.id] {
                        PageBirdView(
                            bird: bird, placement: placement, pageSize: geometry.size,
                            introducesItself: isLive && style.introducesNewBirds && hasSettled)
                    }
                }

                if birds.isEmpty {
                    emptyState.frame(width: geometry.size.width, height: geometry.size.height)
                } else if !hasTappedABird {
                    tapHint.frame(width: geometry.size.width, height: geometry.size.height, alignment: .bottomTrailing)
                }
            }
            .animation(.spring(duration: 0.9, bounce: 0.15), value: birds)
        }
        .background(paper)
        .task {
            try? await Task.sleep(for: .seconds(1))
            hasSettled = true
        }
    }

    // MARK: - Layout

    /// The page minus its margins and the date line.
    private func birdArea(in size: CGSize) -> CGRect {
        CGRect(
            x: Self.margin,
            y: Self.margin + Self.dateLineHeight,
            width: max(0, size.width - Self.margin * 2),
            height: max(0, size.height - Self.margin * 2 - Self.dateLineHeight))
    }

    /// A bird's drawing size: its share of full size, from its calls, within the style's limits.
    private func item(for bird: PageBird, pageWidth: CGFloat) -> PageLayout.Item {
        let largest = min(style.largestBird, pageWidth * style.largestBirdPageFraction)
        let side = max(style.smallestBird, largest * BirdSize.fraction(calls: bird.calls, style: style))
        return PageLayout.Item(id: bird.id, side: side)
    }

    // MARK: - Pieces

    private var paper: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(theme.page)
            .shadow(color: theme.pageShadow, radius: theme.pageShadowRadius, y: 4)
    }

    private func dateText(_ line: String) -> some View {
        Text(line)
            .font(.hand(19))
            .foregroundStyle(theme.pageSoft)
            .padding(.horizontal, Self.margin + 4)
            .padding(.top, Self.margin)
    }

    private var emptyState: some View {
        Text(emptyNote)
            .font(.hand(22))
            .multilineTextAlignment(.center)
            .foregroundStyle(theme.pageSoft)
            .padding(40)
    }

    /// Until the first tap, a quiet note in the corner says how to see names.
    private var tapHint: some View {
        Text("tap a bird for its name")
            .font(.hand(16))
            .foregroundStyle(theme.pageSoft)
            .padding(.horizontal, Self.margin + 4)
            .padding(.bottom, Self.margin)
            .allowsHitTesting(false)
    }
}
