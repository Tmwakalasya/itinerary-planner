import Testing
import Foundation
@testable import CityTourist

/// The per-phone allowance in front of the paid APIs.
struct RequestBudgetTests {

    private final class Clock: @unchecked Sendable {
        var now = Date(timeIntervalSince1970: 1_791_500_000)
    }

    /// A throwaway defaults suite, removed again when the test is done.
    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let name = "request-budget-test-\(UUID())"
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }
        body(UserDefaults(suiteName: name)!)
    }

    @Test func aMinutesAllowanceComesBackAMinuteLater() {
        let clock = Clock()
        let budget = RequestBudget(name: "test", limits: .init(perMinute: 2, perDay: 100),
                                   defaults: nil, now: { clock.now })

        #expect(budget.spend())
        #expect(budget.spend())
        #expect(!budget.spend(), "the third in a minute waits")

        clock.now += 60
        #expect(budget.spend())
    }

    @Test func todaysAllowanceSurvivesARelaunchAndResetsTomorrow() {
        withDefaults { defaults in
            let clock = Clock()
            let limits = RequestBudget.Limits(perMinute: 100, perDay: 2)
            let first = RequestBudget(name: "test", limits: limits, defaults: defaults, now: { clock.now })
            #expect(first.spend())
            #expect(first.spend())

            let relaunched = RequestBudget(name: "test", limits: limits, defaults: defaults, now: { clock.now })
            #expect(!relaunched.spend(), "relaunching doesn't hand out a fresh day")

            clock.now += 24 * 60 * 60
            #expect(relaunched.spend())
        }
    }

    /// Setting the date back and forward again doesn't hand out a new day.
    @Test func onlyALaterDayResetsTheCount() {
        let clock = Clock()
        let budget = RequestBudget(name: "test", limits: .init(perMinute: 100, perDay: 1),
                                   defaults: nil, now: { clock.now })
        #expect(budget.spend())

        clock.now -= 24 * 60 * 60
        #expect(!budget.spend(), "an earlier day keeps today's count")
        clock.now += 24 * 60 * 60
        #expect(!budget.spend(), "and coming back to today doesn't reset it")
    }

    /// Requests made "in the future" before the clock went back don't hold
    /// the minute shut for an hour.
    @Test func aClockSetBackDoesntBlockTheMinute() {
        let clock = Clock()
        let budget = RequestBudget(name: "test", limits: .init(perMinute: 1, perDay: 100),
                                   defaults: nil, now: { clock.now })
        #expect(budget.spend())
        clock.now -= 30 * 60
        #expect(budget.spend())
    }

    @Test func severalAreTakenTogetherOrNotAtAll() {
        let budget = RequestBudget(name: "test", limits: .init(perMinute: 5, perDay: 100), defaults: nil)
        #expect(!budget.spend(6), "six don't fit in five")
        #expect(budget.spend(5), "and nothing was taken by trying")
        #expect(!budget.spend())
    }

    @Test func aRequestThatNeverWentOutIsHandedBack() {
        let budget = RequestBudget(name: "test", limits: .init(perMinute: 1, perDay: 1), defaults: nil)
        #expect(budget.spend())
        budget.refund()
        #expect(budget.spend())
    }
}

extension PlacesAPITests {

    /// Over the allowance, the request is never sent, and the error says why.
    @Test func overThePhonesAllowanceNothingIsSent() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond(json: #"{"places": []}"#)
        let budget = RequestBudget(name: "test", limits: .init(perMinute: 1, perDay: 100), defaults: nil)
        let service = GooglePlacesService(apiKey: "test-key", session: StubURLProtocol.makeSession(), budget: budget)

        _ = try await service.nearby(city: SampleData.cities[0], category: .food)
        let error = await #expect(throws: GooglePlacesService.ServiceError.self) {
            _ = try await service.nearby(city: SampleData.cities[0], category: .food)
        }

        guard case .rateLimited = error else {
            Issue.record("expected rateLimited, got \(String(describing: error))")
            return
        }
        #expect(StubURLProtocol.recorded.count == 1)
    }

    /// A city's six searches are taken from the allowance together: with
    /// five left, none go out, rather than paying for some and dropping them.
    @Test func aCatalogueThatCantAffordAllSixDoesntStart() async {
        StubURLProtocol.reset()
        StubURLProtocol.respond(json: #"{"places": []}"#)
        let budget = RequestBudget(name: "test", limits: .init(perMinute: 5, perDay: 100), defaults: nil)
        let service = GooglePlacesService(apiKey: "test-key", session: StubURLProtocol.makeSession(), budget: budget)

        await #expect(throws: GooglePlacesService.ServiceError.self) {
            _ = try await service.catalogue(for: SampleData.cities[0])
        }
        #expect(StubURLProtocol.recorded.isEmpty)
    }

    /// Offline, nothing reaches Google, so nothing comes off the allowance.
    @Test func anOfflineRequestIsHandedBack() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let budget = RequestBudget(name: "test", limits: .init(perMinute: 1, perDay: 1), defaults: nil)
        let service = GooglePlacesService(apiKey: "test-key", session: StubURLProtocol.makeSession(), budget: budget)

        await #expect(throws: GooglePlacesService.ServiceError.self) {
            _ = try await service.nearby(city: SampleData.cities[0], category: .food)
        }
        StubURLProtocol.respond(json: #"{"places": []}"#)
        _ = try await service.nearby(city: SampleData.cities[0], category: .food)
        #expect(StubURLProtocol.recorded.count == 2, "back online, the one request left still goes out")
    }

    /// An event's poster is on Ticketmaster's servers and doesn't bill the
    /// Google key; a Places photo over the allowance isn't fetched at all.
    @Test func onlyPlacesPhotosComeOffTheGoogleAllowance() async {
        StubURLProtocol.reset()
        StubURLProtocol.respond(json: "{}")
        let spent = RequestBudget(name: "test", limits: .init(perMinute: 0, perDay: 0), defaults: nil)
        let session = StubURLProtocol.makeSession()

        _ = await PhotoLoader.image(for: URL(string: "https://s1.ticketm.net/img/poster-\(UUID()).jpg")!,
                                    session: session, budget: spent)
        #expect(StubURLProtocol.recorded.count == 1)

        _ = await PhotoLoader.image(for: URL(string: "https://places.googleapis.com/v1/places/x/photos/\(UUID())/media")!,
                                    session: session, budget: spent)
        #expect(StubURLProtocol.recorded.count == 1, "the Places photo wasn't requested")
    }

    /// A stop that wasn't looked up because of the allowance says so, and
    /// isn't reported as Google failing.
    @MainActor
    @Test func aStopHeldBackByTheAllowanceIsPausedNotBroken() async {
        StubURLProtocol.reset()
        let spent = RequestBudget(name: "test", limits: .init(perMinute: 0, perDay: 0), defaults: nil)
        let catalog = PlaceCatalog(
            makeService: { GooglePlacesService(apiKey: "test-key", session: StubURLProtocol.makeSession(), budget: spent) },
            makeEventService: { nil })
        let id = "paused-\(UUID().uuidString)"

        await catalog.resolve([id], cityID: "lisbon")

        #expect(catalog.failedPlaceIDs.contains(id), "it still offers Try again")
        #expect(catalog.pausedPlaceIDs.contains(id))
        #expect(StubURLProtocol.recorded.isEmpty)
    }
}
