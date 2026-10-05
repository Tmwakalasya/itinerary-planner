import Foundation
import Observation
import CoreLocation

/// Every place the app has seen this session, keyed by id.
///
/// Itineraries persist only a `placeID`, so any screen rendering a saved stop
/// needs to resolve that id without knowing where it came from. The directory
/// starts seeded with the bundled sample set and takes on live results as they
/// arrive, so lookups keep working whether or not an API key is configured.
@MainActor
enum PlaceDirectory {
    /// Observable, so a view that looked up a place it didn't have yet redraws
    /// when the place arrives — a stop restored after a relaunch resolves a
    /// moment after the screen first renders.
    // fileprivate, not private: the macro's generated extension must see it.
    @MainActor
    @Observable
    fileprivate final class Storage {
        var byID: [String: Place]
        init(_ places: [Place]) {
            byID = Dictionary(uniqueKeysWithValues: places.map { ($0.id, $0) })
        }
    }

    private static let storage = Storage(SampleData.places)

    static func place(id: String) -> Place? { storage.byID[id] }

    static func register(_ places: [Place]) {
        guard !places.isEmpty else { return }
        // One mutation rather than one per place, so observers redraw once.
        storage.byID.merge(places.map { ($0.id, $0) }) { _, new in new }
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

    /// Saved place ids being looked up right now.
    private(set) var resolvingPlaceIDs: Set<String> = []
    /// Saved place ids whose last lookup failed. The next `resolve` retries them.
    private(set) var failedPlaceIDs: Set<String> = []

    private var cache: [String: [Place]] = [:]
    private var loadedToday: Set<String> = []

    private let makeService: () -> GooglePlacesService?

    /// Tests pass a client wired to a stubbed session.
    init(makeService: @escaping () -> GooglePlacesService? = { GooglePlacesService() }) {
        self.makeService = makeService
    }

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

        guard let service = makeService() else {
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

    /// Looks up any of these places the app doesn't already have, one Place
    /// Details call each.
    ///
    /// Trips and bookmarks persist place ids only — Google's terms allow
    /// keeping an id indefinitely but not the rest of a place — so after a
    /// relaunch anything outside the bundled samples has to be fetched again.
    /// Places already known, or already being fetched, cost nothing.
    ///
    /// `cityID` is the city the places belong to. Pass nil when it isn't known,
    /// and each place is assigned to the nearest known city instead.
    func resolve(_ placeIDs: some Sequence<String>, cityID: String?) async {
        let missing = Set(placeIDs).filter {
            PlaceDirectory.place(id: $0) == nil && !resolvingPlaceIDs.contains($0)
        }
        guard !missing.isEmpty else { return }

        guard let service = makeService() else {
            failedPlaceIDs.formUnion(missing)
            return
        }

        resolvingPlaceIDs.formUnion(missing)
        failedPlaceIDs.subtract(missing)

        var found: [Place] = []
        await withTaskGroup(of: (String, Place?).self) { group in
            for id in missing {
                group.addTask { (id, try? await service.place(id: id, cityID: cityID ?? "")) }
            }
            for await (id, place) in group {
                guard var place else {
                    // Leaving the screen cancels the lookup; that isn't a failure.
                    if !Task.isCancelled { failedPlaceIDs.insert(id) }
                    continue
                }
                if cityID == nil { place.cityID = CityDirectory.nearest(to: place.coordinate).id }
                found.append(place)
            }
        }

        // Registered together rather than as each arrives: the timeline keys
        // its travel-time lookup on which places have resolved, and a trickle
        // would restart that lookup once per place.
        PlaceDirectory.register(found)
        resolvingPlaceIDs.subtract(missing)
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

    /// The known city closest to a coordinate. Only used for bookmarks made
    /// before bookmarks recorded which city they came from.
    static func nearest(to coordinate: Coordinate) -> City {
        let target = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        func distance(_ city: City) -> CLLocationDistance {
            CLLocation(latitude: city.coordinate.latitude, longitude: city.coordinate.longitude)
                .distance(from: target)
        }
        return byID.values.min { distance($0) < distance($1) } ?? SampleData.cities[0]
    }
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
