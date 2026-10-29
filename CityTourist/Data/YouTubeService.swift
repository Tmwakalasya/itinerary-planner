import Foundation

/// A place's short videos, from the YouTube Data API: a search for the place
/// by name and city, then the videos' details for length, title and views.
///
/// The search costs 100 of the key's 10,000 daily quota units and the details
/// one, so each place is looked up once and kept for a week (`PlaceShorts`).
/// Search is loose ("IHOP Miami" also finds any video shot in Miami), so a
/// video stays only if it names the place.
struct YouTubeService {

    enum ServiceError: LocalizedError {
        case http(status: Int)
        case transport(Error)
        /// This phone has used its allowance for now; see `RequestBudget`.
        case rateLimited

        var errorDescription: String? {
            switch self {
            case let .http(status): "YouTube returned \(status)."
            case let .transport(error): error.localizedDescription
            case .rateLimited: "Videos are paused on this device for a while. Try again later."
            }
        }
    }

    static func isRateLimited(_ error: Error) -> Bool {
        if case ServiceError.rateLimited = error { return true }
        return false
    }

    /// Shorts run to three minutes.
    static let longestSeconds = 180
    static let maxResults = 10

    private let session: URLSession
    private let apiKey: String
    private let budget: RequestBudget

    init?(session: URLSession = .shared) {
        guard let key = Secrets.youtubeAPIKey else { return nil }
        self.init(apiKey: key, session: session, budget: .youtube)
    }

    /// Explicit-key initialiser. Used by tests against a stubbed session.
    init(apiKey: String, session: URLSession = .shared, budget: RequestBudget = .unlimited) {
        self.apiKey = apiKey
        self.session = session
        self.budget = budget
    }

    /// Up to ten videos about `place`, in YouTube's order of relevance.
    func shorts(for place: Place, in city: City) async throws -> [PlaceShort] {
        // One allowance covers the search and the details that follow it.
        guard budget.spend() else { throw ServiceError.rateLimited }

        var search = URLComponents(string: "https://www.googleapis.com/youtube/v3/search")!
        search.queryItems = [
            URLQueryItem(name: "part", value: "id"),
            URLQueryItem(name: "type", value: "video"),
            URLQueryItem(name: "q", value: "\(place.name) \(city.name)"),
            URLQueryItem(name: "videoDuration", value: "short"),
            URLQueryItem(name: "videoEmbeddable", value: "true"),
            URLQueryItem(name: "safeSearch", value: "strict"),
            URLQueryItem(name: "maxResults", value: "15")
        ]
        let found: SearchResponse
        do {
            found = try await get(search.url!)
        } catch ServiceError.transport(let error) {
            budget.refund()
            throw ServiceError.transport(error)
        }
        let ids = (found.items ?? []).compactMap(\.id.videoId)
        guard !ids.isEmpty else { return [] }

        var details = URLComponents(string: "https://www.googleapis.com/youtube/v3/videos")!
        details.queryItems = [
            URLQueryItem(name: "part", value: "snippet,contentDetails,statistics"),
            URLQueryItem(name: "id", value: ids.joined(separator: ","))
        ]
        let videos: VideosResponse = try await get(details.url!)
        let byID = Dictionary((videos.items ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return Array(ids.compactMap { byID[$0]?.toShort(about: place.name) }.prefix(Self.maxResults))
    }

    private func get<Response: Decodable>(_ url: URL) async throws -> Response {
        var request = URLRequest(url: url)
        // Header rather than query, so the key stays out of logged URLs. A key
        // restricted to iOS apps also needs the bundle id.
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        if let bundleID = Bundle.main.bundleIdentifier {
            request.setValue(bundleID, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        }
        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ServiceError.transport(error)
        }
        guard let http = response as? HTTPURLResponse else { throw ServiceError.http(status: -1) }
        guard (200..<300).contains(http.statusCode) else { throw ServiceError.http(status: http.statusCode) }
        return try JSONDecoder().decode(Response.self, from: data)
    }

    // MARK: Matching

    /// Whether a video's words name the place: its whole name run together, as
    /// in "#wynwoodwalls", or at least half of its distinctive words.
    static func isAbout(_ placeName: String, text: String) -> Bool {
        let wanted = words(in: placeName).filter { $0.count >= 3 && !commonWords.contains($0) }
        guard !wanted.isEmpty else { return false }
        let folded = fold(text)
        if folded.contains(wanted.joined()) { return true }
        let present = Set(words(in: text))
        return wanted.filter(present.contains).count * 2 >= wanted.count
    }

    /// Words in so many names that they don't say which place a video is of.
    private static let commonWords: Set<String> = ["the", "and", "bar", "cafe", "restaurant"]

    private static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func words(in text: String) -> [String] {
        fold(text).split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    /// "PT1M5S" → 65. Nil for anything that isn't hours, minutes and seconds,
    /// such as "P0D" for a live stream.
    static func seconds(fromISO8601 duration: String) -> Int? {
        guard duration.hasPrefix("PT") else { return nil }
        var total = 0, number = 0, hasNumber = false
        for character in duration.dropFirst(2) {
            if let digit = character.wholeNumberValue {
                number = number * 10 + digit
                hasNumber = true
                continue
            }
            guard hasNumber else { return nil }
            switch character {
            case "H": total += number * 3600
            case "M": total += number * 60
            case "S": total += number
            default: return nil
            }
            number = 0
            hasNumber = false
        }
        return hasNumber ? nil : total
    }
}

/// One short video of a place.
struct PlaceShort: Codable, Hashable, Identifiable {
    /// YouTube's video id.
    let id: String
    let title: String
    let channel: String
    let thumbnailURL: URL?
    let views: Int?
    let seconds: Int

    var watchURL: URL { URL(string: "https://www.youtube.com/watch?v=\(id)")! }
}

// MARK: - Wire format

private struct SearchResponse: Decodable {
    struct Item: Decodable {
        struct ID: Decodable { let videoId: String? }
        let id: ID
    }
    let items: [Item]?
}

private struct VideosResponse: Decodable {
    struct Item: Decodable {
        struct Snippet: Decodable {
            struct Thumbnail: Decodable { let url: String }
            let title: String
            let description: String?
            let channelTitle: String?
            let tags: [String]?
            let thumbnails: [String: Thumbnail]?
            let liveBroadcastContent: String?
        }
        struct ContentDetails: Decodable { let duration: String? }
        /// Counts come as strings.
        struct Statistics: Decodable { let viewCount: String? }

        let id: String
        let snippet: Snippet?
        let contentDetails: ContentDetails?
        let statistics: Statistics?

        /// Nil for a live stream, anything over three minutes, or a video that
        /// doesn't name the place.
        func toShort(about placeName: String) -> PlaceShort? {
            guard let snippet, snippet.liveBroadcastContent ?? "none" == "none",
                  let seconds = contentDetails?.duration.flatMap(YouTubeService.seconds(fromISO8601:)),
                  (1...YouTubeService.longestSeconds).contains(seconds)
            else { return nil }
            let text = ([snippet.title, snippet.description ?? ""] + (snippet.tags ?? [])).joined(separator: " ")
            guard YouTubeService.isAbout(placeName, text: text) else { return nil }
            let thumbnail = snippet.thumbnails?["high"] ?? snippet.thumbnails?["medium"] ?? snippet.thumbnails?["default"]
            return PlaceShort(id: id, title: snippet.title, channel: snippet.channelTitle ?? "YouTube",
                              thumbnailURL: thumbnail.flatMap { URL(string: $0.url) },
                              views: statistics?.viewCount.flatMap(Int.init), seconds: seconds)
        }
    }
    let items: [Item]?
}
