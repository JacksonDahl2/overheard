import OverheardKit
import SwiftUI

/// A bird's name, handwritten on a scrap of the page's own paper so it reads cleanly over any
/// neighbor: "Blue Jay ×3", "sketching… Black-throated Blue Warbler", or a rare bird's red note.
struct NameTag: View {
    let bird: PageBird

    @Environment(\.theme) private var theme
    @Environment(\.pageStyle) private var style

    var body: some View {
        VStack(spacing: 0) {
            if bird.isSketching {
                Text("sketching…").foregroundStyle(theme.accentOnPage)
                Text(bird.species.commonName).foregroundStyle(theme.accentOnPage)
            } else {
                (Text(bird.species.commonName) + Text(callCount).foregroundStyle(theme.pageSoft))
                    .foregroundStyle(theme.pageInk)
            }

            if bird.hasFlourish {
                Flourish(note: "unusual here this time of year")
                    .padding(.top, 2)
            }
        }
        .font(.hand(style.nameFontSize))
        .multilineTextAlignment(.center)
        .frame(maxWidth: 200)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(theme.pageStops.first?.color ?? .white)
                .opacity(0.9)
                .shadow(color: theme.pageShadow, radius: 2, y: 1)
        }
    }

    /// " ×3" after the name; a single call needs no count.
    private var callCount: String {
        bird.calls > 1 ? " ×\(bird.calls)" : ""
    }
}
