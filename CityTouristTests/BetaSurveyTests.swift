import Testing
import Foundation
@testable import CityTourist

/// When the Trips list offers the beta survey, and what its link says.
struct BetaSurveyTests {

    private let cal = Calendar.current

    private func trip(endingDaysAgo days: Int) -> Trip {
        let today = cal.startOfDay(for: .now)
        let end = cal.date(byAdding: .day, value: -days, to: today)!
        let start = cal.date(byAdding: .day, value: -1, to: end)!
        return Trip(cityID: "lisbon", title: "Lisbon", startDate: start, endDate: end)
    }

    @MainActor
    @Test func theLinkSaysWhichBuildAndWhichCity() throws {
        let url = BetaSurvey.url(trip: trip(endingDaysAgo: 1))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(url.host() == "citytourist.pages.dev")
        #expect(url.path() == "/feedback")
        #expect(items.first { $0.name == "trip" }?.value == "Lisbon")
        #expect(items.first { $0.name == "v" }?.value == ProfileView.version)
    }

    @Test func onlyATripThatEndedThisWeekIsOffered() {
        let yesterday = trip(endingDaysAgo: 1)
        let lastMonth = trip(endingDaysAgo: 30)
        let ongoing = trip(endingDaysAgo: 0)

        #expect(BetaSurvey.justEnded([lastMonth, yesterday, ongoing], dismissed: [])?.id == yesterday.id)
        #expect(BetaSurvey.justEnded([lastMonth, ongoing], dismissed: []) == nil,
                "not a trip still running, nor one long gone")
    }

    @Test func aCardWavedOffStaysGone() {
        let yesterday = trip(endingDaysAgo: 1)
        let stored = BetaSurvey.encode([yesterday.id.uuidString])
        #expect(BetaSurvey.justEnded([yesterday], dismissed: BetaSurvey.decode(stored)) == nil)
        #expect(BetaSurvey.decode("") == [])
    }
}
