import Foundation

/// A place's regular weekly opening hours, as Google publishes them.
///
/// Each opening is a span of minutes from the start of the week — Sunday
/// 00:00, Google's day 0 — so a bar open Friday 20:00 to Saturday 02:00 is one
/// unbroken span rather than two half-days. A span that runs past Saturday
/// night simply ends beyond `minutesPerWeek`.
struct WeeklyHours: Codable, Hashable {
    struct Span: Codable, Hashable {
        var start: Int
        var end: Int
    }

    static let minutesPerDay = 24 * 60
    static let minutesPerWeek = 7 * minutesPerDay

    static let alwaysOpen = WeeklyHours(spans: [Span(start: 0, end: minutesPerWeek)])

    var spans: [Span]

    static func minuteOfWeek(day: Int, hour: Int, minute: Int) -> Int {
        day * minutesPerDay + hour * 60 + minute
    }

    /// One day's hours, in minutes from that day's midnight — what both the
    /// timeline note and the day planner reason about. Spans can start the
    /// night before (below 0) or run into tomorrow (past 1440).
    struct Day: Equatable {
        /// Merged, so a place listed 00:00–24:00 day by day reads as open
        /// straight through midnight rather than closing at it.
        var open: [Span]
        /// Openings that begin on this day, unmerged, so the tail of last
        /// night doesn't count as opening today.
        var openings: [Span]

        func span(containing minute: Int) -> Span? {
            open.first { $0.start <= minute && minute < $0.end }
        }

        func nextOpening(after minute: Int) -> Span? {
            openings.first { $0.start > minute }
        }

        /// Nothing opens that day and nothing runs through it.
        var isClosedAllDay: Bool {
            openings.isEmpty && !open.contains { $0.start <= 0 && $0.end >= minutesPerDay }
        }
    }

    /// `weekday` counts from Sunday = 0, as Google does.
    func day(_ weekday: Int) -> Day {
        let dayStart = weekday * Self.minutesPerDay
        // Every span a week either side as well, so one that wraps past
        // Saturday night, or began the evening before, lines up with any day.
        let repeated = spans.flatMap { span in
            [-Self.minutesPerWeek, 0, Self.minutesPerWeek].map {
                Span(start: span.start + $0 - dayStart, end: span.end + $0 - dayStart)
            }
        }.sorted { $0.start < $1.start }

        let merged = repeated.reduce(into: [Span]()) { result, span in
            if let last = result.last, span.start <= last.end {
                result[result.count - 1].end = max(last.end, span.end)
            } else {
                result.append(span)
            }
        }
        return Day(open: merged,
                   openings: repeated.filter { 0 <= $0.start && $0.start < Self.minutesPerDay })
    }
}

/// Flags a stop planned for a time the place isn't open.
///
/// Like the daylight and travel notes it says nothing while the plan works.
/// These are the place's regular hours, so holiday closures aren't covered.
struct HoursNote: Equatable {
    var symbol: String
    var text: String

    static func make(
        on date: Date,
        startMinute: Int,
        durationMinutes: Int,
        hours: WeeklyHours?,
        calendar: Calendar = .current
    ) -> HoursNote? {
        guard let hours, !hours.spans.isEmpty else { return nil }

        let weekday = calendar.component(.weekday, from: date) - 1  // Google's Sunday is 0
        let today = hours.day(weekday)
        let departure = startMinute + durationMinutes

        if let open = today.span(containing: startMinute) {
            guard departure > open.end else { return nil }
            return HoursNote(symbol: "clock.badge.exclamationmark",
                             text: "closes \(clock(open.end)), before you leave")
        }

        // Closed on arrival: say what the place does that day instead.
        guard !today.openings.isEmpty else {
            return HoursNote(symbol: "xmark.circle", text: "closed on \(weekdayNames[weekday])s")
        }
        if let next = today.nextOpening(after: startMinute) {
            return HoursNote(symbol: "clock.badge.exclamationmark",
                             text: "not open until \(clock(next.start))")
        }
        let lastClose = today.openings.map(\.end).max() ?? startMinute
        return HoursNote(symbol: "clock.badge.exclamationmark",
                         text: "closes \(clock(lastClose)), before you arrive")
    }

    /// Wraps minutes from the night before or into tomorrow onto the clock.
    private static func clock(_ minute: Int) -> String {
        let day = WeeklyHours.minutesPerDay
        return DayForecast.clockLabel(((minute % day) + day) % day)
    }

    /// English, like the rest of the app's copy, which isn't localised.
    static let weekdayNames = ["Sunday", "Monday", "Tuesday", "Wednesday",
                               "Thursday", "Friday", "Saturday"]
}
