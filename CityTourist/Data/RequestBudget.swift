import Foundation

/// How many requests this phone may make to a paid API, per minute and per
/// day. The hard limit is the quota set on each key in its provider's
/// console; this keeps one phone, through a loop in the app or someone
/// poking at it, from spending that for everyone.
///
/// The day's count is kept in `UserDefaults`, so relaunching doesn't reset it.
/// Places content can't be kept across launches (Google's terms allow only
/// ids), so every cold launch looks a city and each stop up again: a city is
/// six searches, a trip one lookup per stop. The limits leave room for a
/// long trip opened many times a day. A request that never reaches the
/// server, offline or cancelled, is handed back with `refund`.
final class RequestBudget: @unchecked Sendable {

    struct Limits {
        var perMinute: Int
        var perDay: Int
    }

    /// Searches, place details and city lookups.
    static let googlePlaces = RequestBudget(name: "googlePlaces", limits: Limits(perMinute: 150, perDay: 1500))
    /// Photos are billed one by one, and a scroll through Explore asks for dozens.
    static let googlePhotos = RequestBudget(name: "googlePhotos", limits: Limits(perMinute: 240, perDay: 3000))
    /// Ticketmaster allows 5,000 calls a day for the whole key.
    static let ticketmaster = RequestBudget(name: "ticketmaster", limits: Limits(perMinute: 20, perDay: 200))

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

    /// `calendar` follows the device: after a flight, the day resets at the
    /// new midnight.
    init(name: String, limits: Limits, defaults: UserDefaults? = .standard,
         now: @escaping () -> Date = Date.init, calendar: Calendar = .autoupdatingCurrent) {
        self.limits = limits
        self.storageKey = "requestBudget.\(name)"
        self.defaults = defaults
        self.now = now
        self.calendar = calendar

        let stored = defaults?.dictionary(forKey: storageKey)
        day = stored?["day"] as? String ?? ""
        usedToday = stored?["used"] as? Int ?? 0
    }

    /// Takes `count` requests from the budget, all or none. False when this
    /// minute's or today's allowance can't cover them, and they shouldn't be
    /// sent.
    func spend(_ count: Int = 1) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let now = now()
        rollOver(now)
        // A clock set back leaves entries in the "future"; they don't hold
        // the minute shut.
        recent.removeAll { now.timeIntervalSince($0) >= 60 || now.timeIntervalSince($0) < 0 }
        guard recent.count + count <= limits.perMinute, usedToday + count <= limits.perDay else { return false }

        recent.append(contentsOf: repeatElement(now, count: count))
        usedToday += count
        save()
        return true
    }

    /// Hands back requests that were spent but never reached the server.
    func refund(_ count: Int = 1) {
        lock.lock()
        defer { lock.unlock() }

        rollOver(now())
        recent.removeLast(min(count, recent.count))
        usedToday = max(0, usedToday - count)
        save()
    }

    /// Only a later day starts a fresh count, so setting the date back and
    /// forth doesn't hand out new allowances. Stamps are zero-padded, so they
    /// order as text.
    private func rollOver(_ now: Date) {
        let today = calendar.dayStamp(for: now)
        if today > day {
            day = today
            usedToday = 0
        }
    }

    private func save() {
        defaults?.set(["day": day, "used": usedToday], forKey: storageKey)
    }
}

extension Calendar {
    /// "2026-10-09": which day it is in this calendar's time zone. Shared by
    /// the forecast's day keys, the catalogue's daily refresh and the request
    /// allowance.
    func dayStamp(for date: Date) -> String {
        let parts = dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
