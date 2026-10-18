import Foundation
import Observation
import OverheardKit

/// A species heard during the current session.
struct HeardBird: Identifiable {
    let id: Int  // BirdNET label index
    let commonName: String
    let scientificName: String
    var calls: Int
    var bestConfidence: Float
    var firstHeard: Date
    var lastHeard: Date
}

/// Drives a listening session: mic → BirdNET → running tally of birds.
@MainActor
@Observable
final class Listener {
    var isListening = false
    var errorMessage: String?

    var birds: [HeardBird] = []
    var lastClip: [BirdScore] = []
    var lastLevel: Float = 0
    var lastInferenceMs: Double = 0
    var clipsAnalyzed = 0
    var startedAt: Date?

    // Tuning knobs for field testing.
    var rules = DetectionRules()
    var quietThreshold: Float = 0.002  // RMS below this skips inference

    private let capture = AudioCapture()
    private var classifier: BirdClassifier?
    private let inferenceQueue = DispatchQueue(label: "app.overheardbirds.inference", qos: .userInitiated)

    func toggle() {
        isListening ? stop() : start()
    }

    func start() {
        errorMessage = nil
        do {
            if classifier == nil { classifier = try BirdClassifier.bundled() }
            capture.onClip = { [weak self] clip, level in
                self?.inferenceQueue.async { self?.analyze(clip, level: level) }
            }
            try capture.start()
            birds = []
            lastClip = []
            clipsAnalyzed = 0
            startedAt = .now
            isListening = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stop() {
        capture.stop()
        isListening = false
    }

    // Runs on inferenceQueue.
    nonisolated private func analyze(_ clip: [Float], level: Float) {
        let (classifier, rules, quiet) = MainActor.assumeIsolatedOrSync {
            (self.classifier, self.rules, self.quietThreshold)
        }
        guard let classifier else { return }
        if level < quiet {
            Task { @MainActor in self.record([], level: level, ms: 0) }
            return
        }

        let started = CFAbsoluteTimeGetCurrent()
        let scores =
            (try? classifier.classify(clip, date: .now, rules: rules)) ?? []
        let ms = (CFAbsoluteTimeGetCurrent() - started) * 1000
        Task { @MainActor in self.record(scores, level: level, ms: ms) }
    }

    private func record(_ scores: [BirdScore], level: Float, ms: Double) {
        lastClip = scores
        lastLevel = level
        if ms > 0 { lastInferenceMs = ms }
        clipsAnalyzed += 1

        let now = Date.now
        for score in scores {
            if let i = birds.firstIndex(where: { $0.id == score.index }) {
                birds[i].calls += 1
                birds[i].bestConfidence = max(birds[i].bestConfidence, score.confidence)
                birds[i].lastHeard = now
            } else {
                birds.append(
                    HeardBird(
                        id: score.index, commonName: score.commonName, scientificName: score.scientificName,
                        calls: 1, bestConfidence: score.confidence, firstHeard: now, lastHeard: now))
            }
        }
        birds.sort { $0.calls == $1.calls ? $0.firstHeard < $1.firstHeard : $0.calls > $1.calls }
    }
}

extension MainActor {
    /// Reads main-actor state from a background queue.
    fileprivate static func assumeIsolatedOrSync<T: Sendable>(_ body: @MainActor () -> T) -> T {
        if Thread.isMainThread { return MainActor.assumeIsolated(body) }
        return DispatchQueue.main.sync { MainActor.assumeIsolated(body) }
    }
}
