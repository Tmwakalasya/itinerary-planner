import Testing
import Foundation
@testable import CityTourist

/// No network stub here — the request URL and the payload decoding are both
/// pure functions, so these run fast and stay parallel-safe.
struct WeatherTests {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: year, month: month, day: day)))
    }

    // MARK: Request building

    @Test func requestCoversTheAskedForRange() throws {
        let today = try date(2026, 9, 3)
        let url = try WeatherService.makeURL(
            latitude: 38.7223, longitude: -9.1393,
            from: try date(2026, 9, 15), to: try date(2026, 9, 18),
            calendar: calendar, today: today
        )
        let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        func value(_ name: String) -> String? { query.first { $0.name == name }?.value }

        #expect(value("start_date") == "2026-09-15")
        #expect(value("end_date") == "2026-09-18")
        #expect(value("timezone") == "auto")
        #expect(value("temperature_unit") == nil, "metric is the default")
    }

    /// Open-Meteo rejects the whole request if the end date is past its
    /// horizon, so a long trip must be clamped rather than lost.
    @Test func longTripIsClampedToTheForecastHorizon() throws {
        let today = try date(2026, 9, 3)
        let url = try WeatherService.makeURL(
            latitude: 38.7, longitude: -9.1,
            from: try date(2026, 9, 5), to: try date(2026, 10, 30),
            calendar: calendar, today: today
        )
        let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(query.first { $0.name == "start_date" }?.value == "2026-09-05")
        // today + 15 days
        #expect(query.first { $0.name == "end_date" }?.value == "2026-09-18")
    }

    @Test func tripBeyondTheHorizonReportsNoForecast() throws {
        let today = try date(2026, 9, 3)
        #expect(throws: WeatherService.ServiceError.beyondForecastRange) {
            _ = try WeatherService.makeURL(
                latitude: 38.7, longitude: -9.1,
                from: try date(2027, 6, 1), to: try date(2027, 6, 4),
                calendar: calendar, today: today
            )
        }
    }

    @Test func imperialLocalesAskForFahrenheit() throws {
        let url = try WeatherService.makeURL(
            latitude: 38.7, longitude: -9.1,
            from: try date(2026, 9, 5), to: try date(2026, 9, 6),
            calendar: calendar, today: try date(2026, 9, 3), fahrenheit: true
        )
        let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(query.first { $0.name == "temperature_unit" }?.value == "fahrenheit")
    }

    // MARK: Decoding

    @Test func decodesTheColumnOrientedPayload() throws {
        let json = """
        {
          "daily_units": { "temperature_2m_max": "°C" },
          "daily": {
            "time": ["2026-09-15", "2026-09-16"],
            "weather_code": [2, 61],
            "temperature_2m_max": [36.8, 24.1],
            "temperature_2m_min": [21.8, 17.2],
            "precipitation_probability_max": [0, 80]
          }
        }
        """
        let days = try WeatherService.decode(Data(json.utf8))

        #expect(days.count == 2)
        #expect(days[0].dayKey == "2026-09-15")
        #expect(days[0].temperatureLabel == "37°C / 22°C")
        #expect(days[0].isWet == false)
        #expect(days[1].summary == "Rain")
        #expect(days[1].precipitationChance == 80)
        #expect(days[1].isWet)
    }

    /// Open-Meteo returns nulls for days it has no data for.
    @Test func daysWithMissingTemperaturesAreSkipped() throws {
        let json = """
        {
          "daily": {
            "time": ["2026-09-15", "2026-09-16"],
            "weather_code": [2, null],
            "temperature_2m_max": [20.0, null],
            "temperature_2m_min": [10.0, null],
            "precipitation_probability_max": [10, null]
          }
        }
        """
        let days = try WeatherService.decode(Data(json.utf8))
        #expect(days.count == 1)
        #expect(days[0].dayKey == "2026-09-15")
    }

    // MARK: Interpretation

    @Test func weatherCodesMapToLabelsAndIcons() {
        #expect(WeatherCode(0).summary == "Clear")
        #expect(WeatherCode(0).symbol == "sun.max.fill")
        #expect(WeatherCode(3).summary == "Overcast")
        #expect(WeatherCode(95).summary == "Thunderstorms")
        #expect(WeatherCode(999).summary == "Unsettled", "unknown codes must not crash")

        #expect(!WeatherCode(3).isPrecipitation)
        #expect(WeatherCode(51).isPrecipitation)
        #expect(WeatherCode(95).isPrecipitation)
    }

    /// A dry code with a high chance of rain still counts as wet — that's what
    /// drives the outdoor-stop advisory.
    @Test func highRainChanceCountsAsWetEvenUnderAClearCode() {
        let cloudyButLikely = DayForecast(dayKey: "2026-09-15", code: 3, high: 20, low: 12,
                                          precipitationChance: 70, unit: "°C")
        #expect(cloudyButLikely.isWet)

        let cloudyAndUnlikely = DayForecast(dayKey: "2026-09-15", code: 3, high: 20, low: 12,
                                            precipitationChance: 10, unit: "°C")
        #expect(!cloudyAndUnlikely.isWet)
    }

    @Test func onlyExposedCategoriesCountAsOutdoors() {
        #expect(PlaceCategory.nature.isOutdoors)
        #expect(PlaceCategory.attraction.isOutdoors)
        #expect(PlaceCategory.activity.isOutdoors)
        #expect(!PlaceCategory.museum.isOutdoors)
        #expect(!PlaceCategory.food.isOutdoors)
        #expect(!PlaceCategory.nightlife.isOutdoors)
    }

    @Test func dayKeyMatchesTheApiFormat() throws {
        #expect(WeatherService.dayKey(for: try date(2026, 9, 5), calendar: calendar) == "2026-09-05")
        #expect(WeatherService.dayKey(for: try date(2026, 12, 25), calendar: calendar) == "2026-12-25")
    }
}

