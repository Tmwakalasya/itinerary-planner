import SwiftUI
import CoreLocation

/// The same place search from Explore and from a day being planned. Search
/// is submitted explicitly; editing or clearing the field cancels old work.
struct PlaceSearchView: View {
    let city: City
    var title = "Search places"
    var initialCategory: PlaceCategory? = nil
    var excludedPlaceIDs: Set<String> = []
    var onAdd: ((Place) -> Void)? = nil

    @Environment(AppStore.self) private var store
    @Environment(PlaceCatalog.self) private var catalog
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var category: PlaceCategory?
    @State private var matches: [Place] = []
    @State private var state: PlaceCatalog.LoadState = .idle
    @State private var submittedQuery = ""
    @State private var requestPageToken: String?
    @State private var nextPageToken: String?
    @State private var requestID = UUID()

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var hasQuery: Bool { !trimmedQuery.isEmpty }
    private var visiblePlaces: [Place] {
        let candidates = hasQuery ? matches : catalog.places(in: city.id).sorted { $0.rating > $1.rating }
        return candidates.filter {
            !excludedPlaceIDs.contains($0.id) && (hasQuery || category == nil || $0.category == category)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Around \(city.name)").sectionTitleStyle()
                        Text(catalog.isLiveDataAvailable
                             ? "Find a name, food or activity within 50 km of the city centre."
                             : "Searching sample places. Live search is unavailable.").captionStyle()
                    }
                    if hasQuery {
                        searchContent
                    } else {
                        browseContent
                    }
                }
                .padding(.horizontal, Metric.gutter)
                .padding(.vertical, 16)
            }
            .background(Palette.canvas)
            .scrollDismissesKeyboard(.interactively)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search places near \(city.name)")
            .onSubmit(of: .search) { submit() }
            .onChange(of: query) { _, _ in resetSearch() }
            .onChange(of: city.id) { _, _ in
                query = ""
                category = nil
                resetSearch()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Place.self) { PlaceDetailView(place: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundStyle(Brand.rausch)
                }
            }
            .task(id: city.id) {
                category = initialCategory
                await catalog.load(city: city)
            }
            .task(id: requestID) { await runSearch() }
        }
    }

    @ViewBuilder
    private var browseContent: some View {
        CategoryRail(selection: $category)
        if catalog.state == .loading && visiblePlaces.isEmpty {
            ProgressView("Finding suggestions…").padding(.vertical, 24)
        }
        if case .failed = catalog.state {
            Text("Suggestions couldn’t load. You can still search for a place above.").metaStyle()
        }
        if visiblePlaces.isEmpty && catalog.state != .loading {
            Text("Search for somewhere you have in mind, or try another category.").metaStyle()
        }
        placeRows
    }

    @ViewBuilder
    private var searchContent: some View {
        if state == .idle {
            Text("A favourite café, a museum, or something you want to try.").metaStyle()
            PrimaryButton(title: "Search", isEnabled: trimmedQuery.count >= 2) { submit() }
            if trimmedQuery.count < 2 {
                Text("Enter at least two characters.").captionStyle()
            }
        } else {
            placeRows
            switch state {
            case .loading:
                ProgressView(matches.isEmpty ? "Searching places…" : "Finding more places…")
                    .padding(.vertical, 20)
            case .failed(let message):
                VStack(alignment: .leading, spacing: 12) {
                    Text("Couldn’t search places").cardTitleStyle()
                    Text(message).metaStyle()
                    SecondaryButton(title: "Try again", systemImage: "arrow.clockwise") {
                        state = .loading
                        requestID = UUID()
                    }
                }
            case .loaded:
                if visiblePlaces.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(matches.isEmpty ? "No matches nearby" : "Already on this day").sectionTitleStyle()
                        Text(matches.isEmpty
                             ? "Try a different name or a broader search near \(city.name)."
                             : "The matching places are already in your itinerary. Try another search.").metaStyle()
                    }
                }
                if let nextPageToken {
                    SecondaryButton(title: "More results") {
                        requestPageToken = nextPageToken
                        state = .loading
                        requestID = UUID()
                    }
                }
                if catalog.isLiveDataAvailable {
                    Text("Results from Google Maps").captionStyle()
                }
            case .idle:
                EmptyView()
            }
        }
    }

    private var placeRows: some View {
        ForEach(visiblePlaces) { place in
            HStack(alignment: .center, spacing: 12) {
                NavigationLink(value: place) {
                    HStack(alignment: .top, spacing: 12) {
                        PlacePhoto(place: place, showsGlyph: false)
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(place.name).cardTitleStyle().lineLimit(2)
                            Text(place.neighborhood).captionStyle().lineLimit(2)
                            Text(distanceLabel(for: place)).captionStyle()
                            if place.reviewCount > 0 { RatingLabel(rating: place.rating, size: 12) }
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if let onAdd {
                    Button { onAdd(place) } label: {
                        Image(systemName: "plus.circle")
                            .font(.title2)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Add \(place.name) to this day")
                } else {
                    Button { store.toggleSaved(place) } label: {
                        Image(systemName: store.isSaved(place) ? "heart.fill" : "heart")
                            .font(.title3)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(store.isSaved(place) ? "Unsave \(place.name)" : "Save \(place.name)")
                }
            }
            .tint(Brand.rausch)
            Hairline()
        }
    }

    private func distanceLabel(for place: Place) -> String {
        let centre = CLLocation(latitude: city.coordinate.latitude, longitude: city.coordinate.longitude)
        let location = CLLocation(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude)
        let kilometres = (centre.distance(from: location) / 1_000).formatted(.number.precision(.fractionLength(1)))
        return "\(kilometres) km from city centre · straight-line"
    }

    private func resetSearch() {
        requestID = UUID()
        submittedQuery = ""
        requestPageToken = nil
        nextPageToken = nil
        matches = []
        state = .idle
    }

    private func submit() {
        guard trimmedQuery.count >= 2, state != .loading else { return }
        submittedQuery = trimmedQuery
        matches = []
        requestPageToken = nil
        nextPageToken = nil
        state = .loading
        requestID = UUID()
    }

    private func runSearch() async {
        guard state == .loading, !submittedQuery.isEmpty else { return }
        let currentRequest = requestID
        do {
            let page = try await catalog.searchPlaces(query: submittedQuery, city: city, pageToken: requestPageToken)
            guard !Task.isCancelled, currentRequest == requestID else { return }
            var seen = Set(matches.map(\.id))
            matches += page.places.filter { seen.insert($0.id).inserted }
            nextPageToken = page.nextPageToken
            state = .loaded
        } catch {
            guard !Task.isCancelled, currentRequest == requestID else { return }
            state = .failed(error.localizedDescription)
        }
    }
}
