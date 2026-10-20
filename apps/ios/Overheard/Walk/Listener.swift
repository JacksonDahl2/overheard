import Foundation
import Observation
import OverheardKit

/// Runs a walk: feeds microphone clips and locations to the detection pipeline, publishes what
/// it hears for the screens, and saves the walk as it goes.
///
/// The detection itself happens in `ListeningPipeline` (an actor in OverheardKit); saving is
/// `WalkStore`'s job. This class only connects them to the UI.
@MainActor
@Observable
final class Listener {
    enum Phase {
        case idle  // between walks
        case listening
        case paused  // the walk goes on; the microphone is off
    }

    // MARK: Walk

    private(set) var phase: Phase = .idle
    /// The walk being recorded (nil between walks).
    private(set) var walk: Walk?
    var isWalking: Bool { phase != .idle }

    // MARK: What's been heard

    /// Confirmed birds, most calls first.
    private(set) var birds: [HeardBird] = []
    /// Heard but not confirmed yet: the faint birds "being sketched".
    private(set) var pending: [PendingBird] = []
    /// The most confident bird in the latest clip that had one ("Just heard").
    private(set) var justHeard: BirdScore?
    /// Recent loudness, for the level bars.
    private(set) var levels = LevelHistory()

    // MARK: Status

    private(set) var location: LocationProvider.Status = .idle
    var errorMessage: String?
    private(set) var stats = ListeningStats()

    /// Species names for saved walks, which store codes only.
    let catalog: SpeciesCatalog?

    // MARK: Field-test settings (pushed to the pipeline when they change)

    var rules = DetectionRules() { didSet { pushSettings() } }
    /// Skip clips with nothing above the background, to save battery. Off until it's measured.
    var useGate = false { didSet { pushSettings() } }

    // MARK: Parts

    private let capture = AudioCapture()
    private let locationProvider = LocationProvider()
    private let newBirdAlert = NewBirdAlert()
    private var arrivals = BirdArrivals()
    private let store: WalkStore
    private var pipeline: ListeningPipeline?
    private var listening: Task<Void, Never>?
    private var isNamingPlace = false

    init(store: WalkStore) {
        self.store = store
        catalog = try? SpeciesCatalog(contentsOf: BirdNETResources.bundled().catalog)

        // If the app was killed mid-walk last time, close that walk where it left off.
        attempt { try store.closeInterruptedWalks() }
    }

    // MARK: - Starting and ending a walk

    func startWalk() {
        guard phase == .idle else { return }
        errorMessage = nil

        attempt {
            let pipeline = try self.pipeline ?? ListeningPipeline(resources: .bundled())
            self.pipeline = pipeline

            try capture.start()
            walk = try store.startWalk()
            clearWhatWasHeard()
            newBirdAlert.prepare()
            phase = .listening

            startLocation()
            listen(to: pipeline)
        }
    }

    /// Turns the microphone off without ending the walk.
    func pause() {
        guard phase == .listening else { return }
        capture.stop()
        phase = .paused
    }

    func resume() {
        guard phase == .paused else { return }
        attempt {
            try capture.start()
            phase = .listening
        }
    }

    /// Ends the walk and saves it.
    func endWalk() {
        guard phase != .idle else { return }

        capture.stop()
        locationProvider.stop()
        listening?.cancel()
        listening = nil
        phase = .idle

        guard let walk else { return }
        self.walk = nil
        attempt {
            try store.record(birds, in: walk, at: .now)
            try store.endWalk(walk)
        }
    }

    /// Saves whatever is pending (when the app goes to the background).
    func saveNow() {
        attempt { try store.save() }
    }

    func delete(_ walk: Walk) {
        attempt { try store.delete(walk) }
    }

    // MARK: - Listening

    private func listen(to pipeline: ListeningPipeline) {
        let clips = capture.clips
        let rules = rules
        let gate = gateConfig

        listening = Task { [weak self] in
            await pipeline.configure(rules: rules, gate: gate)
            await pipeline.reset()

            for await clip in clips {
                do {
                    let update = try await pipeline.process(clip.samples, at: clip.time)
                    self?.show(update, at: clip.time)
                } catch {
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func show(_ update: PipelineUpdate, at time: Date) {
        if let walk { attempt { try store.record(update.birds, in: walk, at: time) } }

        for bird in arrivals.newBirds(in: update.birds) { newBirdAlert.announce(bird) }

        birds = update.birds
        pending = update.pending
        if let top = update.lastClip.first { justHeard = top }
        levels.append(level: update.level, heardBird: !update.lastClip.isEmpty)
        stats.update(from: update)
    }

    private func clearWhatWasHeard() {
        birds = []
        pending = []
        justHeard = nil
        arrivals.reset()
        levels.reset()
        stats = ListeningStats()
    }

    // MARK: - Location

    private func startLocation() {
        locationProvider.onChange = { [weak self] status in self?.locationChanged(status) }
        locationProvider.onFix = { [weak self] fix in self?.addToRoute(fix) }
        locationProvider.start()
    }

    private func addToRoute(_ fix: RoutePoint) {
        guard let walk else { return }
        attempt { try store.addRoutePoint(fix, to: walk) }
        nameWalkIfNeeded(from: fix)
    }

    /// Names the walk after the place it started, once.
    private func nameWalkIfNeeded(from fix: RoutePoint) {
        guard let walk, walk.placeName == nil, !isNamingPlace else { return }
        isNamingPlace = true

        Task {
            defer { isNamingPlace = false }
            guard let name = await PlaceNamer.name(for: fix), self.walk === walk else { return }
            attempt { try store.name(walk, placeName: name) }
        }
    }

    private func locationChanged(_ status: LocationProvider.Status) {
        location = status
        guard let pipeline else { return }

        Task {
            switch status {
            case .located(let place):
                do { try await pipeline.updateLocation(place) } catch { errorMessage = error.localizedDescription }
            case .denied:
                await pipeline.clearLocation()
            case .idle, .waiting, .unavailable:
                break  // keep the last known location
            }
        }
    }

    // MARK: - Settings

    private var gateConfig: AdaptiveGate.Config? { useGate ? AdaptiveGate.Config() : nil }

    private func pushSettings() {
        guard let pipeline else { return }
        let rules = rules
        let gate = gateConfig
        Task { await pipeline.configure(rules: rules, gate: gate) }
    }

    // MARK: - Errors

    /// Runs `work`, showing any error it throws instead of failing silently.
    private func attempt(_ work: () throws -> Void) {
        do { try work() } catch { errorMessage = error.localizedDescription }
    }
}

#if DEBUG
    extension Listener {
        /// Fills the screens with a sample walk (launch with `-demo`), for screenshots and design work.
        func showDemo(_ demo: DemoWalk) {
            phase = .listening
            walk = demo.walk
            birds = demo.birds
            pending = demo.pending
            justHeard = demo.justHeard
            for sample in demo.levels { levels.append(level: sample.level, heardBird: sample.heardBird) }
        }
    }
#endif
