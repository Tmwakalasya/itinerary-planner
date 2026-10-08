import Testing
import Foundation
@testable import CityTourist

/// The day planner, on days built by hand: minutes past midnight, travel
/// tables in minutes, and hours that are the same every day of the week.
struct DayPlannerTests {

    private let ids = (0..<12).map { _ in UUID() }

    private func stop(_ n: Int, minutes: Int = 60, outdoors: Bool = false,
                      hours: WeeklyHours.Day? = nil, meal: Bool = false) -> DayPlanner.Stop {
        DayPlanner.Stop(id: ids[n], duration: minutes, isOutdoors: outdoors, hours: hours, isMeal: meal)
    }

    /// Open `from`–`to` every day; times are minutes past midnight.
    private func open(_ from: Int, _ to: Int) -> WeeklyHours.Day {
        WeeklyHours(spans: (0..<7).map { .init(start: $0 * 1440 + from, end: $0 * 1440 + to) }).day(2)
    }

    /// Every hop takes the same time.
    private func flat(_ count: Int, _ minutes: Int) -> [[Int]] {
        (0..<count).map { i in (0..<count).map { j in i == j ? 0 : minutes } }
    }

    /// Stops along a straight street, `step` minutes apart per position.
    private func street(_ positions: [Int], step: Int) -> [[Int]] {
        positions.map { a in positions.map { b in abs(a - b) * step } }
    }

    private func order(_ plan: DayPlanner.Plan) -> [UUID] { plan.visits.map(\.id) }

    // MARK: Leaving a good day alone

    @Test func aDayThatWorksIsLeftAlone() {
        let planner = DayPlanner(stops: [stop(0), stop(1), stop(2)],
                                 slots: [9 * 60, 11 * 60, 14 * 60], travel: flat(3, 10))
        let best = planner.best()

        #expect(best == planner.current())
        #expect(best.visits.map(\.start) == [9 * 60, 11 * 60, 14 * 60])
        #expect(best.fixableProblems == 0)
    }

    // MARK: Opening hours

    /// The headline case: a museum planned for late afternoon closes before
    /// the visit ends, so it trades slots with something that doesn't mind.
    @Test func aMuseumClosingEarlyTradesForAMorningSlot() {
        let planner = DayPlanner(
            stops: [stop(0), stop(1, minutes: 90, outdoors: true), stop(2, minutes: 120, hours: open(600, 1020))],
            slots: [9 * 60, 11 * 60, 16 * 60], travel: flat(3, 10), sunset: 19 * 60)

        #expect(planner.current().visits[2].problem == .closesEarly(by: 60))

        let best = planner.best()
        #expect(order(best) == [ids[0], ids[2], ids[1]])
        #expect(best.fixableProblems == 0)
        #expect(best.visits.map(\.start) == [9 * 60, 11 * 60, 16 * 60], "every slot keeps its time")
    }

    @Test func itWaitsForAPlaceThatOpensShortlyAfter() {
        let planner = DayPlanner(stops: [stop(0, hours: open(600, 1080))], slots: [9 * 60], travel: flat(1, 0))
        let visit = planner.best().visits[0]
        #expect(visit.start == 10 * 60)
        #expect(visit.problem == nil)
    }

    @Test func aPlaceOpeningMuchLaterIsFlaggedNotWaitedFor() {
        let planner = DayPlanner(stops: [stop(0, hours: open(12 * 60, 1080))], slots: [9 * 60], travel: flat(1, 0))
        let visit = planner.best().visits[0]
        #expect(visit.start == 9 * 60)
        #expect(visit.problem == .closedOnArrival)
    }

    /// No order opens a door that's shut all day, so it mustn't drive the
    /// order — the fix is another day, which the sheet offers.
    @Test func closedAllDayIsReportedButNotChased() {
        let shut = WeeklyHours(spans: [.init(start: 600, end: 1080)]).day(2)  // Sundays only
        let planner = DayPlanner(stops: [stop(0, hours: shut), stop(1)],
                                 slots: [10 * 60, 12 * 60], travel: flat(2, 10))
        let best = planner.best()

        #expect(order(best) == [ids[0], ids[1]])
        #expect(best.visits[0].problem == .closedAllDay)
        #expect(best.fixableProblems == 0)
    }

