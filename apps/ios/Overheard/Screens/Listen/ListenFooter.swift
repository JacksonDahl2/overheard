import OverheardKit
import SwiftUI

/// The bottom of the Listen screen during a walk: what was just heard, the walk's totals,
/// and Pause / End walk.
struct ListenFooter: View {
    let justHeard: BirdScore?
    let species: Int
    let calls: Int
    let meters: Double
    let isPaused: Bool
    let onPauseOrResume: () -> Void
    let onEnd: () -> Void

    @Environment(\.theme) private var theme
    @State private var isConfirmingEnd = false

    var body: some View {
        VStack(spacing: 12) {
            if let justHeard { justHeardLine(justHeard) }

            HStack(spacing: 10) {
                totals
                Spacer(minLength: 0)

                Button(action: onPauseOrResume) {
                    Label(isPaused ? "Resume" : "Pause", systemImage: isPaused ? "play.fill" : "pause.fill")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.secondaryPill)

                Button("End walk") { isConfirmingEnd = true }
                    .buttonStyle(.primaryPill)
                    .confirmationDialog("End this walk?", isPresented: $isConfirmingEnd) {
                        Button("End walk", role: .destructive, action: onEnd)
                    } message: {
                        Text("It's saved to your journal.")
                    }
            }
        }
    }

    // MARK: - Pieces

    /// "Just heard  Black-throated Blue Warbler  94% sure"
    private func justHeardLine(_ score: BirdScore) -> some View {
        HStack(spacing: 10) {
            Text("Just heard").smallCapsLabel(15).foregroundStyle(theme.accent)

            Text(score.species.commonName)
                .font(.bodyItalic(15))
                .foregroundStyle(theme.chromeInk)
                .lineLimit(1)

            Spacer(minLength: 4)

            Text("\(Int(score.confidence * 100))% sure")
                .font(.body(15))
                .monospacedDigit()
                .foregroundStyle(theme.chromeSoft)
        }
        .accessibilityElement(children: .combine)
    }

    /// "6 species" over "14 calls · 1.6 mi"
    private var totals: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Formatting.count(species, "species", "species"))
                .font(.body(20, weight: .medium))
                .foregroundStyle(theme.chromeInk)

            Text("\(Formatting.count(calls, "call", "calls")) · \(Formatting.distance(meters))")
                .font(.body(14))
                .foregroundStyle(theme.chromeSoft)
        }
        .monospacedDigit()
        .accessibilityElement(children: .combine)
    }
}
