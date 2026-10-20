import CoreML
import Foundation

/// One species BirdNET reported in a clip, with the filter's verdict.
public struct BirdScore: Hashable, Sendable {
    /// BirdNET output index. Only meaningful inside the pipeline; store `species.code`.
    public let index: Int
    public let species: Species
    public let confidence: Float
    /// The confidence it had to reach (higher for rarer species here).
    public let requiredConfidence: Float
    /// How expected the species is here this week; nil when the location is unknown.
    public let commonness: Commonness?

    public init(
        index: Int, species: Species, confidence: Float, requiredConfidence: Float = 0, commonness: Commonness? = nil
    ) {
        self.index = index
        self.species = species
        self.confidence = confidence
        self.requiredConfidence = requiredConfidence
        self.commonness = commonness
    }
}

/// Runs the BirdNET v2.4 Core ML audio model on 3 s clips and applies `SpeciesFilter`.
public final class BirdClassifier {
    public static let sampleRate: Double = 48_000
    public static let clipLength = 144_000  // 3 s

    public let catalog: SpeciesCatalog
    public let filter: SpeciesFilter
    private let model: MLModel

    /// - Parameters:
    ///   - modelURL: a compiled model (`.mlmodelc`).
    ///   - catalog: species for each output index (`species.json`).
    public init(modelURL: URL, catalog: SpeciesCatalog) throws {
        let config = MLModelConfiguration()
        config.computeUnits = .all
        model = try MLModel(contentsOf: modelURL, configuration: config)
        self.catalog = catalog
        filter = SpeciesFilter(catalog: catalog)
    }

    /// Scores a clip and returns the reportable birds, best first.
    public func classify(_ clip: [Float], local: LocalSpecies?, rules: DetectionRules) throws -> [BirdScore] {
        try reportable(confidences(for: clip), local: local, rules: rules)
    }

    /// The reportable birds among per-label confidences, best first.
    public func reportable(_ confidences: [Float], local: LocalSpecies?, rules: DetectionRules) -> [BirdScore] {
        confidences.enumerated()
            .compactMap { index, confidence in
                filter.assess(index, confidence: confidence, local: local, rules: rules).map {
                    BirdScore(
                        index: index, species: catalog[index], confidence: confidence,
                        requiredConfidence: $0.requiredConfidence, commonness: $0.commonness)
                }
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
            (0..<min(values.count, catalog.count)).map { Self.sigmoid(values[$0]) }
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
