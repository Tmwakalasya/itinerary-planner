import Foundation
import Observation
import UserNotifications

/// Single source of truth for trips, saved places and the signed-in account.
///
/// Everything persists to a JSON file in Documents, which covers the brief's
/// "save trips across sessions and devices" locally; the same `State` shape is
/// what a sync backend would read and write.
@MainActor
@Observable
final class AppStore {

    // MARK: State

    private(set) var trips: [Trip] = []
    private(set) var savedPlaceIDs: Set<String> = []
    private(set) var account: Account?
    /// Cities the user has searched for, kept so their trips still resolve.
    private(set) var knownCities: [City] = []
    /// City currently being browsed on Explore.
    var browsingCityID: String = "lisbon"

    var isSignedIn: Bool { account != nil }
    var browsingCity: City { CityDirectory.city(id: browsingCityID) }

    /// Most recently used cities, newest first, for the destination picker.
    var recentCities: [City] {
        var seen = Set<String>()
        return knownCities.reversed().filter { seen.insert($0.id).inserted }.prefix(6).map { $0 }
    }

    /// Switches the Explore feed to a city, remembering it for next launch.
    func browse(_ city: City) {
        CityDirectory.register(city)
        if !knownCities.contains(where: { $0.id == city.id }) { knownCities.append(city) }
        browsingCityID = city.id
        persist()
    }

    // MARK: Lifecycle

    /// Where state is written. Tests point this at a temp file.
    private let fileURL: URL

    init(storageURL: URL? = nil, loadFromDisk: Bool = true, seedDemoContent: Bool = true) {
        self.fileURL = storageURL ?? URL.documentsDirectory.appending(path: "citytourist-state.json")

        if loadFromDisk, let state = Self.load(from: fileURL) {
            trips = state.trips
            savedPlaceIDs = state.savedPlaceIDs
            account = state.account
            browsingCityID = state.browsingCityID
            knownCities = state.knownCities ?? []
            CityDirectory.register(knownCities)
        } else if seedDemoContent {
            seedDemoTrip()
        }
    }

    // MARK: - Saved places

    func isSaved(_ place: Place) -> Bool { savedPlaceIDs.contains(place.id) }

    func toggleSaved(_ place: Place) {
        if savedPlaceIDs.contains(place.id) {
            savedPlaceIDs.remove(place.id)
        } else {
            savedPlaceIDs.insert(place.id)
        }
        persist()
    }

    var savedPlaces: [Place] {
        savedPlaceIDs.compactMap(PlaceDirectory.place(id:)).sorted { $0.name < $1.name }
    }

    // MARK: - Trips

    @discardableResult
    func createTrip(city: City, start: Date, end: Date, title: String? = nil) -> Trip {
        // Remember the city itself, not just its id — a searched city isn't in
        // the bundled set, so nothing else would be able to resolve it later.
        CityDirectory.register(city)
        knownCities.removeAll { $0.id == city.id }
        knownCities.append(city)

        let cal = Calendar.current
        let startDay = cal.startOfDay(for: start)
        let endDay = cal.startOfDay(for: end)
        let dayCount = max(0, cal.dateComponents([.day], from: startDay, to: endDay).day ?? 0) + 1

        let days = (0..<dayCount).compactMap { offset -> ItineraryDay? in
            guard let date = cal.date(byAdding: .day, value: offset, to: startDay) else { return nil }
            return ItineraryDay(date: date)
        }

        let trip = Trip(
            cityID: city.id,
            title: title?.isEmpty == false ? title! : city.name,
            startDate: startDay,
            endDate: endDay,
            days: days
        )
        trips.insert(trip, at: 0)
        persist()
        return trip
    }

    func trip(id: Trip.ID) -> Trip? { trips.first { $0.id == id } }

    func deleteTrip(_ trip: Trip) {
        trips.removeAll { $0.id == trip.id }
        persist()
    }

    func update(_ trip: Trip) {
        guard let index = trips.firstIndex(where: { $0.id == trip.id }) else { return }
        trips[index] = trip
        persist()
    }

    /// Trips that haven't ended yet, newest start first.
    var upcomingTrips: [Trip] {
        let today = Calendar.current.startOfDay(for: .now)
        return trips.filter { $0.endDate >= today }.sorted { $0.startDate < $1.startDate }
    }

    var pastTrips: [Trip] {
        let today = Calendar.current.startOfDay(for: .now)
        return trips.filter { $0.endDate < today }.sorted { $0.startDate > $1.startDate }
    }

    // MARK: - Stops

    /// Inserts a stop in time order so the day's timeline never needs re-sorting.
    func addStop(place: Place, to tripID: Trip.ID, dayIndex: Int, startMinute: Int, note: String = "") {
        guard var trip = trip(id: tripID), trip.days.indices.contains(dayIndex) else { return }
        let stop = ItineraryStop(
            placeID: place.id,
            startMinute: startMinute,
            durationMinutes: place.typicalMinutes,
            note: note
        )
        trip.days[dayIndex].stops.append(stop)
        trip.days[dayIndex].stops.sort { $0.startMinute < $1.startMinute }
        update(trip)
    }

    func updateStop(_ stop: ItineraryStop, in tripID: Trip.ID, dayIndex: Int) {
        guard var trip = trip(id: tripID), trip.days.indices.contains(dayIndex),
              let stopIndex = trip.days[dayIndex].stops.firstIndex(where: { $0.id == stop.id })
        else { return }
        trip.days[dayIndex].stops[stopIndex] = stop
        trip.days[dayIndex].stops.sort { $0.startMinute < $1.startMinute }
        update(trip)
        syncReminder(for: stop, on: trip.days[dayIndex].date)
    }

