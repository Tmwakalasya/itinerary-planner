import Foundation

/// A stretch of today with nothing planned in it.
struct FreeTime: Equatable {
    /// Minutes past midnight.
    var start: Int
    var end: Int
    /// The stop just before: where you'd be setting off from.
    var after: ItineraryStop?
    /// The stop just after, which you still need to make in time.
    var before: ItineraryStop?

    var minutes: Int { end - start }

    /// Shorter than this isn't worth suggesting anything for.
    static let shortest = 60
    /// Past this the day is winding down; suggestions stop here.
    static let dayEnds = 21 * 60

    /// The next stretch of an hour or more with nothing planned, from `now`
    /// on. `stops` are in time order.
    static func next(in stops: [ItineraryStop], now: Int) -> FreeTime? {
        var free = now
        var previous: ItineraryStop?
        for stop in stops {
            if stop.startMinute - free >= shortest {
                return FreeTime(start: free, end: stop.startMinute, after: previous, before: stop)
            }
            // Overlapping stops don't open a gap; you're free once both end.
            free = max(free, stop.startMinute + stop.durationMinutes)
            previous = stop
        }
        guard dayEnds - free >= shortest else { return nil }
        return FreeTime(start: free, end: dayEnds, after: previous, before: nil)
    }
}

/// A place that fits a stretch of free time.
struct GapSuggestion: Identifiable, Equatable {
    var place: Place
    /// When the visit would start, minutes past midnight.
    var start: Int
    /// Minutes to get there from where you'd be.
    var travelMinutes: Int

    var id: String { place.id }
}

/// Finds places for free time: open then, not outdoors in the dark or the
/// rain, and close enough to get there, see it, and still make the next stop.
/// Nearby first, and among places about as near, the better rated.
enum GapFiller {
    static let eveningStarts = 18 * 60

    static func suggestions(
        for gap: FreeTime,
        among places: [Place],
        on date: Date,
        from origin: Coordinate?,
        to next: Coordinate?,
        forecast: DayForecast?,
        excluding planned: Set<String>,
        limit: Int = 3
    ) -> [GapSuggestion] {
        let fitting = places.compactMap { place -> (suggestion: GapSuggestion, detour: Int)? in
            guard !planned.contains(place.id) else { return nil }
            let there = origin.map { TravelEstimate.minutes(from: $0, to: place.coordinate) } ?? 0
            let onward = next.map { TravelEstimate.minutes(from: place.coordinate, to: $0) } ?? 0
            let start = (gap.start + there + 4) / 5 * 5
            guard start + place.typicalMinutes + onward <= gap.end else { return nil }

            guard HoursNote.make(on: date, startMinute: start, durationMinutes: place.typicalMinutes,
                                 hours: place.weeklyHours) == nil,
                  DaylightNote.make(startMinute: start, durationMinutes: place.typicalMinutes,
                                    category: place.category, forecast: forecast) == nil,
                  !(forecast?.isWet == true && place.category.isOutdoors),
                  // Bars and clubs wait for the evening, hours known or not.
                  place.category != .nightlife || start >= GapFiller.eveningStarts
            else { return nil }

            return (GapSuggestion(place: place, start: start, travelMinutes: there), there + onward)
        }

        // Ten-minute bands: a place five minutes further but much better
        // rated is worth it; one twenty minutes further usually isn't.
        return fitting
            .sorted { a, b in
                a.detour / 10 != b.detour / 10 ? a.detour < b.detour : a.suggestion.place.rating > b.suggestion.place.rating
            }
            .prefix(limit)
            .map(\.suggestion)
    }
}
