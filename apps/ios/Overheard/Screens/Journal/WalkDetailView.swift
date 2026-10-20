import OverheardKit
import SwiftUI

/// A finished walk: its journal page, the route on a map, and the facts.
/// The page is the same one drawn live on Listen, now complete.
struct WalkDetailView: View {
    let walk: Walk
    let catalog: SpeciesCatalog?

    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                title

                JournalPage(
                    seed: walk.id.uuidString,
                    dateLine: Formatting.pageDate(walk.startedAt),
                    birds: pageBirds,
                    emptyNote: "No birds on this walk"
                )
                .frame(height: 520)

                if walk.route.points.count > 0 {
                    RouteMap(route: walk.route)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                facts
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 24)
        }
        .background(theme.chromeBackground.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Pieces

    private var title: some View {
        Text(walk.title)
            .font(.display(28))
            .foregroundStyle(theme.chromeInk)
            .padding(.horizontal, 10)
    }

    /// "6 species · 14 calls · 42 min · 1.6 mi", and a note if the walk was cut short.
    private var facts: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(
                [
                    Formatting.count(walk.birds.count, "species", "species"),
                    Formatting.count(walk.birds.reduce(0) { $0 + $1.calls }, "call", "calls"),
                    Formatting.duration(walk.duration),
                    Formatting.distance(walk.route.distance),
                ].joined(separator: " · ")
            )
            .font(.body(17))
            .foregroundStyle(theme.chromeInk)

            if walk.interrupted {
                Text("This walk was cut short: the app was closed before it ended.")
                    .font(.body(15))
                    .foregroundStyle(theme.chromeSoft)
            }
        }
        .padding(.horizontal, 10)
    }

    // MARK: - Birds

    /// The walk's birds in first-heard order, named from the catalog.
    private var pageBirds: [PageBird] {
        walk.birds
            .sorted { $0.firstHeard < $1.firstHeard }
            .map { PageBird($0, species: species($0.speciesCode)) }
    }

    /// A code this model doesn't know still shows, as its code.
    private func species(_ code: String) -> Species {
        catalog?.species(code: code) ?? Species(code: code, commonName: code, scientificName: "", isBird: true)
    }
}
