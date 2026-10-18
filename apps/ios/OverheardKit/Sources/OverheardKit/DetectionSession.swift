import Foundation

/// A species heard during a session.
public struct HeardBird: Identifiable, Sendable, Equatable {
    public var id: String { species.code }
    public let species: Species
    public var calls: Int
    public var bestConfidence: Float
    public var firstHeard: Date
    public var lastHeard: Date
}

/// Turns per-clip detections into the running tally of birds heard. Pure value type, so the
/// app and the eval harness share it and it's unit-tested without a model.
///
/// Today every clip a species is reported in counts as one call. (Merging back-to-back
/// clips into a single call is step 3 of the detection-quality plan.)
public struct DetectionSession: Sendable, Equatable {
    public private(set) var byCode: [String: HeardBird] = [:]

    public init() {}

    /// Birds ordered for display: most calls first, then earliest heard.
    public var birds: [HeardBird] {
        byCode.values.sorted { $0.calls == $1.calls ? $0.firstHeard < $1.firstHeard : $0.calls > $1.calls }
    }

    /// Records one clip's reportable scores, heard at `time`.
    public mutating func record(_ scores: [BirdScore], at time: Date) {
        // Lumped species share a code; count each species once per clip.
        var best: [String: BirdScore] = [:]
        for score in scores where score.confidence > (best[score.species.code]?.confidence ?? -1) {
            best[score.species.code] = score
        }
        for (code, score) in best {
            if var bird = byCode[code] {
                bird.calls += 1
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
