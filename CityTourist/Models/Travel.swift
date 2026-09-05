import Foundation

enum TravelMode: String, Codable, Hashable {
    case walking, driving

    var verb: String { self == .walking ? "walk" : "drive" }
    var symbol: String { self == .walking ? "figure.walk" : "car.fill" }
}

/// A measured hop between two consecutive stops.
struct TravelLeg: Codable, Hashable {
    var fromPlaceID: String
    var toPlaceID: String
    var mode: TravelMode
    var seconds: TimeInterval

    var minutes: Int { max(1, Int((seconds / 60).rounded())) }
}

/// The one line shown between two stops on the timeline.
///
/// Deliberately a single caption: it stays grey when the plan works and only
/// turns red when it doesn't, so the timeline reads calm until something needs
/// attention.
struct TravelNote: Equatable {
    var symbol: String
    var text: String
    var isTight: Bool

    /// `gapMinutes` is the space between one stop ending and the next starting.
    /// With no route estimate this falls back to reporting free time, which is
    /// all the itinerary could say before.
    static func make(gapMinutes: Int, leg: TravelLeg?) -> TravelNote? {
        guard let leg else {
            guard gapMinutes >= 20 else { return nil }
            return TravelNote(symbol: "clock", text: "\(duration(gapMinutes)) free", isTight: false)
        }

        let spare = gapMinutes - leg.minutes
        let travel = "\(leg.minutes) min \(leg.mode.verb)"

        if spare < 0 {
            return TravelNote(symbol: leg.mode.symbol,
                              text: "\(travel) · \(duration(-spare)) short",
                              isTight: true)
        }
        if spare == 0 {
            return TravelNote(symbol: leg.mode.symbol, text: "\(travel) · just enough", isTight: false)
        }
        return TravelNote(symbol: leg.mode.symbol,
                          text: "\(travel) · \(duration(spare)) spare",
                          isTight: false)
    }

    private static func duration(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) hr" : "\(h) hr \(m) min"
    }
}
