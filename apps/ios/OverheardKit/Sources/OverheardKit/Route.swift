import Foundation

/// One GPS fix along a walk.
public struct RoutePoint: Sendable, Codable, Equatable {
    public let latitude: Double
    public let longitude: Double
    public let time: Date
    /// Horizontal accuracy in meters (CoreLocation's radius of uncertainty).
    public let accuracy: Double

    public init(latitude: Double, longitude: Double, time: Date, accuracy: Double) {
        self.latitude = latitude
        self.longitude = longitude
        self.time = time
        self.accuracy = accuracy
    }

    /// Great-circle distance in meters (haversine).
    public func distance(to other: RoutePoint) -> Double {
        let r = 6_371_000.0
        let lat1 = latitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        let dLat = lat2 - lat1
        let dLon = (other.longitude - longitude) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * atan2(a.squareRoot(), (1 - a).squareRoot())
    }
}

/// A walk's path. Keeps a point only when it's accurate and the walker has moved, so standing
/// still to listen doesn't pile up points or GPS jitter doesn't add distance.
public struct Route: Sendable, Codable, Equatable {
    /// Fixes less accurate than this are dropped (Wi-Fi/cell fixes indoors, approximate location).
    public static let maxAccuracy: Double = 50
    /// A new point needs to be at least this far from the last kept one.
    public static let minStep: Double = 10

    public private(set) var points: [RoutePoint] = []
    /// Meters walked: the sum of the kept steps.
    public private(set) var distance: Double = 0

    public init() {}

    /// Adds a fix if it's worth keeping. Returns true when it was kept.
    @discardableResult
    public mutating func add(_ point: RoutePoint) -> Bool {
        guard point.accuracy >= 0, point.accuracy <= Self.maxAccuracy else { return false }
        guard let last = points.last else {
            points.append(point)
            return true
        }
        guard point.time > last.time else { return false }
        let step = last.distance(to: point)
        // A step smaller than the two fixes' uncertainty is likely jitter, not walking.
        guard step >= max(Self.minStep, (point.accuracy + last.accuracy) / 2) else { return false }
        points.append(point)
        distance += step
        return true
    }
}
