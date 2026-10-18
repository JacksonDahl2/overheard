import CoreML
import Foundation

/// One species BirdNET scored in a clip.
public struct BirdScore: Hashable, Sendable {
    public let index: Int
    public let commonName: String
    public let scientificName: String
    public let confidence: Float
}

/// Runs the BirdNET v2.4 Core ML model on 3 s clips and applies `SpeciesFilter`.
public final class BirdClassifier {
    public static let sampleRate: Double = 48_000
    public static let clipLength = 144_000  // 3 s

    public let labels: [(scientific: String, common: String)]
    public let filter: SpeciesFilter
    private let model: MLModel

    /// - Parameters:
    ///   - modelURL: a compiled model (`.mlmodelc`).
    ///   - labelsURL: BirdNET `labels.txt` (`Scientific_Common` per line, index = output index).
    ///   - filter: which labels may be reported.
    public init(modelURL: URL, labelsURL: URL, filter: SpeciesFilter) throws {
        let config = MLModelConfiguration()
        config.computeUnits = .all
        model = try MLModel(contentsOf: modelURL, configuration: config)
        self.filter = filter
        labels = try String(contentsOf: labelsURL, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                let parts = line.split(separator: "_", maxSplits: 1).map(String.init)
                return (parts.first ?? "", parts.count > 1 ? parts[1] : (parts.first ?? ""))
            }
    }

    /// Scores a clip and returns the reportable birds, best first.
    public func classify(_ clip: [Float], date: Date, rules: DetectionRules) throws -> [BirdScore] {
        let confidences = try confidences(for: clip)
        let expected = filter.expectedSpecies(on: date)
        return confidences.enumerated()
            .filter { filter.isReportable($0.offset, confidence: $0.element, expected: expected, rules: rules) }
            .map {
                BirdScore(
                    index: $0.offset, commonName: labels[$0.offset].common,
                    scientificName: labels[$0.offset].scientific, confidence: $0.element)
            }
            .sorted { $0.confidence > $1.confidence }
    }

    /// Confidence (0–1) for every label, in label order.
    public func confidences(for clip: [Float]) throws -> [Float] {
        let input = try MLMultiArray(shape: [1, NSNumber(value: clip.count)], dataType: .float32)
        clip.withUnsafeBufferPointer { src in
            input.withUnsafeMutableBytes { dst, _ in
                dst.copyMemory(from: UnsafeRawBufferPointer(src))
            }
        }
        let output = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["inputs": input]))
        guard let logits = output.featureValue(for: "Identity")?.multiArrayValue else {
            throw ClassifierError.badOutput
        }
        return logits.withUnsafeBufferPointer(ofType: Float.self) { values in
            (0..<min(values.count, labels.count)).map { Self.sigmoid(values[$0]) }
        }
    }

    /// BirdNET's default sigmoid (sensitivity 1.0), with the same clipping it uses.
    private static func sigmoid(_ x: Float) -> Float {
        1 / (1 + exp(-min(max(x, -15), 15)))
    }
}

public enum ClassifierError: LocalizedError {
    case missingResource(String)
    case badOutput

    public var errorDescription: String? {
        switch self {
        case .missingResource(let name): "Missing \(name). Run the ml/ scripts first."
        case .badOutput: "The model returned no scores."
        }
    }
}
