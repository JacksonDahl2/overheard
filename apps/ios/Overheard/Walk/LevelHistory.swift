import Foundation

/// The last few seconds of sound, one sample per clip, for the level bars under the title.
/// Bars where a bird was heard are drawn in the accent color.
struct LevelHistory {
    struct Sample: Identifiable {
        let id: Int
        /// Bird-band loudness (`LevelMeter.highPassRMS`).
        let level: Float
        let heardBird: Bool
    }

    /// How many bars fit across the screen.
    static let capacity = 44

    private(set) var samples: [Sample] = []
    private var nextID = 0

    mutating func append(level: Float, heardBird: Bool) {
        samples.append(Sample(id: nextID, level: level, heardBird: heardBird))
        nextID += 1

        if samples.count > Self.capacity { samples.removeFirst(samples.count - Self.capacity) }
    }

    mutating func reset() {
        samples = []
    }
}
