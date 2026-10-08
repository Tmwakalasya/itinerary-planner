import Foundation
import MapKit

/// Anything that can time a hop between two places: `RouteService` in the
/// app, a fake in tests, since MapKit can't route offline.
protocol RouteEstimating {
    /// `departing` matters for transit, which runs to a timetable; nil is now.
    func leg(from: Place, to: Place, by gettingAround: GettingAround, departing: Date?) async -> TravelLeg?
}

/// Travel estimates between stops, via MapKit.
///
/// MapKit rather than the Google Routes API on purpose: `MKDirections` is free,
/// needs no key, and an itinerary only ever asks for a handful of short hops.
struct RouteService: RouteEstimating {

    /// Up to this, a hop is walked however the trip gets around.
    static let walkingCeilingMinutes = 20
    /// Where Apple Maps has no transit, a walk this long still beats a taxi.
    static let longestWalkMinutes = 40

    /// Estimated travel time: a walk when it's short, otherwise transit or a
    /// drive, as the trip gets around. Without transit data for the city, a
    /// trip without a car walks up to `longestWalkMinutes` before driving.
    /// Returns nil when MapKit can't route it — across water, or too far —
    /// and the timeline then just reports free time.
    func leg(from: Place, to: Place, by gettingAround: GettingAround, departing: Date?) async -> TravelLeg? {
        await leg(from: from.coordinate, fromID: from.id, to: to.coordinate, toID: to.id,
                  by: gettingAround, departing: departing)
    }

    /// From wherever you are right now to a place, for the Today screen.
    func leg(fromHere here: Coordinate, to place: Place, by gettingAround: GettingAround) async -> TravelLeg? {
        await leg(from: here, fromID: "here", to: place.coordinate, toID: place.id,
                  by: gettingAround, departing: nil)
    }

    private func leg(from: Coordinate, fromID: String, to: Coordinate, toID: String,
                     by gettingAround: GettingAround, departing: Date?) async -> TravelLeg? {
        func hop(_ mode: TravelMode, _ seconds: TimeInterval) -> TravelLeg {
            TravelLeg(fromPlaceID: fromID, toPlaceID: toID, mode: mode, seconds: seconds)
        }

        let walking = await estimate(from: from, to: to, mode: .walking, departing: departing).map { hop(.walking, $0) }
        if let walking, walking.minutes <= Self.walkingCeilingMinutes {
            return walking
        }
        if gettingAround == .transit {
            if let transit = await estimate(from: from, to: to, mode: .transit, departing: departing) {
                // A slow connection loses to walking it.
                return walking.map { $0.seconds <= transit ? $0 : hop(.transit, transit) } ?? hop(.transit, transit)
            }
            if let walking, walking.minutes <= Self.longestWalkMinutes {
                return walking
            }
        }
        if let driving = await estimate(from: from, to: to, mode: .driving, departing: departing) {
            return hop(.driving, driving)
        }
        // A long walk is still better information than none.
        return walking
    }

    private func estimate(from: Coordinate, to: Coordinate, mode: TravelMode, departing: Date?) async -> TimeInterval? {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: from.clLocation))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to.clLocation))
        switch mode {
        case .walking: request.transportType = .walking
        case .driving: request.transportType = .automobile
        case .transit: request.transportType = .transit
        }
        if let departing { request.departureDate = departing }

        // calculateETA is lighter than a full route — we only need the time.
        do {
            let response = try await MKDirections(request: request).calculateETA()
            return response.expectedTravelTime
        } catch {
            return nil
        }
    }
}
