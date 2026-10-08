import Foundation

/// What makes a place an event: it happens once, at a set time, with tickets.
///
/// Events ride on `Place` so a stop at one works everywhere a stop at a
/// museum does: the timeline, the map, share links, reminders, and being
/// looked up again by id after a relaunch.
struct EventInfo: Codable, Hashable {
    /// The event's own page, where tickets are bought.
    var ticketURL: URL?
    /// "2026-10-08", in the venue's own calendar.
    var localDate: String
    /// Minutes past midnight, venue time.
    var startMinute: Int
    var venue: String
    /// "Music · Rock"
    var kind: String
    /// "€25–€60", when Ticketmaster has a price.
    var price: String?
}

extension Place {
    /// Event ids are kept apart from Google's: a stop stores only the id, and
    /// the prefix says which service can look it up again.
    static let eventIDPrefix = "tm:"

    var isEvent: Bool { id.hasPrefix(Self.eventIDPrefix) }
}

/// Geohash encoding, the form Ticketmaster takes a search point in.
enum Geohash {
    private static let alphabet = Array("0123456789bcdefghjkmnpqrstuvwxyz")

    /// Nine characters pins a point to within a few metres, far finer than a
    /// city-wide search needs.
    static func encode(latitude: Double, longitude: Double, precision: Int = 9) -> String {
        var latRange = (-90.0, 90.0), lonRange = (-180.0, 180.0)
        var hash = "", bits = 0, value = 0, evenBit = true
        while hash.count < precision {
            if evenBit {
                let mid = (lonRange.0 + lonRange.1) / 2
                if longitude >= mid { value = value << 1 | 1; lonRange.0 = mid } else { value <<= 1; lonRange.1 = mid }
            } else {
                let mid = (latRange.0 + latRange.1) / 2
                if latitude >= mid { value = value << 1 | 1; latRange.0 = mid } else { value <<= 1; latRange.1 = mid }
            }
            evenBit.toggle()
            bits += 1
            if bits == 5 {
                hash.append(alphabet[value])
                bits = 0
                value = 0
            }
        }
        return hash
    }
}
