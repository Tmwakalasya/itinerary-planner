import Foundation
import CoreLocation

/// Client for the Google Places API (New).
///
/// Uses Nearby Search to pull what's actually around a city centre right now,
/// including today's opening hours, and maps the response onto our `Place`.
struct GooglePlacesService {

    enum ServiceError: LocalizedError {
        case missingKey
        case http(status: Int, message: String)
        case transport(Error)

        var errorDescription: String? {
            switch self {
            case .missingKey:
                "No Google Places API key configured."
            case let .http(status, message):
                "Google Places returned \(status): \(message)"
            case let .transport(error):
                error.localizedDescription
            }
        }
    }

    private let session: URLSession
    private let apiKey: String

    init?(session: URLSession = .shared) {
        guard let key = Secrets.googlePlacesAPIKey else { return nil }
        self.init(apiKey: key, session: session)
    }

    /// Explicit-key initialiser. Used by tests against a stubbed session.
    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    /// Everything we ask Google for about a place. Field masks are billed, so
    /// this is kept to exactly what the UI renders.
    private static let placeFields = [
        "id",
        "displayName",
        "shortFormattedAddress",
        "location",
        "rating",
        "userRatingCount",
        "priceLevel",
        "types",
        "primaryTypeDisplayName",
        "editorialSummary",
        "photos",
        "currentOpeningHours"
    ]

    /// Nearby Search nests results under `places`, so its mask is prefixed.
    private static let fieldMask = placeFields.map { "places.\($0)" }.joined(separator: ",")
    private static let detailsFieldMask = placeFields.joined(separator: ",")

    // MARK: Nearby search

    /// One category's worth of places around a city centre.
    func nearby(city: City, category: PlaceCategory, radiusMeters: Double = 12_000) async throws -> [Place] {
        var request = URLRequest(url: URL(string: "https://places.googleapis.com/v1/places:searchNearby")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue(Self.fieldMask, forHTTPHeaderField: "X-Goog-FieldMask")

        let body: [String: Any] = [
            "includedTypes": Self.includedTypes(for: category),
            "maxResultCount": 20,
            "rankPreference": "POPULARITY",
            "locationRestriction": [
                "circle": [
                    "center": [
                        "latitude": city.coordinate.latitude,
                        "longitude": city.coordinate.longitude
                    ],
                    "radius": radiusMeters
                ]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await send(request)
        guard let http = response as? HTTPURLResponse else {
            throw ServiceError.http(status: -1, message: "No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ServiceError.http(
                status: http.statusCode,
                message: String(data: data, encoding: .utf8)?.prefix(300).description ?? ""
            )
        }

        let decoded = try JSONDecoder().decode(NearbyResponse.self, from: data)
        return (decoded.places ?? []).compactMap { $0.toPlace(cityID: city.id, fallbackCategory: category) }
    }

    /// All six categories at once, deduped — one city's full catalogue.
    func catalogue(for city: City) async throws -> [Place] {
        try await withThrowingTaskGroup(of: [Place].self) { group in
            for category in PlaceCategory.allCases {
                group.addTask { try await nearby(city: city, category: category) }
            }
            var byID: [String: Place] = [:]
            for try await batch in group {
                for place in batch where byID[place.id] == nil {
                    byID[place.id] = place
                }
            }
            return Array(byID.values).sorted { $0.rating > $1.rating }
        }
    }

    private func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw ServiceError.transport(error)
        }
    }

    // MARK: Place details

    /// One place by id — how a stop or bookmark from an earlier session gets
    /// its details back, since only the id is kept on disk.
    func place(id: String, cityID: String) async throws -> Place {
        guard let url = URL(string: "https://places.googleapis.com/v1/places/\(id)") else {
            throw ServiceError.transport(URLError(.badURL))
        }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue(Self.detailsFieldMask, forHTTPHeaderField: "X-Goog-FieldMask")

        let (data, response) = try await send(request)
        try Self.check(response, data)
        let decoded = try JSONDecoder().decode(GooglePlace.self, from: data)

        // The category it was first found under isn't stored, so an
        // unrecognised type set lands on the broadest one.
        guard let place = decoded.toPlace(cityID: cityID, fallbackCategory: .attraction) else {
            throw ServiceError.http(status: 200, message: "Place details were incomplete.")
        }
        return place
    }

    // MARK: City search

    /// Autocomplete over cities only. Cheap and partial-match friendly, so it
    /// runs on every keystroke (debounced); the expensive details call happens
    /// once, when a suggestion is picked.
    ///
    /// `sessionToken` ties the keystrokes and the eventual details call into
    /// one billable session — pass the same token to `cityDetails`.
    func autocompleteCities(input: String, sessionToken: String) async throws -> [CitySuggestion] {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }

        var request = URLRequest(url: URL(string: "https://places.googleapis.com/v1/places:autocomplete")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "input": trimmed,
            "includedPrimaryTypes": ["(cities)"],
            "sessionToken": sessionToken
        ])

