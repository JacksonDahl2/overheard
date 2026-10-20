import CoreGraphics
import Foundation

/// Places birds on a journal page the way someone sketches in a notebook: scattered across the
/// page, each a little tilted, drawings nestled close but never covering one another. Pure
/// geometry, so it's unit-tested and the app only draws what it returns.
///
/// Each bird has its own spot on the page (`target`), spread evenly by the order it was heard
/// and nudged by its species code, and goes in the free space nearest that spot. Nothing is
/// random between runs: the same birds always land in the same places, and earlier birds never
/// depend on later ones, so a newly heard bird doesn't move the rest.
///
/// If they don't all fit, everything shrinks a step and is laid out again; with room to spare
/// (`maxScale` > 1), a few birds are drawn larger so they fill the page.
public struct PageLayout: Sendable, Equatable {

    public struct Item: Sendable, Equatable {
        public let id: String
        /// The bird's drawing, as a square side, before any scaling.
        public let side: Double
        /// Room under the drawing for its handwritten label.
        public let labelHeight: Double
        /// The label's width; at least the drawing's, so a small bird's name still fits.
        public let labelWidth: Double

        public init(id: String, side: Double, labelHeight: Double, labelWidth: Double = 0) {
            self.id = id
            self.side = side
            self.labelHeight = labelHeight
            self.labelWidth = labelWidth
        }
    }

    public struct Placement: Sendable, Equatable {
        /// Where the drawing goes.
        public let art: CGRect
        /// Where its label goes: directly under the drawing, centered on it.
        public let label: CGRect
        /// A slight hand-placed tilt, in degrees.
        public let tilt: Double

        /// The whole footprint: drawing plus label.
        public var frame: CGRect { art.union(label) }
    }

    public let placements: [String: Placement]
    /// How much everything was scaled to fit (1 = each bird's own size).
    public let scale: Double

    /// Drawings have a little empty paper around the bird, so neighbors may tuck this far into each other.
    public static let nestle: Double = 4
    /// Space kept around every label, so handwriting never runs into a drawing (tilts included).
    public static let labelGap: Double = 6
    /// The largest tilt either way, in degrees.
    public static let maxTilt: Double = 5
    /// How finely free spots are searched for, in points.
    static let step: Double = 8
    static let shrinkStep = 0.9
    static let smallestScale = 0.3

    /// Lays out `items` inside `bounds` (the page, minus its margins and date line).
    public init(items: [Item], in bounds: CGRect, maxScale: Double = 1) {
        var scale = max(1, maxScale)

        // Shrink until every bird fits, or until birds are as small as they get.
        while scale * Self.shrinkStep >= Self.smallestScale {
            if Self.place(items, in: bounds, scale: scale, stopAtFirstMiss: true).count == items.count { break }
            scale *= Self.shrinkStep
        }

        // At the smallest size, a very long walk shows the birds that fit, first heard first.
        self.placements = Self.place(items, in: bounds, scale: scale)
        self.scale = scale
    }

    // MARK: - Placing

    /// Places each item that fits at this scale, in order; items that don't fit are left out.
    /// `stopAtFirstMiss` gives up as soon as one doesn't fit (enough to know this scale is too big).
    static func place(_ items: [Item], in bounds: CGRect, scale: Double, stopAtFirstMiss: Bool = false)
        -> [String: Placement]
    {
        var placements: [String: Placement] = [:]
        var taken: [Placement] = []

        for (index, item) in items.enumerated() {
            let target = target(forBirdAt: index, id: item.id, in: bounds)
            guard let placement = bestSpot(for: item, scale: scale, near: target, avoiding: taken, in: bounds) else {
                if stopAtFirstMiss { break }
                continue
            }

            placements[item.id] = placement
            taken.append(placement)
        }

        return placements
    }

