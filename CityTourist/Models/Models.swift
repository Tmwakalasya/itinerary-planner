import Foundation
import CoreLocation

// MARK: - Place

enum PlaceCategory: String, Codable, CaseIterable, Identifiable, Hashable {
    case attraction, food, museum, nature, activity, nightlife

    var id: String { rawValue }

    var title: String {
        switch self {
        case .attraction: "Landmarks"
        case .food:       "Food"
        case .museum:     "Museums"
        case .nature:     "Outdoors"
        case .activity:   "Things to do"
        case .nightlife:  "Nightlife"
        }
    }

    /// Icons echo the little line-art glyphs on Airbnb's category rail.
    var symbol: String {
        switch self {
        case .attraction: "building.columns"
        case .food:       "fork.knife"
        case .museum:     "photo.artframe"
        case .nature:     "leaf"
        case .activity:   "figure.walk"
        case .nightlife:  "wineglass"
        }
    }
}

struct Coordinate: Codable, Hashable {
    var latitude: Double
    var longitude: Double

    var clLocation: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct Place: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var cityID: String
    var category: PlaceCategory
    var neighborhood: String
    var rating: Double
    var reviewCount: Int
    /// 1...4, rendered as $ … $$$$
    var priceLevel: Int
    /// Typical visit length in minutes.
    var typicalMinutes: Int
    var blurb: String
    var about: String
    var coordinate: Coordinate
    var tags: [String]

    // Live-data fields. Nil when the place came from the bundled sample set.
    /// Google Places photo resource name, e.g. `places/ChIJ…/photos/…`.
    var photoName: String? = nil
    var isOpenNow: Bool? = nil
    /// Today's opening hours as Google reports them, e.g. "9:00 AM – 6:00 PM".
    var todayHours: String? = nil
    /// The regular weekly schedule, for checking a stop on any day of a trip.
    var weeklyHours: WeeklyHours? = nil
    /// A picture from somewhere other than Google, e.g. an event's poster.
    var imageURL: URL? = nil
    /// Set when this is a ticketed event rather than somewhere to visit.
    var event: EventInfo? = nil

    var photoURL: URL? {
        imageURL ?? photoName.flatMap { GooglePlacesService.photoURL(name: $0) }
    }

    /// Short form for the feed card: "Open now" / "Closed".
    var openLabel: String? {
        guard let isOpenNow else { return nil }
        return isOpenNow ? "Open now" : "Closed"
    }

    /// "Open now · closes 6:00 PM" style status line, when we know it.
    var openStatus: String? {
        switch (isOpenNow, todayHours) {
        case let (.some(open), .some(hours)):
            return open ? "Open now · \(hours)" : "Closed · \(hours)"
        case let (.some(open), .none):
            return open ? "Open now" : "Closed now"
        case let (.none, .some(hours)):
            return "Today \(hours)"
        default:
            return nil
        }
    }

    var priceLabel: String { String(repeating: "$", count: max(1, min(4, priceLevel))) }

    var durationLabel: String {
        let h = typicalMinutes / 60, m = typicalMinutes % 60
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) hr" : "\(h) hr \(m) min"
    }
}

// MARK: - City

struct City: Identifiable, Codable, Hashable {
    /// Google place id for a searched city; a slug for the bundled samples.
    var id: String
    var name: String
    var country: String
    /// One-line description. Empty for most searched cities — Google rarely
    /// has an editorial summary for a locality.
    var tagline: String
    var coordinate: Coordinate
    /// Google Places photo resource name for the city itself, used as the
    /// cover image on trip cards.
    var photoName: String? = nil

    var displayName: String {
        country.isEmpty ? name : "\(name), \(country)"
    }

    var photoURL: URL? {
        photoName.flatMap { GooglePlacesService.photoURL(name: $0) }
    }
}

/// An autocomplete hit, before we've paid for the details call.
struct CitySuggestion: Identifiable, Hashable {
    var id: String
    var name: String
    var region: String
}

// MARK: - Itinerary

struct ItineraryStop: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var placeID: String
    /// Minutes past midnight, so a stop's time survives a change of date.
    var startMinute: Int
    var durationMinutes: Int
    var note: String = ""
    var remindMe: Bool = false
    /// A reservation or timed ticket: the time is fixed, so re-planning the
    /// day works around it rather than moving it.
    var isBooked: Bool = false

    var timeLabel: String {
        let date = Calendar.current.date(
            bySettingHour: startMinute / 60, minute: startMinute % 60, second: 0, of: .now
        ) ?? .now
        return date.formatted(.dateTime.hour().minute())
    }
}

extension ItineraryStop {
    /// Stops saved before bookings existed have no `isBooked` key; the
    /// synthesized decoder would reject them and with them the whole save.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        placeID = try container.decode(String.self, forKey: .placeID)
        startMinute = try container.decode(Int.self, forKey: .startMinute)
        durationMinutes = try container.decode(Int.self, forKey: .durationMinutes)
        note = try container.decode(String.self, forKey: .note)
        remindMe = try container.decode(Bool.self, forKey: .remindMe)
        isBooked = try container.decodeIfPresent(Bool.self, forKey: .isBooked) ?? false
    }
}

struct ItineraryDay: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var date: Date
    var stops: [ItineraryStop] = []

    var isEmpty: Bool { stops.isEmpty }
}

// MARK: - Sharing

enum SharePermission: String, Codable, CaseIterable, Identifiable {
    case view, edit
    var id: String { rawValue }
    var title: String { self == .view ? "Can view" : "Can edit" }
}

struct Collaborator: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var email: String
    var permission: SharePermission

    var initials: String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }
}

// MARK: - Trip

struct Trip: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var cityID: String
    var title: String
    var startDate: Date
    var endDate: Date
    var days: [ItineraryDay] = []
    var collaborators: [Collaborator] = []
    var isDownloadedForOffline: Bool = false
    /// Where the traveller is staying. Each day starts and ends there, so it
    /// shapes the order the planner suggests and the first leave-by time.
    var lodging: Lodging? = nil
    /// Stable slug used to build the public share link.
    var shareSlug: String = String(UUID().uuidString.prefix(8)).lowercased()

    var stopCount: Int { days.reduce(0) { $0 + $1.stops.count } }

    var dateRangeLabel: String {
        let cal = Calendar.current
        let sameMonth = cal.isDate(startDate, equalTo: endDate, toGranularity: .month)
        let start = startDate.formatted(.dateTime.month(.abbreviated).day())
        let end = sameMonth
            ? endDate.formatted(.dateTime.day())
            : endDate.formatted(.dateTime.month(.abbreviated).day())
        return "\(start) – \(end)"
    }

}

/// A hotel or address the traveller picked themselves, found with Apple Maps.
struct Lodging: Codable, Hashable {
    var name: String
    var coordinate: Coordinate
}

// MARK: - Account

struct Account: Codable, Hashable {
    var name: String
    var email: String

    var initials: String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }
}