        let (data, response) = try await send(request)
        try Self.check(response, data)
        let decoded = try JSONDecoder().decode(AutocompleteResponse.self, from: data)
        return (decoded.suggestions ?? []).compactMap { suggestion in
            guard let prediction = suggestion.placePrediction,
                  let id = prediction.placeId,
                  let name = prediction.structuredFormat?.mainText?.text
            else { return nil }
            return CitySuggestion(
                id: id,
                name: name,
                region: prediction.structuredFormat?.secondaryText?.text ?? ""
            )
        }
    }

    /// Turns a picked suggestion into a full `City` with coordinates and a cover photo.
    func cityDetails(placeID: String, sessionToken: String) async throws -> City {
        var components = URLComponents(string: "https://places.googleapis.com/v1/places/\(placeID)")!
        components.queryItems = [URLQueryItem(name: "sessionToken", value: sessionToken)]

        var request = URLRequest(url: components.url!)
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue(
            "id,displayName,formattedAddress,location,photos,editorialSummary",
            forHTTPHeaderField: "X-Goog-FieldMask"
        )

        let (data, response) = try await send(request)
        try Self.check(response, data)
        let place = try JSONDecoder().decode(CityDetails.self, from: data)

        guard let name = place.displayName?.text,
              let latitude = place.location?.latitude,
              let longitude = place.location?.longitude
        else { throw ServiceError.http(status: 200, message: "City details were incomplete.") }

        // "Barcelona, Spain" — everything after the city name is the region.
        let country = place.formattedAddress?
            .split(separator: ",")
            .dropFirst()
            .joined(separator: ",")
            .trimmingCharacters(in: .whitespaces) ?? ""

        return City(
            id: place.id ?? placeID,
            name: name,
            country: country,
            tagline: place.editorialSummary?.text ?? "",
            coordinate: Coordinate(latitude: latitude, longitude: longitude),
            photoName: place.photos?.first?.name
        )
    }

    private static func check(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw ServiceError.http(status: -1, message: "No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ServiceError.http(
                status: http.statusCode,
                message: String(data: data, encoding: .utf8)?.prefix(300).description ?? ""
            )
        }
    }

    // MARK: Photos

    /// Places photos are served by resource name; the API redirects to the image.
    static func photoURL(name: String, maxHeight: Int = 900) -> URL? {
        guard let key = Secrets.googlePlacesAPIKey else { return nil }
        var components = URLComponents(string: "https://places.googleapis.com/v1/\(name)/media")
        components?.queryItems = [
            URLQueryItem(name: "maxHeightPx", value: String(maxHeight)),
            URLQueryItem(name: "key", value: key)
        ]
        return components?.url
    }

    // MARK: Type mapping

    private static func includedTypes(for category: PlaceCategory) -> [String] {
        switch category {
        case .attraction: ["tourist_attraction", "historical_landmark", "monument"]
        case .food:       ["restaurant", "cafe", "bakery"]
        case .museum:     ["museum", "art_gallery"]
        case .nature:     ["park", "garden", "national_park"]
        case .activity:   ["market", "shopping_mall", "amusement_park", "zoo"]
        case .nightlife:  ["bar", "night_club"]
        }
    }

    static func category(fromTypes types: [String], fallback: PlaceCategory) -> PlaceCategory {
        let set = Set(types)
        if !set.isDisjoint(with: ["night_club", "bar", "pub", "wine_bar"]) { return .nightlife }
        if !set.isDisjoint(with: ["museum", "art_gallery", "performing_arts_theater"]) { return .museum }
        if !set.isDisjoint(with: ["restaurant", "cafe", "bakery", "meal_takeaway", "food"]) { return .food }
        if !set.isDisjoint(with: ["park", "garden", "national_park", "hiking_area", "beach"]) { return .nature }
        if !set.isDisjoint(with: ["tourist_attraction", "historical_landmark", "monument", "church", "place_of_worship"]) { return .attraction }
        if !set.isDisjoint(with: ["market", "shopping_mall", "amusement_park", "zoo"]) { return .activity }
        return fallback
    }

    /// Google doesn't publish visit lengths, so we estimate from the category —
    /// the user can change it on the stop anyway.
    /// `weekdayDescriptions` is Monday-first; `Calendar` weekdays are
    /// Sunday-first (1 = Sunday). Getting this conversion wrong shifts every
    /// opening time by a day silently, so it takes the date as a parameter and
    /// is covered for all seven days in the tests.
    static func todayHours(from descriptions: [String]?, on date: Date = .now,
                           calendar: Calendar = .current) -> String? {
        guard let descriptions, descriptions.count == 7 else { return nil }
        let weekday = calendar.component(.weekday, from: date)  // 1 = Sunday
        let index = (weekday + 5) % 7
        guard descriptions.indices.contains(index) else { return nil }
        // Each entry reads "Tuesday: 9:00 AM – 6:00 PM"; keep just the hours.
        let entry = descriptions[index]
        guard let colon = entry.firstIndex(of: ":") else { return entry }
        return entry[entry.index(after: colon)...].trimmingCharacters(in: .whitespaces)
    }

    static func typicalMinutes(for category: PlaceCategory) -> Int {
        switch category {
        case .attraction: 90
        case .food:       75
        case .museum:     120
        case .nature:     60
        case .activity:   90
        case .nightlife:  110
        }
    }
}

