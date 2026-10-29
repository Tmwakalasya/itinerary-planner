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
    @ObservationIgnored private let fixTimeout: Duration
    @ObservationIgnored private var timeout: Task<Void, Never>?

    /// What the screens say when there's no fix to be had: indoors, a
    /// simulator with no location set, or Core Location giving up.
    static let noFixMessage = "Your phone couldn’t work out where you are. Try again, or enter where you’re starting from."

    var isAuthorized: Bool {
        authorization == .authorizedWhenInUse || authorization == .authorizedAlways
    }

    /// Asking is pointless once someone has said no; Settings is the way back.
    var canAsk: Bool { authorization == .notDetermined }

    /// `fixTimeout`: Core Location can sit on a request indefinitely, and
    /// "Finding your location…" mustn't.
    init(desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyHundredMeters,
         fixTimeout: Duration = .seconds(15)) {
        self.fixTimeout = fixTimeout
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
        timeout = Task { [fixTimeout] in
            try? await Task.sleep(for: fixTimeout)
            guard !Task.isCancelled, self.isLocating else { return }
            self.manager.stopUpdatingLocation()
            self.finish(error: Self.noFixMessage)
        }
    }

    func stop() {
        wantsLocation = false
        timeout?.cancel()
        manager.stopUpdatingLocation()
        isLocating = false
    }

    private func finish(error: String?) {
        timeout?.cancel()
        isLocating = false
        errorMessage = error
        if error != nil { coordinate = nil }
    }

    static func message(for error: Error) -> String {
        (error as? CLError)?.code == .network
            ? "Finding where you are needs a connection. Try again, or enter where you’re starting from."
            : noFixMessage
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            if !self.isAuthorized {
                self.finish(error: nil)
                self.coordinate = nil
                self.horizontalAccuracy = nil
            } else if self.wantsLocation {
                self.refresh()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard self.wantsLocation else { return }
            guard let location = locations.last, Self.isUsable(location) else {
                self.finish(error: "A recent location wasn’t available. Try again, or enter where you’re starting from.")
                return
            }
            self.finish(error: nil)
            self.coordinate = Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
            self.horizontalAccuracy = location.horizontalAccuracy
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            guard self.wantsLocation else { return }
            self.finish(error: Self.message(for: error))
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
