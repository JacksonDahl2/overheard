import CoreGraphics
import Foundation

/// Places birds on a journal page the way someone sketches in a notebook: scattered across the
/// page, each a little tilted, its name written wherever there's room (below, above, beside, or
/// a little apart with an arrow), drawings nestled close but never covering one another. Pure
/// geometry, so it's unit-tested and the app only draws what it returns.
///
/// Each bird has its own spot on the page (`target`), spread evenly by the order it was heard
/// and nudged per bird, and goes in the free space nearest that spot. Its label has a favorite
/// side and moves to another only when that side is cramped. The nudge, side, arrow and tilt
/// come from the page's `seed` (the walk) plus the species, so every walk's page is sketched
/// differently, but within one page nothing is random: a bird keeps its place as the page
/// updates, and earlier birds never depend on later ones, so a newly heard bird doesn't move the rest.
///
/// If they don't all fit, everything shrinks a step and is laid out again; with room to spare
/// (`maxScale` > 1), a few birds are drawn larger so they fill the page.
public struct PageLayout: Sendable, Equatable {

    public struct Item: Sendable, Equatable {
        public let id: String
        /// The bird's drawing, as a square side, before any scaling.
        public let side: Double
        /// Room for its handwritten label.
        public let labelHeight: Double
        /// The label's width; at least the drawing's when it's above or below, so a small bird's
        /// name still fits.
        public let labelWidth: Double

        public init(id: String, side: Double, labelHeight: Double, labelWidth: Double = 0) {
            self.id = id
            self.side = side
            self.labelHeight = labelHeight
            self.labelWidth = labelWidth
        }
    }

    /// Where a bird's name is written, relative to its drawing.
    public enum LabelSide: Sendable, CaseIterable {
        case below, above, leading, trailing
    }

    public struct Placement: Sendable, Equatable {
        /// Where the drawing goes.
        public let art: CGRect
        /// Where its label goes.
        public let label: CGRect
        public let labelSide: LabelSide
        /// True when the label sits a little apart and an arrow points from it to the bird.
        public let hasArrow: Bool
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
    /// How far apart a label sits from its bird when an arrow joins them.
    public static let arrowGap: Double = 22
    /// The largest tilt either way, in degrees.
    public static let maxTilt: Double = 5
    /// How finely free spots are searched for, in points.
    static let step: Double = 8
    /// How much farther (in points) a bird will sit from its spot to keep its label's favorite side.
    static let sidePreference: Double = 14
    static let shrinkStep = 0.9
    static let smallestScale = 0.3

    /// Lays out `items` inside `bounds` (the page, minus its margins and date line).
    /// `seed` names the page (the walk's id), so each walk is arranged its own way.
    public init(items: [Item], in bounds: CGRect, maxScale: Double = 1, seed: String = "") {
        var scale = max(1, maxScale)

        // Shrink until every bird fits, or until birds are as small as they get.
        while scale * Self.shrinkStep >= Self.smallestScale {
            if Self.place(items, in: bounds, scale: scale, seed: seed, stopAtFirstMiss: true).count == items.count {
                break
            }
            scale *= Self.shrinkStep
        }

        // At the smallest size, a very long walk shows the birds that fit, first heard first.
        self.placements = Self.place(items, in: bounds, scale: scale, seed: seed)
        self.scale = scale
    }

    // MARK: - Placing

    /// Places each item that fits at this scale, in order; items that don't fit are left out.
    /// `stopAtFirstMiss` gives up as soon as one doesn't fit (enough to know this scale is too big).
    static func place(
        _ items: [Item], in bounds: CGRect, scale: Double, seed: String = "", stopAtFirstMiss: Bool = false
    ) -> [String: Placement] {
        var placements: [String: Placement] = [:]
        var taken: [Placement] = []

        for (index, item) in items.enumerated() {
            let key = BirdKey(page: seed, id: item.id)
            let target = target(forBirdAt: index, key: key, in: bounds)
            guard let placement = bestSpot(for: item, key: key, scale: scale, near: target, avoiding: taken, in: bounds)
            else {
                if stopAtFirstMiss { break }
                continue
            }

            placements[item.id] = placement
            taken.append(placement)
        }

        return placements
    }

    /// The free spot for `item` nearest `target`, trying each label side; the bird's favorite
    /// sides win unless they put it noticeably farther from its spot.
    static func bestSpot(
        for item: Item, key: BirdKey = BirdKey(page: "", id: ""), scale: Double, near target: CGPoint,
        avoiding taken: [Placement], in bounds: CGRect
    ) -> Placement? {
        let side = item.side * scale
        let style = LabelStyle(for: key)
        let tilt = tilt(for: key)
        var best: (placement: Placement, score: Double)?

        for (rank, labelSide) in style.sides.enumerated() {
            let size = footprint(for: item, side: side, labelSide: labelSide, hasArrow: style.hasArrow)
            guard size.width <= bounds.width, size.height <= bounds.height else { continue }

            let penalty = Double(rank) * sidePreference

            for x in stride(from: bounds.minX, through: bounds.maxX - size.width, by: step) {
                for y in stride(from: bounds.minY, through: bounds.maxY - size.height, by: step) {
                    let candidate = placement(
                        for: item, side: side, labelSide: labelSide, hasArrow: style.hasArrow, tilt: tilt,
                        at: CGPoint(x: x, y: y))
                    let score = hypot(candidate.art.midX - target.x, candidate.art.midY - target.y) + penalty

                    guard score < (best?.score ?? .infinity), fits(candidate, among: taken) else { continue }
                    best = (candidate, score)
                }
            }
        }

        return best?.placement
    }

