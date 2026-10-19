import CoreML
import Foundation

/// Where and when the user is listening, as BirdNET's location model sees it.
public struct Place: Sendable, Equatable {
    public let latitude: Double
    public let longitude: Double
    /// BirdNET week 1–48 (four per month).
    public let week: Int

    public init(latitude: Double, longitude: Double, week: Int) {
        self.latitude = latitude
        self.longitude = longitude
        self.week = week
    }

    public init(latitude: Double, longitude: Double, date: Date) {
        self.init(latitude: latitude, longitude: longitude, week: SpeciesFilter.birdNETWeek(for: date))
    }

    /// Great-circle distance in kilometres.
    public func distance(to other: Place) -> Double {
        let r = 6371.0
        let dLat = (other.latitude - latitude) * .pi / 180
        let dLon = (other.longitude - longitude) * .pi / 180
        let a =
            sin(dLat / 2) * sin(dLat / 2) + cos(latitude * .pi / 180) * cos(other.latitude * .pi / 180)
            * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * asin(min(1, a.squareRoot()))
    }
}

/// How likely each species is at a place and week (0–1 per label), from BirdNET's location model.
public struct LocalSpecies: Sendable, Equatable {
    public let place: Place
    public let occurrence: [Float]  // index = BirdNET output index

    public init(place: Place, occurrence: [Float]) {
        self.place = place
        self.occurrence = occurrence
    }

    /// How likely the species is here this week (0–1); 0 for an unknown index.
    public func occurrence(of index: Int) -> Float {
        index < occurrence.count ? occurrence[index] : 0
    }

    /// Whether this is still a good estimate for `place`: same week, within `km`.
    public func covers(_ place: Place, withinKilometers km: Double = 10) -> Bool {
        place.week == self.place.week && self.place.distance(to: place) <= km
    }
}

/// Runs BirdNET's location (meta) model: [latitude, longitude, week] → occurrence per species.
public final class LocationModel {
    private let model: MLModel
    private let outputName: String

    /// - Parameter modelURL: a compiled model (`.mlmodelc`).
    public init(modelURL: URL) throws {
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndNeuralEngine
        model = try MLModel(contentsOf: modelURL, configuration: config)
        guard let output = model.modelDescription.outputDescriptionsByName.keys.first else {
            throw ClassifierError.badOutput
        }
        outputName = output
    }

    public func localSpecies(at place: Place) throws -> LocalSpecies {
        let input = try MLMultiArray(shape: [1, 3], dataType: .float32)
        input[0] = NSNumber(value: Float(place.latitude))
        input[1] = NSNumber(value: Float(place.longitude))
        input[2] = NSNumber(value: Float(place.week))
        let output = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["location": input]))
        guard let values = output.featureValue(for: outputName)?.multiArrayValue else {
            throw ClassifierError.badOutput
        }
        let occurrence = values.withUnsafeBufferPointer(ofType: Float.self) { Array($0) }
        return LocalSpecies(place: place, occurrence: occurrence)
    }
}
