import Foundation

/// How many requests this phone may make to a paid API, per minute and per
/// day. The hard limit is the quota set on each key in its provider's
/// console; this keeps one phone, through a loop in the app or someone
/// poking at it, from spending that for everyone. Normal use stays well
/// under: a city's places are six searches, and they're cached for the day.
///
/// The day's count is kept in `UserDefaults`, so relaunching doesn't reset it.
final class RequestBudget: @unchecked Sendable {

    struct Limits {
        var perMinute: Int
        var perDay: Int
    }

    /// Searches, place details and city lookups.
    static let googlePlaces = RequestBudget(name: "googlePlaces", limits: Limits(perMinute: 60, perDay: 400))
    /// Photos are billed one by one, and a scroll through Explore asks for dozens.
    static let googlePhotos = RequestBudget(name: "googlePhotos", limits: Limits(perMinute: 120, perDay: 800))
    /// Ticketmaster allows 5,000 calls a day for the whole key.
    static let ticketmaster = RequestBudget(name: "ticketmaster", limits: Limits(perMinute: 20, perDay: 100))

    /// No limit, for tests against a stubbed session.
    static var unlimited: RequestBudget {
        RequestBudget(name: "unlimited", limits: Limits(perMinute: .max, perDay: .max), defaults: nil)
    }

    private let limits: Limits
    private let storageKey: String
    private let defaults: UserDefaults?
    private let now: () -> Date
    private let calendar: Calendar
    private let lock = NSLock()

    /// When this minute's requests went out.
    private var recent: [Date] = []
    private var day: String
    private var usedToday: Int

    init(name: String, limits: Limits, defaults: UserDefaults? = .standard,
         now: @escaping () -> Date = Date.init, calendar: Calendar = .current) {
        self.limits = limits
        self.storageKey = "requestBudget.\(name)"
        self.defaults = defaults
        self.now = now
        self.calendar = calendar

        let stored = defaults?.dictionary(forKey: storageKey)
        day = stored?["day"] as? String ?? ""
        usedToday = stored?["used"] as? Int ?? 0
    }

    /// Takes one request from the budget. False when this minute's or
    /// today's allowance is used up, and the request shouldn't be sent.
    func spend() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let now = now()
        let today = Self.dayKey(now, calendar)
        if today != day {
            day = today
            usedToday = 0
        }
        recent.removeAll { now.timeIntervalSince($0) >= 60 }
        guard recent.count < limits.perMinute, usedToday < limits.perDay else { return false }

        recent.append(now)
        usedToday += 1
        defaults?.set(["day": day, "used": usedToday], forKey: storageKey)
        return true
    }

    private static func dayKey(_ date: Date, _ calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }
}
