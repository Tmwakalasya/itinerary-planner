import Testing
import Foundation
@testable import CityTourist

/// Itinerary editing and persistence, against a temp file rather than the
/// real Documents store.
@MainActor
struct AppStoreTests {

    private func makeStore(seed: Bool = false) -> (AppStore, URL) {
        let url = URL.temporaryDirectory.appending(path: "citytourist-test-\(UUID().uuidString).json")
        return (AppStore(storageURL: url, loadFromDisk: false, seedDemoContent: seed), url)
    }

    private func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: Calendar.current.startOfDay(for: .now))!
    }

    // MARK: Trips

    @Test func createTripBuildsOneDayPerDateInclusive() {
        let (store, _) = makeStore()
        let trip = store.createTrip(city: SampleData.cities[0], start: day(1), end: day(3))

        #expect(trip.days.count == 3, "a Mon–Wed trip is three days, not two")
        #expect(Calendar.current.isDate(trip.days[0].date, inSameDayAs: day(1)))
        #expect(Calendar.current.isDate(trip.days[2].date, inSameDayAs: day(3)))
    }

    @Test func singleDayTripStillGetsOneDay() {
        let (store, _) = makeStore()
        let trip = store.createTrip(city: SampleData.cities[0], start: day(2), end: day(2))
        #expect(trip.days.count == 1)
    }

    @Test func createTripRegistersASearchedCityForLaterLookup() {
        let (store, _) = makeStore()
        let barcelona = City(id: "city-barcelona", name: "Barcelona", country: "Spain",
                             tagline: "", coordinate: Coordinate(latitude: 41.38, longitude: 2.16))

        let trip = store.createTrip(city: barcelona, start: day(1), end: day(2))

        // Without this the trip card would fall back to a bundled sample city.
        #expect(CityDirectory.city(id: trip.cityID).name == "Barcelona")
        #expect(store.recentCities.contains { $0.id == "city-barcelona" })
    }

    // MARK: Stops

    @Test func stopsAreKeptInTimeOrderRegardlessOfInsertOrder() {
        let (store, _) = makeStore()
        let trip = store.createTrip(city: SampleData.cities[0], start: day(1), end: day(1))
        let places = SampleData.places(in: "lisbon")

        store.addStop(place: places[0], to: trip.id, dayIndex: 0, startMinute: 15 * 60)
        store.addStop(place: places[1], to: trip.id, dayIndex: 0, startMinute: 9 * 60)
        store.addStop(place: places[2], to: trip.id, dayIndex: 0, startMinute: 12 * 60)

        let minutes = store.trip(id: trip.id)!.days[0].stops.map(\.startMinute)
        #expect(minutes == [9 * 60, 12 * 60, 15 * 60])
    }

    @Test func suggestedTimeFollowsTheLastStop() {
        let (store, _) = makeStore()
        let trip = store.createTrip(city: SampleData.cities[0], start: day(1), end: day(1))
        let place = SampleData.places(in: "lisbon")[0]

        #expect(store.suggestedStartMinute(tripID: trip.id, dayIndex: 0) == 9 * 60)

        store.addStop(place: place, to: trip.id, dayIndex: 0, startMinute: 10 * 60)
        // 10:00 + the place's own duration + a 30 minute gap.
        let expected = 10 * 60 + place.typicalMinutes + 30
        #expect(store.suggestedStartMinute(tripID: trip.id, dayIndex: 0) == expected)
    }

    @Test func reorderingKeepsTheDaysExistingTimeSlots() {
        let (store, _) = makeStore()
        let trip = store.createTrip(city: SampleData.cities[0], start: day(1), end: day(1))
        let places = SampleData.places(in: "lisbon")

        store.addStop(place: places[0], to: trip.id, dayIndex: 0, startMinute: 9 * 60)
        store.addStop(place: places[1], to: trip.id, dayIndex: 0, startMinute: 13 * 60)

        let before = store.trip(id: trip.id)!.days[0].stops
        store.moveStops(from: IndexSet(integer: 1), to: 0, in: trip.id, dayIndex: 0)
        let after = store.trip(id: trip.id)!.days[0].stops

        #expect(after.map(\.placeID) == [before[1].placeID, before[0].placeID])
        #expect(after.map(\.startMinute) == [9 * 60, 13 * 60],
                "times stay with the slot, not with the place")
    }

    @Test func removingAStopLeavesTheRest() {
        let (store, _) = makeStore()
        let trip = store.createTrip(city: SampleData.cities[0], start: day(1), end: day(1))
        let places = SampleData.places(in: "lisbon")
        store.addStop(place: places[0], to: trip.id, dayIndex: 0, startMinute: 9 * 60)
        store.addStop(place: places[1], to: trip.id, dayIndex: 0, startMinute: 11 * 60)

        store.removeStops(at: IndexSet(integer: 0), in: trip.id, dayIndex: 0)

        let stops = store.trip(id: trip.id)!.days[0].stops
        #expect(stops.count == 1)
        #expect(stops[0].placeID == places[1].id)
    }

    @Test func editsToAMissingTripAreIgnored() {
        let (store, _) = makeStore()
        let ghost = UUID()
        // Must not trap — TripDetailView can outlive a deleted trip.
        store.addStop(place: SampleData.places[0], to: ghost, dayIndex: 0, startMinute: 600)
        store.removeStops(at: IndexSet(integer: 0), in: ghost, dayIndex: 0)
        #expect(store.trips.isEmpty)
    }

    @Test func outOfRangeDayIndexIsIgnored() {
        let (store, _) = makeStore()
        let trip = store.createTrip(city: SampleData.cities[0], start: day(1), end: day(1))
        store.addStop(place: SampleData.places[0], to: trip.id, dayIndex: 9, startMinute: 600)
        #expect(store.trip(id: trip.id)!.stopCount == 0)
    }

    // MARK: Persistence

    @Test func stateSurvivesARelaunch() {
        let (store, url) = makeStore()
        let barcelona = City(id: "city-barcelona", name: "Barcelona", country: "Spain",
                             tagline: "", coordinate: Coordinate(latitude: 41.38, longitude: 2.16))
        let trip = store.createTrip(city: barcelona, start: day(1), end: day(3))
        store.addStop(place: SampleData.places[0], to: trip.id, dayIndex: 0, startMinute: 9 * 60)
        store.toggleSaved(SampleData.places[1])

        let reopened = AppStore(storageURL: url, loadFromDisk: true, seedDemoContent: false)

        #expect(reopened.trips.count == 1)
        #expect(reopened.trips[0].id == trip.id)
        #expect(reopened.trips[0].stopCount == 1)
        #expect(reopened.savedPlaceIDs.contains(SampleData.places[1].id))
        #expect(reopened.knownCities.contains { $0.id == "city-barcelona" })
        #expect(CityDirectory.city(id: "city-barcelona").name == "Barcelona")
    }

    /// State written before city search existed has no `knownCities` key.
    /// It must still load rather than throwing the user's trips away.
    @Test func stateWrittenBeforeCitySearchStillLoads() throws {
        let url = URL.temporaryDirectory.appending(path: "legacy-\(UUID().uuidString).json")
        let legacy = """
        {
          "trips": [{
            "id": "\(UUID().uuidString)",
            "cityID": "lisbon",
            "title": "Lisbon",
            "startDate": 780000000,
            "endDate": 780200000,
            "days": [],
            "collaborators": [],
            "isDownloadedForOffline": false,
            "shareSlug": "abc12345"
          }],
          "savedPlaceIDs": ["lis-castelo"],
          "browsingCityID": "lisbon"
        }
        """
        try Data(legacy.utf8).write(to: url)

        let store = AppStore(storageURL: url, loadFromDisk: true, seedDemoContent: false)

        #expect(store.trips.count == 1)
        #expect(store.trips[0].title == "Lisbon")
        #expect(store.savedPlaceIDs.contains("lis-castelo"))
        #expect(store.knownCities.isEmpty)
        #expect(store.savedPlaceIDsByCity[nil] == ["lis-castelo"],
                "a bookmark with no recorded city is still offered for lookup")
    }

    /// Only a saved place's id is kept on disk, and fetching it back needs the
    /// city it came from — so that has to survive a relaunch too.
    @Test func savedPlacesRememberTheirCityAcrossARelaunch() {
        let (store, url) = makeStore()
        let live = Place(id: "place-sagrada", name: "Sagrada Família", cityID: "city-barcelona",
                         category: .attraction, neighborhood: "Eixample", rating: 4.8, reviewCount: 10,
                         priceLevel: 3, typicalMinutes: 90, blurb: "", about: "",
                         coordinate: Coordinate(latitude: 41.4036, longitude: 2.1744), tags: [])
        store.toggleSaved(live)

        let reopened = AppStore(storageURL: url, loadFromDisk: true, seedDemoContent: false)
        #expect(reopened.savedPlaceIDsByCity["city-barcelona"] == ["place-sagrada"])

        reopened.toggleSaved(live)
        #expect(reopened.savedPlaceCityIDs.isEmpty, "unsaving forgets the city too")
    }

    @Test func savedPlacesToggleBothWays() {
        let (store, _) = makeStore()
        let place = SampleData.places[0]
        #expect(!store.isSaved(place))
        store.toggleSaved(place)
        #expect(store.isSaved(place))
        store.toggleSaved(place)
        #expect(!store.isSaved(place))
    }

    // MARK: Sharing

    @Test func eachTripGetsItsOwnShareSlug() {
        let (store, _) = makeStore()
        let a = store.createTrip(city: SampleData.cities[0], start: day(1), end: day(2))
        let b = store.createTrip(city: SampleData.cities[1], start: day(1), end: day(2))
        #expect(a.shareSlug != b.shareSlug)
    }

    @Test func collaboratorsCanBeAddedAndRemoved() {
        let (store, _) = makeStore()
        let trip = store.createTrip(city: SampleData.cities[0], start: day(1), end: day(2))
        let sam = Collaborator(name: "Sam Okafor", email: "sam@example.com", permission: .edit)

        store.addCollaborator(sam, to: trip.id)
        #expect(store.trip(id: trip.id)?.collaborators.count == 1)
        #expect(store.trip(id: trip.id)?.collaborators.first?.initials == "SO")

        store.removeCollaborator(sam, from: trip.id)
        #expect(store.trip(id: trip.id)?.collaborators.isEmpty == true)
    }
}
