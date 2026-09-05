import Foundation

/// The itinerary as it travels inside a share link.
///
/// Keys are short on purpose: the whole thing is base64'd into a URL fragment,
/// so every character counts. Nothing here is secret, but note that a fragment
/// is never sent to the server — the plan stays out of the host's logs.
struct SharedItinerary: Codable, Equatable {
    var v: Int = 1
    var title: String
    var city: String
    var days: [Day]

    struct Day: Codable, Equatable {
        /// "2026-09-15"
        var d: String
        var stops: [Stop]
    }

    struct Stop: Codable, Equatable {
        /// Minutes past midnight; the page formats it for the reader's locale.
        var t: Int
        var n: String
        var b: String?
        var note: String?
        /// Duration in minutes.
        var m: Int
        var lat: Double?
        var lon: Double?
    }
}

enum ShareLinkBuilder {

    /// Beyond this the link still works in browsers, but it gets long enough
    /// that intermediaries — link previews, some messaging clients — may
    /// mangle it. A normal trip lands around 1–3 KB; this is roughly 40 stops.
    static let comfortableURLLength = 8000

    static func isOversized(_ url: URL) -> Bool {
        url.absoluteString.count > comfortableURLLength
    }

    enum BuildError: LocalizedError {
        case emptyItinerary
        var errorDescription: String? {
            "This trip has no stops yet, so there's nothing to share."
        }
    }

    /// Flattens a trip into the payload the web viewer renders.
    static func snapshot(trip: Trip, city: City, resolve: (String) -> Place?) -> SharedItinerary {
        SharedItinerary(
            title: trip.title,
            city: city.displayName,
            days: trip.days.map { day in
                SharedItinerary.Day(
                    d: WeatherService.dayKey(for: day.date),
                    stops: day.stops.compactMap { stop in
                        guard let place = resolve(stop.placeID) else { return nil }
                        return SharedItinerary.Stop(
                            t: stop.startMinute,
                            n: place.name,
                            b: place.blurb.isEmpty ? nil : place.blurb,
                            note: stop.note.isEmpty ? nil : stop.note,
                            m: stop.durationMinutes,
                            lat: place.coordinate.latitude,
                            lon: place.coordinate.longitude
                        )
                    }
                )
            }
        )
    }

    /// Encodes the payload into a base64url string with no padding, safe to
    /// drop straight into a URL fragment.
    static func encode(_ itinerary: SharedItinerary) throws -> String {
        let data = try JSONEncoder().encode(itinerary)
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ encoded: String) throws -> SharedItinerary {
        var base64 = encoded
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        // Restore the padding base64url drops.
        let remainder = base64.count % 4
        if remainder > 0 { base64 += String(repeating: "=", count: 4 - remainder) }

        guard let data = Data(base64Encoded: base64) else {
            throw BuildError.emptyItinerary
        }
        return try JSONDecoder().decode(SharedItinerary.self, from: data)
    }

    /// The full link to hand to someone.
    static func url(trip: Trip, city: City, resolve: (String) -> Place?) throws -> URL {
        let itinerary = snapshot(trip: trip, city: city, resolve: resolve)
        guard itinerary.days.contains(where: { !$0.stops.isEmpty }) else {
            throw BuildError.emptyItinerary
        }
        let encoded = try encode(itinerary)
        guard let url = URL(string: "\(Secrets.shareBaseURL)#i=\(encoded)") else {
            throw BuildError.emptyItinerary
        }
        return url
    }
}
