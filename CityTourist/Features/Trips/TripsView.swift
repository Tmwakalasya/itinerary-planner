import SwiftUI

struct TripsView: View {
    @Environment(AppStore.self) private var store
    @State private var isCreating = false

    var body: some View {
        NavigationStack {
            Group {
                if store.trips.isEmpty {
                    VStack {
                        Spacer()
                        EmptyStateView(
                            symbol: "airplane.departure",
                            title: "No trips yet",
                            message: "Pick a city and your dates, and we'll lay out a day for each one.",
                            actionTitle: "Plan a trip"
                        ) { isCreating = true }
                        Spacer()
                    }
                } else {
                    list
                }
            }
            .background(Palette.canvas)
            .navigationTitle("Trips")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isCreating = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                    }
                }
            }
            .navigationDestination(for: Trip.ID.self) { TripDetailView(tripID: $0) }
            .sheet(isPresented: $isCreating) { NewTripView() }
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                section("Upcoming", trips: store.upcomingTrips)
                section("Past trips", trips: store.pastTrips)
            }
            .padding(.horizontal, Metric.gutter)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private func section(_ title: String, trips: [Trip]) -> some View {
        if !trips.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                Text(title).sectionTitleStyle()
                ForEach(trips) { trip in
                    NavigationLink(value: trip.id) {
                        TripCard(trip: trip)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Delete trip", systemImage: "trash", role: .destructive) {
                            store.deleteTrip(trip)
                        }
                    }
                }
            }
        }
    }
}

struct TripCard: View {
    let trip: Trip

    private var city: City { CityDirectory.city(id: trip.cityID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PlacePhoto(seed: "trip-\(trip.cityID)", category: .attraction,
                       photoURL: CityDirectory.city(id: trip.cityID).photoURL)
                .aspectRatio(16.0 / 10.0, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(trip.title)
                            .font(.system(size: 24, weight: .bold))
                            .tracking(-0.5)
                        Text(city.country)
                            .font(.system(size: 14, weight: .medium))
                            .opacity(0.9)
                    }
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
                    .padding(18)
                }
                .overlay(alignment: .topTrailing) {
                    if trip.isDownloadedForOffline {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.3), radius: 3)
                            .padding(14)
                    }
                }

            HStack(spacing: 6) {
                Text(trip.dateRangeLabel).cardTitleStyle()
                Text("·").foregroundStyle(Palette.inkMuted)
                Text("\(trip.stopCount) \(trip.stopCount == 1 ? "stop" : "stops")").metaStyle()
                Spacer(minLength: 8)
                if !trip.collaborators.isEmpty {
                    collaboratorStack
                }
            }
        }
    }

    private var collaboratorStack: some View {
        HStack(spacing: -8) {
            ForEach(trip.collaborators.prefix(3)) { collaborator in
                InitialsAvatar(initials: collaborator.initials, size: 24)
                    .overlay(Circle().strokeBorder(Palette.canvas, lineWidth: 2))
            }
        }
    }
}

#Preview {
    TripsView().environment(AppStore(loadFromDisk: false))
        .environment(PlaceCatalog())
}
