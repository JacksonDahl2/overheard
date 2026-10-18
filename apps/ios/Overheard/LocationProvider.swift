import CoreLocation
import OverheardKit

/// Where the user is, for BirdNET's location filter. Approximate location is plenty: the
/// filter works at city scale, so the app also works with "Precise Location" turned off.
@MainActor
final class LocationProvider {
    enum Status: Equatable {
        case idle
        case waiting  // asked, no fix yet
        case located(Place)
        case denied  // user said no (or restricted); the filter is off
        case unavailable  // no fix (e.g. airplane mode indoors)
    }

    private(set) var status: Status = .idle
    var onChange: ((Status) -> Void)?

    private let manager = CLLocationManager()
    private var updates: Task<Void, Never>?

    func start() {
        guard updates == nil else { return }
        switch manager.authorizationStatus {
        case .denied, .restricted:
            set(.denied)
            return
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            break
        }
        set(.waiting)
        updates = Task { [weak self] in
            do {
                for try await update in CLLocationUpdate.liveUpdates() {
                    guard let self else { return }
                    if let location = update.location {
                        self.set(
                            .located(
                                Place(
                                    latitude: location.coordinate.latitude,
                                    longitude: location.coordinate.longitude, date: .now)))
                    } else if self.manager.authorizationStatus == .denied
                        || self.manager.authorizationStatus == .restricted
                    {
                        self.set(.denied)
                    }
                }
            } catch {
                self?.set(.unavailable)
            }
        }
    }

    func stop() {
        updates?.cancel()
        updates = nil
        if case .located = status {} else { set(.idle) }
    }

    private func set(_ new: Status) {
        guard new != status else { return }
        status = new
        onChange?(new)
    }
}
