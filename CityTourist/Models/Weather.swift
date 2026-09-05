import Foundation

/// One day's forecast, keyed by calendar day rather than an instant so it
/// lines up with an itinerary day regardless of the destination's timezone.
struct DayForecast: Identifiable, Codable, Hashable {
    /// "2026-09-15" in the destination's own calendar.
    var dayKey: String
    /// WMO weather interpretation code.
    var code: Int
    var high: Double
    var low: Double
    var precipitationChance: Int
    /// "°C" or "°F", whichever the request asked for.
    var unit: String
    /// Minutes past local midnight at the destination. Open-Meteo returns
    /// these already in the city's own timezone, so they compare directly
    /// against a stop's start time without any conversion.
    var sunriseMinute: Int?
    var sunsetMinute: Int?

    var id: String { dayKey }

    var sunsetLabel: String? { sunsetMinute.map(Self.clockLabel) }
    var sunriseLabel: String? { sunriseMinute.map(Self.clockLabel) }

    /// Respects the device's 12/24-hour preference.
    static func clockLabel(_ minute: Int) -> String {
        let date = Calendar.current.date(
            bySettingHour: minute / 60, minute: minute % 60, second: 0, of: .now
        ) ?? .now
        return date.formatted(.dateTime.hour().minute())
    }

    var temperatureLabel: String {
        "\(Int(high.rounded()))\(unit) / \(Int(low.rounded()))\(unit)"
    }

    /// True when the day is wet enough to be worth rethinking outdoor stops.
    var isWet: Bool {
        WeatherCode(code).isPrecipitation || precipitationChance >= 50
    }

    var summary: String { WeatherCode(code).summary }
    var symbol: String { WeatherCode(code).symbol }
}

/// WMO code interpretation. Open-Meteo returns the raw number; the names and
/// icons are ours.
struct WeatherCode {
    let raw: Int

    init(_ raw: Int) { self.raw = raw }

    var summary: String {
        switch raw {
        case 0: "Clear"
        case 1: "Mainly clear"
        case 2: "Partly cloudy"
        case 3: "Overcast"
        case 45, 48: "Fog"
        case 51, 53, 55: "Drizzle"
        case 56, 57: "Freezing drizzle"
        case 61, 63: "Rain"
        case 65: "Heavy rain"
        case 66, 67: "Freezing rain"
        case 71, 73, 75, 77: "Snow"
        case 80, 81: "Rain showers"
        case 82: "Heavy showers"
        case 85, 86: "Snow showers"
        case 95: "Thunderstorms"
        case 96, 99: "Thunderstorms with hail"
        default: "Unsettled"
        }
    }

    var symbol: String {
        switch raw {
        case 0, 1: "sun.max.fill"
        case 2: "cloud.sun.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51, 53, 55, 56, 57: "cloud.drizzle.fill"
        case 61, 63, 66, 67: "cloud.rain.fill"
        case 65, 82: "cloud.heavyrain.fill"
        case 71, 73, 75, 77, 85, 86: "cloud.snow.fill"
        case 80, 81: "cloud.sun.rain.fill"
        case 95, 96, 99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }

    /// Anything falling out of the sky — drizzle upward.
    var isPrecipitation: Bool { raw >= 51 }
}

extension PlaceCategory {
    /// Whether a stop of this kind is exposed to the weather. Drives the
    /// rainy-day advisory on the itinerary.
    var isOutdoors: Bool {
        switch self {
        case .nature, .attraction, .activity: true
        case .food, .museum, .nightlife: false
        }
    }
}


/// Flags an outdoor stop that runs outside daylight.
///
/// Only outdoor categories are checked: a bar at 22:00 is the point, a
/// viewpoint at 22:00 is a wasted trip.
struct DaylightNote: Equatable {
    var symbol: String
    var text: String

    static func make(
        startMinute: Int,
        durationMinutes: Int,
        category: PlaceCategory,
        forecast: DayForecast?
    ) -> DaylightNote? {
        guard category.isOutdoors, let forecast else { return nil }
        let end = startMinute + durationMinutes

        if let sunrise = forecast.sunriseMinute, startMinute < sunrise {
            return DaylightNote(symbol: "sunrise", text: "before sunrise")
        }
        guard let sunset = forecast.sunsetMinute else { return nil }
        if startMinute >= sunset {
            return DaylightNote(symbol: "moon.stars", text: "after dark")
        }
        if end > sunset {
            return DaylightNote(symbol: "sunset", text: "ends after sunset")
        }
        return nil
    }
}
