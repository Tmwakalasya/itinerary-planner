import Testing
import Foundation
@testable import CityTourist

/// Whether a stop lands while its place is open. Dates are fixed and the
/// calendar is UTC, so the weekday never depends on where the tests run.
struct OpeningHoursTests {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// A day in the week starting Sunday 6 September 2026, numbered the way
    /// Google numbers them: 0 is Sunday.
    private func date(weekday: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 6 + weekday))!
    }

    /// One opening; times are minutes past midnight.
    private func span(_ day: Int, _ open: Int, to closeDay: Int, _ close: Int) -> WeeklyHours.Span {
        let start = day * 1440 + open
        var end = closeDay * 1440 + close
        if end <= start { end += 7 * 1440 }
        return WeeklyHours.Span(start: start, end: end)
    }

    /// Closed Mondays, otherwise 10:00–18:00.
    private var museum: WeeklyHours {
        WeeklyHours(spans: [0, 2, 3, 4, 5, 6].map { span($0, 10 * 60, to: $0, 18 * 60) })
    }

    /// Friday and Saturday nights, 20:00 to 02:00.
    private var bar: WeeklyHours {
        WeeklyHours(spans: [span(5, 20 * 60, to: 6, 2 * 60), span(6, 20 * 60, to: 0, 2 * 60)])
    }

    private func note(_ hours: WeeklyHours?, weekday: Int, at minute: Int, for duration: Int = 60) -> HoursNote? {
        HoursNote.make(on: date(weekday: weekday), startMinute: minute, durationMinutes: duration,
                       hours: hours, calendar: calendar)
    }

    private func clock(_ hour: Int) -> String { DayForecast.clockLabel(hour * 60) }

    // MARK: Ordinary days

    @Test func aVisitInsideOpeningHoursSaysNothing() {
        #expect(note(museum, weekday: 2, at: 11 * 60, for: 90) == nil)
    }

    @Test func aClosedDayIsNamed() throws {
        let note = try #require(note(museum, weekday: 1, at: 11 * 60))
        #expect(note.text == "closed on Mondays")
        #expect(note.symbol == "xmark.circle")
    }

    @Test func arrivingBeforeOpeningSaysWhenItOpens() {
        #expect(note(museum, weekday: 2, at: 9 * 60)?.text == "not open until \(clock(10))")
    }

    /// Between lunch and dinner service, the useful answer is when it reopens.
    @Test func arrivingDuringABreakSaysWhenItReopens() {
        let restaurant = WeeklyHours(spans: [span(2, 12 * 60, to: 2, 14 * 60 + 30),
                                             span(2, 19 * 60, to: 2, 23 * 60)])
        #expect(note(restaurant, weekday: 2, at: 16 * 60)?.text == "not open until \(clock(19))")
    }

    @Test func arrivingAfterClosingIsFlagged() {
        #expect(note(museum, weekday: 2, at: 18 * 60 + 30)?.text == "closes \(clock(18)), before you arrive")
    }

    @Test func aVisitRunningPastClosingIsFlagged() {
        #expect(note(museum, weekday: 2, at: 17 * 60, for: 90)?.text == "closes \(clock(18)), before you leave")
    }

    @Test func theBoundariesAreExact() {
        #expect(note(museum, weekday: 2, at: 10 * 60) == nil, "arriving as it opens is fine")
        #expect(note(museum, weekday: 2, at: 16 * 60 + 30, for: 90) == nil, "leaving as it closes is fine")
    }

    // MARK: Past midnight

    /// Friday night covers early Saturday, and Saturday night wraps into
    /// Sunday — the start of Google's week.
    @Test func lateNightsRunPastMidnightAndTheEndOfTheWeek() {
        #expect(note(bar, weekday: 6, at: 60) == nil, "1:00 on Saturday is still Friday night")
        #expect(note(bar, weekday: 6, at: 23 * 60 + 30, for: 120) == nil, "out by 1:30 on Sunday")
        #expect(note(bar, weekday: 0, at: 60) == nil, "1:00 on Sunday is still Saturday night")
    }

    /// The tail of Friday night isn't Saturday's opening: arriving Saturday
    /// afternoon is answered with Saturday evening.
    @Test func lastNightsTailIsNotTodaysOpening() {
        #expect(note(bar, weekday: 6, at: 15 * 60)?.text == "not open until \(clock(20))")
        #expect(note(bar, weekday: 1, at: 21 * 60)?.text == "closed on Mondays")
    }

    @Test func roundTheClockListedDayByDayNeverCloses() {
        let station = WeeklyHours(spans: (0..<7).map { span($0, 0, to: ($0 + 1) % 7, 0) })
        #expect(note(station, weekday: 6, at: 23 * 60, for: 120) == nil, "no false alarm at midnight")
        #expect(note(.alwaysOpen, weekday: 3, at: 3 * 60) == nil)
    }

    @Test func withoutHoursNothingIsClaimed() {
        #expect(note(nil, weekday: 1, at: 11 * 60) == nil)
    }
}
