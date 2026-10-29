import SwiftUI

struct SavedView: View {
    @Environment(AppStore.self) private var store
    @Environment(PlaceCatalog.self) private var catalog

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
        ScrollView {
            unresolvedNote
            LazyVStack(alignment: .leading, spacing: 28) {
                let groups = store.savedPlacesByCity
                ForEach(groups.keys.sorted {
                    let left = CityDirectory.city(id: $0).displayName
                    let right = CityDirectory.city(id: $1).displayName
                    return left == right ? $0 < $1 : left.localizedStandardCompare(right) == .orderedAscending
                }, id: \.self) { cityID in
                    let places = groups[cityID] ?? []
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(CityDirectory.city(id: cityID).displayName)
                                .font(.headline)
                            Spacer()
                            Text("\(places.count) \(places.count == 1 ? "place" : "places")")
                                .captionStyle()
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isHeader)

                        LazyVGrid(columns: columns, spacing: 24) {
                            ForEach(places) { place in
                                savedCard(place)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Metric.gutter)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
    }

    private func savedCard(_ place: Place) -> some View {
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
                    .captionStyle().lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SavedView().environment(AppStore(loadFromDisk: false))
        .environment(PlaceCatalog())
}
