import CoreGraphics
import Foundation

/// Places birds on a journal page the way someone sketches in a notebook: scattered across the
/// page, each a little tilted, drawings nestled close but never covering one another. Names
/// aren't part of the layout; the page shows a bird's name when it's tapped. Pure geometry, so
/// it's unit-tested and the app only draws what it returns. Every setting comes from `PageStyle`.
///
/// Each bird has its own spot on the page, spread evenly by the order it was heard and nudged per
/// bird, and goes in the free space nearest that spot. The nudge and tilt come from the page's
/// `seed` (the walk) plus the species, so every walk's page is sketched differently, and the same
/// page always redraws the same.
///
/// If the birds don't all fit, a few other arrangements are tried before everything shrinks a
/// step, so one awkward gap doesn't make a whole page small; the page may rearrange as birds
/// arrive. With room to spare (`maxScale` > 1), a few birds are drawn larger to fill the page.
public struct PageLayout: Sendable, Equatable {

    public struct Item: Sendable, Equatable {
        public let id: String
        /// The bird's drawing, as a square side, before any scaling.
        public let side: Double

        public init(id: String, side: Double) {
            self.id = id
            self.side = side
        }
    }

    public struct Placement: Sendable, Equatable {
        /// Where the drawing goes.
        public let art: CGRect
        /// A slight hand-placed tilt, in degrees.
        public let tilt: Double
    }

    public let placements: [String: Placement]
    /// How much everything was scaled to fit (1 = each bird's own size).
    public let scale: Double

    /// Lays out `items` inside `bounds` (the page, minus its margins and date line).
    /// `seed` names the page (the walk's id), so each walk is arranged its own way.
    public init(
        items: [Item], in bounds: CGRect, maxScale: Double = 1, seed: String = "", style: PageStyle = .standard
    ) {
        var scale = max(1, maxScale)

        // The largest size at which some arrangement fits every bird.
        while scale * style.shrinkStep >= style.smallestScale {
            let placer = Placer(style: style, bounds: bounds, scale: scale)
            if let arrangement = placer.firstArrangementThatFits(items, seed: seed) {
                self.placements = arrangement
                self.scale = scale
                return
            }
            scale *= style.shrinkStep
        }

        // At the smallest size, a very long walk shows the birds that fit, first heard first.
        self.placements = Placer(style: style, bounds: bounds, scale: scale).place(items, seed: seed)
        self.scale = scale
    }

    /// Whether a drawing at `art` can go beside the drawings already `taken`: they may tuck into
    /// each other's empty margins, but never cover each other.
    static func fits(_ art: CGRect, among taken: [CGRect], style: PageStyle = .standard) -> Bool {
        let inner = art.insetBy(dx: style.nestle, dy: style.nestle)
        return !taken.contains { $0.insetBy(dx: style.nestle, dy: style.nestle).intersects(inner) }
    }
}

// MARK: - Placing

/// One attempt at laying out a page: a style, the page's bounds, and a scale.
struct Placer {
    let style: PageStyle
    let bounds: CGRect
    let scale: Double

    /// Tries a few arrangements of the page (the first is the page's own; the rest are derived
    /// from it) and returns the first that fits every bird.
    func firstArrangementThatFits(_ items: [PageLayout.Item], seed: String) -> [String: PageLayout.Placement]? {
        for attempt in 0..<max(1, style.arrangementsPerSize) {
            let arrangementSeed = attempt == 0 ? seed : "\(seed)#\(attempt)"
            let placed = place(items, seed: arrangementSeed, stopAtFirstMiss: true)
            if placed.count == items.count { return placed }
        }
        return nil
    }

    /// Places each item that fits, in order; items that don't fit are left out.
    /// `stopAtFirstMiss` gives up as soon as one doesn't fit (enough to know it's too crowded).
    func place(_ items: [PageLayout.Item], seed: String, stopAtFirstMiss: Bool = false)
        -> [String: PageLayout.Placement]
    {
        var placements: [String: PageLayout.Placement] = [:]
        var taken: [CGRect] = []

        for (index, item) in items.enumerated() {
            let bird = BirdKey(page: seed, id: item.id)
            guard let art = bestSpot(for: item, near: target(forBirdAt: index, bird: bird), avoiding: taken) else {
                if stopAtFirstMiss { break }
                continue
            }

            placements[item.id] = PageLayout.Placement(art: art, tilt: tilt(for: bird))
            taken.append(art)
        }

        return placements
    }

    /// The free spot for `item`'s drawing whose center is nearest `target`.
    func bestSpot(for item: PageLayout.Item, near target: CGPoint, avoiding taken: [CGRect]) -> CGRect? {
        let side = item.side * scale
        guard side <= bounds.width, side <= bounds.height else { return nil }

        let step = max(2, style.searchStep)
        var best: (art: CGRect, distance: Double)?

        for x in stride(from: bounds.minX, through: bounds.maxX - side, by: step) {
            for y in stride(from: bounds.minY, through: bounds.maxY - side, by: step) {
                let art = CGRect(x: x, y: y, width: side, height: side)
                let distance = hypot(art.midX - target.x, art.midY - target.y)

                guard distance < (best?.distance ?? .infinity), PageLayout.fits(art, among: taken, style: style)
                else { continue }
                best = (art, Double(distance))  // CGFloat → Double: older Swift won't convert inside a tuple
            }
        }

        return best?.art
    }

    // MARK: Where each bird wants to be

    /// Bird `index`'s spot on the page. The first sits at the style's first spot; later ones
    /// spread evenly over its band (a Halton sequence), each nudged its own way so pages differ.
    func target(forBirdAt index: Int, bird: BirdKey) -> CGPoint {
        let spread =
            index == 0
            ? CGPoint(x: style.firstSpotX, y: style.firstSpotY)
            : CGPoint(
                x: style.spreadLeft + (style.spreadRight - style.spreadLeft) * Halton.value(index, base: 2),
                y: style.spreadTop + (style.spreadBottom - style.spreadTop) * Halton.value(index, base: 3))

        var seed = bird.hash
        let nudgeX = StableHash.unit(&seed) - 0.5
        let nudgeY = StableHash.unit(&seed) - 0.5

        return CGPoint(
            x: bounds.minX + bounds.width * (spread.x + nudgeX * style.nudge),
            y: bounds.minY + bounds.height * (spread.y + nudgeY * style.nudge))
    }

    /// The tilt a bird is sketched at on this page.
    func tilt(for bird: BirdKey) -> Double {
        var seed = bird.hash ^ 0x9E37_79B9_7F4A_7C15
        return (StableHash.unit(&seed) * 2 - 1) * style.maxTilt
    }
}

/// One bird on one page: what its spot and tilt are derived from.
struct BirdKey {
    let page: String
    let id: String

    var hash: UInt64 { StableHash.of(page + "|" + id) }
}

/// The Halton sequence: evenly spread points that never clump.
enum Halton {
    /// The `index`-th value (0…1) in `base`.
    static func value(_ index: Int, base: Int) -> Double {
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
