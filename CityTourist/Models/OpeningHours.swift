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

        let day = calendar.component(.weekday, from: date) - 1  // Google's Sunday is 0
        let dayStart = day * WeeklyHours.minutesPerDay
        let arrival = dayStart + startMinute
        let departure = arrival + durationMinutes
        let spans = repeated(hours.spans)

        // Merged first, so a place listed as 00:00–24:00 day by day reads as
        // open straight through midnight rather than closing at it.
        if let open = merged(spans).first(where: { $0.start <= arrival && arrival < $0.end }) {
            guard departure > open.end else { return nil }
            return HoursNote(symbol: "clock.badge.exclamationmark",
                             text: "closes \(clock(open.end)), before you leave")
        }

        // Closed on arrival. What does the place do that day? Unmerged here,
        // so the tail of the previous night doesn't count as opening today.
        let today = spans.filter { dayStart <= $0.start && $0.start < dayStart + WeeklyHours.minutesPerDay }
        guard !today.isEmpty else {
            return HoursNote(symbol: "xmark.circle", text: "closed on \(weekdays[day])s")
        }
        if let next = today.filter({ $0.start > arrival }).min(by: { $0.start < $1.start }) {
            return HoursNote(symbol: "clock.badge.exclamationmark",
                             text: "not open until \(clock(next.start))")
        }
        let lastClose = today.map(\.end).max() ?? arrival
        return HoursNote(symbol: "clock.badge.exclamationmark",
                         text: "closes \(clock(lastClose)), before you arrive")
    }

    /// Every span a week either side as well, so one that wraps past Saturday
    /// night, or began the evening before, lines up with any day.
    private static func repeated(_ spans: [WeeklyHours.Span]) -> [WeeklyHours.Span] {
        let week = WeeklyHours.minutesPerWeek
        return spans.flatMap { span in
            [-week, 0, week].map { WeeklyHours.Span(start: span.start + $0, end: span.end + $0) }
        }
    }

    /// Joins spans that touch or overlap.
    private static func merged(_ spans: [WeeklyHours.Span]) -> [WeeklyHours.Span] {
        spans.sorted { $0.start < $1.start }.reduce(into: []) { result, span in
            if let last = result.last, span.start <= last.end {
                result[result.count - 1].end = max(last.end, span.end)
            } else {
                result.append(span)
            }
        }
    }

    private static func clock(_ minuteOfWeek: Int) -> String {
        let day = WeeklyHours.minutesPerDay
        return DayForecast.clockLabel(((minuteOfWeek % day) + day) % day)
    }

    /// English, like the rest of the app's copy, which isn't localised.
    private static let weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday",
                                   "Thursday", "Friday", "Saturday"]
}
