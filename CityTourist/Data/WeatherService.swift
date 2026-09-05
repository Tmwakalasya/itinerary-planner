import Foundation

/// Daily forecasts from Open-Meteo.
///
/// The brief suggests OpenWeatherMap; Open-Meteo covers the same ground, needs
/// no API key or signup, and is free for non-commercial use — which keeps the
/// project to a single key to manage. Swapping providers means reimplementing
/// this one type: nothing above it knows where a `DayForecast` came from.
struct WeatherService {

    enum ServiceError: LocalizedError, Equatable {
        case beyondForecastRange
        case http(status: Int)
        case transport(String)

        var errorDescription: String? {
            switch self {
            case .beyondForecastRange:
                "Forecasts only reach about two weeks ahead."
            case let .http(status):
                "The weather service returned \(status)."
            case let .transport(message):
                message
            }
        }
    }

    /// Open-Meteo publishes 16 days; past that the API rejects the request.
    static let forecastHorizonDays = 15

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Forecasts for each day in the range, clamped to what the service covers.
    /// Returns fewer days than asked for when a trip runs past the horizon.
    func forecast(
        latitude: Double,
        longitude: Double,
        from start: Date,
        to end: Date,
        calendar: Calendar = .current,
        today: Date = .now,
        fahrenheit: Bool = Locale.current.measurementSystem == .us
    ) async throws -> [DayForecast] {

        let url = try Self.makeURL(
            latitude: latitude, longitude: longitude, from: start, to: end,
            calendar: calendar, today: today, fahrenheit: fahrenheit
        )

        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw ServiceError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw ServiceError.http(status: -1)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ServiceError.http(status: http.statusCode)
        }

        return try Self.decode(data)
    }

    /// Builds the request URL, clamping the range to what the service covers.
    /// Split out from `forecast` so the clamping is testable without a network
    /// stub — it's the part most likely to be wrong.
    static func makeURL(
        latitude: Double,
        longitude: Double,
        from start: Date,
        to end: Date,
        calendar: Calendar = .current,
        today: Date = .now,
        fahrenheit: Bool = false
    ) throws -> URL {
        let firstDay = calendar.startOfDay(for: start)
        let lastAvailable = calendar.date(
            byAdding: .day, value: forecastHorizonDays, to: calendar.startOfDay(for: today)
        ) ?? today

        // A trip that starts past the horizon has nothing to show at all.
        guard firstDay <= lastAvailable else { throw ServiceError.beyondForecastRange }
        let lastDay = min(calendar.startOfDay(for: end), lastAvailable)

        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "start_date", value: dayKey(for: firstDay, calendar: calendar)),
            URLQueryItem(name: "end_date", value: dayKey(for: lastDay, calendar: calendar))
        ]
        if fahrenheit {
            components.queryItems?.append(URLQueryItem(name: "temperature_unit", value: "fahrenheit"))
        }
        return components.url!
    }

    /// Parses the column-oriented payload into one forecast per day.
    static func decode(_ data: Data) throws -> [DayForecast] {
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        let daily = payload.daily
        let unit = payload.dailyUnits?.temperature2mMax ?? "°"

        return daily.time.indices.compactMap { index in
            guard let high = daily.temperature2mMax?[safe: index] ?? nil,
                  let low = daily.temperature2mMin?[safe: index] ?? nil
            else { return nil }
            return DayForecast(
                dayKey: daily.time[index],
                code: daily.weatherCode?[safe: index].flatMap { $0 } ?? 0,
                high: high,
                low: low,
                precipitationChance: daily.precipitationProbabilityMax?[safe: index].flatMap { $0 } ?? 0,
                unit: unit,
                sunriseMinute: minuteOfDay(daily.sunrise?[safe: index].flatMap { $0 }),
                sunsetMinute: minuteOfDay(daily.sunset?[safe: index].flatMap { $0 })
            )
        }
    }

    /// Open-Meteo returns "2026-09-05T20:01" in the destination's own local
    /// time, so the clock part is taken as-is — converting it would move the
    /// sunset into the phone's timezone, which is exactly wrong.
    static func minuteOfDay(_ iso: String?) -> Int? {
        guard let iso, let tIndex = iso.firstIndex(of: "T") else { return nil }
        let clock = iso[iso.index(after: tIndex)...].split(separator: ":")
        guard clock.count >= 2, let hour = Int(clock[0]), let minute = Int(clock[1]),
              (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
        return hour * 60 + minute
    }

    /// The "2026-09-15" form both the API and our day lookups use.
    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    // MARK: Wire format

    private struct Payload: Decodable {
        struct Daily: Decodable {
            let time: [String]
            let weatherCode: [Int?]?
            let temperature2mMax: [Double?]?
            let temperature2mMin: [Double?]?
            let precipitationProbabilityMax: [Int?]?
            let sunrise: [String?]?
            let sunset: [String?]?

            enum CodingKeys: String, CodingKey {
                case time
                case weatherCode = "weather_code"
                case temperature2mMax = "temperature_2m_max"
                case temperature2mMin = "temperature_2m_min"
                case precipitationProbabilityMax = "precipitation_probability_max"
                case sunrise, sunset
            }
        }
        struct Units: Decodable {
            let temperature2mMax: String?
            enum CodingKeys: String, CodingKey { case temperature2mMax = "temperature_2m_max" }
        }
        let daily: Daily
        let dailyUnits: Units?
        enum CodingKeys: String, CodingKey {
            case daily
            case dailyUnits = "daily_units"
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
