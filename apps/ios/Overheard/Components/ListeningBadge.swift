import SwiftUI

/// "● Listening" in the accent color, with a softly pulsing dot. Shows "Paused" when paused.
struct ListeningBadge: View {
    let isPaused: Bool

    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isPaused ? theme.chromeSoft : theme.accent)
                .frame(width: 8, height: 8)
                .background(Circle().fill(theme.accentHalo).padding(-4).opacity(pulse ? 1 : 0.3))

            Text(isPaused ? "Paused" : "Listening")
                .smallCapsLabel(15)
        }
        .foregroundStyle(isPaused ? theme.chromeSoft : theme.accent)
        .onAppear { startPulse() }
        .onChange(of: isPaused) { startPulse() }
        .accessibilityElement(children: .combine)
    }

    private func startPulse() {
        guard !isPaused, !reduceMotion else {
            pulse = false
            return
        }
        withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulse = true }
    }
}