// MARK: - Wire format

private struct NearbyResponse: Decodable {
    let places: [GooglePlace]?
}

private struct GooglePlace: Decodable {
    struct LocalizedText: Decodable { let text: String? }
    struct LatLng: Decodable { let latitude: Double?; let longitude: Double? }
    struct Photo: Decodable { let name: String? }
    struct OpeningHours: Decodable {
        let openNow: Bool?
        let weekdayDescriptions: [String]?
    }

    let id: String?
    let displayName: LocalizedText?
    let shortFormattedAddress: String?
    let location: LatLng?
    let rating: Double?
    let userRatingCount: Int?
    let priceLevel: String?
    let types: [String]?
    let primaryTypeDisplayName: LocalizedText?
    let editorialSummary: LocalizedText?
    let photos: [Photo]?
    let currentOpeningHours: OpeningHours?

    func toPlace(cityID: String, fallbackCategory: PlaceCategory) -> Place? {
        guard let id,
              let name = displayName?.text,
              let latitude = location?.latitude,
              let longitude = location?.longitude
        else { return nil }

        let category = GooglePlacesService.category(fromTypes: types ?? [], fallback: fallbackCategory)
        let summary = editorialSummary?.text
        let typeLabel = primaryTypeDisplayName?.text ?? category.title

        return Place(
            id: id,
            name: name,
            cityID: cityID,
            category: category,
            neighborhood: shortFormattedAddress ?? typeLabel,
            rating: rating ?? 0,
            reviewCount: userRatingCount ?? 0,
            priceLevel: Self.priceLevel(from: priceLevel),
            typicalMinutes: GooglePlacesService.typicalMinutes(for: category),
            blurb: summary ?? typeLabel,
            about: summary ?? "\(typeLabel) in \(shortFormattedAddress ?? "the city").",
            coordinate: Coordinate(latitude: latitude, longitude: longitude),
            tags: Self.tags(from: types ?? []),
            photoName: photos?.first?.name,
            isOpenNow: currentOpeningHours?.openNow,
            todayHours: GooglePlacesService.todayHours(from: currentOpeningHours?.weekdayDescriptions)
        )
    }

    private static func priceLevel(from value: String?) -> Int {
        switch value {
        case "PRICE_LEVEL_FREE", "PRICE_LEVEL_INEXPENSIVE": 1
        case "PRICE_LEVEL_MODERATE": 2
        case "PRICE_LEVEL_EXPENSIVE": 3
        case "PRICE_LEVEL_VERY_EXPENSIVE": 4
        default: 2
        }
    }

    private static func tags(from types: [String]) -> [String] {
        types
            .filter { !["point_of_interest", "establishment"].contains($0) }
            .prefix(3)
            .map { $0.replacingOccurrences(of: "_", with: " ").capitalized }
    }
}


private struct AutocompleteResponse: Decodable {
    struct Suggestion: Decodable {
        struct Prediction: Decodable {
            struct StructuredFormat: Decodable {
                struct Text: Decodable { let text: String? }
                let mainText: Text?
                let secondaryText: Text?
            }
            let placeId: String?
            let structuredFormat: StructuredFormat?
        }
        let placePrediction: Prediction?
    }
    let suggestions: [Suggestion]?
}

private struct CityDetails: Decodable {
    struct LocalizedText: Decodable { let text: String? }
    struct LatLng: Decodable { let latitude: Double?; let longitude: Double? }
    struct Photo: Decodable { let name: String? }

    let id: String?
    let displayName: LocalizedText?
    let formattedAddress: String?
    let location: LatLng?
    let photos: [Photo]?
    let editorialSummary: LocalizedText?
}
