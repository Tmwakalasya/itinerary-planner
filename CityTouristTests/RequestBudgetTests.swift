import Testing
import Foundation
@testable import CityTourist

/// The per-phone allowance in front of the paid APIs.
struct RequestBudgetTests {

    private final class Clock: @unchecked Sendable {
        var now = Date(timeIntervalSince1970: 1_791_500_000)
    }

    private func freshDefaults() -> UserDefaults {
        let name = "request-budget-test-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func aMinutesAllowanceComesBackAMinuteLater() {
        let clock = Clock()
        let budget = RequestBudget(name: "test", limits: .init(perMinute: 2, perDay: 100),
                                   defaults: freshDefaults(), now: { clock.now })

        #expect(budget.spend())
        #expect(budget.spend())
        #expect(!budget.spend(), "the third in a minute waits")

        clock.now += 60
        #expect(budget.spend())
    }

    @Test func todaysAllowanceSurvivesARelaunchAndResetsTomorrow() {
        let clock = Clock()
        let defaults = freshDefaults()
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
}
