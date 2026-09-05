import SwiftUI

struct ExploreView: View {
    @Environment(AppStore.self) private var store
    @Environment(PlaceCatalog.self) private var catalog

    @State private var category: PlaceCategory?
    @State private var searchText = ""
    @State private var isSearchPresented = false
    @State private var isMapPresented = false

    private var city: City { store.browsingCity }

    private var results: [Place] {
        catalog.places(in: store.browsingCityID)
            .filter { category == nil || $0.category == category }
            .filter {
                searchText.isEmpty
                || $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.neighborhood.localizedCaseInsensitiveContains(searchText)
                || $0.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
            }
            .sorted { $0.rating > $1.rating }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Metric.cardGap) {
                    header

                    if catalog.state == .loading && results.isEmpty {
                        loadingPlaceholder
                    } else if results.isEmpty {
                        EmptyStateView(
                            symbol: "magnifyingglass",
                            title: "No places match",
                            message: "Try a different category, or clear the filters to see everything in \(city.name).",
                            actionTitle: "Clear filters"
                        ) {
                            withAnimation { category = nil; searchText = "" }
                        }
                        .padding(.top, 60)
                    } else {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, place in
                            NavigationLink(value: place) {
                                ListingCard(
                                    place: place,
                                    isSaved: store.isSaved(place),
                                    // Airbnb badges its top result; ours flags the highest rated.
                                    badge: index == 0 && category == nil ? "Traveller favourite" : nil
                                ) {
                                    store.toggleSaved(place)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, Metric.gutter)
                .padding(.bottom, 90)
            }
            .background(Palette.canvas)
            .scrollIndicators(.hidden)
            .refreshable { await catalog.load(city: city, force: true) }
            .safeAreaInset(edge: .top, spacing: 0) { searchHeader }
            .overlay(alignment: .bottom) { mapButton }
            .navigationDestination(for: Place.self) { PlaceDetailView(place: $0) }
            .sheet(isPresented: $isSearchPresented) { SearchSheet() }
            .fullScreenCover(isPresented: $isMapPresented) {
                CityMapView(city: city, places: results)
            }
            .task(id: store.browsingCityID) {
                await catalog.load(city: city)
            }
        }
    }

    // MARK: Header

    private var searchHeader: some View {
        VStack(spacing: 12) {
            SearchPill(title: city.name, subtitle: pillSubtitle) {
                isSearchPresented = true
            }
            .padding(.horizontal, Metric.gutter)

            CategoryRail(selection: $category)

            Hairline()
        }
        .padding(.top, 8)
        .background(.bar)
    }

    private var pillSubtitle: String {
        catalog.state == .loading ? "Finding places…" : "Anytime · \(results.count) places"
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 4) {
                Text(category?.title ?? "Top rated in \(city.name)")
                    .sectionTitleStyle()
                Text(city.tagline)
                    .metaStyle()
            }
            dataSourceNote
        }
        .padding(.top, 20)
    }

    /// Tells you where these results came from, and lets you retry a failure.
    @ViewBuilder
    private var dataSourceNote: some View {
        switch catalog.state {
        case .failed(let message):
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 12, weight: .semibold))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Showing sample places — \(message)")
                        .font(.system(size: 12))
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Try again") {
                        Task { await catalog.load(city: city, force: true) }
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .underline()
                }
            }
            .foregroundStyle(Brand.rausch)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Brand.rausch.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))

        case .loaded where catalog.source.isLive:
            Label("Live from Google Places · updated today", systemImage: "dot.radiowaves.up.forward")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Brand.babu)

        case .loaded, .idle where !catalog.isLiveDataAvailable:
            Label("Sample places — add a Google Places key for live results",
                  systemImage: "info.circle")
                .font(.system(size: 12))
                .foregroundStyle(Palette.inkFaint)

        default:
            EmptyView()
        }
    }

    /// Skeleton cards while the first fetch is in flight.
    private var loadingPlaceholder: some View {
        VStack(spacing: Metric.cardGap) {
            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 10) {
                    RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous)
                        .fill(Palette.surface)
                        .aspectRatio(Metric.photoAspect, contentMode: .fit)
                    RoundedRectangle(cornerRadius: 4).fill(Palette.surface).frame(width: 180, height: 14)
                    RoundedRectangle(cornerRadius: 4).fill(Palette.surface).frame(width: 120, height: 12)
                }
            }
        }
        .redacted(reason: .placeholder)
        .shimmer()
    }

    private var mapButton: some View {
        CapsuleActionButton(title: "Map", systemImage: "map") {
            isMapPresented = true
        }
        .padding(.bottom, 12)
    }
}

/// Slow sheen across skeleton content while it loads.
private struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                LinearGradient(
                    colors: [.clear, .white.opacity(0.35), .clear],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                .offset(x: phase * 320)
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
            }
            .mask(content)
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 1.4
                }
            }
    }
}

private extension View {
    func shimmer() -> some View { modifier(ShimmerModifier()) }
}

#Preview {
    ExploreView().environment(AppStore(loadFromDisk: false))
        .environment(PlaceCatalog())
}
