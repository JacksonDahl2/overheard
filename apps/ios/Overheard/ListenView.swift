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
                }

                Section("Heard") {
                    if listener.birds.isEmpty {
                        Text(listener.isListening ? "Listening…" : "Nothing yet")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(listener.birds) { bird in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(bird.commonName)
                                Text(bird.scientificName).font(.caption).italic().foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text("×\(bird.calls)").monospacedDigit()
                                Text("best \(Int(bird.bestConfidence * 100))%").font(.caption).foregroundStyle(.secondary)
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
                            Text(score.commonName)
                            Spacer()
                            Text("\(Int(score.confidence * 100))%").monospacedDigit()
                        }
                    }
                }

                Section("Tuning") {
                    VStack(alignment: .leading) {
                        Text("Min confidence: \(Int(listener.minConfidence * 100))%")
                        Slider(value: $listener.minConfidence, in: 0.1...0.95, step: 0.05)
                    }
                    Toggle("Central Park species filter", isOn: $listener.useLocationFilter)
                }

                Section("Stats") {
                    LabeledContent("Clips analyzed", value: "\(listener.clipsAnalyzed)")
                    LabeledContent("Inference", value: String(format: "%.0f ms", listener.lastInferenceMs))
                    LabeledContent("Level (RMS)", value: String(format: "%.4f", listener.lastLevel))
                    LabeledContent("BirdNET week", value: "\(BirdClassifier.birdNETWeek(for: .now))")
                    if let started = listener.startedAt {
                        LabeledContent("Started", value: started.formatted(date: .omitted, time: .shortened))
                    }
                }
            }
            .navigationTitle("Overheard")
        }
    }
}
