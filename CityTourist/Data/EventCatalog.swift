import Foundation
import Observation

/// What's on near a trip's city during its dates.
///
/// Fetched once, when the trip is opened, and kept for the session:
/// Ticketmaster's terms allow caching only for as long as the service needs
/// it, and expect requests to answer what someone is doing. Without a
/// Ticketmaster key there are simply no events.
@MainActor
@Observable
final class EventCatalog {
    /// trip id → day key → events that day, earliest first.
    private var byTrip: [Trip.ID: [String: [Place]]] = [:]
    private var loading: Set<Trip.ID> = []

    private let makeService: () -> TicketmasterService?

    /// Tests pass a client wired to a stubbed session.
    init(makeService: @escaping () -> TicketmasterService? = { TicketmasterService() }) {
        self.makeService = makeService
    }

    func events(for trip: Trip, on date: Date) -> [Place] {
        byTrip[trip.id]?[WeatherService.dayKey(for: date)] ?? []
    }

    /// Once per trip per session. A failed fetch isn't remembered, so opening
    /// the trip again tries again.
    func load(trip: Trip, city: City) async {
        guard byTrip[trip.id] == nil, !loading.contains(trip.id), let service = makeService() else { return }
        loading.insert(trip.id)
        defer { loading.remove(trip.id) }

        guard let found = try? await service.events(near: city.coordinate, cityID: city.id,
                                                     from: trip.startDate, to: trip.endDate)
        else { return }

        // The search window runs a day either side; keep only the trip's days.
        let days = Set(trip.days.map { WeatherService.dayKey(for: $0.date) })
        let onTrip = found.filter { $0.event.map { days.contains($0.localDate) } ?? false }
        // Registered so a stop added from one resolves straight away.
        PlaceDirectory.register(onTrip)
        byTrip[trip.id] = Dictionary(grouping: onTrip) { $0.event?.localDate ?? "" }
            .mapValues { $0.sorted { ($0.event?.startMinute ?? 0) < ($1.event?.startMinute ?? 0) } }
    }
}
