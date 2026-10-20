import OverheardKit
import SwiftUI

/// The Listen tab: before a walk, an invitation to start one; during a walk, the live journal
/// page with birds drawn as they're heard (design/mockups/Main.dc.html).
struct ListenScreen: View {
    @Bindable var listener: Listener

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            if let walk = listener.walk {
                walking(walk)
            } else {
                readyToWalk
            }
        }
        .padding(.top, 12)
        .background(theme.chromeBackground.ignoresSafeArea())
    }

    // MARK: - During a walk

    private func walking(_ walk: Walk) -> some View {
        VStack(spacing: 10) {
            ListenHeader(walk: walk, isPaused: listener.phase == .paused, levels: listener.levels)
                .padding(.horizontal, 22)

            JournalPage(
                dateLine: Formatting.pageDate(walk.startedAt),
                birds: PageBird.onPage(birds: listener.birds, pending: listener.pending),
                emptyNote: "Listening…\nthe birds you hear\nwill be sketched here"
            )
            .padding(.horizontal, 12)

            errorLine

            ListenFooter(
                justHeard: listener.justHeard,
                species: listener.birds.count,
                calls: listener.birds.reduce(0) { $0 + $1.calls },
                meters: walk.route.distance,
                isPaused: listener.phase == .paused,
                onPauseOrResume: { listener.phase == .paused ? listener.resume() : listener.pause() },
                onEnd: listener.endWalk
            )
            .padding(.horizontal, 22)
            .padding(.bottom, 12)
        }
    }

    // MARK: - Before a walk

    private var readyToWalk: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Ready when you are").smallCapsLabel(15).foregroundStyle(theme.accent)
                Text(WalkTitle.default(for: .now)).font(.display(30)).foregroundStyle(theme.chromeInk)
            }
            .padding(.horizontal, 22)

            JournalPage(
                dateLine: Formatting.pageDate(.now),
                birds: [],
                emptyNote: "Start a walk, and the birds you hear\nwill be drawn on this page"
            )
            .padding(.horizontal, 12)

            errorLine

            Button("Start walk", action: listener.startWalk)
                .buttonStyle(.primaryPill)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 12)
        }
    }

    // MARK: - Shared

    @ViewBuilder
    private var errorLine: some View {
        if let message = listener.errorMessage {
            Text(message)
                .font(.body(15))
                .foregroundStyle(theme.accent)
                .padding(.horizontal, 22)
        }
    }
}