    /// The free spot for `item` whose center is nearest `target`.
    static func bestSpot(
        for item: Item, scale: Double, near target: CGPoint, avoiding taken: [Placement], in bounds: CGRect
    ) -> Placement? {
        let side = item.side * scale
        let width = max(side, item.labelWidth)
        let height = side + item.labelHeight
        guard width <= bounds.width, height <= bounds.height else { return nil }

        var best: (placement: Placement, distance: Double)?

        for x in stride(from: bounds.minX, through: bounds.maxX - width, by: step) {
            for y in stride(from: bounds.minY, through: bounds.maxY - height, by: step) {
                let candidate = placement(for: item, side: side, width: width, at: CGPoint(x: x, y: y))
                let distance = hypot(candidate.frame.midX - target.x, candidate.frame.midY - target.y)

                guard distance < (best?.distance ?? .infinity), fits(candidate, among: taken) else { continue }
                best = (candidate, distance)
            }
        }

        return best?.placement
    }

    /// A bird's drawing and label at `origin`, the drawing centered over its label.
    static func placement(for item: Item, side: Double, width: Double, at origin: CGPoint) -> Placement {
        let art = CGRect(x: origin.x + (width - side) / 2, y: origin.y, width: side, height: side)
        let label = CGRect(x: origin.x, y: art.maxY, width: width, height: item.labelHeight)
        return Placement(art: art, label: label, tilt: tilt(for: item.id))
    }

    /// Drawings may tuck into each other's empty margins; labels stay clear of everything.
    static func fits(_ candidate: Placement, among taken: [Placement]) -> Bool {
        let art = candidate.art.insetBy(dx: nestle, dy: nestle)
        let label = candidate.label.insetBy(dx: -labelGap, dy: -labelGap)

        return !taken.contains { other in
            let otherArt = other.art.insetBy(dx: nestle, dy: nestle)
            return art.intersects(otherArt)
                || label.intersects(other.label)
                || label.intersects(other.art)
                || other.label.insetBy(dx: -labelGap, dy: -labelGap).intersects(candidate.art)
        }
    }

    // MARK: - Where each bird wants to be

    /// Bird `index`'s spot on the page. The first sits near the top middle; later ones spread
    /// evenly over the page (a Halton sequence), each nudged by its species code so pages differ.
    static func target(forBirdAt index: Int, id: String, in bounds: CGRect) -> CGPoint {
        let spread =
            index == 0
            ? CGPoint(x: 0.5, y: 0.22)
            : CGPoint(x: 0.12 + 0.76 * halton(index, base: 2), y: 0.1 + 0.8 * halton(index, base: 3))

        var seed = StableHash.of(id)
        let nudge = CGPoint(x: StableHash.unit(&seed) - 0.5, y: StableHash.unit(&seed) - 0.5)

        return CGPoint(
            x: bounds.minX + bounds.width * (spread.x + nudge.x * 0.12),
            y: bounds.minY + bounds.height * (spread.y + nudge.y * 0.1))
    }

    /// The tilt a bird is sketched at, the same every time for the same species.
    static func tilt(for id: String) -> Double {
        var seed = StableHash.of(id) ^ 0x9E37_79B9_7F4A_7C15
        return (StableHash.unit(&seed) * 2 - 1) * maxTilt
    }

    /// The `index`-th value (0…1) of the Halton sequence in `base`: evenly spread, never clumped.
    static func halton(_ index: Int, base: Int) -> Double {
        var result = 0.0
        var fraction = 1.0 / Double(base)
        var i = index

        while i > 0 {
            result += fraction * Double(i % base)
            i /= base
            fraction /= Double(base)
        }
        return result
    }
}

/// A hash that's the same on every run and device (Swift's `hashValue` changes per launch),
/// so a species always lands in the same spot and tilt.
enum StableHash {
    /// FNV-1a over the string's UTF-8 bytes.
    static func of(_ string: String) -> UInt64 {
        string.utf8.reduce(0xCBF2_9CE4_8422_2325) { ($0 ^ UInt64($1)) &* 0x100_0000_01B3 }
    }

    /// The next value in 0..<1 from `seed` (SplitMix64), advancing it.
    static func unit(_ seed: inout UInt64) -> Double {
        seed &+= 0x9E37_79B9_7F4A_7C15
        var z = seed
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }
}