    /// Even when it's out of the way: moving it would save an hour of
    /// travel, but the fix is another day, not another slot.
    @Test func aStopShutAllDayKeepsItsSlot() {
        let shut = WeeklyHours(spans: [.init(start: 600, end: 1080)]).day(2)
        let planner = DayPlanner(stops: [stop(0), stop(1, hours: shut), stop(2)],
                                 slots: [9 * 60, 11 * 60, 13 * 60],
                                 travel: [[0, 60, 5], [60, 0, 60], [5, 60, 0]])
        #expect(order(planner.best()) == [ids[0], ids[1], ids[2]])
    }

    // MARK: Daylight

    @Test func anOutdoorStopIsKeptOutOfTheDark() {
        let planner = DayPlanner(
            stops: [stop(0, hours: open(9 * 60, 21 * 60)), stop(1, outdoors: true)],
            slots: [16 * 60, 19 * 60], travel: flat(2, 10), sunset: 19 * 60 + 30)

        #expect(planner.current().visits[1].problem == .inTheDark(minutes: 30))
        #expect(order(planner.best()) == [ids[1], ids[0]])
    }

    // MARK: Travel

    @Test func aShorterRouteWinsWhenNothingElseIsWrong() {
        // Planned zig-zagging along a street: 0, then 20, back to 10, on to 30.
        let planner = DayPlanner(stops: [stop(0), stop(2), stop(1), stop(3)],
                                 slots: [9 * 60, 12 * 60, 15 * 60, 18 * 60],
                                 travel: street([0, 20, 10, 30], step: 3))
        let best = planner.best()

        #expect(order(best) == [ids[0], ids[1], ids[2], ids[3]])
        #expect(best.travelMinutes == 90)
        #expect(planner.current().travelMinutes == 150)
    }

    /// A few minutes saved isn't worth rearranging someone's day.
    @Test func aSmallSavingDoesNotReshuffleTheDay() {
        let planner = DayPlanner(stops: [stop(0), stop(2), stop(1), stop(3)],
                                 slots: [9 * 60, 11 * 60, 13 * 60, 15 * 60],
                                 travel: street([0, 20, 10, 30], step: 1))
        #expect(planner.best() == planner.current(), "20 minutes saved, but two stops would move")
    }

    /// The hotel is right by the second stop, and the walk from it to
    /// breakfast is an hour. Saving that isn't worth breakfast at lunchtime.
    @Test func mealsKeepTheirTime() {
        var planner = DayPlanner(stops: [stop(0, meal: true), stop(1), stop(2)],
                                 slots: [9 * 60, 11 * 60, 13 * 60], travel: flat(3, 10))
        planner.fromLodging = [60, 5, 30]
        #expect(order(planner.best()).first == ids[0])

        planner.stops[0].isMeal = false
        #expect(order(planner.best()).first == ids[1], "the same stop that isn't a meal does move")
    }

    @Test func aHopThatDoesNotFitPushesTheNextStopBack() {
        let planner = DayPlanner(stops: [stop(0), stop(1)], slots: [9 * 60, 10 * 60], travel: flat(2, 23))
        let best = planner.best()

        // 10:00 finish + 23 minutes, rounded up to a whole five.
        #expect(best.visits[1].start == 10 * 60 + 25)
        #expect(best.pushedMinutes == 25)
    }

