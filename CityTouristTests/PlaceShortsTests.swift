import Testing
import Foundation
@testable import CityTourist

/// Short videos on place pages: matching, durations and the links out.
struct PlaceShortsTests {

    @Test func youTubeDurationsReadAsSeconds() {
        #expect(YouTubeService.seconds(fromISO8601: "PT45S") == 45)
        #expect(YouTubeService.seconds(fromISO8601: "PT1M5S") == 65)
        #expect(YouTubeService.seconds(fromISO8601: "PT2M") == 120)
        #expect(YouTubeService.seconds(fromISO8601: "PT1H2M3S") == 3723)
        #expect(YouTubeService.seconds(fromISO8601: "P0D") == nil, "a live stream has no length")
        #expect(YouTubeService.seconds(fromISO8601: "PTM") == nil)
    }

    @Test func aVideoMustNameThePlace() {
        #expect(YouTubeService.isAbout("Wynwood Walls", text: "Day out #wynwoodwalls #miami"))
        #expect(YouTubeService.isAbout("Wynwood Walls", text: "Exploring Wynwood!"), "half the name is enough")
        #expect(YouTubeService.isAbout("Pastéis de Belém", text: "Trying PASTEIS DE BELEM in Lisbon"))
        #expect(!YouTubeService.isAbout("Wynwood Walls", text: "Miami Beach sunset"))
        #expect(!YouTubeService.isAbout("IHOP", text: "Best breakfast in Miami"))
        #expect(!YouTubeService.isAbout("The Bar", text: "the bar"), "nothing distinctive to match")
    }

    @Test func tikTokAndInstagramOpenTheirOwnSearch() throws {
        let place = try #require(SampleData.places(in: "lisbon").first)
        let city = SampleData.cities[0]

        let tikTok = URLComponents(url: PlaceShorts.tikTokURL(for: place, in: city), resolvingAgainstBaseURL: false)
        #expect(tikTok?.host == "www.tiktok.com")
        #expect(tikTok?.queryItems?.first?.value == "\(place.name) \(city.name)")
        #expect(PlaceShorts.instagramURL(for: place)?.absoluteString
                == "https://www.instagram.com/explore/tags/belemtower/")
    }
}

/// YouTube's two calls, against the shared stub; see `PlacesAPITests`.
extension PlacesAPITests {

    private enum YouTubeFixtures {
        /// Relevance order: a long tour, the match, an unrelated video, a
        /// hashtag-only match, a channel, and a live stream.
        static let search = """
        { "items": [
            { "id": { "videoId": "long1" } }, { "id": { "videoId": "good1" } },
            { "id": { "videoId": "other" } }, { "id": { "videoId": "tag1" } },
            { "id": { "channelId": "chan" } }, { "id": { "videoId": "live1" } } ] }
        """

        /// Not in the search's order, as YouTube doesn't promise one.
        static let videos = """
        { "items": [
            { "id": "tag1", "snippet": { "title": "Lisbon day 2", "description": "#belemtower #lisbon",
                "channelTitle": "Kendle", "liveBroadcastContent": "none" },
              "contentDetails": { "duration": "PT1M5S" }, "statistics": {} },
            { "id": "other", "snippet": { "title": "Lisbon food tour", "channelTitle": "Eats",
                "liveBroadcastContent": "none" },
              "contentDetails": { "duration": "PT50S" }, "statistics": { "viewCount": "900" } },
            { "id": "good1", "snippet": { "title": "Belem Tower at sunset", "channelTitle": "angel",
                "liveBroadcastContent": "none",
                "thumbnails": { "high": { "url": "https://i.ytimg.com/vi/good1/hqdefault.jpg" } } },
              "contentDetails": { "duration": "PT45S" }, "statistics": { "viewCount": "240100" } },
            { "id": "long1", "snippet": { "title": "Belém Tower full tour", "channelTitle": "Guide",
                "liveBroadcastContent": "none" },
              "contentDetails": { "duration": "PT12M3S" }, "statistics": { "viewCount": "5" } },
            { "id": "live1", "snippet": { "title": "Belém Tower live cam", "channelTitle": "Cam",
                "liveBroadcastContent": "live" },
              "contentDetails": { "duration": "P0D" }, "statistics": {} } ] }
        """

