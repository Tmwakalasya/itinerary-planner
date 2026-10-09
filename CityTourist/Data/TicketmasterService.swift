import Foundation

/// Client for Ticketmaster's Discovery API: what's on near a city during a trip.
///
/// Its terms allow caching event content only "for reasonable periods" while
/// providing the service, and expect calls to answer what someone is doing.
/// So events are fetched when a trip is opened and kept in memory for the
/// session, and a stop stores only the event's id, looked up again after a
/// relaunch the way Google places are.
struct TicketmasterService {

    enum ServiceError: LocalizedError {
        case http(status: Int)
        case transport(Error)
        case unusable
        /// This phone has used its allowance for now; see `RequestBudget`.
        case rateLimited

        var errorDescription: String? {
            switch self {
            case let .http(status): "Ticketmaster returned \(status)."
            case let .transport(error): error.localizedDescription
            case .unusable: "That event is missing its time or venue."
            case .rateLimited: "Events are paused on this iPhone for a while. Try again later."
            }
        }
    }

    /// Far enough to take in a city and its arenas, near enough to get to.
    static let radiusKilometres = 25

    private let session: URLSession
    private let apiKey: String
    private let budget: RequestBudget

    init?(session: URLSession = .shared) {
        guard let key = Secrets.ticketmasterAPIKey else { return nil }
        self.init(apiKey: key, session: session, budget: .ticketmaster)
    }

    /// Explicit-key initialiser. Used by tests against a stubbed session.
    init(apiKey: String, session: URLSession = .shared, budget: RequestBudget = .unlimited) {
        self.apiKey = apiKey
        self.session = session
        self.budget = budget
    }

    /// Events within the radius of `center` over a trip's days, earliest first.
    ///
    /// The window is sent in UTC but events are dated in the venue's own
    /// timezone, so it's widened a day either side; callers match on each
    /// event's local date.
    func events(near center: Coordinate, cityID: String, from start: Date, to end: Date,
                calendar: Calendar = .current) async throws -> [Place] {
        let first = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: start)) ?? start
        let last = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: end)) ?? end

        var components = URLComponents(string: "https://app.ticketmaster.com/discovery/v2/events.json")!
        components.queryItems = [
            URLQueryItem(name: "apikey", value: apiKey),
            URLQueryItem(name: "geoPoint", value: Geohash.encode(latitude: center.latitude, longitude: center.longitude)),
            URLQueryItem(name: "radius", value: String(Self.radiusKilometres)),
            URLQueryItem(name: "unit", value: "km"),
            URLQueryItem(name: "startDateTime", value: Self.utc.string(from: first)),
            URLQueryItem(name: "endDateTime", value: Self.utc.string(from: last)),
            URLQueryItem(name: "sort", value: "date,asc"),
            URLQueryItem(name: "size", value: "100"),
            URLQueryItem(name: "locale", value: "*")
        ]
        let data = try await get(components.url!)
        let page = try JSONDecoder().decode(SearchResponse.self, from: data)
        return (page.embedded?.events ?? []).compactMap { $0.toPlace(cityID: cityID) }
    }

    /// One event by its Ticketmaster id, for a stop restored after a relaunch.
    func event(id: String, cityID: String) async throws -> Place {
        var components = URLComponents(string: "https://app.ticketmaster.com/discovery/v2/events/\(id).json")
        components?.queryItems = [URLQueryItem(name: "apikey", value: apiKey),
                                  URLQueryItem(name: "locale", value: "*")]
        guard let url = components?.url else { throw ServiceError.transport(URLError(.badURL)) }
        let data = try await get(url)
        guard let place = try JSONDecoder().decode(TicketmasterEvent.self, from: data).toPlace(cityID: cityID)
        else { throw ServiceError.unusable }
        return place
    }

    private func get(_ url: URL) async throws -> Data {
        guard budget.spend() else { throw ServiceError.rateLimited }
        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw ServiceError.transport(error)
        }
        guard let http = response as? HTTPURLResponse else { throw ServiceError.http(status: -1) }
        guard (200..<300).contains(http.statusCode) else { throw ServiceError.http(status: http.statusCode) }
        return data
    }

    /// "2026-10-07T04:00:00Z", the form Ticketmaster takes dates in.
    private static let utc: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

// MARK: - Wire format

private struct SearchResponse: Decodable {
    struct Embedded: Decodable { let events: [TicketmasterEvent]? }
    let embedded: Embedded?
    enum CodingKeys: String, CodingKey { case embedded = "_embedded" }
}

