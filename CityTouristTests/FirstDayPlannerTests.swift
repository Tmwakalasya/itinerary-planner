import Testing
import Foundation
@testable import CityTourist

struct FirstDayPlannerTests {
    private let city = City(id: "test-city", name: "Test City", country: "", tagline: "",
                            coordinate: Coordinate(latitude: 38.71, longitude: -9.14))
    private let date = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 12))!

    private func place(_ id: String, category: PlaceCategory = .museum, minutes: Int = 60,
                       hours: WeeklyHours? = .alwaysOpen, latitude: Double = 38.71) -> Place {
        Place(id: id, name: id, cityID: city.id, category: category, neighborhood: "Centre",
              rating: 4.6, reviewCount: 200, priceLevel: 1, typicalMinutes: minutes,
              blurb: "", about: "", coordinate: Coordinate(latitude: latitude, longitude: -9.14),
              tags: [], weeklyHours: hours)
    }

    private func planner(_ pace: FirstDayPlanner.Pace = .relaxed) -> FirstDayPlanner {
        FirstDayPlanner(city: city, date: date, interests: [.museum], pace: pace)
    }

    @Test func interestsLunchAndPaceShapeAFeasibleDay() {
        let places = (0..<6).map { place("museum-\($0)") } + [place("lunch", category: .food), place("park", category: .nature)]
        for pace in FirstDayPlanner.Pace.allCases {
            let plan = planner(pace).propose(among: places)
            #expect(plan.count == pace.slots.count)
            #expect(plan.filter { $0.place.category == .food }.count == 1)
            #expect(!plan.contains { $0.id == "park" })
            #expect(Set(plan.map(\.id)).count == plan.count)
            for (before, after) in zip(plan, plan.dropFirst()) {
                let travel = TravelEstimate.minutes(from: before.place.coordinate, to: after.place.coordinate)
                #expect(after.start >= before.start + before.place.typicalMinutes + travel + pace.buffer)
            }
            #expect(plan.allSatisfy { $0.start + $0.place.typicalMinutes <= FirstDayPlanner.dayEnds })
        }
    }

    @Test func closedAndTooLongVisitsAreExcluded() {
        let plan = planner().propose(among: [place("closed", hours: WeeklyHours(spans: [])),
                                             place("too-long", minutes: 600), place("fits")])
        #expect(plan.map(\.id) == ["fits"])
    }

    @Test func waitsForOpeningAndRejectsVisitsCutShortByClosing() throws {
        let weekday = Calendar.current.component(.weekday, from: date) - 1
        let base = weekday * 1440
        let hours = WeeklyHours(spans: [.init(start: base + 630, end: base + 720)])
        let plan = planner().propose(among: [place("opens-later", hours: hours)])
        #expect(try #require(plan.first).start == 630)
        #expect(planner().propose(among: [place("cannot-finish", minutes: 100, hours: hours)]).isEmpty)
    }

    @Test func nearbyBeatsADetourEvenWithHigherRating() {
        var distant = place("distant", latitude: 39.1)
        distant.rating = 5
        distant.reviewCount = 1000
        let plan = planner().propose(among: [distant, place("near-a"), place("near-b")])
        #expect(plan.map(\.id) == ["near-a", "near-b"])
    }

    @Test func sparseFiveStarRatingDoesNotBeatEstablishedPlace() throws {
        var sparse = place("a-sparse")
        sparse.rating = 5
        sparse.reviewCount = 1
        let plan = planner().propose(among: [sparse, place("established")])
        #expect(try #require(plan.first).id == "established")
    }

    @Test func mustSeeIsIncludedEvenOutsideInterestsAndFailureIsExplicit() {
        let anchor = place("park", category: .nature)
        let plan = planner().propose(among: [place("museum"), anchor], mustSee: anchor)
        #expect(plan.first?.id == anchor.id)
        #expect(plan.first?.reason == "Your must-see")
        let closed = place("closed", hours: WeeklyHours(spans: []))
        #expect(planner().propose(among: [closed, place("museum")], mustSee: closed).isEmpty)
    }

    @Test func swapPreservesOtherPlacesAndEveryStartTime() throws {
        let places = [place("a"), place("b"), place("c"), place("lunch", category: .food)]
        let original = planner().propose(among: places)
        let first = try #require(original.first)
        let swapped = try #require(planner().replacing(first.id, in: original, among: places))
        #expect(swapped.first?.id != first.id)
        #expect(swapped.dropFirst().map(\.id) == original.dropFirst().map(\.id))
        #expect(swapped.map(\.start) == original.map(\.start))
        #expect(planner().replacing(first.id, in: original, among: original.map(\.place)) == nil)
        #expect(planner().replacing(first.id, in: original, among: places, excluding: ["c"]) == nil)
    }

    @Test func afternoonOnlyMustSeeIsPlacedInALaterSlot() throws {
        let weekday = Calendar.current.component(.weekday, from: date) - 1
        let base = weekday * 1440
        let anchor = place("afternoon", hours: WeeklyHours(spans: [.init(start: base + 900, end: base + 1080)]))
        let plan = planner().propose(among: [anchor, place("morning"), place("lunch", category: .food)], mustSee: anchor)
        let visit = try #require(plan.first { $0.id == anchor.id })
        #expect(visit.start == 900)
        #expect(plan.count == 3)
    }

    @Test func swapRejectsAnAlternativeThatWouldDelayLunch() throws {
        let places = [place("a"), place("lunch", category: .food)]
        let original = planner().propose(among: places)
        let first = try #require(original.first)
        #expect(planner().replacing(first.id, in: original,
                                   among: places + [place("long", minutes: 240)]) == nil)
    }

    @Test func unknownHoursAreUsableAndOtherCitiesAndDuplicatesAreExcluded() {
        let unknown = place("unknown", hours: nil)
        var wrongCity = place("wrong")
        wrongCity.cityID = "elsewhere"
        let plan = planner().propose(among: [unknown, unknown, wrongCity, place("bar", category: .nightlife)])
        #expect(plan.map(\.id) == ["unknown"])
        #expect(plan.first?.place.weeklyHours == nil)
        #expect(planner().propose(among: []).isEmpty)
    }

    @Test func sameDaySuggestionsNeverStartBeforeDepartureAndLateDaysStayEmpty() {
        var request = planner()
        request.availableFrom = 16 * 60
        let places = [place("a"), place("b"), place("lunch", category: .food)]
        let plan = request.propose(among: places)
        #expect(!plan.isEmpty)
        #expect(plan.allSatisfy { $0.start > request.availableFrom })
        request.availableFrom = 18 * 60
        #expect(request.propose(among: places).isEmpty)
    }

    @Test func candidateOrderDoesNotChangeTheRecommendation() {
        let places = [place("a"), place("b"), place("c"), place("lunch", category: .food)]
        let forward = planner().propose(among: places)
        let backward = planner().propose(among: places.reversed())
        #expect(forward.map(\.id) == backward.map(\.id))
        #expect(forward.map(\.start) == backward.map(\.start))
    }
}
