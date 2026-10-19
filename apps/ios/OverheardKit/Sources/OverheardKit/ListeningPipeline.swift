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
    /// New species heard but not yet confirmed: the faint birds "being sketched".
    public let pending: [PendingBird]
    public let lastClip: [BirdScore]
    /// The clip's bird-band level (`LevelMeter.highPassRMS`) and the gate's background estimate.
    public let level: Float
    public let noiseFloor: Float?
    public let inferenceMs: Double?  // nil when the gate skipped the clip
    public let clipsSeen: Int
    public let clipsAnalyzed: Int
    public let place: Place?  // nil until a location arrives (or if it's denied)
}

/// The whole detection pipeline for a listening session: clip → gate → BirdNET → filter → tally.
/// An actor, so the models and session state are only touched from one place, off the main thread.
public actor ListeningPipeline {
    public private(set) var rules = DetectionRules()
    /// Skips clips with nothing above the background, to save battery. nil (the default) analyzes
    /// every clip: in the eval the gate cost 2–6 points of recall, most in city noise, and its
    /// battery saving hasn't been measured on a device yet (todo).
    public private(set) var gateConfig: AdaptiveGate.Config? = nil

    private let classifier: BirdClassifier
    private let locationModel: LocationModel
    private var local: LocalSpecies?
    private var session = DetectionSession()
    private var gate = AdaptiveGate()
    private var clipsSeen = 0
    private var clipsAnalyzed = 0

    public init(resources: BirdNETResources) throws {
        let catalog = try SpeciesCatalog(contentsOf: resources.catalog)
        classifier = try BirdClassifier(modelURL: resources.audioModel, catalog: catalog)
        locationModel = try LocationModel(modelURL: resources.locationModel)
    }

    public func configure(rules: DetectionRules, gate gateConfig: AdaptiveGate.Config?) {
        self.rules = rules
        if gateConfig != self.gateConfig {
            self.gateConfig = gateConfig
            gate = AdaptiveGate(config: gateConfig ?? AdaptiveGate.Config())
        }
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
        gate = AdaptiveGate(config: gateConfig ?? AdaptiveGate.Config())
        clipsSeen = 0
        clipsAnalyzed = 0
    }

    public func process(_ clip: [Float], at time: Date) throws -> PipelineUpdate {
        clipsSeen += 1
        let level = LevelMeter.highPassRMS(clip)
        let analyze = gate.shouldAnalyze(level: level) || gateConfig == nil
        guard analyze else {
            session.advance(to: time)  // a skipped clip still ends calls (and fades unconfirmed ones)
            return update(lastClip: [], level: level, inferenceMs: nil)
        }
        clipsAnalyzed += 1
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
            birds: session.birds, pending: session.pending, lastClip: lastClip, level: level,
            noiseFloor: gate.noiseFloor, inferenceMs: inferenceMs, clipsSeen: clipsSeen, clipsAnalyzed: clipsAnalyzed,
            place: local?.place)
    }
}
