import Foundation
import Observation
import UserNotifications

/// Single source of truth for trips and saved places.
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
    /// Which city each saved place came from, so it can be looked up again
    /// after a relaunch. Missing for places saved before this was recorded.
    private(set) var savedPlaceCityIDs: [String: String] = [:]
    /// Cities the user has searched for, kept so their trips still resolve.
    private(set) var knownCities: [City] = []
    /// City currently being browsed on Explore.
    var browsingCityID: String = "lisbon"
    /// The last plan applied in one go, kept briefly so it can be taken back.
    private(set) var pendingUndo: PlanUndo?

    enum StorageIssue {
        case unreadable, unsaved
    }
    private(set) var storageIssue: StorageIssue?
    /// A failed read must never turn into a fresh save over the original file.
    private var canPersist = true

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
    /// Where stop reminders go. Tests record them instead.
    private let reminders: any ReminderScheduling

    init(storageURL: URL? = nil, loadFromDisk: Bool = true,
         reminders: any ReminderScheduling = SystemReminders()) {
        self.fileURL = storageURL ?? URL.documentsDirectory.appending(path: "citytourist-state.json")
        self.reminders = reminders

        if loadFromDisk {
            do {
                if let state = try Self.load(from: fileURL) {
                    restore(state)
                    return
                }
            } catch {
                canPersist = false
                storageIssue = .unreadable
                return
            }
        }
    }

    // MARK: - Saved places

    func isSaved(_ place: Place) -> Bool { savedPlaceIDs.contains(place.id) }

    func toggleSaved(_ place: Place) {
        if savedPlaceIDs.contains(place.id) {
            savedPlaceIDs.remove(place.id)
            savedPlaceCityIDs[place.id] = nil
        } else {
            savedPlaceIDs.insert(place.id)
            savedPlaceCityIDs[place.id] = place.cityID
        }
        persist()
    }

    /// Saved places that have resolved. Ones from an earlier session may still
    /// be on their way — see `PlaceCatalog.resolve`.
    var savedPlaces: [Place] {
        savedPlaceIDs.compactMap(PlaceDirectory.place(id:)).sorted { $0.name < $1.name }
    }

    /// Saved place ids grouped by the city each came from; nil holds places
    /// saved before cities were recorded.
    var savedPlaceIDsByCity: [String?: [String]] {
        Dictionary(grouping: savedPlaceIDs) { savedPlaceCityIDs[$0] }
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
        deleteTrips([trip.id])
    }

    func deleteTrips(_ ids: Set<Trip.ID>) {
        // Otherwise their reminders outlive them and fire for plans that are gone.
        let stops = trips.filter { ids.contains($0.id) }.flatMap { $0.days.flatMap(\.stops) }
        trips.removeAll { ids.contains($0.id) }
        if let undo = pendingUndo, ids.contains(undo.tripID) { pendingUndo = nil }
        persist()
        stops.forEach(cancelReminder)
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
    /// `isBooked` for something with a fixed time, like an event's ticket.
    func addStop(place: Place, to tripID: Trip.ID, dayIndex: Int, startMinute: Int, note: String = "",
                 isBooked: Bool = false) {
        editDay(dayIndex, of: tripID) { stops in
            stops.append(ItineraryStop(placeID: place.id, startMinute: startMinute,
                                       durationMinutes: place.typicalMinutes, note: note, isBooked: isBooked))
        }
    }

    func updateStop(_ stop: ItineraryStop, in tripID: Trip.ID, dayIndex: Int) {
        editDay(dayIndex, of: tripID) { stops in
            guard let index = stops.firstIndex(where: { $0.id == stop.id }) else { return }
            stops[index] = stop
        }
    }

    func removeStops(at offsets: IndexSet, in tripID: Trip.ID, dayIndex: Int) {
        guard let trip = trip(id: tripID), trip.days.indices.contains(dayIndex) else { return }
        let removed = offsets.map { trip.days[dayIndex].stops[$0] }
        editDay(dayIndex, of: tripID) { $0.remove(atOffsets: offsets) }
        removed.forEach(cancelReminder)
    }

    func moveStops(from source: IndexSet, to destination: Int, in tripID: Trip.ID, dayIndex: Int) {
        editDay(dayIndex, of: tripID) { stops in
            // Reordering by hand implies the times should follow the new order,
            // so redistribute the existing start times down the list. Booked
            // stops keep theirs; the rest trade the remaining times.
            var times = stops.filter { !$0.isBooked }.map(\.startMinute).sorted().makeIterator()
            stops.move(fromOffsets: source, toOffset: destination)
            for index in stops.indices where !stops[index].isBooked {
                if let time = times.next() { stops[index].startMinute = time }
            }
        }
    }

    /// Gives stops new start times: a fixed day, or the rest of one re-planned
    /// around running late. A day stays in time order, so new times are also
    /// the new order. Stops not mentioned keep theirs.
    func retime(_ starts: [ItineraryStop.ID: Int], in tripID: Trip.ID, dayIndex: Int) {
        editDay(dayIndex, of: tripID) { stops in
            for index in stops.indices {
                if let start = starts[stops[index].id] { stops[index].startMinute = start }
            }
        }
    }

    /// A whole re-planned day, applied at once and offered back as an undo:
    /// several times change together, so taking it back should be one tap.
    func applyPlan(_ starts: [ItineraryStop.ID: Int], in tripID: Trip.ID, dayIndex: Int, message: String) {
        guard let trip = trip(id: tripID), trip.days.indices.contains(dayIndex), !starts.isEmpty else { return }
        let before = trip.days[dayIndex].stops
        retime(starts, in: tripID, dayIndex: dayIndex)
        pendingUndo = PlanUndo(tripID: tripID, dayIndex: dayIndex, stops: before, message: message)
    }

    func undoPlan() {
        guard let undo = pendingUndo else { return }
        editDay(undo.dayIndex, of: undo.tripID) { $0 = undo.stops }
    }

    /// Lets an undo lapse, unless a newer one has replaced it.
    func dismissUndo(_ id: PlanUndo.ID) {
        if pendingUndo?.id == id { pendingUndo = nil }
    }

    /// Moves a stop to another day of the trip at the same time of day, for a
    /// place that's shut on the day it was planned.
    func moveStop(_ stopID: ItineraryStop.ID, in tripID: Trip.ID, from dayIndex: Int, to targetIndex: Int) {
        guard var trip = trip(id: tripID), dayIndex != targetIndex,
              trip.days.indices.contains(dayIndex), trip.days.indices.contains(targetIndex),
              let index = trip.days[dayIndex].stops.firstIndex(where: { $0.id == stopID })
        else { return }
        pendingUndo = nil
        trip.days[targetIndex].stops.append(trip.days[dayIndex].stops.remove(at: index))
        trip.days[targetIndex].stops.sort { $0.startMinute < $1.startMinute }
        update(trip)
        syncReminders(for: trip, dayIndex: dayIndex)
        syncReminders(for: trip, dayIndex: targetIndex)
    }

    /// Changes one day's stops, keeps them in time order, and reschedules the
    /// day's reminders, since a stop's leave-by time depends on the one before.
    private func editDay(_ dayIndex: Int, of tripID: Trip.ID, _ edit: (inout [ItineraryStop]) -> Void) {
        guard var trip = trip(id: tripID), trip.days.indices.contains(dayIndex) else { return }
        // Any later change makes an undo stale: taking it back would undo that too.
        pendingUndo = nil
        edit(&trip.days[dayIndex].stops)
        trip.days[dayIndex].stops.sort { $0.startMinute < $1.startMinute }
        update(trip)
        syncReminders(for: trip, dayIndex: dayIndex)
    }

    /// Suggests the next sensible start time: after the last stop, else 9:00.
    /// On today's date it's never a time that's already gone — at least a
    /// quarter of an hour from now, on the quarter hour.
    func suggestedStartMinute(tripID: Trip.ID, dayIndex: Int, now: Date = .now) -> Int {
        guard let trip = trip(id: tripID), trip.days.indices.contains(dayIndex) else { return 9 * 60 }
        let day = trip.days[dayIndex]
        var minute = min(21 * 60, day.stops.last.map { $0.startMinute + $0.durationMinutes + 30 } ?? 9 * 60)
        if Calendar.current.isDate(day.date, inSameDayAs: now) {
            minute = max(minute, (now.minuteOfDay + 15 + 14) / 15 * 15)
        }
        // Still the same day, however late it's getting.
        return min(minute, 23 * 60 + 45)
    }

    // MARK: - Lodging and today

    func setLodging(_ lodging: Lodging?, for tripID: Trip.ID) {
        guard var trip = trip(id: tripID) else { return }
        trip.lodging = lodging
        update(trip)
        // Each day's first leave-by time is measured from here.
        for dayIndex in trip.days.indices { syncReminders(for: trip, dayIndex: dayIndex) }
    }

    func setGettingAround(_ gettingAround: GettingAround, for tripID: Trip.ID) {
        guard var trip = trip(id: tripID), trip.gettingAround != gettingAround else { return }
        trip.gettingAround = gettingAround
        update(trip)
        // Every leave-by time depends on it.
        for dayIndex in trip.days.indices { syncReminders(for: trip, dayIndex: dayIndex) }
    }

    /// The trip and day happening today, if one is.
    var tripToday: (trip: Trip, dayIndex: Int)? {
        for trip in upcomingTrips {
            if let dayIndex = trip.days.firstIndex(where: { Calendar.current.isDateInToday($0.date) }) {
                return (trip, dayIndex)
            }
        }
        return nil
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

    // MARK: - Reminders

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Reschedules every reminder on a day for when to set off.
    private func syncReminders(for trip: Trip, dayIndex: Int) {
        guard trip.days.indices.contains(dayIndex) else { return }
        let day = trip.days[dayIndex]
        var origin = trip.lodging.map { (name: $0.name, coordinate: $0.coordinate) }
        for stop in day.stops {
            syncReminder(for: stop, on: day.date, from: origin, by: trip.gettingAround)
            origin = PlaceDirectory.place(id: stop.placeID).map { (name: $0.name, coordinate: $0.coordinate) }
        }
    }

    /// Fires when it's time to leave `origin` — the stop before, or where
    /// you're staying — for this one. It's scheduled ahead without asking
    /// MapKit, so the hop is a straight-line estimate. With nowhere to come
    /// from, it's a nudge half an hour before.
    private func syncReminder(for stop: ItineraryStop, on date: Date,
                              from origin: (name: String, coordinate: Coordinate)?,
                              by gettingAround: GettingAround) {
        let identifier = "stop-\(stop.id.uuidString)"
        reminders.cancel(identifiers: [identifier])
        guard stop.remindMe, let place = PlaceDirectory.place(id: stop.placeID) else { return }

        let hop = origin.map { TravelEstimate.minutes(from: $0.coordinate, to: place.coordinate, by: gettingAround) }
        let fireMinute = hop.map { LeaveBy(start: stop.startMinute, travelMinutes: $0).minute }
            ?? stop.startMinute - 30

        let cal = Calendar.current
        guard let fireDate = cal.date(byAdding: .minute, value: fireMinute, to: cal.startOfDay(for: date)),
              fireDate > .now
        else { return }

        let content = UNMutableNotificationContent()
        content.title = place.name
        if let hop, let origin {
            content.body = "Time to head off: about \(hop) min from \(origin.name). Starts at \(stop.timeLabel)."
        } else {
            content.body = "Coming up at \(stop.timeLabel) · \(place.neighborhood)"
        }
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: cal.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate),
            repeats: false
        )
        reminders.schedule(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    private func cancelReminder(_ stop: ItineraryStop) {
        reminders.cancel(identifiers: ["stop-\(stop.id.uuidString)"])
    }

    // MARK: - Persistence

    private struct State: Codable {
        var trips: [Trip]
        var savedPlaceIDs: Set<String>
        var browsingCityID: String
        /// Optional so state written before city search still decodes.
        var knownCities: [City]?
        /// Optional so state written before bookmarks recorded a city still decodes.
        var savedPlaceCityIDs: [String: String]?
    }

    private func persist() {
        guard canPersist else { return }
        let state = State(trips: trips, savedPlaceIDs: savedPlaceIDs,
                          browsingCityID: browsingCityID,
                          knownCities: knownCities, savedPlaceCityIDs: savedPlaceCityIDs)
        do {
            let data = try JSONEncoder().encode(state)
            try data.write(to: fileURL, options: .atomic)
            storageIssue = nil
        } catch {
            storageIssue = .unsaved
        }
    }

    func retryStorage() {
        if canPersist {
            persist()
            return
        }
        do {
            // Recovery only accepts a readable save. A missing file after a
            // failed load is not a reason to replace the user's trips with nothing.
            guard let state = try Self.load(from: fileURL) else { return }
            restore(state)
            canPersist = true
            storageIssue = nil
        } catch {
            storageIssue = .unreadable
        }
    }

    private func restore(_ state: State) {
        trips = state.trips
        savedPlaceIDs = state.savedPlaceIDs
        savedPlaceCityIDs = state.savedPlaceCityIDs ?? [:]
        browsingCityID = state.browsingCityID
        knownCities = state.knownCities ?? []
        CityDirectory.register(knownCities)
    }

    private static func load(from fileURL: URL) throws -> State? {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        }
        return try JSONDecoder().decode(State.self, from: data)
    }
}

// MARK: - Reminder delivery

/// Where stop reminders are sent: the notification centre in the app, a
/// recorder in tests, which can't rely on notification permission.
protocol ReminderScheduling {
    func schedule(_ request: UNNotificationRequest)
    func cancel(identifiers: [String])
}

struct SystemReminders: ReminderScheduling {
    func schedule(_ request: UNNotificationRequest) {
        UNUserNotificationCenter.current().add(request)
    }

    func cancel(identifiers: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}

/// A day as it was before a plan was applied to it.
struct PlanUndo: Identifiable, Equatable {
    let id = UUID()
    let tripID: Trip.ID
    let dayIndex: Int
    let stops: [ItineraryStop]
    /// What the undo bar says happened, e.g. "Day updated".
    let message: String
}
