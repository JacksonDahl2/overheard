import AVFoundation

/// Captures microphone audio and delivers fixed-length 48 kHz mono clips.
///
/// BirdNET expects 3 s of 48 kHz mono Float32 audio. The input node runs at the
/// hardware rate, so every tap buffer is resampled before it is accumulated.
final class AudioCapture {
    static let sampleRate: Double = 48_000
    static let clipLength = 144_000  // 3 s

    /// Called on a background queue with each complete clip and its RMS level.
    var onClip: (([Float], Float) -> Void)?

    private let engine = AVAudioEngine()
    private let queue = DispatchQueue(label: "app.overheardbirds.audio")
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: AudioCapture.sampleRate, channels: 1, interleaved: false)!
    private var converter: AVAudioConverter?
    private var pending: [Float] = []
    private var interruptionObserver: NSObjectProtocol?

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        // .measurement turns off voice processing and gain control, which would
        // otherwise suppress quiet, high-pitched birdsong.
        try session.setCategory(.record, mode: .measurement)
        try session.setPreferredSampleRate(Self.sampleRate)
        try session.setActive(true)

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        pending.removeAll(keepingCapacity: true)

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.queue.async { self?.append(buffer) }
        }
        engine.prepare()
        try engine.start()
        observeInterruptions()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        interruptionObserver = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Private

    private func append(_ buffer: AVAudioPCMBuffer) {
        guard let converter else { return }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var consumed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let samples = out.floatChannelData?[0] else { return }

        pending.append(contentsOf: UnsafeBufferPointer(start: samples, count: Int(out.frameLength)))
        while pending.count >= Self.clipLength {
            let clip = Array(pending.prefix(Self.clipLength))
            pending.removeFirst(Self.clipLength)
            onClip?(clip, Self.rms(clip))
        }
    }

    private func observeInterruptions() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: nil
        ) { [weak self] note in
            guard let self,
                  let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .ended
            else { return }
            // A call or Siri paused us; pick back up where we left off.
            try? AVAudioSession.sharedInstance().setActive(true)
            try? self.engine.start()
        }
    }

    private static func rms(_ clip: [Float]) -> Float {
        var sum: Float = 0
        for s in clip { sum += s * s }
        return (sum / Float(clip.count)).squareRoot()
    }
}
