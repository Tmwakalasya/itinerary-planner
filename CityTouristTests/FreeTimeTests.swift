import Testing
import Foundation
@testable import CityTourist

/// Finding today's free time, and what fits in it.
@MainActor
struct FreeTimeTests {

    private func stop(_ start: Int, _ minutes: Int = 60) -> ItineraryStop {
        ItineraryStop(placeID: "p\(start)", startMinute: start, durationMinutes: minutes)
    }

    // MARK: Finding the gap

    @Test func theNextHourOrMoreBetweenStopsIsFound() throws {
        let stops = [stop(9 * 60), stop(11 * 60, 75), stop(15 * 60)]
        // At the second stop, which runs until 12:15.
        let gap = try #require(FreeTime.next(in: stops, now: 11 * 60 + 30))

        #expect(gap.start == 12 * 60 + 15)
        #expect(gap.end == 15 * 60)
        #expect(gap.after?.startMinute == 11 * 60)
        #expect(gap.before?.startMinute == 15 * 60)
    }

    @Test func gapsUnderAnHourArePassedOver() {
        let stops = [stop(9 * 60), stop(10 * 60 + 45), stop(14 * 60)]
        #expect(FreeTime.next(in: stops, now: 8 * 60 + 30)?.start == 11 * 60 + 45)
    }

    @Test func overlappingStopsDoNotOpenAGap() {
        let stops = [stop(9 * 60, 180), stop(10 * 60), stop(12 * 60 + 30)]
        let gap = FreeTime.next(in: stops, now: 9 * 60)
        #expect(gap?.start == 13 * 60 + 30)
        #expect(gap?.before == nil, "the rest of the day")
    }

    /// The Boca case: a morning's plan, finished by lunchtime.
    @Test func onceThePlanIsDoneTheRestOfTheDayIsFree() {
        let stops = [stop(9 * 60, 120), stop(11 * 60 + 30, 75)]
        let gap = FreeTime.next(in: stops, now: 12 * 60 + 48)
        #expect(gap?.start == 12 * 60 + 48)
        #expect(gap?.end == FreeTime.dayEnds)
        #expect(gap?.after?.startMinute == 11 * 60 + 30, "you set off from where you last were")
    }

    @Test func lateInTheEveningNothingIsOffered() {
        #expect(FreeTime.next(in: [], now: 20 * 60 + 30) == nil)
    }

    // MARK: What fits

    private func place(_ id: String) -> Place { SampleData.place(id: id)! }

    /// Noon on a Monday.
    private let monday = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 12))!

    private func ids(_ suggestions: [GapSuggestion]) -> [String] { suggestions.map(\.place.id) }

    @Test func nearbyComesFirst() {
        let suggestions = GapFiller.suggestions(
            for: FreeTime(start: 13 * 60, end: 18 * 60), among: [place("lis-castelo"), place("lis-jeronimos")],
            on: monday, from: place("lis-belem-tower").coordinate, to: nil, forecast: nil, excluding: [])
        #expect(ids(suggestions) == ["lis-jeronimos", "lis-castelo"])
    }

    /// An hour and a half from Belém Tower: there's time for custard tarts
    /// down the road, not for the monastery's hour and three quarters.
    @Test func onlyWhatFitsIsSuggested() throws {
        let suggestions = GapFiller.suggestions(
            for: FreeTime(start: 9 * 60, end: 10 * 60 + 30), among: [place("lis-pasteis-belem"), place("lis-jeronimos")],
            on: monday, from: place("lis-belem-tower").coordinate, to: nil, forecast: nil, excluding: [])

        #expect(ids(suggestions) == ["lis-pasteis-belem"])
        let tarts = try #require(suggestions.first)
        #expect(tarts.start % 5 == 0 && tarts.start >= 9 * 60 + tarts.travelMinutes, "starts once you could be there")
    }

    @Test func aPlaceShutThenIsLeftOut() {
        var monastery = place("lis-jeronimos")
        monastery.weeklyHours = WeeklyHours(spans: [.init(start: 600, end: 1080)])  // Sundays only
        let suggestions = GapFiller.suggestions(
            for: FreeTime(start: 13 * 60, end: 18 * 60), among: [monastery, place("lis-castelo")],
            on: monday, from: place("lis-belem-tower").coordinate, to: nil, forecast: nil, excluding: [])
        #expect(ids(suggestions) == ["lis-castelo"])
    }

    @Test func somewhereAlreadyPlannedIsLeftOut() {
        let suggestions = GapFiller.suggestions(
            for: FreeTime(start: 13 * 60, end: 18 * 60), among: [place("lis-jeronimos"), place("lis-castelo")],
            on: monday, from: nil, to: nil, forecast: nil, excluding: ["lis-jeronimos"])
        #expect(ids(suggestions) == ["lis-castelo"])
    }

    @Test func outdoorsIsLeftOutInTheRain() {
        let rain = DayForecast(dayKey: "2026-10-05", code: 63, high: 20, low: 15, precipitationChance: 80,
                               unit: "°C", sunriseMinute: 7 * 60, sunsetMinute: 19 * 60)
        let suggestions = GapFiller.suggestions(
            for: FreeTime(start: 13 * 60, end: 18 * 60), among: [place("lis-belem-tower"), place("lis-jeronimos")],
            on: monday, from: place("lis-pasteis-belem").coordinate, to: nil, forecast: rain, excluding: [])
        #expect(ids(suggestions) == ["lis-jeronimos"])
    }

    /// Sample places carry no hours, so nothing else would stop a bar being
    /// offered at lunchtime.
    @Test func barsWaitForTheEvening() {
        let bar = place("lis-pensao-amor")
        let lunch = GapFiller.suggestions(for: FreeTime(start: 13 * 60, end: 17 * 60), among: [bar],
                                          on: monday, from: nil, to: nil, forecast: nil, excluding: [])
        let evening = GapFiller.suggestions(for: FreeTime(start: 18 * 60, end: 21 * 60), among: [bar],
                                            on: monday, from: nil, to: nil, forecast: nil, excluding: [])
        #expect(lunch.isEmpty)
        #expect(ids(evening) == ["lis-pensao-amor"])
    }
}
