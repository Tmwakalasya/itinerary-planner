import CoreLocation
import Observation

/// A location fix for the Today screen and the directions preview.
///
/// Asks only when-in-use, and only when the traveller taps to use it; until
/// then the screen times the next hop from the stop before instead.
@MainActor
@Observable
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private(set) var coordinate: Coordinate?
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private(set) var isLocating = false
    private(set) var errorMessage: String?
    private(set) var horizontalAccuracy: CLLocationAccuracy?

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var wantsLocation = false

    var isAuthorized: Bool {
        authorization == .authorizedWhenInUse || authorization == .authorizedAlways
    }

    /// Asking is pointless once someone has said no; Settings is the way back.
    var canAsk: Bool { authorization == .notDetermined }

    init(desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyHundredMeters) {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = desiredAccuracy
        authorization = manager.authorizationStatus
    }

    func requestPermission() {
        wantsLocation = true
        manager.requestWhenInUseAuthorization()
    }

    /// One fix, not a stream: enough for a leave-by time, easy on the battery.
    func refresh() {
        wantsLocation = true
        guard isAuthorized, !isLocating else { return }
        coordinate = nil
        horizontalAccuracy = nil
        errorMessage = nil
        isLocating = true
        manager.requestLocation()
    }

    func stop() {
        wantsLocation = false
        manager.stopUpdatingLocation()
        isLocating = false
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            if !self.isAuthorized {
                self.coordinate = nil
                self.horizontalAccuracy = nil
                self.isLocating = false
            } else if self.wantsLocation {
                self.refresh()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard self.wantsLocation else { return }
            self.isLocating = false
            guard let location = locations.last, Self.isUsable(location) else {
                self.coordinate = nil
                self.errorMessage = "A recent location wasn’t available. Try updating your location again."
                return
            }
            self.coordinate = Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
            self.horizontalAccuracy = location.horizontalAccuracy
            self.errorMessage = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            guard self.wantsLocation else { return }
            self.isLocating = false
            self.coordinate = nil
            self.errorMessage = error.localizedDescription
        }
    }

    /// Core Location may deliver a cached fix. Do not label an old or invalid
    /// coordinate as the traveller's current position.
    static func isUsable(_ location: CLLocation, now: Date = .now) -> Bool {
        location.horizontalAccuracy >= 0
            && CLLocationCoordinate2DIsValid(location.coordinate)
            && (-5...120).contains(now.timeIntervalSince(location.timestamp))
    }
}
