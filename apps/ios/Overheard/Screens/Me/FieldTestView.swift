import OverheardKit
import SwiftUI

/// Tuning controls and live numbers for field testing (apps/ios/README.md checklist).
/// A plain system list on purpose: it's a tool, not part of the journal.
struct FieldTestView: View {
    @Bindable var listener: Listener

    var body: some View {
        List {
            lastClipSection
            tuningSection
            statsSection
        }
        .navigationTitle("Field-test tools")
    }

    // MARK: - Sections

    private var lastClipSection: some View {
        Section("Last 3 seconds") {
            if listener.stats.lastClip.isEmpty {
                Text("No birds above threshold").foregroundStyle(.secondary)
            }
            ForEach(listener.stats.lastClip.prefix(5), id: \.index) { score in
                LabeledContent(score.species.commonName, value: "\(Int(score.confidence * 100))%")
                    .monospacedDigit()
            }
        }
    }

    private var tuningSection: some View {
        Section("Tuning") {
            VStack(alignment: .leading) {
                Text("Min confidence (common birds; rarer need more): \(Int(listener.rules.minConfidence * 100))%")
                Slider(value: $listener.rules.minConfidence, in: 0.1...0.95, step: 0.05)
            }
            Toggle("Only birds expected here this week", isOn: $listener.rules.useLocationFilter)
            Toggle("Skip clips with nothing above the background", isOn: $listener.useGate)
        }
    }

    private var statsSection: some View {
        Section("Stats") {
            LabeledContent("Clips analyzed", value: clipsSummary)
            LabeledContent("Inference", value: String(format: "%.0f ms", listener.stats.inferenceMs))
            LabeledContent("Bird-band level", value: String(format: "%.4f", listener.stats.level))
            LabeledContent(
                "Background", value: listener.stats.noiseFloor.map { String(format: "%.4f", $0) } ?? "learning…")
            LabeledContent("Location", value: locationSummary)
            LabeledContent("BirdNET week", value: "\(SpeciesFilter.birdNETWeek(for: .now))")
        }
        .monospacedDigit()
    }

    // MARK: - Formatting

    private var clipsSummary: String {
        let stats = listener.stats
        guard stats.clipsSeen > 0 else { return "0" }

        let skipped = 100 * (stats.clipsSeen - stats.clipsAnalyzed) / stats.clipsSeen
        return "\(stats.clipsAnalyzed) of \(stats.clipsSeen) (\(skipped)% skipped)"
    }

    private var locationSummary: String {
        switch listener.location {
        case .idle: "—"
        case .waiting: "Finding…"
        case .located(let place): String(format: "%.2f, %.2f", place.latitude, place.longitude)
        case .denied: "Off"
        case .unavailable: "Unavailable"
        }
    }
}
