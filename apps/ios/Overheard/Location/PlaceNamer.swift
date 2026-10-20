import CoreLocation
import OverheardKit

/// Turns a walk's first location into a name for it, like "The Ramble, Central Park".
enum PlaceNamer {
    static func name(for point: RoutePoint) async -> String? {
        let location = CLLocation(latitude: point.latitude, longitude: point.longitude)
        guard let place = try? await CLGeocoder().reverseGeocodeLocation(location).first else { return nil }

        return name(from: place)
    }

    /// The most specific name first (a feature like "The Ramble"), then the park or area it's in.
    /// Street addresses aren't walk names, so a place with only an address falls back to its
    /// neighborhood or city.
    static func name(from place: CLPlacemark) -> String? {
        let feature = place.areasOfInterest?.first
        let specific = place.name.flatMap { $0 == feature || looksLikeAddress($0, place) ? nil : $0 }
        let parts = [specific, feature ?? place.subLocality ?? place.locality].compactMap { $0 }

        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private static func looksLikeAddress(_ name: String, _ place: CLPlacemark) -> Bool {
        guard let street = place.thoroughfare else { return false }
        return name.contains(street)
    }
}
