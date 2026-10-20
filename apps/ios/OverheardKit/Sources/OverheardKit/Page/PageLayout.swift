import CoreGraphics
import Foundation

/// Places birds on a journal page: a loose cluster, not a grid, with no overlaps and nothing
/// off the page. Pure geometry, so it's unit-tested and the app only draws what it returns.
///
/// Birds are placed one at a time, in the order given (the app passes first-heard order).
/// Each goes in the open spot, touching a bird already placed, that's closest to the page's
/// focal point. Earlier birds never depend on later ones, so a newly heard bird doesn't move
/// the rest. If they don't all fit, everything shrinks a step and is laid out again.
public struct PageLayout: Sendable, Equatable {

    public struct Item: Sendable, Equatable {
        public let id: String
        /// The bird's drawing, as a square side, before any shrinking to fit.
        public let side: Double
        /// Room under the drawing for its handwritten label.
        public let labelHeight: Double

        public init(id: String, side: Double, labelHeight: Double) {
            self.id = id
            self.side = side
            self.labelHeight = labelHeight
        }
    }

    public struct Placement: Sendable, Equatable {
        /// Where the drawing goes.
        public let art: CGRect
        /// Where its label goes: directly under the drawing, the same width.
        public let label: CGRect

        /// The whole footprint: drawing plus label.
        public var frame: CGRect { art.union(label) }
    }

    public let placements: [String: Placement]
    /// How much everything was shrunk to fit (1 = full size).
    public let scale: Double

    /// Space kept between birds.
    public static let gap: Double = 6
    static let shrinkStep = 0.9
    static let smallestScale = 0.3

    /// Lays out `items` inside `bounds` (the page, minus its margins and date line).
    public init(items: [Item], in bounds: CGRect) {
        var scale = 1.0

        // Shrink until every bird fits, or until birds are as small as they get.
        while scale * Self.shrinkStep >= Self.smallestScale {
            let attempt = Self.place(items, in: bounds, scale: scale)
            if attempt.count == items.count { break }
            scale *= Self.shrinkStep
        }

        // At the smallest size, a very long walk shows the birds that fit, first heard first.
        self.placements = Self.place(items, in: bounds, scale: scale)
        self.scale = scale
    }

    // MARK: - Placing

    /// Places each item that fits at this scale, in order; items that don't fit are left out.
    static func place(_ items: [Item], in bounds: CGRect, scale: Double) -> [String: Placement] {
        var placements: [String: Placement] = [:]
        var taken: [CGRect] = []

        for item in items {
            guard let placement = bestSpot(for: item, scale: scale, avoiding: taken, in: bounds) else { continue }
            placements[item.id] = placement
            taken.append(placement.frame)
        }

        return placements
    }

    /// The open spot for `item` nearest the focal point, touching a bird already placed.
    static func bestSpot(for item: Item, scale: Double, avoiding taken: [CGRect], in bounds: CGRect) -> Placement? {
        let side = item.side * scale
        let size = CGSize(width: side, height: side + item.labelHeight)
        let focus = focalPoint(of: bounds)

        let candidates =
            taken.isEmpty
            ? [centered(size, on: focus, in: bounds)]
            : taken.flatMap { neighbors(of: $0, size: size) }

        let open =
            candidates
            .map { CGRect(origin: $0, size: size) }
            .filter { bounds.contains($0) && !overlapsAny($0, taken) }

        guard let best = open.min(by: { distance($0, to: focus) < distance($1, to: focus) }) else { return nil }

        let art = CGRect(x: best.minX, y: best.minY, width: side, height: side)
        let label = CGRect(x: best.minX, y: art.maxY, width: side, height: item.labelHeight)
        return Placement(art: art, label: label)
    }

    // MARK: - Geometry

    /// Where the cluster gathers: centered, a little above the middle, since the eye reads top-down.
    static func focalPoint(of bounds: CGRect) -> CGPoint {
        CGPoint(x: bounds.midX, y: bounds.minY + bounds.height * 0.42)
    }

    /// The origin that centers a frame of `size` on `point`, kept inside `bounds` vertically.
    static func centered(_ size: CGSize, on point: CGPoint, in bounds: CGRect) -> CGPoint {
        let y = min(max(bounds.minY, point.y - size.height / 2), bounds.maxY - size.height)
        return CGPoint(x: point.x - size.width / 2, y: y)
    }

    /// Origins that put a frame of `size` against each side of `frame`: at its start, middle and end.
    static func neighbors(of frame: CGRect, size: CGSize) -> [CGPoint] {
        let right = frame.maxX + gap
        let left = frame.minX - gap - size.width
        let below = frame.maxY + gap
        let above = frame.minY - gap - size.height

        let alongX = [frame.minX, frame.midX - size.width / 2, frame.maxX - size.width]
        let alongY = [frame.minY, frame.midY - size.height / 2, frame.maxY - size.height]

        let beside = alongY.flatMap { y in [CGPoint(x: right, y: y), CGPoint(x: left, y: y)] }
        let aboveOrBelow = alongX.flatMap { x in [CGPoint(x: x, y: below), CGPoint(x: x, y: above)] }
        return beside + aboveOrBelow
    }

    static func overlapsAny(_ frame: CGRect, _ taken: [CGRect]) -> Bool {
        taken.contains { $0.insetBy(dx: -gap / 2, dy: -gap / 2).intersects(frame) }
    }

    static func distance(_ frame: CGRect, to point: CGPoint) -> Double {
        hypot(frame.midX - point.x, frame.midY - point.y)
    }
}
