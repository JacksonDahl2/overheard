import CoreLocation
import OverheardKit

/// Where the user is: for BirdNET's location filter (`status`) and the walk's route (`onFix`).
/// Approximate location is plenty for the filter, so the app works with "Precise Location"
/// off; the route is then just coarse (`Route` drops inaccurate fixes).
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
    /// Every fix, for the route.
    var onFix: ((RoutePoint) -> Void)?

    private let manager = CLLocationManager()
    private var updates: Task<Void, Never>?
    /// Keeps updates coming with the screen locked (with the `location` background mode).
    private var background: CLBackgroundActivitySession?

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
        background = CLBackgroundActivitySession()
        updates = Task { [weak self] in
            do {
                for try await update in CLLocationUpdate.liveUpdates(.fitness) {
                    guard let self else { return }
                    if let location = update.location {
                        self.onFix?(
                            RoutePoint(
                                latitude: location.coordinate.latitude,
                                longitude: location.coordinate.longitude, time: location.timestamp,
                                accuracy: location.horizontalAccuracy))
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
        background?.invalidate()
        background = nil
        if case .located = status {} else { set(.idle) }
    }

    private func set(_ new: Status) {
        guard new != status else { return }
        status = new
        onChange?(new)
    }
}