        /// Answers each call from its own fixture.
        static func respond(search: String = search, videos: String = videos) {
            StubURLProtocol.handler = { request in
                let body = request.url?.path.hasSuffix("/search") == true ? search : videos
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                                               headerFields: ["Content-Type": "application/json"])!
                return (response, Data(body.utf8))
            }
        }
    }

    private var belemTower: Place { SampleData.places(in: "lisbon")[0] }
    private var lisbon: City { SampleData.cities[0] }

    private func youTube(budget: RequestBudget = .unlimited) -> YouTubeService {
        YouTubeService(apiKey: "test-key", session: StubURLProtocol.makeSession(), budget: budget)
    }

    @Test func youTubeSearchesForShortEmbeddableVideosOfThePlace() async throws {
        StubURLProtocol.reset()
        YouTubeFixtures.respond()

        _ = try await youTube().shorts(for: belemTower, in: lisbon)

        let search = try #require(StubURLProtocol.recorded.first)
        let query = URLComponents(url: search.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { query.first { $0.name == name }?.value }
        #expect(search.url?.path == "/youtube/v3/search")
        #expect(value("q") == "\(belemTower.name) Lisbon")
        #expect(value("type") == "video")
        #expect(value("videoDuration") == "short")
        #expect(value("videoEmbeddable") == "true")
        #expect(value("key") == nil, "the key goes in a header, not the URL")
        #expect(search.value(forHTTPHeaderField: "X-Goog-Api-Key") == "test-key")
        #expect(search.value(forHTTPHeaderField: "X-Ios-Bundle-Identifier") == Bundle.main.bundleIdentifier)

        let details = try #require(StubURLProtocol.recorded.last)
        let ids = URLComponents(url: details.url!, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "id" }?.value
        #expect(details.url?.path == "/youtube/v3/videos")
        #expect(ids == "long1,good1,other,tag1,live1")
    }

    @Test func youTubeKeepsRelevanceOrderAndOnlyShortVideosOfThePlace() async throws {
        StubURLProtocol.reset()
        YouTubeFixtures.respond()

        let shorts = try await youTube().shorts(for: belemTower, in: lisbon)

        #expect(shorts.map(\.id) == ["good1", "tag1"],
                "no long tour, unrelated video, channel or live stream; search order kept")
        #expect(shorts.first?.views == 240_100)
        #expect(shorts.first?.seconds == 45)
        #expect(shorts.first?.channel == "angel")
        #expect(shorts.first?.thumbnailURL?.absoluteString == "https://i.ytimg.com/vi/good1/hqdefault.jpg")
        #expect(shorts.last?.views == nil)
    }

    @Test func noYouTubeResultsSkipTheDetailsCall() async throws {
        StubURLProtocol.reset()
        YouTubeFixtures.respond(search: #"{ "items": [] }"#)

        let shorts = try await youTube().shorts(for: belemTower, in: lisbon)

        #expect(shorts.isEmpty)
        #expect(StubURLProtocol.recorded.count == 1)
    }

    @Test func youTubeOverThePhonesAllowanceSendsNothing() async {
        StubURLProtocol.reset()
        YouTubeFixtures.respond()
        let spent = RequestBudget(name: "test", limits: .init(perMinute: 0, perDay: 0), defaults: nil)

        do {
            _ = try await youTube(budget: spent).shorts(for: belemTower, in: lisbon)
            Issue.record("an exhausted allowance should stop the search")
        } catch {
            #expect(YouTubeService.isRateLimited(error))
        }
        #expect(StubURLProtocol.recorded.isEmpty)
    }

    @Test func anOfflineYouTubeSearchIsHandedBack() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let budget = RequestBudget(name: "test", limits: .init(perMinute: 1, perDay: 1), defaults: nil)
        let service = youTube(budget: budget)

        await #expect(throws: YouTubeService.ServiceError.self) {
            _ = try await service.shorts(for: belemTower, in: lisbon)
        }
        YouTubeFixtures.respond()
        let shorts = try await service.shorts(for: belemTower, in: lisbon)
        #expect(!shorts.isEmpty, "back online, the one look-up left still goes out")
    }

    /// A place is looked up once a week, even across launches; one with no
    /// videos is asked about again the next day.
    @MainActor
    @Test func shortsAreKeptForAWeekAndNoneForADay() async throws {
        StubURLProtocol.reset()
        YouTubeFixtures.respond()
        let file = URL.temporaryDirectory.appending(path: "shorts-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        func store() -> PlaceShorts {
            PlaceShorts(makeService: { self.youTube() }, cacheURL: file, now: { now })
        }

        await store().load(belemTower)
        #expect(StubURLProtocol.recorded.count == 2)

        let relaunched = store()
        await relaunched.load(belemTower)
        #expect(StubURLProtocol.recorded.count == 2, "a relaunch reads the week's results from disk")
        guard case .loaded(let shorts) = relaunched.state(for: belemTower) else {
            Issue.record("expected the cached videos")
            return
        }
        #expect(shorts.map(\.id) == ["good1", "tag1"])

        now += 8 * 24 * 60 * 60
        YouTubeFixtures.respond(search: #"{ "items": [] }"#)
        await store().load(belemTower)
        #expect(StubURLProtocol.recorded.count == 3, "after a week it looks again")

        now += 2 * 60 * 60
        await store().load(belemTower)
        #expect(StubURLProtocol.recorded.count == 3, "none found is remembered for the day")
        now += 24 * 60 * 60
        await store().load(belemTower)
        #expect(StubURLProtocol.recorded.count == 4)
    }

    @MainActor
    @Test func aFailedLookUpSaysSoAndCanBeTriedAgain() async {
        StubURLProtocol.reset()
        StubURLProtocol.respond(status: 403, json: "{}")
        let shorts = PlaceShorts(makeService: { self.youTube() }, cacheURL: nil)

        await shorts.load(belemTower)
        guard case .failed(let message) = shorts.state(for: belemTower) else {
            Issue.record("expected a visible failure")
            return
        }
        #expect(!message.isEmpty)

        YouTubeFixtures.respond()
        await shorts.load(belemTower)
        #expect(shorts.state(for: belemTower) != nil)
        if case .loaded = shorts.state(for: belemTower) {} else { Issue.record("Try again should load") }
    }

    @MainActor
    @Test func withoutAKeyThereAreNoVideosOnlyLinks() async {
        StubURLProtocol.reset()
        let shorts = PlaceShorts(makeService: { nil }, cacheURL: nil)

        await shorts.load(belemTower)

        #expect(!shorts.isAvailable)
        #expect(shorts.state(for: belemTower) == nil)
        #expect(StubURLProtocol.recorded.isEmpty)
    }
}
