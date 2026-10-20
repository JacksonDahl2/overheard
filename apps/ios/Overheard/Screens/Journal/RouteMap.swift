import CoreLocation
import MapKit
import OverheardKit
import SwiftUI

/// A walk's route on a map, in iron-gall ink, with its starting point.
struct RouteMap: View {
    let route: Route

    @Environment(\.theme) private var theme

    var body: some View {
        let path = route.points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }

        Map(interactionModes: [.pan, .zoom]) {
            if path.count > 1 {
                MapPolyline(coordinates: path).stroke(theme.accent, lineWidth: 4)
            }
            if let start = path.first {
                Marker("Start", systemImage: "figure.walk", coordinate: start).tint(theme.accent)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
    }
}