    @Test func theDayLeansTowardsWhereYouAreStaying() {
        var planner = DayPlanner(stops: [stop(0), stop(1), stop(2)],
                                 slots: [9 * 60, 12 * 60, 15 * 60], travel: flat(3, 10))
        planner.fromLodging = [60, 5, 60]
        planner.toLodging = [60, 5, 60]
        let best = planner.best()

        #expect(best.visits.first?.id == ids[1] || best.visits.last?.id == ids[1],
                "the stop by the hotel starts or ends the day")
        #expect(best.travelMinutes == 85)
    }

    // MARK: Running late

    @Test func runningLateOnlyPushesWhatItMust() {
        var planner = DayPlanner(stops: [stop(0), stop(1)], slots: [10 * 60, 14 * 60], travel: flat(2, 10))
        planner.availableFrom = 10 * 60 + 30
        let best = planner.best()

        #expect(best.visits.map(\.start) == [10 * 60 + 30, 14 * 60], "the afternoon absorbs it")
        #expect(best.pushedMinutes == 30)
    }

    /// An hour behind, keeping the order would reach the museum after it
    /// shuts; going there first still makes it.
    @Test func runningLateReordersToBeatClosingTime() {
        var planner = DayPlanner(stops: [stop(0), stop(1, hours: open(600, 17 * 60))],
                                 slots: [15 * 60, 16 * 60], travel: flat(2, 10))
        planner.availableFrom = 16 * 60

        #expect(planner.current().visits[1].problem == .closedOnArrival)

        let best = planner.best()
        #expect(order(best) == [ids[1], ids[0]])
        #expect(best.fixableProblems == 0)
    }

    // MARK: Bookings

    /// The zig-zag that a shorter route straightens out, with its far stop
    /// booked: the rest of the day can rearrange, but around it.
    @Test func aBookedStopKeepsItsSlotWhenAShorterRouteWouldMoveIt() {
        var planner = DayPlanner(stops: [stop(0), stop(2), stop(1), stop(3)],
                                 slots: [9 * 60, 12 * 60, 15 * 60, 18 * 60],
                                 travel: street([0, 20, 10, 30], step: 3))
        planner.stops[1].isBooked = true
        let best = planner.best()

        #expect(best.visits[1].id == ids[2])
        #expect(best.visits[1].start == 12 * 60)

        planner.stops[1].isBooked = false
        #expect(order(planner.best())[1] != ids[2], "unbooked, the same stop moves")
    }

    /// An early-entry tour and a sunset cruise: unbooked, the first would
    /// wait for opening and the second would be flagged for the dark.
    @Test func aBookingIsTrustedOverRegularHoursAndDaylight() {
        var planner = DayPlanner(stops: [stop(0, hours: open(10 * 60, 18 * 60)), stop(1, outdoors: true)],
                                 slots: [9 * 60, 20 * 60], travel: flat(2, 10), sunset: 19 * 60)
        planner.stops[0].isBooked = true
        planner.stops[1].isBooked = true
        let current = planner.current()

        #expect(current.visits.map(\.start) == [9 * 60, 20 * 60])
        #expect(current.visits.allSatisfy { $0.problem == nil })
    }

    /// A far-off morning stop makes the booked lunch 15 minutes late; the
    /// nearby afternoon stop trades places with it so lunch is on time.
    @Test func otherStopsSwapToReachABookingOnTime() {
        var planner = DayPlanner(stops: [stop(0, minutes: 90), stop(1, meal: true), stop(2)],
                                 slots: [10 * 60, 12 * 60, 15 * 60],
                                 travel: [[0, 45, 50], [45, 0, 10], [50, 10, 0]])
        planner.stops[1].isBooked = true

        #expect(planner.current().visits[1].problem == .lateForBooking(by: 15))

        let best = planner.best()
        #expect(order(best) == [ids[2], ids[1], ids[0]])
        #expect(best.lateBookings == 0)
        #expect(best.visits.map(\.start) == [10 * 60, 12 * 60, 15 * 60])
    }

    /// Half an hour behind with dinner booked: dinner keeps its time and
    /// says you'll be late, rather than quietly moving.
    @Test func runningLateNeverMovesABooking() {
        var planner = DayPlanner(stops: [stop(0, meal: true), stop(1)],
                                 slots: [19 * 60, 21 * 60], travel: flat(2, 10))
        planner.stops[0].isBooked = true
        planner.availableFrom = 19 * 60 + 30
        let best = planner.best()

        #expect(best.visits.map(\.start) == [19 * 60, 21 * 60])
        #expect(best.visits[0].problem == .lateForBooking(by: 30))
        #expect(best.lateBookings == 1)
    }

    // MARK: Bigger days

    @Test func nineStopsAreStillSolvedExactly() {
        let positions = [4, 0, 7, 2, 8, 1, 6, 3, 5]
        let planner = DayPlanner(stops: positions.indices.map { stop($0, minutes: 30) },
                                 slots: positions.indices.map { 8 * 60 + $0 * 60 },
                                 travel: street(positions, step: 30))
        #expect(planner.best().travelMinutes == 240, "one end of the street to the other")
    }

    @Test func longerDaysImproveOneSwapAtATime() {
        let positions = [5, 0, 9, 2, 10, 1, 7, 3, 8, 4, 6]
        let planner = DayPlanner(stops: positions.indices.map { stop($0, minutes: 20) },
                                 slots: positions.indices.map { 7 * 60 + $0 * 45 },
                                 travel: street(positions, step: 10))
        #expect(planner.best().travelMinutes < planner.current().travelMinutes)
    }
}
