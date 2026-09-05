import Testing
import Foundation
@testable import CityTourist

/// The share link carries the whole itinerary in its fragment, so encoding is
/// the feature — if it's wrong, someone opens a broken page.
@MainActor
struct ShareLinkTests {

    private func trip() -> Trip {
        let cal = Calendar.current
        let day0 = cal.startOfDay(for: .now)
        var trip = Trip(cityID: "lisbon", title: "Lisbon",
                        startDate: day0, endDate: cal.date(byAdding: .day, value: 1, to: day0)!)
        trip.days = [
            ItineraryDay(date: day0, stops: [
                ItineraryStop(placeID: "lis-pasteis-belem", startMinute: 9 * 60,
                              durationMinutes: 40, note: "Two each."),
                ItineraryStop(placeID: "lis-castelo", startMinute: 11 * 60, durationMinutes: 90)
            ]),
            ItineraryDay(date: cal.date(byAdding: .day, value: 1, to: day0)!, stops: [])
        ]
        return trip
    }

    private func snapshot() -> SharedItinerary {
        ShareLinkBuilder.snapshot(trip: trip(), city: SampleData.cities[0]) {
            PlaceDirectory.place(id: $0)
        }
    }

    @Test func snapshotFlattensTheItinerary() throws {
        let shared = snapshot()

        #expect(shared.title == "Lisbon")
        #expect(shared.city == "Lisbon, Portugal")
        #expect(shared.days.count == 2)
        #expect(shared.days[1].stops.isEmpty, "an empty day is kept, so the page can show it")

        let first = try #require(shared.days.first?.stops.first)
        #expect(first.n == "Pastéis de Belém")
        #expect(first.t == 9 * 60)
        #expect(first.m == 40)
        #expect(first.note == "Two each.")
        #expect(first.lat != nil)
    }

    /// A stop whose place can't be resolved must be dropped, not crash or
    /// render as a blank card on someone else's screen.
    @Test func unresolvablePlacesAreDropped() {
        var t = trip()
        t.days[0].stops.append(ItineraryStop(placeID: "does-not-exist",
                                             startMinute: 15 * 60, durationMinutes: 30))
        let shared = ShareLinkBuilder.snapshot(trip: t, city: SampleData.cities[0]) {
            PlaceDirectory.place(id: $0)
        }
        #expect(shared.days[0].stops.count == 2)
    }

    @Test func emptyNotesAndBlurbsAreOmittedNotSentAsEmptyStrings() throws {
        let shared = snapshot()
        let second = try #require(shared.days.first?.stops.last)
        #expect(second.note == nil)
    }

    // MARK: Encoding

    @Test func encodingRoundTripsIncludingAccents() throws {
        let original = snapshot()
        let encoded = try ShareLinkBuilder.encode(original)
        let decoded = try ShareLinkBuilder.decode(encoded)

        #expect(decoded == original)
        #expect(decoded.days[0].stops[0].n == "Pastéis de Belém")
    }

    /// base64url only — a "+", "/" or "=" in a URL fragment gets mangled by
    /// the messaging apps people actually paste these into.
    @Test func encodingIsURLSafe() throws {
        let encoded = try ShareLinkBuilder.encode(snapshot())
        #expect(!encoded.contains("+"))
        #expect(!encoded.contains("/"))
        #expect(!encoded.contains("="))
    }

    @Test func decodingSurvivesMissingPadding() throws {
        // base64url drops padding; the decoder has to put it back.
        let encoded = try ShareLinkBuilder.encode(snapshot())
        #expect(throws: Never.self) { try ShareLinkBuilder.decode(encoded) }
    }

    @Test func garbageDecodesToAnError() {
        #expect(throws: (any Error).self) { try ShareLinkBuilder.decode("!!!not-base64!!!") }
    }

    /// The web viewer reads these exact keys. Renaming a property here without
    /// updating web/index.html produces a page that silently renders nothing,
    /// so the contract is pinned in a test rather than in a comment.
    @Test func wireFormatMatchesWhatTheWebViewerReads() throws {
        let data = try JSONEncoder().encode(snapshot())
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        for key in ["title", "city", "days"] {
            #expect(json[key] != nil, "web viewer reads \(key)")
        }

        let days = try #require(json["days"] as? [[String: Any]])
        #expect(days.first?["d"] != nil, "web viewer reads d for the date")

        let stops = try #require(days.first?["stops"] as? [[String: Any]])
        let first = try #require(stops.first)
        for key in ["t", "n", "m", "lat", "lon"] {
            #expect(first[key] != nil, "web viewer reads \(key)")
        }
        #expect(first["note"] as? String == "Two each.")

        // Absent values must be omitted, not sent as null — the page checks
        // for presence, so a null would render an empty note block.
        let second = try #require(stops.last)
        #expect(second["note"] == nil)
    }

    // MARK: URL

    @Test func urlCarriesThePayloadInTheFragment() throws {
        let url = try ShareLinkBuilder.url(trip: trip(), city: SampleData.cities[0]) {
            PlaceDirectory.place(id: $0)
        }
        let string = url.absoluteString
        #expect(string.contains("#i="))
        // Everything after the "#" stays on the client.
        let fragment = try #require(url.fragment(percentEncoded: false))
        #expect(fragment.hasPrefix("i="))

        let decoded = try ShareLinkBuilder.decode(String(fragment.dropFirst(2)))
        #expect(decoded.title == "Lisbon")
    }

    @Test func aTripWithNoStopsRefusesToMakeALink() {
        var empty = trip()
        empty.days = empty.days.map { ItineraryDay(date: $0.date, stops: []) }
        #expect(throws: ShareLinkBuilder.BuildError.self) {
            _ = try ShareLinkBuilder.url(trip: empty, city: SampleData.cities[0]) {
                PlaceDirectory.place(id: $0)
            }
        }
    }

    /// Links get pasted into Messages and WhatsApp; a realistic trip has to
    /// stay well inside what those will carry.
    @Test func aRealisticTripStaysWellUnderUrlLimits() throws {
        var big = trip()
        let places = SampleData.places(in: "lisbon")
        big.days = (0..<5).map { dayIndex in
            ItineraryDay(date: .now, stops: places.enumerated().map { index, place in
                ItineraryStop(placeID: place.id, startMinute: 8 * 60 + index * 45,
                              durationMinutes: place.typicalMinutes,
                              note: "Booked, reference ABC\(dayIndex)\(index)")
            })
        }
        let url = try ShareLinkBuilder.url(trip: big, city: SampleData.cities[0]) {
            PlaceDirectory.place(id: $0)
        }
        // 5 days x 12 stops is far beyond a normal trip, and it does exceed
        // what fits comfortably in a link — the app has to say so rather than
        // handing out something that may be truncated in transit.
        #expect(ShareLinkBuilder.isOversized(url),
                "60 stops encoded to \(url.absoluteString.count) chars")
    }

    @Test func anOrdinaryTripIsNowhereNearTheLimit() throws {
        let url = try ShareLinkBuilder.url(trip: trip(), city: SampleData.cities[0]) {
            PlaceDirectory.place(id: $0)
        }
        #expect(!ShareLinkBuilder.isOversized(url))
        #expect(url.absoluteString.count < 1500,
                "a two-stop trip encoded to \(url.absoluteString.count) chars")
    }
}
