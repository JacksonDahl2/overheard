import Foundation
import Observation
import OverheardKit

/// UI state for a walk. The detection work happens in `ListeningPipeline` (an actor in
/// OverheardKit); this class feeds it clips and locations, publishes what comes back, and
/// saves the walk through `WalkStore` as it goes.
@MainActor
@Observable
final class Listener {
    var isListening = false
    var errorMessage: String?
    /// The walk being recorded (nil between walks).
    private(set) var walk: Walk?
    /// For showing saved walks, which store species codes only.
    let catalog: SpeciesCatalog?

    var birds: [HeardBird] = []
    var pending: [PendingBird] = []  // heard, not yet confirmed ("sketching…")
    var lastClip: [BirdScore] = []
    var lastLevel: Float = 0
    var noiseFloor: Float?
    var clipsSeen = 0
    var lastInferenceMs: Double = 0
    var clipsAnalyzed = 0
    var startedAt: Date?
    var location: LocationProvider.Status = .idle

    // Tuning knobs for field testing; pushed to the pipeline when they change.
    var rules = DetectionRules() { didSet { pushSettings() } }
    /// Skip clips with nothing above the background (saves battery). Off analyzes every clip.
    var useGate = false { didSet { pushSettings() } }  // off until battery is measured on a device

    private let capture = AudioCapture()
    private let locationProvider = LocationProvider()
    private let store: WalkStore
    private var pipeline: ListeningPipeline?
    private var listening: Task<Void, Never>?

    init(store: WalkStore) {
        self.store = store
        catalog = try? SpeciesCatalog(contentsOf: BirdNETResources.bundled().catalog)
        do {
            try store.closeInterruptedWalks()  // the app was killed mid-walk last time
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func start() {
        guard !isListening else { return }
        errorMessage = nil
        do {
            let pipeline = try self.pipeline ?? ListeningPipeline(resources: .bundled())
            self.pipeline = pipeline
            try capture.start()
            walk = try store.startWalk()
            birds = []
            pending = []
            lastClip = []
            clipsAnalyzed = 0
            clipsSeen = 0
            startedAt = .now
            isListening = true

            locationProvider.onChange = { [weak self] status in self?.locationChanged(status) }
            locationProvider.onFix = { [weak self] fix in self?.addToRoute(fix) }
            locationProvider.start()

            let clips = capture.clips
            let rules = rules
            let gate = gateConfig
            listening = Task { [weak self] in
                await pipeline.configure(rules: rules, gate: gate)
                await pipeline.reset()
                for await clip in clips {
                    do {
                        let update = try await pipeline.process(clip.samples, at: clip.time)
                        self?.apply(update, at: clip.time)
                    } catch {
                        self?.errorMessage = error.localizedDescription
                    }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Ends the walk and saves it.
    func stop() {
        guard isListening else { return }
        capture.stop()
        locationProvider.stop()
        listening?.cancel()
        listening = nil
        isListening = false
        guard let walk else { return }
        self.walk = nil
        do {
            try store.record(birds, in: walk, at: .now)
            try store.endWalk(walk)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Saves whatever is pending (call when the app goes to the background).
    func saveNow() {
        do { try store.save() } catch { errorMessage = error.localizedDescription }
    }

    func delete(_ walk: Walk) {
        do { try store.delete(walk) } catch { errorMessage = error.localizedDescription }
    }

    private func apply(_ update: PipelineUpdate, at time: Date) {
        if let walk {
            do {
                try store.record(update.birds, in: walk, at: time)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        birds = update.birds
        pending = update.pending
        lastClip = update.lastClip
        lastLevel = update.level
        noiseFloor = update.noiseFloor
        clipsSeen = update.clipsSeen
        if let ms = update.inferenceMs { lastInferenceMs = ms }
        clipsAnalyzed = update.clipsAnalyzed
    }

    private func addToRoute(_ fix: RoutePoint) {
        guard let walk else { return }
        do { try store.addRoutePoint(fix, to: walk) } catch { errorMessage = error.localizedDescription }
    }

    private func locationChanged(_ status: LocationProvider.Status) {
        location = status
        guard let pipeline else { return }
        Task {
            switch status {
            case .located(let place):
                do {
                    try await pipeline.updateLocation(place)
                } catch {
                    errorMessage = error.localizedDescription
                }
            case .denied:
                await pipeline.clearLocation()
            case .idle, .waiting, .unavailable:
                break  // keep the last known location
            }
        }
    }

    private var gateConfig: AdaptiveGate.Config? { useGate ? AdaptiveGate.Config() : nil }

    private func pushSettings() {
        guard let pipeline else { return }
        let rules = rules
        let gate = gateConfig
        Task { await pipeline.configure(rules: rules, gate: gate) }
    }
}
