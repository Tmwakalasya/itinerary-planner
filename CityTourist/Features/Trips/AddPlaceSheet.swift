import SwiftUI

/// Browse the city's places from inside an itinerary and drop one straight onto
/// the day you're looking at.
struct AddPlaceSheet: View {
    let tripID: Trip.ID
    let dayIndex: Int
    /// Opens the sheet already filtered, e.g. to museums on a wet day.
    var initialCategory: PlaceCategory? = nil

    @Environment(AppStore.self) private var store
    @Environment(PlaceCatalog.self) private var catalog
    @Environment(\.dismiss) private var dismiss

    @State private var category: PlaceCategory?
    @State private var searchText = ""

    private var trip: Trip? { store.trip(id: tripID) }

    private var places: [Place] {
        guard let trip else { return [] }
        let alreadyOnThisDay = Set(
            trip.days.indices.contains(dayIndex) ? trip.days[dayIndex].stops.map(\.placeID) : []
        )
        return catalog.places(in: trip.cityID)
            .filter { !alreadyOnThisDay.contains($0.id) }
            .filter { category == nil || $0.category == category }
            .filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) }
            .sorted { $0.rating > $1.rating }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(places) { place in
                        Button {
                            add(place)
                        } label: {
                            HStack(spacing: 12) {
                                PlaceRow(place: place, trailingText: place.durationLabel)
                                Image(systemName: "plus.circle")
                                    .font(.system(size: 22, weight: .light))
                                    .foregroundStyle(Brand.rausch)
                            }
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        Hairline()
                    }

                    if places.isEmpty {
                        EmptyStateView(symbol: "checkmark.circle",
                                       title: "Nothing left to add",
                                       message: "Everything matching this filter is already on the day.")
                            .padding(.top, 60)
                    }
                }
                .padding(.horizontal, Metric.gutter)
                .padding(.bottom, 24)
            }
            .background(Palette.canvas)
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 12) {
                    CategoryRail(selection: $category)
                    Hairline()
                }
                .padding(.top, 4)
                .background(.bar)
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search places")
            .navigationTitle("Add to day \(dayIndex + 1)")
            .task {
                if category == nil { category = initialCategory }
                if let trip { await catalog.load(city: CityDirectory.city(id: trip.cityID)) }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }.foregroundStyle(Palette.ink)
                }
            }
        }
    }

    private func add(_ place: Place) {
        let minute = store.suggestedStartMinute(tripID: tripID, dayIndex: dayIndex)
        store.addStop(place: place, to: tripID, dayIndex: dayIndex, startMinute: minute)
        dismiss()
    }
}
