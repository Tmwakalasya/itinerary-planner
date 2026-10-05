import Foundation
import MapKit

/// Anything that can time a hop between two places: `RouteService` in the
/// app, a fake in tests, since MapKit can't route offline.
protocol RouteEstimating {
    func leg(from: Place, to: Place) async -> TravelLeg?
}

/// Travel estimates between stops, via MapKit.
///
/// MapKit rather than the Google Routes API on purpose: `MKDirections` is free,
/// needs no key, and an itinerary only ever asks for a handful of short hops.
struct RouteService: RouteEstimating {

    /// Past this, walking stops being the sensible suggestion and we quote
    /// driving instead.
    static let walkingCeilingMinutes = 40

    /// Estimated travel time, preferring walking and falling back to driving
    /// for anything across town. Returns nil when MapKit can't route it —
    /// across water, or too far — and the timeline then just reports free time.
    func leg(from: Place, to: Place) async -> TravelLeg? {
        var walkingLeg: TravelLeg?
        if let walking = await estimate(from: from.coordinate, to: to.coordinate, mode: .walking) {
            walkingLeg = TravelLeg(fromPlaceID: from.id, toPlaceID: to.id,
                                   mode: .walking, seconds: walking)
            if let walkingLeg, walkingLeg.minutes <= Self.walkingCeilingMinutes {
                return walkingLeg
            }
        }
        if let driving = await estimate(from: from.coordinate, to: to.coordinate, mode: .driving) {
            return TravelLeg(fromPlaceID: from.id, toPlaceID: to.id,
                             mode: .driving, seconds: driving)
        }
        // A long walk is still better information than none.
        return walkingLeg
    }

    private func estimate(from: Coordinate, to: Coordinate, mode: TravelMode) async -> TimeInterval? {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: from.clLocation))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to.clLocation))
        request.transportType = mode == .walking ? .walking : .automobile

        // calculateETA is lighter than a full route — we only need the time.
        do {
            let response = try await MKDirections(request: request).calculateETA()
            return response.expectedTravelTime
        } catch {
            return nil
        }
    }
}