    func removeStops(at offsets: IndexSet, in tripID: Trip.ID, dayIndex: Int) {
        guard var trip = trip(id: tripID), trip.days.indices.contains(dayIndex) else { return }
        let removed = offsets.map { trip.days[dayIndex].stops[$0] }
        trip.days[dayIndex].stops.remove(atOffsets: offsets)
        update(trip)
        removed.forEach(cancelReminder)
    }

    func moveStops(from source: IndexSet, to destination: Int, in tripID: Trip.ID, dayIndex: Int) {
        guard var trip = trip(id: tripID), trip.days.indices.contains(dayIndex) else { return }
        var stops = trip.days[dayIndex].stops
        stops.move(fromOffsets: source, toOffset: destination)
        // Reordering by hand implies the times should follow the new order, so
        // redistribute the existing start times down the list.
        let times = trip.days[dayIndex].stops.map(\.startMinute).sorted()
        for (index, time) in times.enumerated() where stops.indices.contains(index) {
            stops[index].startMinute = time
        }
        trip.days[dayIndex].stops = stops
        update(trip)
    }

    /// Suggests the next sensible start time: after the last stop, else 9:00.
    func suggestedStartMinute(tripID: Trip.ID, dayIndex: Int) -> Int {
        guard let trip = trip(id: tripID), trip.days.indices.contains(dayIndex),
              let last = trip.days[dayIndex].stops.last
        else { return 9 * 60 }
        return min(21 * 60, last.startMinute + last.durationMinutes + 30)
    }

    // MARK: - Collaborators

    func addCollaborator(_ collaborator: Collaborator, to tripID: Trip.ID) {
        guard var trip = trip(id: tripID) else { return }
        trip.collaborators.append(collaborator)
        update(trip)
    }

    func removeCollaborator(_ collaborator: Collaborator, from tripID: Trip.ID) {
        guard var trip = trip(id: tripID) else { return }
        trip.collaborators.removeAll { $0.id == collaborator.id }
        update(trip)
    }

    // MARK: - Account

    func signIn(name: String, email: String) {
        account = Account(name: name, email: email)
        persist()
    }

    func signOut() {
        account = nil
        persist()
    }

    // MARK: - Reminders

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func syncReminder(for stop: ItineraryStop, on date: Date) {
        let center = UNUserNotificationCenter.current()
        let identifier = "stop-\(stop.id.uuidString)"
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard stop.remindMe, let place = PlaceDirectory.place(id: stop.placeID) else { return }

        let cal = Calendar.current
        // Fire 30 minutes before the stop is due to start.
        guard let stopDate = cal.date(bySettingHour: stop.startMinute / 60,
                                      minute: stop.startMinute % 60, second: 0, of: date),
              let fireDate = cal.date(byAdding: .minute, value: -30, to: stopDate),
              fireDate > .now
        else { return }

        let content = UNMutableNotificationContent()
        content.title = place.name
        content.body = "Coming up at \(stop.timeLabel) · \(place.neighborhood)"
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: cal.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate),
            repeats: false
        )
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    private func cancelReminder(_ stop: ItineraryStop) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["stop-\(stop.id.uuidString)"])
    }

    // MARK: - Persistence

    private struct State: Codable {
        var trips: [Trip]
        var savedPlaceIDs: Set<String>
        var account: Account?
        var browsingCityID: String
        /// Optional so state written before city search still decodes.
        var knownCities: [City]?
    }

    private func persist() {
        let state = State(trips: trips, savedPlaceIDs: savedPlaceIDs,
                          account: account, browsingCityID: browsingCityID,
                          knownCities: knownCities)
        do {
            let data = try JSONEncoder().encode(state)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Losing a write shouldn't take the app down; the next one will retry.
            print("Failed to persist state: \(error)")
        }
    }

    private static func load(from fileURL: URL) -> State? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(State.self, from: data)
    }

    // MARK: - Demo content

    /// First launch shows a half-planned Lisbon trip rather than an empty app.
    private func seedDemoTrip() {
        account = Account(name: "Alex Rivera", email: "alex@example.com")
        savedPlaceIDs = ["lis-senhora-monte", "kyo-fushimi", "mex-contramar"]

        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: 12, to: cal.startOfDay(for: .now)) ?? .now
        let end = cal.date(byAdding: .day, value: 15, to: cal.startOfDay(for: .now)) ?? .now
        var trip = createTrip(city: SampleData.cities[0], start: start, end: end, title: "Lisbon")

        trip.collaborators = [
            Collaborator(name: "Sam Okafor", email: "sam@example.com", permission: .edit),
            Collaborator(name: "Mira Patel", email: "mira@example.com", permission: .view)
        ]
        if trip.days.indices.contains(0) {
            trip.days[0].stops = [
                ItineraryStop(placeID: "lis-pasteis-belem", startMinute: 9 * 60, durationMinutes: 40,
                              note: "Two each, standing at the counter."),
                ItineraryStop(placeID: "lis-jeronimos", startMinute: 10 * 60 + 15, durationMinutes: 105),
                ItineraryStop(placeID: "lis-belem-tower", startMinute: 12 * 60 + 30, durationMinutes: 75),
                ItineraryStop(placeID: "lis-lx-factory", startMinute: 15 * 60, durationMinutes: 100)
            ]
        }
        if trip.days.indices.contains(1) {
            trip.days[1].stops = [
                ItineraryStop(placeID: "lis-castelo", startMinute: 9 * 60 + 30, durationMinutes: 90),
                ItineraryStop(placeID: "lis-alfama", startMinute: 11 * 60 + 30, durationMinutes: 120),
                ItineraryStop(placeID: "lis-senhora-monte", startMinute: 18 * 60 + 45, durationMinutes: 35,
                              note: "Sunset is at 19:22.")
            ]
        }
        update(trip)
    }
}
