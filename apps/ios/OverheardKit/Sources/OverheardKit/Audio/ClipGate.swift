import Foundation

/// Cheap loudness measures for deciding whether a clip is worth classifying.
public enum LevelMeter {
    /// RMS of the signal above `cutoffHz` (a 2nd-order Butterworth high-pass).
    ///
    /// City background (traffic, HVAC, wind) is mostly low-frequency, while nearly all songbirds
    /// sing above 1 kHz, so this tracks "something bird-like got louder" far better than raw RMS.
    public static func highPassRMS(
        _ samples: [Float], cutoffHz: Double = 1000, sampleRate: Double = BirdClassifier.sampleRate
    ) -> Float {
        guard !samples.isEmpty else { return 0 }
        // RBJ biquad high-pass, Q = 1/√2.
        let w0 = 2 * Double.pi * cutoffHz / sampleRate
        let alpha = sin(w0) / (2 * (1 / 2.0.squareRoot()))
        let cosw = cos(w0)
        let a0 = 1 + alpha
        let b0 = Float((1 + cosw) / 2 / a0)
        let b1 = Float(-(1 + cosw) / a0)
        let b2 = b0
        let a1 = Float(-2 * cosw / a0)
        let a2 = Float((1 - alpha) / a0)

        var x1: Float = 0
        var x2: Float = 0
        var y1: Float = 0
        var y2: Float = 0
        var sum: Float = 0
        for x in samples {
            let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1
            x1 = x
            y2 = y1
            y1 = y
            sum += y * y
        }
        return (sum / Float(samples.count)).squareRoot()
    }
}

/// Decides which clips to classify, to save battery: a clip is analyzed when its bird-band level
/// (`LevelMeter.highPassRMS`) is clearly above the recent background, so steady city noise and
/// silence are skipped but a bird singing over them isn't.
///
/// Pure value type: the app and the eval run the same gate, and it's unit-tested.
public struct AdaptiveGate: Sendable, Equatable {
    public struct Config: Sendable, Hashable {
        /// Analyze when the level is at least this many times the noise floor (2 ≈ 6 dB).
        public var aboveFloor: Float
        /// Below this level a clip is silence and always skipped (it can't hold a bird).
        public var silence: Float
        /// Never skip more than this many clips in a row, so the gate is never blind for long.
        public var maxSkippedInARow: Int
        /// Recent clips the noise floor is estimated from (its lower quartile).
        public var floorWindow: Int

        public init(aboveFloor: Float = 2, silence: Float = 0.0002, maxSkippedInARow: Int = 4, floorWindow: Int = 30) {
            self.aboveFloor = aboveFloor
            self.silence = silence
            self.maxSkippedInARow = maxSkippedInARow
            self.floorWindow = floorWindow
        }
    }

    public let config: Config
    /// The current background estimate (nil until a few clips have been seen).
    public private(set) var noiseFloor: Float?
    private var recent: [Float] = []
    private var skippedInARow = 0

    public init(config: Config = Config()) {
        self.config = config
    }

    /// Records a clip's level and returns whether to classify it. Call once per clip, in order.
    public mutating func shouldAnalyze(level: Float) -> Bool {
        let decision = decide(level)
        recent.append(level)
        if recent.count > config.floorWindow { recent.removeFirst(recent.count - config.floorWindow) }
        if recent.count >= 5 { noiseFloor = recent.sorted()[recent.count / 4] }
        skippedInARow = decision ? 0 : skippedInARow + 1
        return decision
    }

    private func decide(_ level: Float) -> Bool {
        if level < config.silence { return false }
        guard let noiseFloor else { return true }  // still learning the background
        if level >= noiseFloor * config.aboveFloor { return true }
        return skippedInARow >= config.maxSkippedInARow
    }
}
