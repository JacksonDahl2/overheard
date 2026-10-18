import Foundation

/// Where the BirdNET files live (bundled in the app, or under ml/models/coreml on the Mac).
public struct BirdNETResources: Sendable {
    public let audioModel: URL  // compiled .mlmodelc
    public let locationModel: URL  // compiled .mlmodelc
    public let catalog: URL  // species.json

    public init(audioModel: URL, locationModel: URL, catalog: URL) {
        self.audioModel = audioModel
        self.locationModel = locationModel
        self.catalog = catalog
    }
}

/// What the UI needs after each clip.
public struct PipelineUpdate: Sendable {
    public let birds: [HeardBird]
    public let lastClip: [BirdScore]
    public let level: Float
    public let inferenceMs: Double?  // nil when the clip was skipped as quiet
    public let clipsAnalyzed: Int
    public let place: Place?  // nil until a location arrives (or if it's denied)
}

/// The whole detection pipeline for a listening session: clip → BirdNET → filter → tally.
/// An actor, so the models and session state are only touched from one place, off the main thread.
public actor ListeningPipeline {
    public private(set) var rules = DetectionRules()
    /// RMS below this skips inference (saves battery on silence).
    public private(set) var quietThreshold: Float = 0.002

    private let classifier: BirdClassifier
    private let locationModel: LocationModel
    private var local: LocalSpecies?
    private var session = DetectionSession()
    private var clipsAnalyzed = 0

    public init(resources: BirdNETResources) throws {
        let catalog = try SpeciesCatalog(contentsOf: resources.catalog)
        classifier = try BirdClassifier(modelURL: resources.audioModel, catalog: catalog)
        locationModel = try LocationModel(modelURL: resources.locationModel)
    }

    public func configure(rules: DetectionRules, quietThreshold: Float) {
        self.rules = rules
        self.quietThreshold = quietThreshold
    }

    /// Recomputes expected species if the user moved ~10 km or the week changed.
    /// Returns true when it recomputed.
    @discardableResult
    public func updateLocation(_ place: Place) throws -> Bool {
        if let local, local.covers(place) { return false }
        local = try locationModel.localSpecies(at: place)
        return true
    }

    /// Forgets the location (e.g. permission revoked); the location filter then stops applying.
    public func clearLocation() {
        local = nil
    }

    public func reset() {
        session = DetectionSession()
        clipsAnalyzed = 0
    }

    public func process(_ clip: [Float], level: Float, at time: Date) throws -> PipelineUpdate {
        clipsAnalyzed += 1
        guard level >= quietThreshold else {
            return update(lastClip: [], level: level, inferenceMs: nil)
        }
        // A new week mid-session (e.g. a walk past midnight on a Sunday) needs fresh likelihoods.
        if let place = local?.place {
            try updateLocation(Place(latitude: place.latitude, longitude: place.longitude, date: time))
        }
        let started = Date()
        let scores = try classifier.classify(clip, local: local, rules: rules)
        let ms = Date().timeIntervalSince(started) * 1000
        session.record(scores, at: time)
        return update(lastClip: scores, level: level, inferenceMs: ms)
    }

    private func update(lastClip: [BirdScore], level: Float, inferenceMs: Double?) -> PipelineUpdate {
        PipelineUpdate(
            birds: session.birds, lastClip: lastClip, level: level, inferenceMs: inferenceMs,
            clipsAnalyzed: clipsAnalyzed, place: local?.place)
    }
}
