import Foundation
import Observation

/// Caches travel estimates between stops.
///
/// Legs are fetched one at a time rather than concurrently: MapKit throttles
/// bursts of direction requests, and a day only ever has a handful of hops.
@MainActor
@Observable
final class RouteStore {

    private var cache: [String: TravelLeg] = [:]
    /// Pairs MapKit couldn't route, so we stop asking.
    private var unroutable: Set<String> = []
    private var inFlight = false

    private let service: RouteService

    init(service: RouteService = RouteService()) {
        self.service = service
    }

    func leg(from: Place, to: Place) -> TravelLeg? {
        cache[Self.key(from.id, to.id)]
    }

    /// Fills in any missing legs for one day's stops, in order.
    func loadLegs(for stops: [ItineraryStop]) async {
        guard !inFlight else { return }
        let places = stops.compactMap { PlaceDirectory.place(id: $0.placeID) }
        guard places.count > 1 else { return }

        inFlight = true
        defer { inFlight = false }

        for (a, b) in zip(places, places.dropFirst()) {
            let key = Self.key(a.id, b.id)
            guard cache[key] == nil, !unroutable.contains(key) else { continue }
            if let leg = await service.leg(from: a, to: b) {
                cache[key] = leg
            } else {
                unroutable.insert(key)
            }
        }
    }

    private static func key(_ from: String, _ to: String) -> String { "\(from)|\(to)" }
}
