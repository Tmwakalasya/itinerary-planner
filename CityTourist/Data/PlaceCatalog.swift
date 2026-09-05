import Foundation
import Observation

/// Every place the app has seen this session, keyed by id.
///
/// Itineraries persist only a `placeID`, so any screen rendering a saved stop
/// needs to resolve that id without knowing where it came from. The directory
/// starts seeded with the bundled sample set and takes on live results as they
/// arrive, so lookups keep working whether or not an API key is configured.
@MainActor
enum PlaceDirectory {
    private static var byID: [String: Place] = Dictionary(
        uniqueKeysWithValues: SampleData.places.map { ($0.id, $0) }
    )

    static func place(id: String) -> Place? { byID[id] }

    static func register(_ places: [Place]) {
        for place in places { byID[place.id] = place }
    }
}

/// Loads and caches a city's places, live from Google when a key is present and
/// from the bundled sample set otherwise.
@MainActor
@Observable
final class PlaceCatalog {

    enum Source: Equatable {
        case sample
        case live(fetchedAt: Date)

        var isLive: Bool { if case .live = self { true } else { false } }
    }

    enum LoadState: Equatable {
        case idle, loading, loaded, failed(String)
    }

    private(set) var state: LoadState = .idle
    private(set) var source: Source = .sample

    private var cache: [String: [Place]] = [:]
    private var loadedToday: Set<String> = []

    var isLiveDataAvailable: Bool { Secrets.hasGooglePlacesKey }

    /// Places for a city — live results once they're in, sample data until then.
    func places(in cityID: String) -> [Place] {
        cache[cityID] ?? SampleData.places(in: cityID)
    }

    /// Fetches today's data for a city. Cheap to call repeatedly: it only hits
    /// the network once per city per day.
    func load(city: City, force: Bool = false) async {
        let stamp = "\(city.id)-\(Self.dayStamp)"
        guard force || !loadedToday.contains(stamp) else { return }

        guard let service = GooglePlacesService() else {
            source = .sample
            state = .loaded
            return
        }

        state = .loading
        do {
            let places = try await service.catalogue(for: city)
            guard !places.isEmpty else {
                // A valid key with no results still shouldn't blank the screen.
                state = .failed("No places came back for \(city.name).")
                return
            }
            cache[city.id] = places
            PlaceDirectory.register(places)
            loadedToday.insert(stamp)
            source = .live(fetchedAt: .now)
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Today's date, so a day-old cache refetches on next launch.
    private static var dayStamp: String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }
}

/// Every city the app knows about: the bundled samples plus any the user has
/// searched for. Trips store only a `cityID`, so this is what lets a trip to a
/// searched city still render its name and cover after a relaunch.
@MainActor
enum CityDirectory {
    private static var byID: [String: City] = Dictionary(
        uniqueKeysWithValues: SampleData.cities.map { ($0.id, $0) }
    )

    /// Falls back to the first sample city so callers never have to unwrap.
    /// In practice every city a trip references is registered before use.
    static func city(id: String) -> City {
        byID[id] ?? SampleData.cities[0]
    }

    static func register(_ cities: [City]) {
        for city in cities { byID[city.id] = city }
    }

    static func register(_ city: City) { byID[city.id] = city }
}

/// Debounced city autocomplete backing the "Where to?" field.
@MainActor
@Observable
final class CitySearchModel {
    var query: String = ""
    private(set) var suggestions: [CitySuggestion] = []
    private(set) var isSearching = false
    private(set) var errorMessage: String?

    /// Groups the keystrokes and the eventual details call into one billable
    /// session; rotated once a city is picked.
    private var sessionToken = UUID().uuidString

    var isAvailable: Bool { Secrets.hasGooglePlacesKey }

    /// Shown before the user types anything.
    var popular: [City] { SampleData.cities }

    func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            suggestions = []
            errorMessage = nil
            return
        }
        guard let service = GooglePlacesService() else {
            errorMessage = "Add a Google Places key to search any city."
            return
        }

        // Debounce — a cancelled task here means another keystroke landed.
        do { try await Task.sleep(for: .milliseconds(280)) } catch { return }
        guard !Task.isCancelled else { return }

        isSearching = true
        defer { isSearching = false }
        do {
            suggestions = try await service.autocompleteCities(input: trimmed, sessionToken: sessionToken)
            errorMessage = suggestions.isEmpty ? "No cities match “\(trimmed)”." : nil
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    /// Resolves a suggestion to a full city and registers it for later lookups.
    func resolve(_ suggestion: CitySuggestion) async -> City? {
        guard let service = GooglePlacesService() else { return nil }
        do {
            let city = try await service.cityDetails(placeID: suggestion.id, sessionToken: sessionToken)
            CityDirectory.register(city)
            sessionToken = UUID().uuidString  // the billable session ends here
            return city
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}