private struct TicketmasterEvent: Decodable {
    struct Dates: Decodable {
        struct Start: Decodable {
            let localDate: String?
            let localTime: String?
            let timeTBA: Bool?
            let noSpecificTime: Bool?
        }
        struct Status: Decodable { let code: String? }
        let start: Start?
        let status: Status?
    }
    struct Image: Decodable {
        let url: String?
        let ratio: String?
        let width: Int?
    }
    struct Classification: Decodable {
        struct Name: Decodable { let name: String? }
        let segment: Name?
        let genre: Name?
    }
    struct PriceRange: Decodable {
        let min: Double?
        let max: Double?
        let currency: String?
    }
    struct Embedded: Decodable {
        struct Venue: Decodable {
            struct Location: Decodable {
                // Ticketmaster sends coordinates as strings.
                let latitude: String?
                let longitude: String?
            }
            let name: String?
            let location: Location?
        }
        let venues: [Venue]?
    }

    let id: String?
    let name: String?
    let url: String?
    let dates: Dates?
    let images: [Image]?
    let classifications: [Classification]?
    let priceRanges: [PriceRange]?
    let embedded: Embedded?

    enum CodingKeys: String, CodingKey {
        case id, name, url, dates, images, classifications, priceRanges
        case embedded = "_embedded"
    }

    /// Nil for anything that can't go in a plan: no set time, called off, or
    /// nowhere to put on the map.
    func toPlace(cityID: String) -> Place? {
        guard let id, let name,
              let start = dates?.start, start.timeTBA != true, start.noSpecificTime != true,
              let localDate = start.localDate, let minute = Self.minute(start.localTime),
              !["cancelled", "postponed"].contains(dates?.status?.code ?? ""),
              let venue = embedded?.venues?.first,
              let latitude = venue.location?.latitude.flatMap(Double.init),
              let longitude = venue.location?.longitude.flatMap(Double.init)
        else { return nil }

        let segment = classifications?.first?.segment?.name.flatMap(Self.meaningful)
        let genre = classifications?.first?.genre?.name.flatMap(Self.meaningful).flatMap { $0 == segment ? nil : $0 }
        let kind = [segment, genre].compactMap { $0 }.joined(separator: " · ")
        let venueName = venue.name ?? "Venue"
        let info = EventInfo(ticketURL: url.flatMap(URL.init(string:)), localDate: localDate,
                             startMinute: minute, venue: venueName,
                             kind: kind.isEmpty ? "Event" : kind, price: Self.price(priceRanges?.first))

        return Place(
            id: Place.eventIDPrefix + id,
            name: name,
            cityID: cityID,
            category: .activity,
            neighborhood: venueName,
            rating: 0,
            reviewCount: 0,
            priceLevel: 2,
            typicalMinutes: Self.duration(for: segment),
            blurb: info.kind,
            about: "\(info.kind) at \(venueName).",
            coordinate: Coordinate(latitude: latitude, longitude: longitude),
            tags: [segment, genre].compactMap { $0 },
            imageURL: Self.image(from: images),
            event: info
        )
    }

    /// "20:00:00" → 1200.
    private static func minute(_ time: String?) -> Int? {
        guard let parts = time?.split(separator: ":"), parts.count >= 2,
              let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
        return hour * 60 + minute
    }

    /// Ticketmaster fills unknown classifications with "Undefined".
    private static func meaningful(_ name: String) -> String? {
        ["Undefined", "Miscellaneous", "Other"].contains(name) ? nil : name
    }

    /// Events don't list a length, so a typical one for the kind: the stop
    /// can still be edited.
    private static func duration(for segment: String?) -> Int {
        switch segment {
        case "Sports": 180
        case "Music", "Arts & Theatre": 150
        default: 120
        }
    }

    /// A wide image big enough for a card, without fetching the largest.
    private static func image(from images: [Image]?) -> URL? {
        let wide = (images ?? []).filter { $0.ratio == "16_9" }
        let pick = wide.filter { ($0.width ?? 0) >= 640 }.min { ($0.width ?? 0) < ($1.width ?? 0) }
            ?? wide.max { ($0.width ?? 0) < ($1.width ?? 0) }
            ?? images?.first
        return pick?.url.flatMap(URL.init(string:))
    }

    /// "€25–€60", or "€25" when there's one price.
    static func price(_ range: PriceRange?) -> String? {
        guard let range, let currency = range.currency, let min = range.min else { return nil }
        let style = FloatingPointFormatStyle<Double>.Currency(code: currency).precision(.fractionLength(0))
        guard let max = range.max, max > min else { return min.formatted(style) }
        return "\(min.formatted(style))–\(max.formatted(style))"
    }
}
