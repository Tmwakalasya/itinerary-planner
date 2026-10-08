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

    func leg(from: Place, to: Place, by gettingAround: GettingAround) -> TravelLeg? {
        cache[Self.key(from.id, to.id, gettingAround)]
    }

    /// Fills in any missing legs for one day's stops, in order.
    ///
    /// A lookup that arrives while another is running queues behind it rather
    /// than being dropped — switching days mid-load used to leave the new day
    /// without travel times. The work runs in its own task, so leaving the
    /// screen can't cut a request short and have it cached as unroutable.
    ///
    /// Each hop is timed from when the stop before it ends on `date`, so
    /// transit is looked up on that day's timetable. A hop already past is
    /// timed from now.
    func loadLegs(for stops: [ItineraryStop], on date: Date, by gettingAround: GettingAround,
                  calendar: Calendar = .current) async {
        let hops = stops.compactMap { stop in
            PlaceDirectory.place(id: stop.placeID).map { (place: $0, leaves: stop.startMinute + stop.durationMinutes) }
        }
        guard hops.count > 1 else { return }

        let previous = queue
        let lookup = Task {
            await previous?.value
            for (a, b) in zip(hops, hops.dropFirst()) {
                let key = Self.key(a.place.id, b.place.id, gettingAround)
                guard cache[key] == nil, !unroutable.contains(key) else { continue }
                let departing = calendar.date(byAdding: .minute, value: a.leaves, to: calendar.startOfDay(for: date))
                    .flatMap { $0 > .now ? $0 : nil }
                if let leg = await service.leg(from: a.place, to: b.place, by: gettingAround, departing: departing) {
                    cache[key] = leg
                } else {
                    unroutable.insert(key)
                }
            }
        }
        queue = lookup
        await lookup.value
    }

    private static func key(_ from: String, _ to: String, _ gettingAround: GettingAround) -> String {
        "\(from)|\(to)|\(gettingAround.rawValue)"
    }
}
