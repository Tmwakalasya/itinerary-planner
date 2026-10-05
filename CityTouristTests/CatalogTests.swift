import Testing
import Foundation
@testable import CityTourist

@MainActor
struct CatalogTests {

    /// With no API key the app must still be fully usable on bundled data.
    @Test func catalogFallsBackToSampleDataWithoutAKey() async {
        let catalog = PlaceCatalog()
        let places = catalog.places(in: "lisbon")

        #expect(!places.isEmpty)
        #expect(places.count == SampleData.places(in: "lisbon").count)

        if !Secrets.hasGooglePlacesKey {
            await catalog.load(city: SampleData.cities[0])
            #expect(catalog.source == .sample)
            #expect(catalog.state == .loaded)
        }
    }

    @Test func unknownCityFallsBackToAnEmptySampleList() {
        let catalog = PlaceCatalog()
        #expect(catalog.places(in: "city-barcelona").isEmpty)
    }

    /// Stops persist a place id only, so every place the UI renders must be
    /// resolvable — including one that only ever arrived from the API.
    @Test func directoryResolvesBothSampleAndLivePlaces() {
        #expect(PlaceDirectory.place(id: "lis-castelo")?.name == "Castelo de São Jorge")
        #expect(PlaceDirectory.place(id: "not-a-place") == nil)

        let live = Place(id: "place-live-1", name: "Live Place", cityID: "city-barcelona",
                         category: .food, neighborhood: "Gràcia", rating: 4.6, reviewCount: 10,
                         priceLevel: 2, typicalMinutes: 60, blurb: "", about: "",
                         coordinate: Coordinate(latitude: 41.4, longitude: 2.15), tags: [])
        PlaceDirectory.register([live])
        #expect(PlaceDirectory.place(id: "place-live-1")?.name == "Live Place")
    }

    /// Compared by name: the test host is the app itself, so the directory may
    /// also hold a searched copy of a sample city, loaded from the simulator.
    @Test func nearestCityPicksTheClosestKnownOne() {
        #expect(CityDirectory.nearest(to: Coordinate(latitude: 19.42, longitude: -99.16)).name == "Mexico City")
        #expect(CityDirectory.nearest(to: Coordinate(latitude: 38.70, longitude: -9.20)).name == "Lisbon")
    }

    @Test func openStatusReadsCorrectlyInBothDirections() {
        var place = SampleData.places[0]
        #expect(place.openLabel == nil, "sample data carries no opening hours")

        place.isOpenNow = true
        place.todayHours = "9:00 AM – 6:00 PM"
        #expect(place.openLabel == "Open now")
        #expect(place.openStatus == "Open now · 9:00 AM – 6:00 PM")

        place.isOpenNow = false
        #expect(place.openLabel == "Closed")
        #expect(place.openStatus == "Closed · 9:00 AM – 6:00 PM")
    }

    @Test func durationLabelReadsNaturally() {
        var place = SampleData.places[0]
        place.typicalMinutes = 45;  #expect(place.durationLabel == "45 min")
        place.typicalMinutes = 60;  #expect(place.durationLabel == "1 hr")
        place.typicalMinutes = 105; #expect(place.durationLabel == "1 hr 45 min")
    }
}
