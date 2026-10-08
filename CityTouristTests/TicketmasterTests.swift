import Testing
import Foundation
@testable import CityTourist

/// Geohash, the form Ticketmaster takes a search point in.
struct GeohashTests {
    /// The worked example from the geohash reference.
    @Test func matchesTheReferenceEncoding() {
        #expect(Geohash.encode(latitude: 57.64911, longitude: 10.40744, precision: 11) == "u4pruydqqvj")
        #expect(Geohash.encode(latitude: 57.64911, longitude: 10.40744) == "u4pruydqq")
    }
}

/// Events from Ticketmaster, against the same stubbed session as Places.
/// An extension of that suite, because the stub's state is static: run in
/// parallel with it, these would hand each other the wrong responses.
extension PlacesAPITests {

    private func ticketmaster() -> TicketmasterService {
        TicketmasterService(apiKey: "test-key", session: StubURLProtocol.makeSession())
    }

    /// 8–9 October 2026, Lisbon.
    private func lisbonTrip() -> Trip {
        let cal = Calendar.current
        let first = cal.date(from: DateComponents(year: 2026, month: 10, day: 8))!
        let second = cal.date(byAdding: .day, value: 1, to: first)!
        return Trip(cityID: "lisbon", title: "Lisbon", startDate: first, endDate: second,
                    days: [ItineraryDay(date: first), ItineraryDay(date: second)])
    }

    private func query(_ request: URLRequest?) -> [String: String] {
        let items = request?.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    // MARK: Searching

    @Test func eventSearchIsScopedToTheCityAndTheTrip() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond(json: TicketmasterFixtures.search)
        let trip = lisbonTrip(), lisbon = SampleData.cities[0]

        _ = try await ticketmaster().events(near: lisbon.coordinate, cityID: "lisbon",
                                            from: trip.startDate, to: trip.endDate)

        let request = try #require(StubURLProtocol.recorded.first)
        #expect(request.url?.host() == "app.ticketmaster.com")
        #expect(request.url?.path() == "/discovery/v2/events.json")
        let params = query(request)
        #expect(params["apikey"] == "test-key")
        #expect(params["geoPoint"] == Geohash.encode(latitude: lisbon.coordinate.latitude,
                                                      longitude: lisbon.coordinate.longitude))
        #expect(params["radius"] == "25" && params["unit"] == "km")
        #expect(params["sort"] == "date,asc")

        // A day either side, in UTC, since events are dated in venue time.
        let utc = ISO8601DateFormatter()
        let cal = Calendar.current
        #expect(params["startDateTime"] == utc.string(from: cal.date(byAdding: .day, value: -1, to: trip.startDate)!))
        #expect(params["endDateTime"] == utc.string(from: cal.date(byAdding: .day, value: 2, to: trip.endDate)!))
    }

    @Test func eventsBecomePlacesReadyToPlan() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond(json: TicketmasterFixtures.search)
        let trip = lisbonTrip()

        let events = try await ticketmaster().events(near: SampleData.cities[0].coordinate, cityID: "lisbon",
                                                     from: trip.startDate, to: trip.endDate)

        // Called off, and no set time yet: neither can go in a plan.
        #expect(events.map(\.id) == ["tm:fado-1", "tm:game-1", "tm:later-1"])

        let fado = try #require(events.first)
        let info = try #require(fado.event)
        #expect(fado.name == "Fado Night")
        #expect(fado.cityID == "lisbon")
        #expect(info.localDate == "2026-10-08")
        #expect(info.startMinute == 21 * 60 + 30)
        #expect(info.venue == "Clube de Fado" && fado.neighborhood == "Clube de Fado")
        #expect(info.kind == "Music · World")
        #expect(info.ticketURL?.absoluteString == "https://www.ticketmaster.pt/event/fado-1")
        #expect(abs(fado.coordinate.latitude - 38.7108) < 0.0001)
        #expect(fado.typicalMinutes == 150)
        #expect(fado.rating == 0, "events have no rating to show")
        #expect(fado.imageURL?.absoluteString == "https://s1.ticketm.net/img/fado_16_9_640.jpg",
                "the smallest wide image that still fills a card")

        let style = FloatingPointFormatStyle<Double>.Currency(code: "EUR").precision(.fractionLength(0))
        #expect(info.price == "\(25.0.formatted(style))–\(60.0.formatted(style))")

        let game = try #require(events.dropFirst().first)
        #expect(game.event?.kind == "Sports · Soccer")
        #expect(game.typicalMinutes == 180)
        #expect(game.event?.price == nil)
    }

    @Test func eventErrorsAreSurfaced() async {
        StubURLProtocol.reset()
        StubURLProtocol.respond(status: 401, json: #"{"fault":{"faultstring":"Invalid ApiKey"}}"#)

        await #expect(throws: TicketmasterService.ServiceError.self) {
            _ = try await ticketmaster().events(near: SampleData.cities[0].coordinate, cityID: "lisbon",
                                                from: .now, to: .now)
        }
    }

    // MARK: Looking one up again

    @Test func anEventIsLookedUpAgainByItsID() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond(json: TicketmasterFixtures.event(id: "fado-1"))

        let place = try await ticketmaster().event(id: "fado-1", cityID: "lisbon")

        #expect(place.id == "tm:fado-1")
        #expect(StubURLProtocol.recorded.first?.url?.path() == "/discovery/v2/events/fado-1.json")
    }

    /// A stop at an event stores only `tm:<id>`; after a relaunch it has to go
    /// back to Ticketmaster, not Google.
    @MainActor
    @Test func restoredEventStopsAreLookedUpWithTicketmaster() async {
        StubURLProtocol.reset()
        StubURLProtocol.handler = { request in
            let id = request.url!.deletingPathExtension().lastPathComponent
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                                           headerFields: ["Content-Type": "application/json"])!
            return (response, Data(TicketmasterFixtures.event(id: id).utf8))
        }
        let id = "restored-\(UUID().uuidString)"
        let catalog = PlaceCatalog(makeService: { nil }, makeEventService: { ticketmaster() })

        await catalog.resolve(["tm:\(id)"], cityID: "lisbon")

        #expect(PlaceDirectory.place(id: "tm:\(id)")?.event != nil)
        #expect(StubURLProtocol.recorded.first?.url?.host() == "app.ticketmaster.com")
        #expect(catalog.failedPlaceIDs.isEmpty)
    }

    // MARK: The trip's events

    @MainActor
    @Test func theCatalogKeepsEachTripDaysEvents() async {
        StubURLProtocol.reset()
        StubURLProtocol.respond(json: TicketmasterFixtures.search)
        let trip = lisbonTrip()
        let catalog = EventCatalog(makeService: { ticketmaster() })

        await catalog.load(trip: trip, city: SampleData.cities[0])

        #expect(catalog.events(for: trip, on: trip.days[0].date).map(\.id) == ["tm:fado-1"])
        #expect(catalog.events(for: trip, on: trip.days[1].date).map(\.id) == ["tm:game-1"],
                "the 12th is after the trip, so it's left out")
        #expect(PlaceDirectory.place(id: "tm:fado-1") != nil, "ready to add as a stop")

        await catalog.load(trip: trip, city: SampleData.cities[0])
        #expect(StubURLProtocol.recorded.count == 1, "once per trip per session")
    }

    @MainActor
    @Test func withoutAKeyThereAreNoEvents() async {
        StubURLProtocol.reset()
        let trip = lisbonTrip()
        let catalog = EventCatalog(makeService: { nil })

        await catalog.load(trip: trip, city: SampleData.cities[0])

        #expect(catalog.events(for: trip, on: trip.days[0].date).isEmpty)
        #expect(StubURLProtocol.recorded.isEmpty)
    }
}

