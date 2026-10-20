import Foundation
import SwiftData

/// A saved walk. The phone generates `id`, so uploads can be retried safely later.
@Model
public final class Walk {
    @Attribute(.unique) public var id: UUID
    public var startedAt: Date
    /// Where it was, e.g. "The Ramble, Central Park"; nil until a place name is found.
    public var placeName: String?
    /// nil while the walk is going. A walk found open at launch was cut short (see `WalkStore`).
    public var endedAt: Date?
    /// Last time anything was saved: where an interrupted walk is considered to have ended.
    public var updatedAt: Date
    /// True when the app was killed mid-walk and the walk was closed at the next launch.
    public var interrupted: Bool
    /// The encoded `Route`. One blob instead of a row per point: it's only ever read whole.
    @Attribute(.externalStorage) var routeData: Data?
    @Relationship(deleteRule: .cascade, inverse: \WalkBird.walk) public var birds: [WalkBird]

    public init(id: UUID = UUID(), startedAt: Date) {
        self.id = id
        self.startedAt = startedAt
        self.updatedAt = startedAt
        self.interrupted = false
        self.birds = []
    }

    public var isActive: Bool { endedAt == nil }

    /// The place name, or a time-of-day name ("Morning walk") until there is one.
    public var title: String { placeName ?? WalkTitle.default(for: startedAt) }

    public var duration: TimeInterval { (endedAt ?? updatedAt).timeIntervalSince(startedAt) }

    public var route: Route {
        get { routeData.flatMap { try? JSONDecoder().decode(Route.self, from: $0) } ?? Route() }
        set { routeData = try? JSONEncoder().encode(newValue) }
    }

    /// Birds for display: most calls first, then earliest heard (same order as `DetectionSession`).
    public var sortedBirds: [WalkBird] {
        birds.sorted { $0.calls == $1.calls ? $0.firstHeard < $1.firstHeard : $0.calls > $1.calls }
    }
}

/// A species heard on a walk. Stored by `Species.code`, never a BirdNET index; names come from
/// the catalog at display time.
@Model
public final class WalkBird {
    public var speciesCode: String
    public var calls: Int
    public var bestConfidence: Float
    public var firstHeard: Date
    public var lastHeard: Date
    var commonnessRaw: Int?
    public var walk: Walk?

    public init(_ bird: HeardBird) {
        speciesCode = bird.species.code
        calls = bird.calls
        bestConfidence = bird.bestConfidence
        firstHeard = bird.firstHeard
        lastHeard = bird.lastHeard
        commonnessRaw = bird.commonness?.rawValue
    }

    /// The rarest it was here on this walk; `.unusual` gets the rare-bird flourish.
    public var commonness: Commonness? {
        get { commonnessRaw.flatMap(Commonness.init(rawValue:)) }
        set { commonnessRaw = newValue?.rawValue }
    }

    func update(from bird: HeardBird) {
        calls = bird.calls
        bestConfidence = bird.bestConfidence
        firstHeard = bird.firstHeard
        lastHeard = bird.lastHeard
        commonness = bird.commonness
    }

    func matches(_ bird: HeardBird) -> Bool {
        calls == bird.calls && bestConfidence == bird.bestConfidence && firstHeard == bird.firstHeard
            && lastHeard == bird.lastHeard && commonness == bird.commonness
    }
}
