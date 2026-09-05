import SwiftUI

struct SavedView: View {
    @Environment(AppStore.self) private var store

    private let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

    var body: some View {
        NavigationStack {
            Group {
                if store.savedPlaces.isEmpty {
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
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 24) {
                ForEach(store.savedPlaces) { place in
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
                            Text(CityDirectory.city(id: place.cityID).name).captionStyle()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Metric.gutter)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
    }
}

#Preview {
    SavedView().environment(AppStore(loadFromDisk: false))
        .environment(PlaceCatalog())
}