/// Sun times and the daylight check on outdoor stops.
struct DaylightTests {

    private func forecast(sunrise: Int?, sunset: Int?) -> DayForecast {
        DayForecast(dayKey: "2026-09-15", code: 0, high: 24, low: 15,
                    precipitationChance: 0, unit: "°C",
                    sunriseMinute: sunrise, sunsetMinute: sunset)
    }

    // MARK: Parsing

    /// The clock part is taken as-is: Open-Meteo already returns it in the
    /// destination's timezone, so converting would shift the sunset.
    @Test func sunTimesParseToLocalMinutes() {
        #expect(WeatherService.minuteOfDay("2026-09-05T20:01") == 20 * 60 + 1)
        #expect(WeatherService.minuteOfDay("2026-09-05T07:09") == 7 * 60 + 9)
        #expect(WeatherService.minuteOfDay("2026-09-05T00:00") == 0)
    }

    @Test func malformedSunTimesAreIgnored() {
        #expect(WeatherService.minuteOfDay(nil) == nil)
        #expect(WeatherService.minuteOfDay("2026-09-05") == nil)
        #expect(WeatherService.minuteOfDay("2026-09-05T99:99") == nil)
        #expect(WeatherService.minuteOfDay("nonsense") == nil)
    }

    @Test func sunTimesDecodeFromThePayload() throws {
        let json = """
        {
          "daily": {
            "time": ["2026-09-15"],
            "weather_code": [0],
            "temperature_2m_max": [24.0],
            "temperature_2m_min": [15.0],
            "precipitation_probability_max": [0],
            "sunrise": ["2026-09-15T07:12"],
            "sunset": ["2026-09-15T19:40"]
          }
        }
        """
        let days = try WeatherService.decode(Data(json.utf8))
        #expect(days.first?.sunriseMinute == 7 * 60 + 12)
        #expect(days.first?.sunsetMinute == 19 * 60 + 40)
    }

    // MARK: The check

    @Test func outdoorStopEndingAfterSunsetIsFlagged() throws {
        // 18:45 for 90 min ends at 20:15; sunset 19:40.
        let note = try #require(DaylightNote.make(
            startMinute: 18 * 60 + 45, durationMinutes: 90, category: .nature,
            forecast: forecast(sunrise: 7 * 60, sunset: 19 * 60 + 40)))
        #expect(note.text == "ends after sunset")
    }

    @Test func outdoorStopStartingAfterSunsetIsFlaggedMoreStrongly() throws {
        let note = try #require(DaylightNote.make(
            startMinute: 21 * 60, durationMinutes: 60, category: .attraction,
            forecast: forecast(sunrise: 7 * 60, sunset: 19 * 60 + 40)))
        #expect(note.text == "after dark")
    }

    @Test func outdoorStopBeforeSunriseIsFlagged() throws {
        let note = try #require(DaylightNote.make(
            startMinute: 5 * 60 + 30, durationMinutes: 120, category: .activity,
            forecast: forecast(sunrise: 7 * 60 + 12, sunset: 19 * 60 + 40)))
        #expect(note.text == "before sunrise")
    }

    @Test func daytimeOutdoorStopsSayNothing() {
        #expect(DaylightNote.make(
            startMinute: 10 * 60, durationMinutes: 90, category: .nature,
            forecast: forecast(sunrise: 7 * 60, sunset: 19 * 60 + 40)) == nil)
    }

    /// A bar after dark is the point; a viewpoint after dark is a wasted trip.
    @Test func indoorAndNightlifeStopsAreNeverFlagged() {
        for category in [PlaceCategory.nightlife, .food, .museum] {
            #expect(DaylightNote.make(
                startMinute: 22 * 60, durationMinutes: 120, category: category,
                forecast: forecast(sunrise: 7 * 60, sunset: 19 * 60 + 40)) == nil,
                "\(category) should not be flagged")
        }
    }

    @Test func withoutSunDataNothingIsClaimed() {
        #expect(DaylightNote.make(
            startMinute: 22 * 60, durationMinutes: 60, category: .nature,
            forecast: nil) == nil)
        #expect(DaylightNote.make(
            startMinute: 22 * 60, durationMinutes: 60, category: .nature,
            forecast: forecast(sunrise: nil, sunset: nil)) == nil)
    }

    /// Ending exactly at sunset is fine; a minute past is not.
    @Test func theBoundaryIsExact() {
        let sunset = 19 * 60 + 40
        #expect(DaylightNote.make(startMinute: sunset - 60, durationMinutes: 60,
                                  category: .nature,
                                  forecast: forecast(sunrise: 7 * 60, sunset: sunset)) == nil)
        #expect(DaylightNote.make(startMinute: sunset - 60, durationMinutes: 61,
                                  category: .nature,
                                  forecast: forecast(sunrise: 7 * 60, sunset: sunset)) != nil)
    }
}
