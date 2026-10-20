/// Cuts a live sample stream into overlapping BirdNET clips: `length` samples every `hop`.
///
/// With the defaults (3 s clips every 1 s) a bird shows up about 2 s sooner than with
/// back-to-back clips, and a short song that straddles a clip boundary is still caught whole.
public struct SlidingWindow: Sendable {
    /// One second of 48 kHz audio: the default hop between clips.
    public static let defaultHop = Int(BirdClassifier.sampleRate)

    public let length: Int
    public let hop: Int
    private var buffer: [Float] = []

    public init(length: Int = BirdClassifier.clipLength, hop: Int = SlidingWindow.defaultHop) {
        precondition(hop > 0 && hop <= length, "hop must be in 1...length")
        self.length = length
        self.hop = hop
    }

    /// Adds samples and returns every clip that's now complete, oldest first.
    public mutating func append(_ samples: some Collection<Float>) -> [[Float]] {
        buffer.append(contentsOf: samples)
        var clips: [[Float]] = []
        while buffer.count >= length {
            clips.append(Array(buffer.prefix(length)))
            buffer.removeFirst(hop)
        }
        return clips
    }

    public mutating func reset() {
        buffer.removeAll(keepingCapacity: true)
    }
}
