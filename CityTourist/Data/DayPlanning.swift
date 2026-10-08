import Foundation

/// Turns a trip day into the planner's terms, from what the app knows right
/// now: MapKit's times for hops it has already measured and estimates for the
/// rest, each place's hours on that weekday, and the day's daylight.
@MainActor
enum DayPlanning {

    /// `stops` must be in time order. `lodging` is where the day starts and
    /// ends; leave it out for a day already under way.
    static func planner(
        for stops: [ItineraryStop],
        on date: Date,
        lodging: Lodging?,
        forecast: DayForecast?,
        routes: RouteStore,
        availableFrom: Int? = nil,
        calendar: Calendar = .current
    ) -> DayPlanner {
        let weekday = calendar.component(.weekday, from: date) - 1
        let places = stops.map { PlaceDirectory.place(id: $0.placeID) }

        func minutes(_ a: Place?, _ b: Place?) -> Int {
            guard let a, let b, a.id != b.id else { return 0 }
            return routes.leg(from: a, to: b)?.minutes
                ?? TravelEstimate.minutes(from: a.coordinate, to: b.coordinate)
        }

        var planner = DayPlanner(
            stops: zip(stops, places).map { stop, place in
                DayPlanner.Stop(id: stop.id, duration: stop.durationMinutes,
                                isOutdoors: place?.category.isOutdoors ?? false,
                                hours: place?.weeklyHours?.day(weekday),
                                isMeal: place?.category == .food,
                                isBooked: stop.isBooked)
            },
            slots: stops.map(\.startMinute),
            travel: places.map { a in places.map { b in minutes(a, b) } },
            availableFrom: availableFrom,
            sunrise: forecast?.sunriseMinute,
            sunset: forecast?.sunsetMinute
        )
        if let lodging {
            let fromHotel = places.map { place in
                place.map { TravelEstimate.minutes(from: lodging.coordinate, to: $0.coordinate) } ?? 0
            }
            planner.fromLodging = fromHotel
            planner.toLodging = places.map { place in
                place.map { TravelEstimate.minutes(from: $0.coordinate, to: lodging.coordinate) } ?? 0
            }
        }
        return planner
    }

    /// The other days of a trip on which a place is open, for a stop planned
    /// on a day it's shut.
    ///
    /// Only days still to come: the stop moves at the same time of day, so
    /// today counts only if that time hasn't passed yet.
    static func openDays(for place: Place, in trip: Trip, besides dayIndex: Int, at startMinute: Int,
                         now: Date = .now, calendar: Calendar = .current) -> [Int] {
        guard let hours = place.weeklyHours else { return [] }
        let today = calendar.startOfDay(for: now)
        return trip.days.indices.filter { index in
            let date = trip.days[index].date
            let isAhead = date > today || (calendar.isDate(date, inSameDayAs: now) && startMinute > now.minuteOfDay)
            return index != dayIndex && isAhead
                && !hours.day(calendar.component(.weekday, from: date) - 1).isClosedAllDay
        }
    }
}

/// A planner result set against the day as planned, for the sheets that
/// offer it.
struct PlanProposal {
    /// The stops in their current order, timed realistically.
    var before: DayPlanner.Plan
    var after: DayPlanner.Plan
    /// Start times as currently planned.
    var planned: [ItineraryStop.ID: Int]

    init(planner: DayPlanner, stops: [ItineraryStop], keepOrder: Bool = false) {
        before = planner.current()
        after = keepOrder ? before : planner.best()
        planned = Dictionary(uniqueKeysWithValues: stops.map { ($0.id, $0.startMinute) })
    }

    /// The new start times worth saving: only the ones that differ.
    var changes: [ItineraryStop.ID: Int] {
        Dictionary(uniqueKeysWithValues: after.visits.compactMap { visit in
            planned[visit.id] == visit.start ? nil : (visit.id, visit.start)
        })
    }

    var isChange: Bool { !changes.isEmpty }

    var reorders: Bool { after.visits.map(\.id) != before.visits.map(\.id) }

    /// One line on what taking it would do, such as
    /// "Fixes 2 problems · 18 min less travel".
    var summary: String {
        var parts: [String] = []
        let fixed = troubled(before, comparedTo: planned).count - troubled(after, comparedTo: [:]).count
        if fixed > 0 { parts.append(fixed == 1 ? "Fixes 1 problem" : "Fixes \(fixed) problems") }
        let saved = before.travelMinutes - after.travelMinutes
        if saved >= 5 { parts.append("\(saved) min less travel") }
        return parts.joined(separator: " · ")
    }

    /// Stops that don't work as planned: shut on arrival, cut short, in the
    /// dark, or reached later than planned. A place shut all day isn't
    /// counted, since no plan fixes it.
    private func troubled(_ plan: DayPlanner.Plan, comparedTo planned: [ItineraryStop.ID: Int]) -> Set<ItineraryStop.ID> {
        Set(plan.visits.filter { visit in
            (visit.problem != nil && visit.problem != .closedAllDay)
                || visit.start > (planned[visit.id] ?? visit.start)
        }.map(\.id))
    }
}
