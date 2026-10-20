import OverheardKit
import SwiftUI

/// The journal page: paper, a handwritten date line, and the birds laid out by `PageLayout`.
/// Each bird's size is its call count (`BirdSize`); nothing else changes how big it is.
struct JournalPage: View {
    let dateLine: String?
    let birds: [PageBird]
    /// Shown in the middle of an empty page.
    let emptyNote: String

    @Environment(\.theme) private var theme

    // Page geometry, in points.
    private static let margin: CGFloat = 14
    private static let dateLineHeight: CGFloat = 34
    private static let smallestArt: CGFloat = 76
    private static let largestArt: CGFloat = 240
    /// Labels stay at least this wide, so a small bird's name doesn't wrap word by word.
    private static let smallestLabel: CGFloat = 104
    /// How much a handful of birds may grow to fill an empty page.
    private static let fillScale = 1.4

    var body: some View {
        GeometryReader { geometry in
            let bounds = birdArea(in: geometry.size)
            let items = birds.map { item(for: $0, pageWidth: bounds.width) }
            let layout = PageLayout(items: items, in: bounds, maxScale: Self.fillScale)

            ZStack(alignment: .topLeading) {
                if let dateLine {
                    Text(dateLine)
                        .font(.hand(19))
                        .foregroundStyle(theme.pageSoft)
                        .padding(.horizontal, Self.margin + 4)
                        .padding(.top, Self.margin)
                }

                ForEach(birds) { bird in
                    if let placement = layout.placements[bird.id] {
                        PageBirdView(bird: bird, placement: placement)
                    }
                }

                if birds.isEmpty {
                    emptyState.frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
            .animation(.spring(duration: 0.9, bounce: 0.15), value: birds)
        }
        .background(paper)
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

    private func item(for bird: PageBird, pageWidth: CGFloat) -> PageLayout.Item {
        let largest = min(Self.largestArt, pageWidth * 0.62)
        let side = max(Self.smallestArt, largest * BirdSize.fraction(calls: bird.calls))
        return PageLayout.Item(
            id: bird.id, side: side, labelHeight: labelHeight(for: bird), labelWidth: Self.smallestLabel)
    }

    /// Two lines of handwriting for a name; more for a sketch's "sketching…" or a flourish.
    private func labelHeight(for bird: PageBird) -> Double {
        if bird.isSketching { return 58 }
        return bird.hasFlourish ? 78 : 42
    }

    // MARK: - Pieces

    private var paper: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(theme.page)
            .shadow(color: theme.pageShadow, radius: theme.pageShadowRadius, y: 4)
    }

    private var emptyState: some View {
        Text(emptyNote)
            .font(.hand(22))
            .multilineTextAlignment(.center)
            .foregroundStyle(theme.pageSoft)
            .padding(40)
    }
}
