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
    /// The most recently queued lookup. Each waits for the one before it.
    private var queue: Task<Void, Never>?

    private let service: any RouteEstimating

    init(service: any RouteEstimating = RouteService()) {
        self.service = service
    }

    func leg(from: Place, to: Place) -> TravelLeg? {
        cache[Self.key(from.id, to.id)]
    }

    /// Fills in any missing legs for one day's stops, in order.
    ///
    /// A lookup that arrives while another is running queues behind it rather
    /// than being dropped — switching days mid-load used to leave the new day
    /// without travel times. The work runs in its own task, so leaving the
    /// screen can't cut a request short and have it cached as unroutable.
    func loadLegs(for stops: [ItineraryStop]) async {
        let places = stops.compactMap { PlaceDirectory.place(id: $0.placeID) }
        guard places.count > 1 else { return }

        let previous = queue
        let lookup = Task {
            await previous?.value
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
        queue = lookup
        await lookup.value
    }

    private static func key(_ from: String, _ to: String) -> String { "\(from)|\(to)" }
}
