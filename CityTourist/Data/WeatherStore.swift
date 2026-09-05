import Foundation
import Observation

/// Caches one forecast per trip, refetched once a day.
@MainActor
@Observable
final class WeatherStore {

    enum LoadState: Equatable {
        case idle, loading, loaded, unavailable(String)
    }

    private(set) var state: LoadState = .idle

    /// trip id → day key → forecast
    private var byTrip: [Trip.ID: [String: DayForecast]] = [:]
    private var fetched: Set<String> = []

    private let service: WeatherService

    init(service: WeatherService = WeatherService()) {
        self.service = service
    }

    func forecast(for trip: Trip, on date: Date) -> DayForecast? {
        byTrip[trip.id]?[WeatherService.dayKey(for: date)]
    }

    /// True once we have any forecast for this trip, so the UI can decide
    /// whether to leave room for it.
    func hasForecast(for trip: Trip) -> Bool {
        !(byTrip[trip.id]?.isEmpty ?? true)
    }

    func load(trip: Trip, city: City, force: Bool = false) async {
        let stamp = "\(trip.id)-\(WeatherService.dayKey(for: .now))"
        guard force || !fetched.contains(stamp) else { return }

        state = .loading
        do {
            let days = try await service.forecast(
                latitude: city.coordinate.latitude,
                longitude: city.coordinate.longitude,
                from: trip.startDate,
                to: trip.endDate
            )
            byTrip[trip.id] = Dictionary(uniqueKeysWithValues: days.map { ($0.dayKey, $0) })
            fetched.insert(stamp)
            state = .loaded
        } catch let error as WeatherService.ServiceError {
            // A trip booked months out simply has no forecast yet; that's not
            // a failure worth shouting about.
            state = .unavailable(error.localizedDescription)
        } catch {
            state = .unavailable(error.localizedDescription)
        }
    }
}
