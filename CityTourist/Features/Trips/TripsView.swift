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
            .navigationDestination(for: TodayRoute.self) { TodayView(tripID: $0.tripID, dayIndex: $0.dayIndex) }
            .sheet(isPresented: $isCreating) { NewTripView() }
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                if let today = store.tripToday {
                    NavigationLink(value: TodayRoute(tripID: today.trip.id, dayIndex: today.dayIndex)) {
                        TodayCard(trip: today.trip, dayIndex: today.dayIndex)
                    }
                    .buttonStyle(.plain)
                }
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

/// The trip happening today, top of the Trips tab: what's next and when to
/// leave for it, with the full Today view a tap away.
struct TodayCard: View {
    let trip: Trip
    let dayIndex: Int

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let day = trip.days[dayIndex]
            let status = TodayStatus.make(stops: day.stops, now: context.date.minuteOfDay)

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Today · Day \(dayIndex + 1) in \(CityDirectory.city(id: trip.cityID).name)")
                        .font(.system(size: 12, weight: .semibold))
                        .textCase(.uppercase)
                        .tracking(0.8)
                        .opacity(0.9)
                    if let next = status.next {
                        Text(PlaceDirectory.place(id: next.placeID)?.name ?? "Your next stop")
                            .font(.system(size: 20, weight: .bold))
                            .tracking(-0.4)
                            .lineLimit(1)
                        Text(subtitle(for: next, in: day, now: context.date.minuteOfDay))
                            .font(.system(size: 14, weight: .medium))
                            .opacity(0.92)
                    } else {
                        Text(day.stops.isEmpty ? "Nothing planned today" : "That's everything for today")
                            .font(.system(size: 20, weight: .bold))
                            .tracking(-0.4)
                    }
                    if day.stops.count > 1 {
                        DayDots(stops: day.stops, now: context.date.minuteOfDay)
                            .padding(.top, 6)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(18)
            .background(
                LinearGradient(colors: [Brand.rausch, Brand.rauschDeep],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous)
            )
        }
    }

    /// "10:15 · leave in 12 min", timed from the stop before or the hotel.
    /// The Today view refines it with MapKit and your location.
    private func subtitle(for stop: ItineraryStop, in day: ItineraryDay, now: Int) -> String {
        guard let place = PlaceDirectory.place(id: stop.placeID) else { return stop.timeLabel }
        let index = day.stops.firstIndex { $0.id == stop.id } ?? 0
        let origin = index > 0
            ? PlaceDirectory.place(id: day.stops[index - 1].placeID)?.coordinate
            : trip.lodging?.coordinate
        guard let origin else { return "Starts \(stop.timeLabel)" }
        let leave = LeaveBy(start: stop.startMinute,
                            travelMinutes: TravelEstimate.minutes(from: origin, to: place.coordinate))
        return "\(stop.timeLabel) · \(leave.countdown(at: now).lowercased())"
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
