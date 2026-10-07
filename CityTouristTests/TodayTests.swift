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

    // MARK: Day strip

    private func at(_ starts: [Int], minutes: Int = 60) -> [ItineraryStop] {
        starts.map { ItineraryStop(placeID: "p", startMinute: $0, durationMinutes: minutes) }
    }

    @Test func stopsAreSpacedByTimeWhenThereIsRoom() {
        let layout = DayStripLayout.make(stops: at([9 * 60, 10 * 60, 13 * 60]), now: 0,
                                         width: 300, inset: 20, minSpacing: 40)
        // 260 points across four hours: an hour is 65.
        #expect(layout.positions == [20, 85, 280])
        #expect(layout.width == 300)
    }

    @Test func closeStopsKeepEnoughRoomForTheirLabels() {
        let layout = DayStripLayout.make(stops: at([9 * 60, 9 * 60 + 10, 15 * 60]), now: 0,
                                         width: 300, inset: 20, minSpacing: 40)
        #expect(layout.positions[1] - layout.positions[0] == 40)
    }

    @Test func aLongDayGrowsWiderAndScrolls() {
        let layout = DayStripLayout.make(stops: at(Array(stride(from: 8 * 60, to: 10 * 60, by: 15))), now: 0,
                                         width: 300, inset: 20, minSpacing: 88)
        #expect(layout.width == CGFloat(20 + 7 * 88 + 20))
    }

    @Test func nowFallsBetweenTheStopsItIsBetween() {
        let stops = at([9 * 60, 10 * 60, 13 * 60], minutes: 30)
        let halfway = DayStripLayout.make(stops: stops, now: 9 * 60 + 30, width: 300, inset: 20, minSpacing: 40)
        #expect(halfway.nowX == CGFloat(20) + 65.0 / 2)
        #expect(DayStripLayout.make(stops: stops, now: 8 * 60, width: 300, inset: 20, minSpacing: 40).nowX == nil,
                "before the day starts")
        #expect(DayStripLayout.make(stops: stops, now: 14 * 60, width: 300, inset: 20, minSpacing: 40).nowX == nil,
                "after the last stop ends")
    }
}
