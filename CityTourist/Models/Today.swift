import Foundation

/// Where today stands: what's done, the stop you're at, the one you're
/// heading to next, and what comes after it.
struct TodayStatus: Equatable {
    var earlier: [ItineraryStop]
    var current: ItineraryStop?
    var next: ItineraryStop?
    var later: [ItineraryStop]

    var isDone: Bool { current == nil && next == nil }

    /// `now` is minutes past midnight; stops are in time order.
    static func make(stops: [ItineraryStop], now: Int) -> TodayStatus {
        let current = stops.last { $0.startMinute <= now && now < $0.startMinute + $0.durationMinutes }
        let upcoming = stops.filter { $0.startMinute > now }
        return TodayStatus(earlier: stops.filter { $0.startMinute + $0.durationMinutes <= now },
                           current: current, next: upcoming.first, later: Array(upcoming.dropFirst()))
    }
}

/// When to set off for a stop.
///
/// Builds in a few minutes' grace for finding the entrance, so "leave by" is
/// a little earlier than the last possible moment and running into that
/// grace still counts as on time.
struct LeaveBy: Equatable {
    static let graceMinutes = 5

    /// Minutes past midnight.
    var minute: Int
    var travelMinutes: Int

    init(start: Int, travelMinutes: Int) {
        self.minute = start - travelMinutes - Self.graceMinutes
        self.travelMinutes = travelMinutes
    }

    /// Positive when you've left it too late, even counting the grace.
    func minutesBehind(at now: Int) -> Int {
        now - (minute + Self.graceMinutes)
    }

    /// "Leave in 12 min", "Leave now", or "8 min behind".
    func countdown(at now: Int) -> String {
        let left = minute - now
        if left > 0 { return "Leave in \(Self.duration(left))" }
        let behind = minutesBehind(at: now)
        return behind > 0 ? "\(Self.duration(behind)) behind" : "Leave now"
    }

    private static func duration(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) hr" : "\(h) hr \(m) min"
    }
}

extension Date {
    /// Minutes past midnight on the device's clock, the unit stops use.
    var minuteOfDay: Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: self)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}