    // MARK: - Footprints

    /// The size of drawing plus label for this label side.
    static func footprint(for item: Item, side: Double, labelSide: LabelSide, hasArrow: Bool) -> CGSize {
        let gap = hasArrow ? arrowGap : 0

        switch labelSide {
        case .below, .above:
            return CGSize(width: max(side, item.labelWidth), height: side + gap + item.labelHeight)
        case .leading, .trailing:
            return CGSize(width: side + gap + item.labelWidth, height: max(side, item.labelHeight))
        }
    }

    /// A bird's drawing and label inside a footprint at `origin`.
    static func placement(
        for item: Item, side: Double, labelSide: LabelSide, hasArrow: Bool, tilt: Double, at origin: CGPoint
    ) -> Placement {
        let size = footprint(for: item, side: side, labelSide: labelSide, hasArrow: hasArrow)
        let gap = hasArrow ? arrowGap : 0
        let art: CGRect
        let label: CGRect

        switch labelSide {
        case .below:
            art = CGRect(x: origin.x + (size.width - side) / 2, y: origin.y, width: side, height: side)
            label = CGRect(x: origin.x, y: art.maxY + gap, width: size.width, height: item.labelHeight)
        case .above:
            label = CGRect(x: origin.x, y: origin.y, width: size.width, height: item.labelHeight)
            art = CGRect(x: origin.x + (size.width - side) / 2, y: label.maxY + gap, width: side, height: side)
        case .leading:
            label = CGRect(
                x: origin.x, y: origin.y + (size.height - item.labelHeight) / 2, width: item.labelWidth,
                height: item.labelHeight)
            art = CGRect(x: label.maxX + gap, y: origin.y + (size.height - side) / 2, width: side, height: side)
        case .trailing:
            art = CGRect(x: origin.x, y: origin.y + (size.height - side) / 2, width: side, height: side)
            label = CGRect(
                x: art.maxX + gap, y: origin.y + (size.height - item.labelHeight) / 2, width: item.labelWidth,
                height: item.labelHeight)
        }

        return Placement(art: art, label: label, labelSide: labelSide, hasArrow: hasArrow, tilt: tilt)
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

    // MARK: - Each bird's habits on this page

    /// One bird on one page: what its spot, label side, arrow and tilt are derived from.
    struct BirdKey {
        let page: String
        let id: String

        var hash: UInt64 { StableHash.of(page + "|" + id) }
    }

    /// Where a bird likes its label on this page, and whether it gets an arrow.
    struct LabelStyle {
        /// Label sides in order of preference; the first is its favorite.
        let sides: [LabelSide]
        let hasArrow: Bool

        init(for key: BirdKey) {
            var seed = key.hash ^ 0x5851_F42D_4C95_7F2D

            // Most names sit under the bird, as in a field guide; some beside or above it.
            let roll = StableHash.unit(&seed)
            let favorite: LabelSide =
                switch roll {
                case ..<0.45: .below
                case ..<0.65: .trailing
                case ..<0.85: .leading
                default: .above
                }
            sides = [favorite] + [.below, .trailing, .leading, .above].filter { $0 != favorite }

            // About one bird in three is labeled from a little way off, with an arrow.
            hasArrow = StableHash.unit(&seed) < 0.33
        }
    }

    /// Bird `index`'s spot on the page. The first sits near the top middle; later ones spread
    /// evenly over the page (a Halton sequence), each nudged its own way so pages differ.
    static func target(forBirdAt index: Int, key: BirdKey, in bounds: CGRect) -> CGPoint {
        let spread =
            index == 0
            ? CGPoint(x: 0.5, y: 0.14)
            : CGPoint(x: 0.12 + 0.76 * halton(index, base: 2), y: 0.06 + 0.84 * halton(index, base: 3))

        var seed = key.hash
        let nudge = CGPoint(x: StableHash.unit(&seed) - 0.5, y: StableHash.unit(&seed) - 0.5)

        return CGPoint(
            x: bounds.minX + bounds.width * (spread.x + nudge.x * 0.12),
            y: bounds.minY + bounds.height * (spread.y + nudge.y * 0.1))
    }

    /// The tilt a bird is sketched at on this page.
    static func tilt(for key: BirdKey) -> Double {
        var seed = key.hash ^ 0x9E37_79B9_7F4A_7C15
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
/// so a bird keeps its spot and tilt on a page every time the page is drawn.
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
