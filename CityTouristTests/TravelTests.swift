import Testing
import Foundation
@testable import CityTourist

/// The schedule arithmetic between two stops. MapKit itself isn't exercised
/// here — it can't be, offline — so the decision logic is kept separate from
/// the lookup and tested on its own.
struct TravelTests {

    private func leg(minutes: Int, mode: TravelMode = .walking) -> TravelLeg {
        TravelLeg(fromPlaceID: "a", toPlaceID: "b", mode: mode,
                  seconds: TimeInterval(minutes * 60))
    }

    // MARK: Loading legs

    /// Switching days while the previous day's legs are still loading used
    /// to drop the new day's lookup entirely, leaving it on "free time".
    @MainActor
    @Test func switchingDaysMidLoadStillLoadsTheNewDay() async {
        let routes = RouteStore(service: SlowEstimator())
        let lisbon = SampleData.places(in: "lisbon")
        let stops = lisbon.prefix(4).map {
            ItineraryStop(placeID: $0.id, startMinute: 9 * 60, durationMinutes: 60)
        }

        async let dayOne: Void = routes.loadLegs(for: [stops[0], stops[1]], on: .now, by: .transit)
        async let dayTwo: Void = routes.loadLegs(for: [stops[2], stops[3]], on: .now, by: .transit)
        _ = await (dayOne, dayTwo)

        #expect(routes.leg(from: lisbon[0], to: lisbon[1], by: .transit) != nil)
        #expect(routes.leg(from: lisbon[2], to: lisbon[3], by: .transit) != nil,
                "the overlapping day must not be dropped")
    }

    /// Each hop is looked up the way the trip gets around, leaving when the
    /// stop before it ends, so transit is timed on that day's timetable.
    @MainActor
    @Test func legsAreTimedForTheDayAndTheWayTheTripGetsAround() async {
        let estimator = RecordingEstimator()
        let routes = RouteStore(service: estimator)
        let lisbon = SampleData.places(in: "lisbon")
        let stops = [ItineraryStop(placeID: lisbon[0].id, startMinute: 9 * 60, durationMinutes: 90),
                     ItineraryStop(placeID: lisbon[1].id, startMinute: 11 * 60, durationMinutes: 60)]
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: .now))!

        await routes.loadLegs(for: stops, on: tomorrow, by: .transit)

        let request = await estimator.requests.first
        #expect(request?.gettingAround == .transit)
        #expect(request?.departing == cal.date(bySettingHour: 10, minute: 30, second: 0, of: tomorrow))
        #expect(routes.leg(from: lisbon[0], to: lisbon[1], by: .transit)?.mode == .transit)
        #expect(routes.leg(from: lisbon[0], to: lisbon[1], by: .car) == nil, "a car trip times its own hops")

        // A day already over is timed from now.
        await routes.loadLegs(for: stops, on: cal.date(byAdding: .day, value: -7, to: tomorrow)!, by: .car)
        #expect(await estimator.requests.count == 2)
        #expect(await estimator.requests.last?.departing == nil)
    }

    // MARK: With an estimate

    @Test func comfortableGapReadsAsSpareTime() throws {
        let note = try #require(TravelNote.make(gapMinutes: 60, leg: leg(minutes: 12)))
        #expect(note.text == "12 min walk · 48 min spare")
        #expect(note.isTight == false)
        #expect(note.symbol == "figure.walk")
    }

    /// The case the whole feature exists for: the plan looks fine until you
    /// know how long the hop takes.
    @Test func gapShorterThanTheHopIsFlagged() throws {
        let note = try #require(TravelNote.make(gapMinutes: 15, leg: leg(minutes: 25)))
        #expect(note.text == "25 min walk · 10 min short")
        #expect(note.isTight)
    }

    @Test func exactlyEnoughTimeIsNotFlagged() throws {
        let note = try #require(TravelNote.make(gapMinutes: 20, leg: leg(minutes: 20)))
        #expect(note.text == "20 min walk · just enough")
        #expect(note.isTight == false)
    }

    @Test func transitReadsAsByTransit() throws {
        let note = try #require(TravelNote.make(gapMinutes: 30, leg: leg(minutes: 22, mode: .transit)))
        #expect(note.text == "22 min by transit · 8 min spare")
        #expect(note.symbol == "tram.fill")
    }

    @Test func noGapAtAllIsFlagged() throws {
        let note = try #require(TravelNote.make(gapMinutes: 0, leg: leg(minutes: 18)))
        #expect(note.text == "18 min walk · 18 min short")
        #expect(note.isTight)
    }

    /// Back-to-back stops can leave a negative gap if one overruns.
    @Test func overlappingStopsStillProduceAdvice() throws {
        let note = try #require(TravelNote.make(gapMinutes: -15, leg: leg(minutes: 10)))
        #expect(note.text == "10 min walk · 25 min short")
        #expect(note.isTight)
    }

    @Test func drivingLegsReadAsDriving() throws {
        let note = try #require(TravelNote.make(gapMinutes: 90, leg: leg(minutes: 50, mode: .driving)))
        #expect(note.text == "50 min drive · 40 min spare")
        #expect(note.symbol == "car.fill")
    }

    @Test func longSpansReadInHours() throws {
        let note = try #require(TravelNote.make(gapMinutes: 200, leg: leg(minutes: 20)))
        #expect(note.text == "20 min walk · 3 hr spare")
    }

    // MARK: Without an estimate

    /// When MapKit can't route the pair we fall back to the old behaviour
    /// rather than showing nothing or, worse, implying it's walkable.
    @Test func withoutAnEstimateItReportsFreeTimeAsBefore() throws {
        let note = try #require(TravelNote.make(gapMinutes: 65, leg: nil))
        #expect(note.text == "1 hr 5 min free")
        #expect(note.isTight == false)
        #expect(note.symbol == "clock")
    }

    @Test func shortUnroutableGapsStayQuiet() {
        #expect(TravelNote.make(gapMinutes: 10, leg: nil) == nil)
        #expect(TravelNote.make(gapMinutes: 19, leg: nil) == nil)
        #expect(TravelNote.make(gapMinutes: 20, leg: nil) != nil)
    }

    // MARK: Without MapKit

    /// Short hops are walked however the trip gets around. Across town a car
    /// is quicker than transit, and both beat walking it.
    @Test func estimatesFollowHowTheTripGetsAround() {
        let baixa = Coordinate(latitude: 38.7105, longitude: -9.1366)
        let chiado = Coordinate(latitude: 38.7106, longitude: -9.1420)
        let belem = Coordinate(latitude: 38.6979, longitude: -9.2065)

        #expect(TravelEstimate.minutes(from: baixa, to: chiado, by: .transit)
                == TravelEstimate.minutes(from: baixa, to: chiado, by: .car))
        let transit = TravelEstimate.minutes(from: baixa, to: belem, by: .transit)
        let car = TravelEstimate.minutes(from: baixa, to: belem, by: .car)
        #expect(car < transit)
        #expect(transit < 60, "an hour and a half on foot")
    }

    // MARK: Leg rounding

    @Test func subMinuteHopsStillReportAMinute() {
        let brief = TravelLeg(fromPlaceID: "a", toPlaceID: "b", mode: .walking, seconds: 20)
        #expect(brief.minutes == 1, "a hop must never read as 0 min")
    }

    @Test func secondsRoundToTheNearestMinute() {
        #expect(TravelLeg(fromPlaceID: "a", toPlaceID: "b", mode: .walking, seconds: 100).minutes == 2)
        #expect(TravelLeg(fromPlaceID: "a", toPlaceID: "b", mode: .walking, seconds: 890).minutes == 15)
    }
}

/// Stands in for MapKit: every hop is a ten-minute walk, returned after a
/// short pause so that overlapping lookups really do overlap.
private struct SlowEstimator: RouteEstimating {
    func leg(from: Place, to: Place, by gettingAround: GettingAround, departing: Date?) async -> TravelLeg? {
        try? await Task.sleep(for: .milliseconds(20))
        return TravelLeg(fromPlaceID: from.id, toPlaceID: to.id, mode: .walking, seconds: 600)
    }
}

/// Stands in for MapKit, noting how each hop was asked for.
private actor RecordingEstimator: RouteEstimating {
    private(set) var requests: [(gettingAround: GettingAround, departing: Date?)] = []

    func leg(from: Place, to: Place, by gettingAround: GettingAround, departing: Date?) async -> TravelLeg? {
        requests.append((gettingAround, departing))
        return TravelLeg(fromPlaceID: from.id, toPlaceID: to.id,
                         mode: gettingAround == .transit ? .transit : .driving, seconds: 900)
    }
}
