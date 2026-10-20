import OverheardKit
import SwiftUI

/// Tuning controls and live stats for field testing (apps/ios/README.md checklist).
struct FieldTestView: View {
    @Bindable var listener: Listener

    var body: some View {
        List {
            Section("Last 3 seconds") {
                if listener.lastClip.isEmpty {
                    Text("No birds above threshold").foregroundStyle(.secondary)
                }
                ForEach(listener.lastClip.prefix(5), id: \.index) { score in
                    HStack {
                        Text(score.species.commonName)
                        Spacer()
                        Text("\(Int(score.confidence * 100))%").monospacedDigit()
                    }
                }
            }

            Section("Tuning") {
                VStack(alignment: .leading) {
                    Text(
                        "Min confidence (common birds; rarer need more): \(Int(listener.rules.minConfidence * 100))%"
                    )
                    Slider(value: $listener.rules.minConfidence, in: 0.1...0.95, step: 0.05)
                }
                Toggle("Only birds expected here this week", isOn: $listener.rules.useLocationFilter)
                Toggle("Skip clips with nothing above the background", isOn: $listener.useGate)
            }

            Section("Stats") {
                LabeledContent("Clips analyzed", value: clipsSummary)
                LabeledContent("Inference", value: String(format: "%.0f ms", listener.lastInferenceMs))
                LabeledContent("Bird-band level", value: String(format: "%.4f", listener.lastLevel))
                LabeledContent(
                    "Background", value: listener.noiseFloor.map { String(format: "%.4f", $0) } ?? "learning…")
                LabeledContent("Location", value: locationSummary)
                LabeledContent("BirdNET week", value: "\(SpeciesFilter.birdNETWeek(for: .now))")
                if let started = listener.startedAt {
                    LabeledContent("Started", value: started.formatted(date: .omitted, time: .shortened))
                }
            }

            Section("Credits") {
                Text(
                    "Bird identification by BirdNET (K. Lisa Yang Center for Conservation Bioacoustics, "
                        + "Cornell Lab of Ornithology, and Chemnitz University of Technology), "
                        + "used under CC BY-NC-SA 4.0. Species names from the eBird/Clements taxonomy."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Field-test tools")
    }

    private var clipsSummary: String {
        guard listener.clipsSeen > 0 else { return "0" }
        let skipped = 100 * (listener.clipsSeen - listener.clipsAnalyzed) / listener.clipsSeen
        return "\(listener.clipsAnalyzed) of \(listener.clipsSeen) (\(skipped)% skipped)"
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
