#if DEBUG
import Foundation

/// A ready-made trip for recording the demo video, loaded when the app is
/// launched with `-DemoTour` (the DemoTour scheme, or the UI test of the same
/// name). Debug builds only, and it keeps its own store in a temporary file,
/// so the real saved trips are never read or written.
@MainActor
enum DemoTour {
    static var isActive: Bool { ProcessInfo.processInfo.arguments.contains("-DemoTour") }

    /// A Lisbon trip that's under way, timed around now so every screen has
    /// something to show: the morning done, a stop in progress, two free
    /// hours before a bar later on; and tomorrow, a museum planned too late
    /// in the day and a castle that's shut.
    static func makeStore() -> AppStore {
        let store = AppStore(storageURL: URL.temporaryDirectory.appending(path: "demo-tour.json"),
                             loadFromDisk: false, seedDemoContent: false)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let lisbon = SampleData.cities[0]

        // Shut today as well as tomorrow, so the fix offers a day still to come.
        giveOpeningHours(castleShutOn: [calendar.component(.weekday, from: today) - 1,
                                        calendar.component(.weekday, from: tomorrow) - 1])
        func place(_ id: String) -> Place { PlaceDirectory.place(id: id)! }

        store.signIn(name: "Alex Rivera", email: "alex@example.com")
        let trip = store.createTrip(city: lisbon, start: today,
                                    end: calendar.date(byAdding: .day, value: 2, to: today)!, title: "Lisbon")
        store.setLodging(Lodging(name: "Memmo Alfama", coordinate: Coordinate(latitude: 38.7115, longitude: -9.1300)),
                         for: trip.id)

        // Today: whichever of the morning's stops are over by now, LX Factory
        // in progress, then two clear hours before the bar.
        let now = Date.now.minuteOfDay / 5 * 5
        let current = now - 30
        let morning: [(String, Int)] = [("lis-pasteis-belem", 9 * 60), ("lis-jeronimos", 10 * 60),
                                        ("lis-belem-tower", 12 * 60 + 30), ("lis-comercio", 14 * 60 + 30)]
        for (id, start) in morning where start + place(id).typicalMinutes <= current {
            store.addStop(place: place(id), to: trip.id, dayIndex: 0, startMinute: start)
        }
        store.addStop(place: place("lis-lx-factory"), to: trip.id, dayIndex: 0, startMinute: current)
        store.addStop(place: place("lis-pensao-amor"), to: trip.id, dayIndex: 0,
                      startMinute: min(now + 200, 22 * 60))

        // Tomorrow, as first planned: Jerónimos at four runs past its 5:30
        // close, and the castle is shut that day.
        for (id, start) in [("lis-pasteis-belem", 9 * 60), ("lis-tram-28", 11 * 60),
                            ("lis-castelo", 13 * 60), ("lis-jeronimos", 16 * 60)] {
            store.addStop(place: place(id), to: trip.id, dayIndex: 1, startMinute: start)
        }
        // The day after, with room to take the castle.
        store.addStop(place: place("lis-timeout"), to: trip.id, dayIndex: 2, startMinute: 15 * 60)
        store.addStop(place: place("lis-senhora-monte"), to: trip.id, dayIndex: 2, startMinute: 18 * 60 + 30)

        for id in ["lis-senhora-monte", "lis-azulejo", "lis-pensao-amor"] {
            store.toggleSaved(place(id))
        }
        return store
    }

    /// The bundled places carry no hours; these are close to the real ones.
    private static func giveOpeningHours(castleShutOn shutDays: Set<Int>) {
        func daily(_ open: Int, _ close: Int, except: Set<Int> = []) -> WeeklyHours {
            WeeklyHours(spans: (0..<7).filter { !except.contains($0) }.map {
                .init(start: $0 * 1440 + open, end: $0 * 1440 + close)
            })
        }
        let hours: [String: WeeklyHours] = [
            "lis-pasteis-belem": daily(8 * 60, 23 * 60),
            "lis-jeronimos": daily(9 * 60 + 30, 17 * 60 + 30),
            "lis-belem-tower": daily(9 * 60 + 30, 18 * 60),
            "lis-timeout": daily(10 * 60, 24 * 60),
            "lis-lx-factory": daily(9 * 60, 24 * 60),
            "lis-pensao-amor": daily(14 * 60, 27 * 60),
            "lis-castelo": daily(9 * 60, 21 * 60, except: shutDays),
            "lis-azulejo": daily(10 * 60, 18 * 60)
        ]
        PlaceDirectory.register(hours.compactMap { id, weekly in
            guard var place = PlaceDirectory.place(id: id) else { return nil }
            place.weeklyHours = weekly
            return place
        })
    }
}
#endif
