import SwiftUI

/// Below "Where you'll be": what the place is like on video. YouTube Shorts
/// play here in YouTube's own player; TikTok and Instagram have no search API
/// an app can show, so their own search opens instead.
struct PlaceShortsSection: View {
    let place: Place

    @Environment(PlaceShorts.self) private var shorts
    @State private var playing: Playing?

    private struct Playing: Identifiable {
        let shorts: [PlaceShort]
        let index: Int
        var id: Int { index }
    }

    private var city: City { CityDirectory.city(id: place.cityID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("What it’s like").sectionTitleStyle()
                Text(shorts.isAvailable
                     ? "Short videos from YouTube. Recorded, not live."
                     : "See it in short videos on TikTok or Instagram.").captionStyle()
            }
            if shorts.isAvailable { videos }
            linksOut
        }
        .task(id: place.id) { await shorts.load(place) }
        .fullScreenCover(item: $playing) { playing in
            ShortPlayerView(place: place, shorts: playing.shorts, index: playing.index)
        }
        .accessibilityIdentifier("placeShorts")
    }

    @ViewBuilder
    private var videos: some View {
        switch shorts.state(for: place) {
        case .loaded(let found) where found.isEmpty:
            Text("No short videos of \(place.name) on YouTube yet.").metaStyle()
        case .loaded(let found):
            ScrollView(.horizontal) {
                LazyHStack(spacing: 12) {
                    ForEach(Array(found.enumerated()), id: \.element.id) { index, short in
                        Button {
                            playing = Playing(shorts: found, index: index)
                        } label: {
                            ShortCard(short: short)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, Metric.gutter, for: .scrollContent)
            .padding(.horizontal, -Metric.gutter)
        case .failed(let message):
            HStack(spacing: 12) {
                Text(message).metaStyle()
                Spacer(minLength: 0)
                Button("Try again") { Task { await shorts.load(place) } }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Brand.rausch)
            }
        case .loading, nil:
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous)
                            .fill(Palette.surface)
                            .frame(width: ShortCard.size.width, height: ShortCard.size.height)
                    }
                }
            }
            .scrollDisabled(true)
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, Metric.gutter, for: .scrollContent)
            .padding(.horizontal, -Metric.gutter)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Loading videos")
        }
    }

    private var linksOut: some View {
        HStack(spacing: 8) {
            Text("More on").captionStyle()
            Link(destination: PlaceShorts.tikTokURL(for: place, in: city)) { linkLabel("TikTok") }
            if let instagram = PlaceShorts.instagramURL(for: place) {
                Link(destination: instagram) { linkLabel("Instagram") }
            }
        }
    }

    private func linkLabel(_ title: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
            Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .semibold))
        }
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, 12)
        .frame(minHeight: 36)
        .overlay(Capsule().strokeBorder(Palette.hairline))
        .contentShape(Capsule())
    }
}

/// A Short's thumbnail, upright like the video, with who posted it and how
/// many have watched.
struct ShortCard: View {
    let short: PlaceShort

    static let size = CGSize(width: 150, height: 250)

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear.overlay {
                AsyncImage(url: short.thumbnailURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Palette.surface
                }
            }
            .clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 3) {
                Text(short.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                Text(short.channel)
                    .font(.system(size: 12))
                    .opacity(0.8)
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(10)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .overlay(alignment: .top) {
            HStack {
                badge("YouTube", symbol: "play.rectangle.fill")
                Spacer(minLength: 4)
                if let views = short.views {
                    badge(views.formatted(.number.notation(.compactName)), symbol: "play.fill")
                }
            }
            .padding(8)
        }
        .clipShape(RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(short.title), by \(short.channel)")
        .accessibilityValue(short.views.map { "\($0.formatted()) views" } ?? "")
        .accessibilityHint("Plays the video")
    }

    private func badge(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 11, weight: .semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(.black.opacity(0.55), in: Capsule())
    }
}

/// One Short at a time in YouTube's player, upright, with the next one a tap
/// away. Starts muted and waits for a tap to play.
struct ShortPlayerView: View {
    let place: Place
    let shorts: [PlaceShort]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var index: Int
    @State private var playback = PlaceVideoPlayback()
    @State private var attempt = UUID()

    init(place: Place, shorts: [PlaceShort], index: Int) {
        self.place = place
        self.shorts = shorts
        _index = State(initialValue: index)
    }

    private var short: PlaceShort { shorts[index] }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let height = max(200, geometry.size.height - 230)
                VStack(alignment: .leading, spacing: 16) {
                    player
                        .frame(width: min(geometry.size.width - Metric.gutter * 2, height * 9 / 16), height: height)
                        .frame(maxWidth: .infinity)
                    details
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Metric.gutter)
                .padding(.top, 8)
            }
            .background(Palette.canvas)
            .navigationTitle(place.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundStyle(Brand.rausch)
                }
            }
            .task(id: attempt) {
                do { try await Task.sleep(for: .seconds(20)) } catch { return }
                playback.timedOut()
            }
        }
    }

    @ViewBuilder
    private var player: some View {
        if case .failed(let message) = playback.state {
            VStack(spacing: 14) {
                Image(systemName: "wifi.exclamationmark").font(.title)
                Text("Video unavailable").font(.headline)
                Text(message).font(.subheadline).multilineTextAlignment(.center)
                Button("Try again") { show(index) }.buttonStyle(.bordered)
            }
            .foregroundStyle(Palette.inkMuted)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metric.cardRadius))
        } else {
            YouTubePlayer(videoID: short.id, playback: playback, isActive: scenePhase == .active)
                .id(attempt)
                .clipShape(RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous))
                .overlay {
                    if playback.state == .loading { ProgressView().tint(.white) }
                }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(short.title).cardTitleStyle().lineLimit(2)
            Text([short.channel, short.views.map { "\($0.formatted(.number.notation(.compactName))) views" }]
                .compactMap { $0 }.joined(separator: " · ")).metaStyle()
            HStack {
                Link("Watch on YouTube ↗", destination: short.watchURL)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Brand.rausch)
                Spacer()
                if shorts.count > 1 {
                    Button { show(index - 1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                        .disabled(index == 0)
                        .accessibilityLabel("Previous video")
                    Text("\(index + 1) of \(shorts.count)").captionStyle()
                    Button { show(index + 1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                        .disabled(index == shorts.count - 1)
                        .accessibilityLabel("Next video")
                }
            }
            .tint(Palette.ink)
        }
    }

    /// A fresh player for each video, so one's error or state never carries over.
    private func show(_ newIndex: Int) {
        guard shorts.indices.contains(newIndex) else { return }
        index = newIndex
        playback = PlaceVideoPlayback()
        attempt = UUID()
    }
}
