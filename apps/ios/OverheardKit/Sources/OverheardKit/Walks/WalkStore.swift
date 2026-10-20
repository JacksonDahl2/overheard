import Foundation
import SwiftData

/// Saves walks as they happen. iOS can kill the app mid-walk, so nothing waits for "End walk":
/// a newly confirmed bird or extra call is saved right away, and the route at least every
/// `routeSaveInterval`. A walk left open by a killed app is closed at the next launch.
@MainActor
public final class WalkStore {
    public static let routeSaveInterval: TimeInterval = 30

    public let context: ModelContext
    private var lastSave: Date?

    public init(context: ModelContext) {
        self.context = context
    }

    /// The app's container (on disk), or an in-memory one for tests and previews.
    public static func container(inMemory: Bool = false) throws -> ModelContainer {
        try ModelContainer(
            for: Walk.self, WalkBird.self, configurations: ModelConfiguration(isStoredInMemoryOnly: inMemory))
    }

    public func startWalk(at time: Date = .now) throws -> Walk {
        let walk = Walk(startedAt: time)
        context.insert(walk)
        try save(at: time)
        return walk
    }

    /// Mirrors the session's confirmed birds onto the walk. Saves when anything changed.
    public func record(_ birds: [HeardBird], in walk: Walk, at time: Date) throws {
        var existing = Dictionary(walk.birds.map { ($0.speciesCode, $0) }, uniquingKeysWith: { a, _ in a })
        var changed = false
        for bird in birds {
            if let saved = existing[bird.species.code] {
                if !saved.matches(bird) {
                    saved.update(from: bird)
                    changed = true
                }
            } else {
                let saved = WalkBird(bird)
                walk.birds.append(saved)
                existing[bird.species.code] = saved
                changed = true
            }
        }
        walk.updatedAt = time
        if changed { try save(at: time) } else { try saveIfDue(at: time) }
    }

    /// Adds a GPS fix to the walk's route (if `Route` keeps it); saved at least every `routeSaveInterval`.
    public func addRoutePoint(_ point: RoutePoint, to walk: Walk) throws {
        var route = walk.route
        guard route.add(point) else { return }
        walk.route = route
        walk.updatedAt = max(walk.updatedAt, point.time)
        // The first fix is where the walk started: worth saving right away.
        if route.points.count == 1 { try save(at: point.time) } else { try saveIfDue(at: point.time) }
    }

    /// Names the walk after where it is (found once, from the first location fix).
    public func name(_ walk: Walk, placeName: String) throws {
        walk.placeName = placeName
        try save()
    }

    public func endWalk(_ walk: Walk, at time: Date = .now) throws {
        walk.endedAt = time
        walk.updatedAt = time
        try save(at: time)
    }

    /// Closes walks a killed app left open, at their last save. Call once at launch, before
    /// starting a new walk. Returns how many it closed.
    @discardableResult
    public func closeInterruptedWalks() throws -> Int {
        let open = try context.fetch(FetchDescriptor<Walk>(predicate: #Predicate { $0.endedAt == nil }))
        for walk in open {
            walk.endedAt = walk.updatedAt
            walk.interrupted = true
        }
        if !open.isEmpty { try context.save() }
        return open.count
    }

    public func delete(_ walk: Walk) throws {
        context.delete(walk)
        try context.save()
    }

    /// All walks, newest first.
    public func walks() throws -> [Walk] {
        try context.fetch(FetchDescriptor<Walk>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)]))
    }

    /// Saves pending changes now, e.g. when the app goes to the background.
    public func save(at time: Date = .now) throws {
        try context.save()
        lastSave = time
    }

    private func saveIfDue(at time: Date) throws {
        if let lastSave, time.timeIntervalSince(lastSave) < Self.routeSaveInterval { return }
        try save(at: time)
    }
}
