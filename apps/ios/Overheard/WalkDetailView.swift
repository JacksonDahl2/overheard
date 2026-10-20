import CoreLocation
import MapKit
import OverheardKit
import SwiftUI

/// A saved walk: when, how far, the route on a map, and the birds heard.
/// A stand-in for the journal page (docs/design.md).
struct WalkDetailView: View {
    let walk: Walk
    let catalog: SpeciesCatalog?

    var body: some View {
        let route = walk.route
        List {
            Section {
                LabeledContent("Started", value: walk.startedAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent(
                    "Length",
                    value: Duration.seconds(walk.duration).formatted(
                        .units(allowed: [.hours, .minutes], width: .abbreviated)))
                LabeledContent("Distance", value: WalkRow.distance(route.distance))
                if walk.interrupted {
                    Text("This walk was cut short: the app was closed before it ended.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }

            if !route.points.isEmpty {
                Section {
                    RouteMap(route: route)
                        .frame(height: 260)
                        .listRowInsets(EdgeInsets())
                }
            }

            Section("Heard") {
                if walk.birds.isEmpty {
                    Text("No birds on this walk").foregroundStyle(.secondary)
                }
                ForEach(walk.sortedBirds, id: \.speciesCode) { bird in
                    BirdRow(
                        species: species(bird.speciesCode), calls: bird.calls, confidence: bird.bestConfidence,
                        commonness: bird.commonness)
                }
            }
        }
        .navigationTitle(walk.startedAt.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Names come from the catalog; a code this model doesn't know still shows (as its code).
    private func species(_ code: String) -> Species {
        catalog?.species(code: code) ?? Species(code: code, commonName: code, scientificName: "", isBird: true)
    }
}

private struct RouteMap: View {
    let route: Route

    var body: some View {
        let coordinates = route.points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        Map(interactionModes: [.pan, .zoom]) {
            if coordinates.count > 1 {
                MapPolyline(coordinates: coordinates).stroke(.brown, lineWidth: 4)
            }
            if let start = coordinates.first {
                Marker("Start", systemImage: "figure.walk", coordinate: start).tint(.green)
            }
        }
    }
}
