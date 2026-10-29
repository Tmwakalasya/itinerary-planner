import Foundation
import Observation

/// Short videos for each place page, from YouTube.
///
/// A look-up spends 100 of the key's 10,000 daily units, so results are kept
/// on disk by place id for a week (YouTube's policies allow keeping API data
/// up to 30 days), and a place with none is asked about again the next day.
/// Only YouTube's data and Google's place id are stored, never place content.
@MainActor
@Observable
final class PlaceShorts {
    enum State: Equatable {
        case loading
        case loaded([PlaceShort])
        case failed(String)
    }

    struct Entry: Codable {
        var fetched: Date
        var shorts: [PlaceShort]
    }

    static let keepFor: TimeInterval = 7 * 24 * 60 * 60
    static let keepEmptyFor: TimeInterval = 24 * 60 * 60

    private var states: [String: State] = [:]
    @ObservationIgnored private var cache: [String: Entry] = [:]
    @ObservationIgnored private let makeService: () -> YouTubeService?
    @ObservationIgnored private let cacheURL: URL?
    @ObservationIgnored private let now: () -> Date

    /// Without a key there are no videos, only the links out.
    let isAvailable: Bool

    /// Tests pass a client wired to a stubbed session, and no cache file or
    /// one of their own.
    init(makeService: @escaping () -> YouTubeService? = { YouTubeService() },
         cacheURL: URL? = URL.cachesDirectory.appending(path: "youtube-shorts.json"),
         now: @escaping () -> Date = Date.init) {
        self.makeService = makeService
        self.cacheURL = cacheURL
        self.now = now
        isAvailable = makeService() != nil
        if let cacheURL, let data = try? Data(contentsOf: cacheURL),
           let stored = try? JSONDecoder().decode([String: Entry].self, from: data) {
            cache = stored
        }
    }

    func state(for place: Place) -> State? { states[place.id] }

    /// From the cache while it's fresh, otherwise one look-up. Leaving the
    /// page cancels it without recording a failure.
    func load(_ place: Place) async {
        guard place.event == nil else { return }
        switch states[place.id] {
        case .loading, .loaded: return
        case .failed, nil: break
        }
        if let entry = cache[place.id], isFresh(entry) {
            states[place.id] = .loaded(entry.shorts)
            return
        }
        guard let service = makeService() else { return }

        states[place.id] = .loading
        do {
            let shorts = try await service.shorts(for: place, in: CityDirectory.city(id: place.cityID))
            states[place.id] = .loaded(shorts)
            cache[place.id] = Entry(fetched: now(), shorts: shorts)
            save()
        } catch {
            if Task.isCancelled {
                states[place.id] = nil
            } else {
                states[place.id] = .failed(YouTubeService.isRateLimited(error)
                    ? "Videos are paused on this phone for a while. Try again later."
                    : "Videos couldn’t load right now.")
            }
        }
    }

    private func isFresh(_ entry: Entry) -> Bool {
        now().timeIntervalSince(entry.fetched) < (entry.shorts.isEmpty ? Self.keepEmptyFor : Self.keepFor)
    }

    private func save() {
        guard let cacheURL else { return }
        cache = cache.filter { isFresh($0.value) }
        try? JSONEncoder().encode(cache).write(to: cacheURL, options: .atomic)
    }

    // MARK: Links out

    /// TikTok has no search API for apps, so its own search opens instead.
    nonisolated static func tikTokURL(for place: Place, in city: City) -> URL {
        var components = URLComponents(string: "https://www.tiktok.com/search")!
        components.queryItems = [URLQueryItem(name: "q", value: "\(place.name) \(city.name)")]
        return components.url!
    }

    /// The place's name as a hashtag page, "#wynwoodwalls".
    nonisolated static func instagramURL(for place: Place) -> URL? {
        let tag = place.name
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        guard !tag.isEmpty else { return nil }
        return URL(string: "https://www.instagram.com/explore/tags/\(tag)/")
    }
}
