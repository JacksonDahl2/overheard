import CoreML
import Foundation

/// One species BirdNET scored in a clip.
struct BirdScore: Hashable {
    let index: Int
    let commonName: String
    let scientificName: String
    let confidence: Float
}

/// Runs the BirdNET v2.4 Core ML model on 3 s clips and applies the location/week filter.
final class BirdClassifier {
    private let model: MLModel
    private let labels: [(scientific: String, common: String)]
    private let weeks: [Int: Set<Int>]

    init() throws {
        let config = MLModelConfiguration()
        config.computeUnits = .all
        guard let modelURL = Bundle.main.url(forResource: "BirdNETAudio", withExtension: "mlmodelc") else {
            throw ClassifierError.missingResource("BirdNETAudio.mlmodelc")
        }
        model = try MLModel(contentsOf: modelURL, configuration: config)

        guard let labelsURL = Bundle.main.url(forResource: "labels", withExtension: "txt") else {
            throw ClassifierError.missingResource("labels.txt")
        }
        labels = try String(contentsOf: labelsURL, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                let parts = line.split(separator: "_", maxSplits: 1).map(String.init)
                return (parts.first ?? "", parts.count > 1 ? parts[1] : (parts.first ?? ""))
            }

        guard let speciesURL = Bundle.main.url(forResource: "species-central-park", withExtension: "json") else {
            throw ClassifierError.missingResource("species-central-park.json")
        }
        let table = try JSONDecoder().decode(SpeciesTable.self, from: Data(contentsOf: speciesURL))
        weeks = Dictionary(
            uniqueKeysWithValues: table.weeks.compactMap { key, value in
                Int(key).map { ($0, Set(value)) }
            })
    }

    /// Scores a clip. Returns species above `minConfidence`, best first.
    /// When `filtered` is true, only species expected at this place and week are kept.
    func classify(_ clip: [Float], date: Date, minConfidence: Float, filtered: Bool) throws -> [BirdScore] {
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

        let allowed = filtered ? weeks[Self.birdNETWeek(for: date)] : nil
        var scores: [BirdScore] = []
        logits.withUnsafeBufferPointer(ofType: Float.self) { values in
            for i in 0..<min(values.count, labels.count) {
                if let allowed, !allowed.contains(i) { continue }
                let confidence = Self.sigmoid(values[i])
                guard confidence >= minConfidence else { continue }
                scores.append(
                    BirdScore(
                        index: i, commonName: labels[i].common, scientificName: labels[i].scientific,
                        confidence: confidence))
            }
        }
        return scores.sorted { $0.confidence > $1.confidence }
    }

    /// BirdNET weeks run 1–48: four per month.
    static func birdNETWeek(for date: Date) -> Int {
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

enum ClassifierError: LocalizedError {
    case missingResource(String)
    case badOutput

    var errorDescription: String? {
        switch self {
        case .missingResource(let name): "Missing \(name) in the app bundle. Run the ml/ scripts first."
        case .badOutput: "The model returned no scores."
        }
    }
}

private struct SpeciesTable: Decodable {
    let weeks: [String: [Int]]
}