/// Trimmed Discovery API responses.
enum TicketmasterFixtures {

    static func event(id: String, name: String = "Fado Night", date: String = "2026-10-08",
                      time: String? = "21:30:00", status: String = "onsale") -> String {
        """
        {
          "id": "\(id)",
          "name": "\(name)",
          "url": "https://www.ticketmaster.pt/event/\(id)",
          "dates": {
            "start": { "localDate": "\(date)" \(time.map { #", "localTime": "\#($0)""# } ?? #", "timeTBA": true"#) },
            "status": { "code": "\(status)" }
          },
          "images": [
            { "url": "https://s1.ticketm.net/img/fado_3_2_640.jpg", "ratio": "3_2", "width": 640 },
            { "url": "https://s1.ticketm.net/img/fado_16_9_1024.jpg", "ratio": "16_9", "width": 1024 },
            { "url": "https://s1.ticketm.net/img/fado_16_9_640.jpg", "ratio": "16_9", "width": 640 },
            { "url": "https://s1.ticketm.net/img/fado_16_9_205.jpg", "ratio": "16_9", "width": 205 }
          ],
          "classifications": [ { "segment": { "name": "Music" }, "genre": { "name": "World" } } ],
          "priceRanges": [ { "min": 25, "max": 60, "currency": "EUR" } ],
          "_embedded": { "venues": [
            { "name": "Clube de Fado", "location": { "latitude": "38.7108", "longitude": "-9.1300" } }
          ] }
        }
        """
    }

    static let game = """
    {
      "id": "game-1",
      "name": "Benfica v Porto",
      "url": "https://www.ticketmaster.pt/event/game-1",
      "dates": { "start": { "localDate": "2026-10-09", "localTime": "20:15:00" }, "status": { "code": "onsale" } },
      "images": [ { "url": "https://s1.ticketm.net/img/game_16_9_1024.jpg", "ratio": "16_9", "width": 1024 } ],
      "classifications": [ { "segment": { "name": "Sports" }, "genre": { "name": "Soccer" } } ],
      "_embedded": { "venues": [
        { "name": "Estádio da Luz", "location": { "latitude": "38.7527", "longitude": "-9.1847" } }
      ] }
    }
    """

    static let search = """
    { "_embedded": { "events": [
      \(event(id: "fado-1")),
      \(event(id: "off-1", name: "Called Off", status: "cancelled")),
      \(event(id: "tba-1", name: "Time To Be Announced", date: "2026-10-09", time: nil)),
      \(game),
      \(event(id: "later-1", name: "After The Trip", date: "2026-10-12"))
    ] } }
    """
}
