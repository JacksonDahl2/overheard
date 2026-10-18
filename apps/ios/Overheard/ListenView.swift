import OverheardKit
import SwiftUI

/// Bare-bones spike UI: start/stop, live detections, and tuning controls.
/// The real parchment design comes later (docs/design.md).
struct ListenView: View {
    @Bindable var listener: Listener

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button(listener.isListening ? "Stop listening" : "Start listening") {
                        listener.toggle()
                    }
                    .font(.headline)
                    if let error = listener.errorMessage {
                        Text(error).foregroundStyle(.red)
                    }
                    if let note = locationNote {
                        Text(note).font(.callout).foregroundStyle(.secondary)
                    }
                }

                Section("Heard") {
                    if listener.birds.isEmpty {
                        Text(listener.isListening ? "Listening…" : "Nothing yet")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(listener.birds) { bird in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(bird.species.commonName)
                                Text(bird.species.scientificName).font(.caption).italic()
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text("×\(bird.calls)").monospacedDigit()
                                Text("best \(Int(bird.bestConfidence * 100))%").font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if !listener.pending.isEmpty {
                    // In the real UI these are the faint birds being sketched: they finish drawing
                    // when confirmed, or fade if the call ends first.
                    Section("Sketching…") {
                        ForEach(listener.pending) { bird in
                            HStack {
                                Text(bird.species.commonName).foregroundStyle(.secondary)
                                Spacer()
                                Text(
                                    "\(Int(bird.peakConfidence * 100))% · \(bird.clips) clip\(bird.clips == 1 ? "" : "s")"
                                )
                                .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                    }
                }

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
                        Text("Min confidence: \(Int(listener.rules.minConfidence * 100))%")
                        Slider(value: $listener.rules.minConfidence, in: 0.1...0.95, step: 0.05)
                    }
                    Toggle("Only birds expected here this week", isOn: $listener.rules.useLocationFilter)
                }

                Section("Stats") {
                    LabeledContent("Clips analyzed", value: "\(listener.clipsAnalyzed)")
                    LabeledContent("Inference", value: String(format: "%.0f ms", listener.lastInferenceMs))
                    LabeledContent("Level (RMS)", value: String(format: "%.4f", listener.lastLevel))
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
            .navigationTitle("Overheard")
        }
    }

    private var locationNote: String? {
        switch listener.location {
        case .denied: "Location is off, so every bird BirdNET hears is shown. Turn on location for more accurate IDs."
        case .unavailable: "Can't get your location right now; showing every bird BirdNET hears."
        case .idle, .waiting, .located: nil
        }
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
