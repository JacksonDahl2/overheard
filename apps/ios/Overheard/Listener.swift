import Foundation
import Observation
import OverheardKit

/// UI state for a listening session. The detection work happens in `ListeningPipeline`
/// (an actor in OverheardKit); this class only feeds it clips and locations and publishes
/// what comes back.
@MainActor
@Observable
final class Listener {
    var isListening = false
    var errorMessage: String?

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
    private var pipeline: ListeningPipeline?
    private var listening: Task<Void, Never>?

    func toggle() {
        isListening ? stop() : start()
    }

    func start() {
        errorMessage = nil
        do {
            let pipeline = try self.pipeline ?? ListeningPipeline(resources: .bundled())
            self.pipeline = pipeline
            try capture.start()
            birds = []
            pending = []
            lastClip = []
            clipsAnalyzed = 0
            clipsSeen = 0
            startedAt = .now
            isListening = true

            locationProvider.onChange = { [weak self] status in self?.locationChanged(status) }
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
                        self?.apply(update)
                    } catch {
                        self?.errorMessage = error.localizedDescription
                    }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stop() {
        capture.stop()
        locationProvider.stop()
        listening?.cancel()
        listening = nil
        isListening = false
    }

    private func apply(_ update: PipelineUpdate) {
        birds = update.birds
        pending = update.pending
        lastClip = update.lastClip
        lastLevel = update.level
        noiseFloor = update.noiseFloor
        clipsSeen = update.clipsSeen
        if let ms = update.inferenceMs { lastInferenceMs = ms }
        clipsAnalyzed = update.clipsAnalyzed
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
