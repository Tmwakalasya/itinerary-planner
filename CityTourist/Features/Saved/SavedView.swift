import SwiftUI

struct SavedView: View {
    @Environment(AppStore.self) private var store
    @Environment(PlaceCatalog.self) private var catalog

    /// The city the list is narrowed to; nil shows every city.
    @State private var selectedCityID: String?

    private let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

    var body: some View {
        NavigationStack {
            Group {
                // Keyed on ids, not resolved places: after a relaunch the
                // places are still on their way and this isn't empty.
                if store.savedPlaceIDs.isEmpty {
                    VStack {
                        Spacer()
                        EmptyStateView(
                            symbol: "heart",
                            title: "Nothing saved yet",
                            message: "Tap the heart on any place to keep it here while you decide which day it belongs to."
                        )
                        Spacer()
                    }
                } else {
                    grid
                }
            }
            .background(Palette.canvas)
            .navigationTitle("Saved")
            .navigationDestination(for: Place.self) { PlaceDetailView(place: $0) }
            .task { await resolveSaved() }
        }
    }

    /// Only ids are kept on disk, so places saved in an earlier session are
    /// fetched again the first time this tab needs them.
    private func resolveSaved() async {
        for (cityID, placeIDs) in store.savedPlaceIDsByCity {
            await catalog.resolve(placeIDs, cityID: cityID)
        }
    }

    /// Saved places that haven't resolved yet: loading, or failed to load.
    @ViewBuilder
    private var unresolvedNote: some View {
        let missing = store.savedPlaceIDs.filter { PlaceDirectory.place(id: $0) == nil }
        let noun = missing.count == 1 ? "place" : "places"

        if !missing.isEmpty {
            Group {
                if missing.allSatisfy(catalog.failedPlaceIDs.contains) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Couldn't load \(missing.count) saved \(noun).")
                            .font(.system(size: 12))
                        Button("Try again") { Task { await resolveSaved() } }
                            .font(.system(size: 12, weight: .semibold))
                            .underline()
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Brand.rausch)
                    .padding(10)
                    .background(Brand.rausch.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Loading \(missing.count) saved \(noun)…").captionStyle()
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.horizontal, Metric.gutter)
            .padding(.top, 8)
        }
    }

    private var grid: some View {
        let groups = store.savedPlacesByCity
        // A city that no longer has saved places falls back to All.
        let selected = groups.first { $0.id == selectedCityID }
        let shown = selected.map { [$0] } ?? groups

        return ScrollView {
            unresolvedNote
            if groups.count > 1 {
                cityFilter(groups, selectedID: selected?.id)
            }
            LazyVStack(alignment: .leading, spacing: 32) {
                ForEach(shown) { group in
                    VStack(alignment: .leading, spacing: 14) {
                        cityHeader(group)
                        LazyVGrid(columns: columns, spacing: 24) {
                            ForEach(group.places) { card($0) }
                        }
                    }
                }
            }
            .padding(.horizontal, Metric.gutter)
            .padding(.top, 12)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
    }

    /// "All · Lisbon 2 · Kyoto 1" — narrows the list to one location.
    private func cityFilter(_ groups: [SavedCityGroup], selectedID: String?) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(title: "All", count: store.savedPlaces.count, isSelected: selectedID == nil) {
                    selectedCityID = nil
                }
                ForEach(groups) { group in
                    filterChip(title: group.city.name, count: group.places.count,
                               isSelected: selectedID == group.id) {
                        selectedCityID = group.id
                    }
                }
            }
            .padding(.horizontal, Metric.gutter)
            .padding(.top, 8)
        }
        .scrollClipDisabled()
    }

    private func filterChip(title: String, count: Int, isSelected: Bool,
                            action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.22)) { action() }
        } label: {
            Chip(title: "\(title) \(count)", isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(count) saved")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func cityHeader(_ group: SavedCityGroup) -> some View {
        let noun = group.places.count == 1 ? "place" : "places"
        let country = group.city.country.isEmpty ? "" : "\(group.city.country) · "
        return VStack(alignment: .leading, spacing: 2) {
            Text(group.city.name).sectionTitleStyle()
            Text("\(country)\(group.places.count) saved \(noun)").captionStyle()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func card(_ place: Place) -> some View {
        NavigationLink(value: place) {
            VStack(alignment: .leading, spacing: 8) {
                PlacePhoto(place: place)
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        HeartButton(isSaved: true, size: 20) { store.toggleSaved(place) }
                            .padding(10)
                    }
                Text(place.name).cardTitleStyle().lineLimit(1)
                Text(place.neighborhood.isEmpty ? place.category.title : place.neighborhood)
                    .captionStyle()
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SavedView().environment(AppStore(loadFromDisk: false))
        .environment(PlaceCatalog())
}
