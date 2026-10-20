import OverheardKit
import SwiftData
import SwiftUI

/// The Journal tab: every finished walk, newest first. Each opens to its journal page.
struct WalksScreen: View {
    @Bindable var listener: Listener

    @Query(filter: #Predicate<Walk> { $0.endedAt != nil }, sort: \Walk.startedAt, order: .reverse)
    private var walks: [Walk]

    @Environment(\.theme) private var theme

    var body: some View {
        NavigationStack {
            List {
                if walks.isEmpty {
                    Text("Your walks will be kept here.")
                        .font(.body(17))
                        .foregroundStyle(theme.chromeSoft)
                        .listRowBackground(Color.clear)
                }

                ForEach(walks) { walk in
                    NavigationLink {
                        WalkDetailView(walk: walk, catalog: listener.catalog)
                    } label: {
                        WalkRow(walk: walk)
                    }
                    .listRowBackground(theme.chromeBackground)
                }
                .onDelete { offsets in
                    for i in offsets { listener.delete(walks[i]) }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(theme.chromeBackground.ignoresSafeArea())
            .navigationTitle("Journal")
        }
    }
}

/// One walk in the list: its name, when, and what it found.
struct WalkRow: View {
    let walk: Walk

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(walk.title)
                .font(.display(21))
                .foregroundStyle(theme.chromeInk)

            Text(summary)
                .font(.body(15))
                .foregroundStyle(theme.chromeSoft)
        }
        .padding(.vertical, 4)
    }

    /// "Sat 18 Oct · 6 species · 42 min · 1.6 mi"
    private var summary: String {
        [
            walk.startedAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)),
            Formatting.count(walk.birds.count, "species", "species"),
            Formatting.duration(walk.duration),
            Formatting.distance(walk.route.distance),
        ].joined(separator: " · ")
    }
}
