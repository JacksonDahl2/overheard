import Foundation

/// A species heard during a session.
public struct HeardBird: Identifiable, Sendable, Equatable {
    public var id: String { species.code }
    public let species: Species
    /// Separate songs or bursts of calls heard. Drives the bird's size on the journal page.
    public var calls: Int
    public var bestConfidence: Float
    public var firstHeard: Date
    /// When the species was last detected (the end of the latest clip it was in).
    public var lastHeard: Date
}

/// Turns per-clip detections into the running tally of birds heard. Pure value type, so the
/// app and the eval harness share it and it's unit-tested without a model.
///
/// Clips overlap (a 3 s clip every 1 s), so one song shows up in several clips in a row.
/// Detections of a species no more than `callGap` apart are one call; a longer silence
/// from that species starts a new one.
public struct DetectionSession: Sendable, Equatable {
    /// Default gap that splits calls, for clips 1 s apart: back-to-back clips (1 s) and a single
    /// missed clip (2 s) stay one call; two or more missed clips start a new one.
    public static let defaultCallGap: TimeInterval = 2.5

    public let callGap: TimeInterval
    public private(set) var byCode: [String: HeardBird] = [:]

    public init(callGap: TimeInterval = DetectionSession.defaultCallGap) {
        self.callGap = callGap
    }

    /// Birds ordered for display: most calls first, then earliest heard.
    public var birds: [HeardBird] {
        byCode.values.sorted { $0.calls == $1.calls ? $0.firstHeard < $1.firstHeard : $0.calls > $1.calls }
    }

    /// Records one clip's reportable scores. `time` is when the clip ended; clips must arrive in order.
    public mutating func record(_ scores: [BirdScore], at time: Date) {
        // Lumped species share a code; count each species once per clip.
        var best: [String: BirdScore] = [:]
        for score in scores where score.confidence > (best[score.species.code]?.confidence ?? -1) {
            best[score.species.code] = score
        }
        for (code, score) in best {
            if var bird = byCode[code] {
                if time.timeIntervalSince(bird.lastHeard) > callGap { bird.calls += 1 }
                bird.bestConfidence = max(bird.bestConfidence, score.confidence)
                bird.lastHeard = time
                byCode[code] = bird
            } else {
                byCode[code] = HeardBird(
                    species: score.species, calls: 1, bestConfidence: score.confidence, firstHeard: time,
                    lastHeard: time)
            }
        }
    }
}
