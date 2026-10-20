import OverheardKit
import SwiftData
import SwiftUI

/// Bare-bones spike UI: start/end a walk, live detections, and past walks.
/// The real parchment design comes later (docs/design.md).
struct ListenView: View {
    @Bindable var listener: Listener
    @Query(sort: \Walk.startedAt, order: .reverse) private var walks: [Walk]
    @State private var confirmingEnd = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if listener.isListening {
                        Button("End walk", role: .destructive) { confirmingEnd = true }
                            .font(.headline)
                            .confirmationDialog("End this walk?", isPresented: $confirmingEnd) {
                                Button("End walk", role: .destructive) { listener.stop() }
                            }
                        if let walk = listener.walk { WalkProgress(walk: walk) }
                    } else {
                        Button("Start walk") { listener.start() }.font(.headline)
                    }
                    if let error = listener.errorMessage {
                        Text(error).foregroundStyle(.red)
                    }
                    if let note = locationNote {
                        Text(note).font(.callout).foregroundStyle(.secondary)
                    }
                }

                if listener.isListening {
                    Section("Heard") {
                        if listener.birds.isEmpty {
                            Text("Listening…").foregroundStyle(.secondary)
                        }
                        ForEach(listener.birds) { bird in
                            BirdRow(
                                species: bird.species, calls: bird.calls, confidence: bird.bestConfidence,
                                commonness: bird.commonness)
                        }
                    }

                    if !listener.pending.isEmpty {
                        // In the real UI these are the faint birds being sketched: they finish drawing
                        // when confirmed, or fade if the call ends first.
                        Section("Sketching…") {
                            ForEach(listener.pending) { bird in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(bird.species.commonName).foregroundStyle(.secondary)
                                        if let note = BirdRow.note(for: bird.commonness) {
                                            Text(note).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Text(
                                        "\(Int(bird.peakConfidence * 100))% · \(bird.clips) clip\(bird.clips == 1 ? "" : "s")"
                                    )
                                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section("Walks") {
                    let past = walks.filter { !$0.isActive }
                    if past.isEmpty {
                        Text("No walks yet").foregroundStyle(.secondary)
                    }
                    ForEach(past) { walk in
                        NavigationLink {
                            WalkDetailView(walk: walk, catalog: listener.catalog)
                        } label: {
                            WalkRow(walk: walk)
                        }
                    }
                    .onDelete { offsets in
                        for i in offsets { listener.delete(past[i]) }
                    }
                }

                Section {
                    NavigationLink("Field-test tools") { FieldTestView(listener: listener) }
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
}

/// Time and distance so far, ticking once a second.
private struct WalkProgress: View {
    let walk: Walk

    var body: some View {
        TimelineView(.periodic(from: walk.startedAt, by: 1)) { context in
            LabeledContent(
                Duration.seconds(context.date.timeIntervalSince(walk.startedAt))
                    .formatted(.time(pattern: .hourMinuteSecond)),
                value: WalkRow.distance(walk.route.distance))
        }
        .monospacedDigit()
    }
}

/// One species: name, the rare-bird note, call count and best confidence.
struct BirdRow: View {
    let species: Species
    let calls: Int
    let confidence: Float
    let commonness: Commonness?

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(species.commonName)
                Text(species.scientificName).font(.caption).italic().foregroundStyle(.secondary)
                if let note = Self.note(for: commonness) {
                    Text(note).font(.caption).foregroundStyle(.red)
                }
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text("×\(calls)").monospacedDigit()
                Text("best \(Int(confidence * 100))%").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// The spike's stand-in for the rare-bird flourish (docs/design.md).
    static func note(for commonness: Commonness?) -> String? {
        switch commonness {
        case .unusual: "unusual here this time of year"
        case .uncommon: "uncommon here"
        case .common, nil: nil
        }
    }
}

struct WalkRow: View {
    let walk: Walk

    var body: some View {
        VStack(alignment: .leading) {
            Text(walk.startedAt.formatted(date: .abbreviated, time: .shortened))
            Text(summary).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var summary: String {
        let species = walk.birds.count
        return [
            "\(species) species",
            Duration.seconds(walk.duration).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)),
            Self.distance(walk.route.distance),
        ].joined(separator: " · ")
    }

    static func distance(_ meters: Double) -> String {
        Measurement(value: meters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }
}
