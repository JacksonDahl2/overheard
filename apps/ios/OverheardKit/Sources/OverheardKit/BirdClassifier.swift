import CoreML
import Foundation

/// One species BirdNET scored in a clip.
public struct BirdScore: Hashable, Sendable {
    public let index: Int
    public let commonName: String
    public let scientificName: String
    public let confidence: Float
}

/// Runs the BirdNET v2.4 Core ML model on 3 s clips and applies the location/week filter.
public final class BirdClassifier {
    public static let sampleRate: Double = 48_000
    public static let clipLength = 144_000  // 3 s

    public let labels: [(scientific: String, common: String)]
    private let model: MLModel
    private let weeks: [Int: Set<Int>]

    /// - Parameters:
    ///   - modelURL: a compiled model (`.mlmodelc`).
    ///   - labelsURL: BirdNET `labels.txt` (`Scientific_Common` per line, index = output index).
    ///   - speciesURL: a per-week species table from `ml/species_list.py`.
    public init(modelURL: URL, labelsURL: URL, speciesURL: URL) throws {
        let config = MLModelConfiguration()
        config.computeUnits = .all
        model = try MLModel(contentsOf: modelURL, configuration: config)

        labels = try String(contentsOf: labelsURL, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                let parts = line.split(separator: "_", maxSplits: 1).map(String.init)
                return (parts.first ?? "", parts.count > 1 ? parts[1] : (parts.first ?? ""))
            }

        let table = try JSONDecoder().decode(SpeciesTable.self, from: Data(contentsOf: speciesURL))
        weeks = Dictionary(
            uniqueKeysWithValues: table.weeks.compactMap { key, value in
                Int(key).map { ($0, Set(value)) }
            })
    }

    /// Scores a clip. Returns species above `minConfidence`, best first.
    /// When `filtered` is true, only species expected at this place and week are kept.
    public func classify(_ clip: [Float], date: Date, minConfidence: Float, filtered: Bool) throws -> [BirdScore] {
        let confidences = try confidences(for: clip)
        let allowed = filtered ? expectedSpecies(on: date) : nil
        var scores: [BirdScore] = []
        for (i, confidence) in confidences.enumerated() where confidence >= minConfidence {
            if let allowed, !allowed.contains(i) { continue }
            scores.append(
                BirdScore(
                    index: i, commonName: labels[i].common, scientificName: labels[i].scientific,
                    confidence: confidence))
        }
        return scores.sorted { $0.confidence > $1.confidence }
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

    /// Label indices expected at this place in the BirdNET week containing `date`.
    public func expectedSpecies(on date: Date) -> Set<Int>? {
        weeks[Self.birdNETWeek(for: date)]
    }

    /// BirdNET weeks run 1–48: four per month.
    public static func birdNETWeek(for date: Date) -> Int {
        let parts = Calendar(identifier: .gregorian).dateComponents([.month, .day], from: date)
        let month = parts.month ?? 1
        let day = parts.day ?? 1
        return (month - 1) * 4 + min(4, (day - 1) / 7 + 1)
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

private struct SpeciesTable: Decodable {
    let weeks: [String: [Int]]
}
