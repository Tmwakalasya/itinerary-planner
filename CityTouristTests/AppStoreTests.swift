import Testing
import Foundation
import UserNotifications
@testable import CityTourist

/// Itinerary editing and persistence, against a temp file rather than the
/// real Documents store.
@MainActor
struct AppStoreTests {

    private func makeStore(seed: Bool = false,
                           reminders: any ReminderScheduling = RecordingReminders()) -> (AppStore, URL) {
        let url = URL.temporaryDirectory.appending(path: "citytourist-test-\(UUID().uuidString).json")
        return (AppStore(storageURL: url, loadFromDisk: false, seedDemoContent: seed,
                         reminders: reminders), url)
    }

    private func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: Calendar.current.startOfDay(for: .now))!
    }

    // MARK: Trips

    @Test func unreadableSaveIsPreservedEvenAfterAnEdit() throws {
        let url = URL.temporaryDirectory.appending(path: "unreadable-\(UUID()).json")
        let original = Data("{ interrupted save".utf8)
        try original.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let store = AppStore(storageURL: url)
        #expect(store.storageIssue == .unreadable)
        #expect(store.trips.isEmpty, "a failed load must not seed demo trips")
        store.toggleSaved(SampleData.places[0])
        store.retryStorage()
        #expect(try Data(contentsOf: url) == original)
        #expect(store.storageIssue == .unreadable)
    }

    @Test func readFailureIsNotTreatedAsAFirstLaunch() throws {
        let directory = URL.temporaryDirectory.appending(path: "unreadable-directory-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = AppStore(storageURL: directory)
        #expect(store.storageIssue == .unreadable)
        #expect(store.trips.isEmpty)
        #expect(try directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true)
    }

    @Test func missingSaveCanStillSeedFirstLaunch() throws {
        let url = URL.temporaryDirectory.appending(path: "first-launch-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = AppStore(storageURL: url)
        #expect(store.storageIssue == nil)
        #expect(!store.trips.isEmpty)
        let reopened = AppStore(storageURL: url, seedDemoContent: false)
        #expect(reopened.trips == store.trips)
    }

    @Test func recoveryReopensTheRepairedSave() throws {
        let (original, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        let trip = original.createTrip(city: SampleData.cities[0], start: day(1), end: day(2))
        let validData = try Data(contentsOf: url)
        try Data("broken".utf8).write(to: url)

        let blocked = AppStore(storageURL: url)
        #expect(blocked.storageIssue == .unreadable)
        try validData.write(to: url)
        blocked.retryStorage()
        #expect(blocked.storageIssue == nil)
        #expect(blocked.trips == [trip])
        blocked.toggleSaved(SampleData.places[0])
        let reopened = AppStore(storageURL: url, seedDemoContent: false)
        #expect(reopened.isSaved(SampleData.places[0]))
        #expect(reopened.trips == [trip])
    }

    @Test func failedSaveStaysInMemoryAndCanBeSavedAgain() throws {
        let directory = URL.temporaryDirectory.appending(path: "save-retry-\(UUID())")
        let url = directory.appending(path: "state.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppStore(storageURL: url, loadFromDisk: false, seedDemoContent: false)
        let trip = store.createTrip(city: SampleData.cities[0], start: day(1), end: day(1))
        #expect(store.storageIssue == .unsaved)
        #expect(store.trips == [trip])

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store.retryStorage()
        #expect(store.storageIssue == nil)
        let reopened = AppStore(storageURL: url, seedDemoContent: false)
        #expect(reopened.trips == [trip])
    }

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

    /// Adding to today used to suggest 9:00 even at lunchtime, which put the
    /// new stop straight into the past.
    @Test func todaysSuggestionIsNeverInThePast() {
        let (store, _) = makeStore()
        let trip = store.createTrip(city: SampleData.cities[0], start: day(0), end: day(0))
        let lunchtime = Calendar.current.date(bySettingHour: 12, minute: 48, second: 0, of: .now)!

        #expect(store.suggestedStartMinute(tripID: trip.id, dayIndex: 0, now: lunchtime) == 13 * 60 + 15)

        let place = SampleData.places(in: "lisbon")[0]
        store.addStop(place: place, to: trip.id, dayIndex: 0, startMinute: 14 * 60)
        #expect(store.suggestedStartMinute(tripID: trip.id, dayIndex: 0, now: lunchtime)
                == 14 * 60 + place.typicalMinutes + 30, "after the last stop when that's later")
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

    // MARK: Reminders

    /// Two stops tomorrow at 9:00 and 13:00, the first with a reminder.
    private func tripWithAReminder(_ reminders: RecordingReminders) -> (AppStore, Trip, ItineraryStop) {
        let (store, _) = makeStore(reminders: reminders)
        let trip = store.createTrip(city: SampleData.cities[0], start: day(1), end: day(1))
        let places = SampleData.places(in: "lisbon")
        store.addStop(place: places[0], to: trip.id, dayIndex: 0, startMinute: 9 * 60)
        store.addStop(place: places[1], to: trip.id, dayIndex: 0, startMinute: 13 * 60)

        var first = store.trip(id: trip.id)!.days[0].stops[0]
        first.remindMe = true
        store.updateStop(first, in: trip.id, dayIndex: 0)
        return (store, trip, first)
    }

    private func trigger(of stop: ItineraryStop, in reminders: RecordingReminders) -> DateComponents? {
        let request = reminders.scheduled.last { $0.identifier == "stop-\(stop.id.uuidString)" }
        return (request?.trigger as? UNCalendarNotificationTrigger)?.dateComponents
    }

    /// Reordering hands start times to different stops, so a reminder has to
    /// move with its stop — and it's now timed for leaving the stop before.
    @Test func movingAStopMovesItsReminder() throws {
        let reminders = RecordingReminders()
        let (store, trip, stop) = tripWithAReminder(reminders)
        let places = SampleData.places(in: "lisbon")

        store.moveStops(from: IndexSet(integer: 0), to: 2, in: trip.id, dayIndex: 0)

        // It takes the 13:00 slot, straight after the other stop.
        let hop = TravelEstimate.minutes(from: places[1].coordinate, to: places[0].coordinate)
        let leaveBy = 13 * 60 - hop - LeaveBy.graceMinutes
        let fires = try #require(trigger(of: stop, in: reminders))
        #expect(fires.hour == leaveBy / 60)
        #expect(fires.minute == leaveBy % 60)
    }

    @Test func theFirstStopIsTimedFromWhereYouAreStaying() throws {
        let reminders = RecordingReminders()
        let (store, trip, stop) = tripWithAReminder(reminders)

        // With nowhere to come from, it's a nudge half an hour before 9:00.
        let nudge = try #require(trigger(of: stop, in: reminders))
        #expect(nudge.hour == 8 && nudge.minute == 30)

        let hotel = Lodging(name: "Baixa hotel", coordinate: Coordinate(latitude: 38.7105, longitude: -9.1366))
        store.setLodging(hotel, for: trip.id)

        let hop = TravelEstimate.minutes(from: hotel.coordinate, to: SampleData.places(in: "lisbon")[0].coordinate)
        let leaveBy = 9 * 60 - hop - LeaveBy.graceMinutes
        let timed = try #require(trigger(of: stop, in: reminders))
        #expect(timed.hour == leaveBy / 60)
        #expect(timed.minute == leaveBy % 60)
    }

    @Test func deletingATripCancelsItsReminders() {
        let reminders = RecordingReminders()
        let (store, trip, stop) = tripWithAReminder(reminders)
        // Scheduling cancels first too, so only count what deleting does.
        let earlier = reminders.cancelled.count

        store.deleteTrip(trip)

        #expect(reminders.cancelled.dropFirst(earlier).contains("stop-\(stop.id.uuidString)"))
    }

    // MARK: Planning

    @Test func retimingReordersTheDayByItsNewTimes() {
        let (store, _) = makeStore()
        let trip = store.createTrip(city: SampleData.cities[0], start: day(1), end: day(1))
        let places = SampleData.places(in: "lisbon")
        store.addStop(place: places[0], to: trip.id, dayIndex: 0, startMinute: 9 * 60)
        store.addStop(place: places[1], to: trip.id, dayIndex: 0, startMinute: 11 * 60)
        let first = store.trip(id: trip.id)!.days[0].stops[0]

        store.retime([first.id: 14 * 60], in: trip.id, dayIndex: 0)

        let after = store.trip(id: trip.id)!.days[0].stops
        #expect(after.map(\.placeID) == [places[1].id, places[0].id])
        #expect(after.map(\.startMinute) == [11 * 60, 14 * 60])
    }

    @Test func anAppliedPlanCanBeUndone() {
        let (store, _) = makeStore()
        let trip = store.createTrip(city: SampleData.cities[0], start: day(1), end: day(1))
        let places = SampleData.places(in: "lisbon")
        store.addStop(place: places[0], to: trip.id, dayIndex: 0, startMinute: 9 * 60)
        store.addStop(place: places[1], to: trip.id, dayIndex: 0, startMinute: 11 * 60)
        let before = store.trip(id: trip.id)!.days[0].stops

        store.applyPlan([before[0].id: 14 * 60], in: trip.id, dayIndex: 0, message: "Day updated")
        #expect(store.pendingUndo?.message == "Day updated")

        store.undoPlan()
        #expect(store.trip(id: trip.id)!.days[0].stops == before)
        #expect(store.pendingUndo == nil)
    }

    /// Undoing after another edit would quietly take that edit back too.
    @Test func anotherEditMakesTheUndoStale() {
        let (store, _) = makeStore()
        let trip = store.createTrip(city: SampleData.cities[0], start: day(1), end: day(1))
        let places = SampleData.places(in: "lisbon")
        store.addStop(place: places[0], to: trip.id, dayIndex: 0, startMinute: 9 * 60)
        let stop = store.trip(id: trip.id)!.days[0].stops[0]

        store.applyPlan([stop.id: 10 * 60], in: trip.id, dayIndex: 0, message: "Day updated")
        store.addStop(place: places[1], to: trip.id, dayIndex: 0, startMinute: 13 * 60)

        #expect(store.pendingUndo == nil)
    }

    /// For a place that's shut on the day it was planned.
    @Test func aStopMovedToAnotherDayKeepsItsTime() {
        let (store, _) = makeStore()
        let trip = store.createTrip(city: SampleData.cities[0], start: day(1), end: day(2))
        let places = SampleData.places(in: "lisbon")
        store.addStop(place: places[0], to: trip.id, dayIndex: 0, startMinute: 11 * 60)
        store.addStop(place: places[1], to: trip.id, dayIndex: 1, startMinute: 9 * 60)
        let moving = store.trip(id: trip.id)!.days[0].stops[0]

        store.moveStop(moving.id, in: trip.id, from: 0, to: 1)

        let days = store.trip(id: trip.id)!.days
        #expect(days[0].stops.isEmpty)
        #expect(days[1].stops.map(\.id) == [days[1].stops[0].id, moving.id])
        #expect(days[1].stops.map(\.startMinute) == [9 * 60, 11 * 60])
    }

    @Test func todaysTripIsFoundByItsDate() {
        let (store, _) = makeStore()
        store.createTrip(city: SampleData.cities[0], start: day(3), end: day(5))
        #expect(store.tripToday == nil)

        let running = store.createTrip(city: SampleData.cities[1], start: day(-1), end: day(1))
        #expect(store.tripToday?.trip.id == running.id)
        #expect(store.tripToday?.dayIndex == 1)
    }

    @Test func lodgingSurvivesARelaunch() {
        let (store, url) = makeStore()
        let trip = store.createTrip(city: SampleData.cities[0], start: day(1), end: day(2))
        store.setLodging(Lodging(name: "Baixa hotel", coordinate: Coordinate(latitude: 38.71, longitude: -9.14)),
                         for: trip.id)

        let reopened = AppStore(storageURL: url, loadFromDisk: true, seedDemoContent: false,
                                reminders: RecordingReminders())
        #expect(reopened.trip(id: trip.id)?.lodging?.name == "Baixa hotel")
    }

    @Test func clearingPastTripsKeepsTheRest() {
        let reminders = RecordingReminders()
        let (store, _) = makeStore(reminders: reminders)
        let old = store.createTrip(city: SampleData.cities[0], start: day(-10), end: day(-8))
        let older = store.createTrip(city: SampleData.cities[1], start: day(-30), end: day(-28))
        let coming = store.createTrip(city: SampleData.cities[2], start: day(3), end: day(5))

        store.deleteTrips(Set(store.pastTrips.map(\.id)))

        #expect(store.trips.map(\.id) == [coming.id])
        #expect(store.trip(id: old.id) == nil && store.trip(id: older.id) == nil)
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

/// Records what the store asks of the notification centre.
final class RecordingReminders: ReminderScheduling {
    private(set) var scheduled: [UNNotificationRequest] = []
    private(set) var cancelled: [String] = []

    func schedule(_ request: UNNotificationRequest) { scheduled.append(request) }
    func cancel(identifiers: [String]) { cancelled += identifiers }
}
