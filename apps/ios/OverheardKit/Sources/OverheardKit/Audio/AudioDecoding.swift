import AVFoundation

/// Reads an audio file (WAV, MP3, …) as 48 kHz mono Float32, the format BirdNET expects.
public enum AudioDecoding {
    public static func load48kMono(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let target = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: BirdClassifier.sampleRate, channels: 1, interleaved: false)!
        guard let converter = AVAudioConverter(from: file.processingFormat, to: target) else {
            throw DecodingError.unsupportedFormat(url.lastPathComponent)
        }

        var samples: [Float] = []
        let chunk: AVAudioFrameCount = 1 << 16
        let ratio = target.sampleRate / file.processingFormat.sampleRate
        let source = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunk)!
        var reachedEnd = false

        while true {
            let out = AVAudioPCMBuffer(
                pcmFormat: target, frameCapacity: AVAudioFrameCount(Double(chunk) * ratio) + 1024)!
            var error: NSError?
            let status = converter.convert(to: out, error: &error) { _, status in
                if reachedEnd {
                    status.pointee = .endOfStream
                    return nil
                }
                do {
                    try file.read(into: source, frameCount: chunk)
                } catch {
                    reachedEnd = true
                }
                if source.frameLength == 0 {
                    reachedEnd = true
                    status.pointee = .endOfStream
                    return nil
                }
                status.pointee = .haveData
                return source
            }
            if let error { throw error }
            if let data = out.floatChannelData?[0], out.frameLength > 0 {
                samples.append(contentsOf: UnsafeBufferPointer(start: data, count: Int(out.frameLength)))
            }
            if status == .endOfStream || status == .error { break }
        }
        return samples
    }

    /// Splits audio into BirdNET clips. A trailing partial clip is zero-padded if it's at least
    /// `minTail` long, otherwise dropped.
    public static func clips(
        _ samples: [Float], hop: Int = BirdClassifier.clipLength, minTail: Int = BirdClassifier.clipLength / 2
    ) -> [[Float]] {
        let length = BirdClassifier.clipLength
        var clips: [[Float]] = []
        var start = 0
        while start + length <= samples.count {
            clips.append(Array(samples[start..<start + length]))
            start += hop
        }
        let tail = samples.count - start
        if tail > 0, tail >= minTail || clips.isEmpty {
            clips.append(Array(samples[start...]) + Array(repeating: 0, count: length - tail))
        }
        return clips
    }

    public enum DecodingError: LocalizedError {
        case unsupportedFormat(String)

        public var errorDescription: String? {
            switch self {
            case .unsupportedFormat(let name): "Can't decode \(name)."
            }
        }
    }
}
