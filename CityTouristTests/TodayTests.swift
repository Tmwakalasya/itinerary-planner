import Testing
import Foundation
@testable import CityTourist

/// The trip-day logic under the Today screen: where the day stands, and
/// when to set off for what's next.
struct TodayTests {

    /// 9:00–10:00, 11:00–12:30 and 15:00–16:00.
    private let stops = [
        ItineraryStop(placeID: "a", startMinute: 9 * 60, durationMinutes: 60),
        ItineraryStop(placeID: "b", startMinute: 11 * 60, durationMinutes: 90),
        ItineraryStop(placeID: "c", startMinute: 15 * 60, durationMinutes: 60)
    ]

    // MARK: Where the day stands

    @Test func beforeTheFirstStopEverythingIsAhead() {
        let status = TodayStatus.make(stops: stops, now: 8 * 60)
        #expect(status.earlier.isEmpty)
        #expect(status.current == nil)
        #expect(status.next?.placeID == "a")
        #expect(status.later.map(\.placeID) == ["b", "c"])
    }

    @Test func duringAStopTheNextIsTheOneAfter() {
        let status = TodayStatus.make(stops: stops, now: 11 * 60 + 30)
        #expect(status.earlier.map(\.placeID) == ["a"])
        #expect(status.current?.placeID == "b")
        #expect(status.next?.placeID == "c")
        #expect(status.later.isEmpty)
    }

    @Test func betweenStopsNothingIsCurrent() {
        let status = TodayStatus.make(stops: stops, now: 10 * 60 + 15)
        #expect(status.current == nil)
        #expect(status.next?.placeID == "b")
    }

    /// Once it's over the stops are still listed as done, not gone: a day
    /// planned this morning shouldn't read as "nothing planned" by lunch.
    @Test func afterTheLastStopTheDayIsDone() {
        let evening = TodayStatus.make(stops: stops, now: 17 * 60)
        #expect(evening.isDone)
        #expect(evening.earlier.map(\.placeID) == ["a", "b", "c"])
        #expect(!TodayStatus.make(stops: stops, now: 15 * 60 + 30).isDone, "still at the last stop")
    }

    // MARK: Leaving

    @Test func leaveByCountsBackFromTheStartWithGrace() {
        let leave = LeaveBy(start: 10 * 60, travelMinutes: 13)
        #expect(leave.minute == 10 * 60 - 13 - LeaveBy.graceMinutes)
    }

    @Test func theCountdownReadsNaturally() {
        let leave = LeaveBy(start: 10 * 60, travelMinutes: 13)  // leave by 9:42
        #expect(leave.countdown(at: 8 * 60 + 40) == "Leave in 1 hr 2 min")
        #expect(leave.countdown(at: 9 * 60 + 30) == "Leave in 12 min")
        #expect(leave.countdown(at: 9 * 60 + 42) == "Leave now")
        #expect(leave.countdown(at: 9 * 60 + 47) == "Leave now", "still within the grace")
        #expect(leave.countdown(at: 9 * 60 + 52) == "5 min behind")
    }
}
