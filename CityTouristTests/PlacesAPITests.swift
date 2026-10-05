import Testing
import Foundation
@testable import CityTourist

/// Exercises the Places integration end to end — request construction, HTTP,
/// decoding and mapping onto our models — against a stubbed session.
///
/// Serialized because `StubURLProtocol` holds the canned response in static
/// state: run in parallel, these tests hand each other the wrong fixture.
@Suite(.serialized)
struct PlacesAPITests {

    private func service() -> GooglePlacesService {
        GooglePlacesService(apiKey: "test-key", session: StubURLProtocol.makeSession())
    }

    @MainActor
    private func catalog() -> PlaceCatalog {
        PlaceCatalog(makeService: { service() })
    }

    /// Answers every Place Details request with a place carrying the id asked for.
    private func stubPlaceDetails(latitude: Double = 38.7139, longitude: Double = -9.1334) {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"]
            )!
            let json = Fixtures.placeDetails(id: request.url!.lastPathComponent,
                                             latitude: latitude, longitude: longitude)
            return (response, Data(json.utf8))
        }
    }

    // MARK: Nearby search

    @Test func nearbySearchMapsResponseOntoPlaces() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond(json: Fixtures.nearbyLisbon)

        let places = try await service().nearby(city: SampleData.cities[0], category: .attraction)

        #expect(places.count == 2)

        let tower = try #require(places.first { $0.id == "place-belem-tower" })
        #expect(tower.name == "Belém Tower")
        #expect(tower.cityID == "lisbon")
        #expect(tower.rating == 4.5)
        #expect(tower.reviewCount == 18420)
        #expect(tower.priceLevel == 2)
        #expect(tower.category == .attraction)
        #expect(tower.blurb == "16th-century riverside fort.")
        #expect(tower.neighborhood == "Av. Brasília, Lisboa")
        #expect(tower.photoName == "places/place-belem-tower/photos/AbC123")
        #expect(tower.isOpenNow == false)
        #expect(abs(tower.coordinate.latitude - 38.6916) < 0.0001)

        // A restaurant among the results must be recategorised off the
        // requested type, not left as .attraction.
        let market = try #require(places.first { $0.id == "place-time-out" })
        #expect(market.category == .food)
        #expect(market.priceLevel == 4)
        #expect(market.isOpenNow == true)
        #expect(market.todayHours == nil)
    }

    @Test func nearbySearchSendsKeyFieldMaskAndBounds() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond(json: Fixtures.nearbyLisbon)

        _ = try await service().nearby(city: SampleData.cities[0], category: .food)

        let request = try #require(StubURLProtocol.recorded.first)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "X-Goog-Api-Key") == "test-key")

        // The field mask is billed, so assert it stays scoped.
        let mask = try #require(request.value(forHTTPHeaderField: "X-Goog-FieldMask"))
        #expect(mask.contains("places.displayName"))
        #expect(mask.contains("places.currentOpeningHours"))
        #expect(!mask.contains("places.reviews"))

        let body = try #require(request.stubBody)
        #expect(body["includedTypes"] as? [String] == ["restaurant", "cafe", "bakery"])
        #expect(body["maxResultCount"] as? Int == 20)
        let circle = (body["locationRestriction"] as? [String: Any])?["circle"] as? [String: Any]
        #expect(circle?["radius"] as? Double == 12_000)
    }

    @Test func incompleteResultsAreDroppedNotFatal() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond(json: Fixtures.nearbyIncomplete)

        let places = try await service().nearby(city: SampleData.cities[0], category: .nature)
        #expect(places.count == 1)
        #expect(places.first?.id == "ok")
    }

    @Test func httpErrorIsSurfaced() async {
        StubURLProtocol.reset()
        StubURLProtocol.respond(status: 403, json: Fixtures.permissionDenied)

        await #expect(throws: GooglePlacesService.ServiceError.self) {
            _ = try await service().nearby(city: SampleData.cities[0], category: .attraction)
        }
    }

    @Test func catalogueDedupesPlacesSeenInMultipleCategories() async throws {
        StubURLProtocol.reset()
        // Every one of the six category calls returns the same two places.
        StubURLProtocol.respond(json: Fixtures.nearbyLisbon)

        let places = try await service().catalogue(for: SampleData.cities[0])

        #expect(StubURLProtocol.recorded.count == PlaceCategory.allCases.count)
        #expect(places.count == 2, "the same id must not appear once per category")
        #expect(places.map(\.id).sorted() == ["place-belem-tower", "place-time-out"])
        // catalogue() sorts by rating, best first.
        #expect(places.first?.id == "place-belem-tower")
    }

    // MARK: Place details

    @Test func placeDetailsFetchesOnePlaceByID() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond(json: Fixtures.placeDetails(id: "place-castelo"))

        let place = try await service().place(id: "place-castelo", cityID: "lisbon")

        #expect(place.id == "place-castelo")
        #expect(place.name == "Castelo de São Jorge")
        #expect(place.cityID == "lisbon")
        #expect(place.category == .attraction)
        #expect(place.photoName == "places/place-castelo/photos/Castle1")

        let request = try #require(StubURLProtocol.recorded.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path() == "/v1/places/place-castelo")
        #expect(request.value(forHTTPHeaderField: "X-Goog-Api-Key") == "test-key")

        // The same billed fields as Nearby Search, minus its `places.` wrapper.
        let mask = try #require(request.value(forHTTPHeaderField: "X-Goog-FieldMask"))
        #expect(mask.contains("displayName"))
        #expect(mask.contains("currentOpeningHours"))
        #expect(!mask.contains("places."))
        #expect(!mask.contains("reviews"))
    }

    @Test func placeDetailsSurfacesAPlaceThatNoLongerExists() async {
        StubURLProtocol.reset()
        StubURLProtocol.respond(status: 404, json: Fixtures.notFound)

        await #expect(throws: GooglePlacesService.ServiceError.self) {
            _ = try await service().place(id: "place-gone", cityID: "lisbon")
        }
    }

    // MARK: Restoring places after a relaunch

    /// After a relaunch a stop is only an id. Resolving must fetch exactly the
    /// places the app doesn't have — bundled ones are free — and file them
    /// under the trip's city. Ids are unique per test because the directory
    /// is shared across the whole run.
    @MainActor
    @Test func resolveFetchesOnlyPlacesTheAppDoesNotHave() async {
        StubURLProtocol.reset()
        stubPlaceDetails()
        let id = "place-\(UUID().uuidString)"

        await catalog().resolve(["lis-castelo", id], cityID: "lisbon")

        #expect(StubURLProtocol.recorded.count == 1, "a bundled place must not be billed")
        #expect(StubURLProtocol.recorded.first?.url?.lastPathComponent == id)
        #expect(PlaceDirectory.place(id: id)?.cityID == "lisbon")
    }

    @MainActor
    @Test func aFailedLookupIsRetriedOnTheNextResolve() async {
        StubURLProtocol.reset()
        StubURLProtocol.respond(status: 503, json: "{}")
        let id = "place-\(UUID().uuidString)"
        let catalog = catalog()

        await catalog.resolve([id], cityID: "lisbon")
        #expect(catalog.failedPlaceIDs.contains(id))
        #expect(PlaceDirectory.place(id: id) == nil)

        stubPlaceDetails()
        await catalog.resolve([id], cityID: "lisbon")
        #expect(!catalog.failedPlaceIDs.contains(id))
        #expect(PlaceDirectory.place(id: id) != nil)
        #expect(catalog.resolvingPlaceIDs.isEmpty)
    }

    /// Bookmarks saved before their city was recorded join the nearest known
    /// city, rather than the Lisbon that an unknown city id falls back to.
    @MainActor
    @Test func aPlaceWithNoRecordedCityJoinsTheNearestKnownCity() async {
        StubURLProtocol.reset()
        stubPlaceDetails(latitude: 35.0037, longitude: 135.7788)  // Gion, Kyoto
        let id = "place-\(UUID().uuidString)"

        await catalog().resolve([id], cityID: nil)

        // By name, since the host app may have registered a searched Kyoto too.
        let cityID = PlaceDirectory.place(id: id)?.cityID
        #expect(cityID.map { CityDirectory.city(id: $0).name } == "Kyoto")
    }

    @MainActor
    @Test func withoutAKeyUnknownPlacesFailWithoutARequest() async {
        StubURLProtocol.reset()
        let id = "place-\(UUID().uuidString)"
        let catalog = PlaceCatalog(makeService: { nil })

        await catalog.resolve([id], cityID: "lisbon")

        #expect(catalog.failedPlaceIDs.contains(id))
        #expect(StubURLProtocol.recorded.isEmpty)
    }

    // MARK: Opening hours

    /// Google lists weekdays Monday-first; Calendar counts Sunday-first. An
    /// off-by-one here would show yesterday's hours with no visible symptom.
    @Test func todayHoursPicksTheRightWeekdayAllSevenDays() throws {
        let descriptions = [
            "Monday: MON", "Tuesday: TUE", "Wednesday: WED", "Thursday: THU",
            "Friday: FRI", "Saturday: SAT", "Sunday: SUN"
        ]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))

        // 2026-09-07 is a Monday.
        let expected = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]
        for offset in 0..<7 {
            var components = DateComponents()
            components.year = 2026; components.month = 9; components.day = 7 + offset
            let date = try #require(calendar.date(from: components))
            let hours = GooglePlacesService.todayHours(from: descriptions, on: date, calendar: calendar)
            #expect(hours == expected[offset],
                    "day offset \(offset) resolved to \(hours ?? "nil")")
        }
    }

    @Test func todayHoursNeedsAFullWeek() {
        #expect(GooglePlacesService.todayHours(from: nil) == nil)
        #expect(GooglePlacesService.todayHours(from: ["Monday: 9-5"]) == nil)
    }

    // MARK: Category and price mapping

    @Test func categoryFallsBackOnlyWhenTypesAreUnknown() {
        #expect(GooglePlacesService.category(fromTypes: ["night_club"], fallback: .food) == .nightlife)
        #expect(GooglePlacesService.category(fromTypes: ["art_gallery"], fallback: .food) == .museum)
        #expect(GooglePlacesService.category(fromTypes: ["park"], fallback: .food) == .nature)
        #expect(GooglePlacesService.category(fromTypes: ["something_new"], fallback: .activity) == .activity)
    }

    // MARK: City search

    @Test func autocompleteKeepsPlacePredictionsAndDropsQueryPredictions() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond(json: Fixtures.autocompleteBarcel)

        let results = try await service().autocompleteCities(input: "Barcel", sessionToken: "tok-1")

        #expect(results.count == 2)
        #expect(results.first?.name == "Barcelona")
        #expect(results.first?.region == "Spain")

        let body = try #require(StubURLProtocol.recorded.first?.stubBody)
        #expect(body["includedPrimaryTypes"] as? [String] == ["(cities)"])
        #expect(body["sessionToken"] as? String == "tok-1")
    }

    @Test func autocompleteSkipsNetworkForVeryShortInput() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond(json: Fixtures.autocompleteBarcel)

        let results = try await service().autocompleteCities(input: "B", sessionToken: "tok")
        #expect(results.isEmpty)
        #expect(StubURLProtocol.recorded.isEmpty, "one-character input must not be billed")
    }

    @Test func cityDetailsSplitsCountryOutOfTheAddress() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond(json: Fixtures.cityDetailsBarcelona)

        let city = try await service().cityDetails(placeID: "city-barcelona", sessionToken: "tok-1")

        #expect(city.id == "city-barcelona")
        #expect(city.name == "Barcelona")
        #expect(city.country == "Spain")
        #expect(city.displayName == "Barcelona, Spain")
        #expect(city.photoName == "places/city-barcelona/photos/CoverPhoto")
        #expect(abs(city.coordinate.latitude - 41.3874) < 0.0001)

        // The session token must ride along so the search bills as one session.
        let url = try #require(StubURLProtocol.recorded.first?.url?.absoluteString)
        #expect(url.contains("sessionToken=tok-1"))
    }
}
