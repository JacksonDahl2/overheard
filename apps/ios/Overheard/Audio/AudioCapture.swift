@preconcurrency import AVFoundation
import OverheardKit

/// Captures microphone audio and delivers overlapping 48 kHz mono clips (3 s, one every second)
/// as an async stream.
///
/// BirdNET expects 3 s of 48 kHz mono Float32 audio. The input node runs at the hardware
/// rate, so every tap buffer is resampled before it is accumulated.
///
/// Keeps listening through interruptions (calls, Siri), audio route changes (AirPods, a
/// wired mic), and media-services resets by rebuilding the tap for the new input format.
final class AudioCapture: @unchecked Sendable {
    // @unchecked: all mutable state below is only touched on `queue`.

    struct Clip: Sendable {
        let samples: [Float]
        let level: Float  // RMS, used to skip silence
        let time: Date  // when the clip ended
    }

    let clips: AsyncStream<Clip>
    private let continuation: AsyncStream<Clip>.Continuation

    private let queue = DispatchQueue(label: "app.overheardbirds.audio")
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false)!

    private var engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var window = SlidingWindow()  // 3 s clips every 1 s
    private var running = false
    private var observers: [NSObjectProtocol] = []

    init() {
        (clips, continuation) = AsyncStream.makeStream(of: Clip.self, bufferingPolicy: .bufferingNewest(4))
    }

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        // .measurement turns off voice processing and gain control, which would
        // otherwise suppress quiet, high-pitched birdsong.
        try session.setCategory(.record, mode: .measurement)
        try session.setPreferredSampleRate(targetFormat.sampleRate)
        try session.setActive(true)
        try queue.sync {
            window.reset()
            try startEngine()
            running = true
        }
        observe()
    }

    func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        queue.sync {
            running = false
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Engine (on `queue`)

    /// (Re)installs the tap for the current input format and starts the engine.
    private func startEngine() throws {
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else { throw CaptureError.noInput }
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        // The tap's buffer is only guaranteed valid until the callback returns, so hand the
        // queue our own copy. (Not queue.sync: stop/restart remove the tap on `queue`, which
        // waits for this callback, so blocking here could deadlock.)
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self, let copy = OwnedBuffer(copying: buffer) else { return }
            self.queue.async { self.append(copy.buffer) }
        }
        engine.prepare()
        try engine.start()
    }

    /// The input changed under us (new route, sample rate, or a media-services reset).
    private func restart(rebuildEngine: Bool) {
        guard running else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        if rebuildEngine { engine = AVAudioEngine() }
        try? AVAudioSession.sharedInstance().setActive(true)
        try? startEngine()
    }

    private func append(_ buffer: AVAudioPCMBuffer) {
        guard running, let converter else { return }
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

        for clip in window.append(UnsafeBufferPointer(start: samples, count: Int(out.frameLength))) {
            continuation.yield(Clip(samples: clip, level: Self.rms(clip), time: .now))
        }
    }

    // MARK: - Notifications

    private func observe() {
        let center = NotificationCenter.default
        observers = [
            // A call or Siri paused us; pick back up when it ends.
            center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) {
                [weak self] note in
                guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                    AVAudioSession.InterruptionType(rawValue: raw) == .ended
                else { return }
                guard let self else { return }
                self.queue.async { self.restart(rebuildEngine: false) }
            },
            // AirPods connected, a wired mic plugged in, …: the input format changed.
            center.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: nil) {
                [weak self] _ in
                guard let self else { return }
                self.queue.async { self.restart(rebuildEngine: false) }
            },
            // The audio daemon restarted; every engine object is invalid now.
            center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: nil) {
                [weak self] _ in
                guard let self else { return }
                self.queue.async {
                    try? AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement)
                    self.restart(rebuildEngine: true)
                }
            },
        ]
    }

    private static func rms(_ clip: [Float]) -> Float {
        var sum: Float = 0
        for s in clip { sum += s * s }
        return (sum / Float(clip.count)).squareRoot()
    }

    /// A private copy of a tap buffer, safe to hand to another queue (nothing else holds it).
    private struct OwnedBuffer: @unchecked Sendable {
        let buffer: AVAudioPCMBuffer

        init?(copying source: AVAudioPCMBuffer) {
            guard let copy = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: source.frameLength),
                let from = source.floatChannelData, let to = copy.floatChannelData
            else { return nil }
            copy.frameLength = source.frameLength
            let frames = Int(source.frameLength)
            let stride = source.format.isInterleaved ? Int(source.format.channelCount) : 1
            let planes = source.format.isInterleaved ? 1 : Int(source.format.channelCount)
            for plane in 0..<planes {
                to[plane].update(from: from[plane], count: frames * stride)
            }
            buffer = copy
        }
    }

    enum CaptureError: LocalizedError {
        case noInput
        var errorDescription: String? { "No microphone input is available." }
    }
}
