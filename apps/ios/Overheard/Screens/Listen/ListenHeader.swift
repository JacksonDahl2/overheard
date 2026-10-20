import OverheardKit
import SwiftUI

/// The top of the Listen screen during a walk: "Listening" and the time walked, the walk's
/// name, and the level bars.
struct ListenHeader: View {
    let walk: Walk
    let isPaused: Bool
    let levels: LevelHistory

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                ListeningBadge(isPaused: isPaused)
                Spacer()
                elapsed
            }

            Text(walk.title)
                .font(.display(30))
                .foregroundStyle(theme.chromeInk)
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            LevelBars(history: levels)
                .padding(.top, 6)
        }
    }

    /// Time since the walk started, ticking every second: "0:42:18".
    private var elapsed: some View {
        TimelineView(.periodic(from: walk.startedAt, by: 1)) { context in
            Text(
                Duration.seconds(context.date.timeIntervalSince(walk.startedAt)),
                format: .time(pattern: .hourMinuteSecond)
            )
            .font(.body(17))
            .monospacedDigit()
            .foregroundStyle(theme.chromeSoft)
        }
        .accessibilityLabel("Time walked")
    }
}
