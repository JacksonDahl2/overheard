import Foundation

/// A species heard (and confirmed) during a session.
public struct HeardBird: Identifiable, Sendable, Equatable {
    public var id: String { species.code }
    public let species: Species
    /// Separate confirmed songs or bursts of calls. Drives the bird's size on the journal page.
    public var calls: Int
    public var bestConfidence: Float
    /// Start of its first confirmed call.
    public var firstHeard: Date
    /// When the species was last detected (the end of the latest clip it was in).
    public var lastHeard: Date
    /// The rarest it was here across its confirmed calls (nil if the location was never known).
    /// `.unusual` gets the rare-bird flourish.
    public var commonness: Commonness?

    public init(
        species: Species, calls: Int, bestConfidence: Float, firstHeard: Date, lastHeard: Date,
        commonness: Commonness?
    ) {
        self.species = species
        self.calls = calls
        self.bestConfidence = bestConfidence
        self.firstHeard = firstHeard
        self.lastHeard = lastHeard
        self.commonness = commonness
    }
}

/// A new species BirdNET may be hearing but hasn't confirmed yet. In the app it's the faint
/// bird that's "being sketched": it finishes drawing when confirmed, or fades if the call ends first.
public struct PendingBird: Identifiable, Sendable, Equatable {
    public var id: String { species.code }
    public let species: Species
    public let clips: Int
    public let peakConfidence: Float
    public let since: Date
    public let commonness: Commonness?

    public init(species: Species, clips: Int, peakConfidence: Float, since: Date, commonness: Commonness?) {
        self.species = species
        self.clips = clips
        self.peakConfidence = peakConfidence
        self.since = since
        self.commonness = commonness
    }
}

/// When a call is believable enough to count.
public struct Confirmation: Sendable, Hashable {
    /// Clips above the confidence threshold a call needs to count…
    public var minClips: Int
    /// …unless one clip is at least this confident (catches short, clear single calls)…
    public var strongConfidence: Float
    /// …and at least this far above the bar the detection had to clear. Rarer species have a
    /// higher bar (`ConfidenceBar`), so one clip that barely clears it isn't enough on its own.
    public var strongMargin: Float

    /// Defaults chosen with overheard-eval (2026-10-18): at a 0.50 threshold they halve wrong
    /// species per recording (0.32 → 0.15) for ~6 points of recall. See ml/eval/README.md.
    public init(minClips: Int = 2, strongConfidence: Float = 0.7, strongMargin: Float = 0.15) {
        self.minClips = minClips
        self.strongConfidence = strongConfidence
        self.strongMargin = strongMargin
    }

    /// Every detection counts immediately (the behavior before confirmation existed).
    public static let none = Confirmation(minClips: 1, strongConfidence: 0, strongMargin: 0)

    /// - Parameter required: the highest bar any clip in the call had to clear.
    func confirms(clips: Int, peak: Float, required: Float) -> Bool {
        clips >= minClips || peak >= min(max(strongConfidence, required + strongMargin), 0.99)
    }
}

/// Turns per-clip detections into the running tally of birds heard. Pure value type, so the
/// app and the eval harness share it and it's unit-tested without a model.
///
/// - Clips overlap (a 3 s clip every 1 s), so one song shows up in several clips in a row.
///   Detections of a species no more than `callGap` apart are one call.
/// - A call only counts once it's confirmed (see `Confirmation`). A real song spans several
///   overlapping clips; a stray lookalike usually spans one.
public struct DetectionSession: Sendable, Equatable {
    /// Default gap that splits calls, for clips 1 s apart: back-to-back clips (1 s) and a single
    /// missed clip (2 s) stay one call; two or more missed clips start a new one.
    public static let defaultCallGap: TimeInterval = 2.5

    public let callGap: TimeInterval
    public let confirmation: Confirmation
    public private(set) var byCode: [String: HeardBird] = [:]
    private var calls: [String: Call] = [:]  // each species' current (most recent) call

    private struct Call: Sendable, Equatable {
        let species: Species
        var clips: Int
        var peak: Float
        var required: Float  // highest bar a clip in this call had to clear
        var commonness: Commonness?  // rarest seen in this call
        let start: Date
        var last: Date
        var confirmed: Bool
    }

    public init(callGap: TimeInterval = DetectionSession.defaultCallGap, confirmation: Confirmation = Confirmation()) {
        self.callGap = callGap
        self.confirmation = confirmation
    }

    /// Confirmed birds, ordered for display: most calls first, then earliest heard.
    public var birds: [HeardBird] {
        byCode.values.sorted { $0.calls == $1.calls ? $0.firstHeard < $1.firstHeard : $0.calls > $1.calls }
    }

    /// New species with a call in progress that isn't confirmed yet, earliest first.
    public var pending: [PendingBird] {
        calls.values
            .filter { !$0.confirmed && byCode[$0.species.code] == nil }
            .map {
                PendingBird(
                    species: $0.species, clips: $0.clips, peakConfidence: $0.peak, since: $0.start,
                    commonness: $0.commonness)
            }
            .sorted { $0.since < $1.since }
    }

    /// Records one clip's reportable scores. `time` is when the clip ended; clips must arrive in order.
    /// Call this for every clip, even ones with no birds, so finished calls are closed on time.
    public mutating func record(_ scores: [BirdScore], at time: Date) {
        advance(to: time)
        // Lumped species share a code; count each species once per clip.
        var best: [String: BirdScore] = [:]
        for score in scores where score.confidence > (best[score.species.code]?.confidence ?? -1) {
            best[score.species.code] = score
        }
        for (code, score) in best {
            var call =
                calls[code].flatMap { time.timeIntervalSince($0.last) <= callGap ? $0 : nil }
                ?? Call(
                    species: score.species, clips: 0, peak: 0, required: 0, commonness: nil, start: time, last: time,
                    confirmed: false)
            call.clips += 1
            call.peak = max(call.peak, score.confidence)
            call.required = max(call.required, score.requiredConfidence)
            call.commonness = Self.rarer(call.commonness, score.commonness)
            call.last = time

            if call.confirmed {
                if var bird = byCode[code] {
                    bird.bestConfidence = max(bird.bestConfidence, score.confidence)
                    bird.lastHeard = time
                    bird.commonness = Self.rarer(bird.commonness, call.commonness)
                    byCode[code] = bird
                }
            } else if confirmation.confirms(clips: call.clips, peak: call.peak, required: call.required) {
                call.confirmed = true
                if var bird = byCode[code] {
                    bird.calls += 1
                    bird.bestConfidence = max(bird.bestConfidence, call.peak)
                    bird.lastHeard = time
                    bird.commonness = Self.rarer(bird.commonness, call.commonness)
                    byCode[code] = bird
                } else {
                    byCode[code] = HeardBird(
                        species: call.species, calls: 1, bestConfidence: call.peak, firstHeard: call.start,
                        lastHeard: time, commonness: call.commonness)
                }
            }
            calls[code] = call
        }
    }

    /// Closes calls that have gone quiet by `time` (unconfirmed ones are dropped). `record`
    /// does this itself; call it directly for clips that weren't classified (e.g. silence).
    public mutating func advance(to time: Date) {
        calls = calls.filter { time.timeIntervalSince($0.value.last) <= callGap }
    }

    private static func rarer(_ a: Commonness?, _ b: Commonness?) -> Commonness? {
        switch (a, b) {
        case (nil, let x), (let x, nil): x
        case (let a?, let b?): max(a, b)
        }
    }
}
