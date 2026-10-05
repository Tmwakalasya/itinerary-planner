import SwiftUI
import MapKit

/// Opens a trip's day in `TodayView` from the Trips tab.
struct TodayRoute: Hashable {
    var tripID: Trip.ID
    var dayIndex: Int
}

/// The trip day as it happens: where you are in it, when to leave for the
/// next stop, and a way to re-plan the rest when the day runs late.
struct TodayView: View {
    let tripID: Trip.ID
    let dayIndex: Int

    @Environment(AppStore.self) private var store
    @Environment(PlaceCatalog.self) private var catalog
    @Environment(RouteStore.self) private var routes
    @Environment(WeatherStore.self) private var weather

    @State private var location = LocationProvider()
    /// MapKit's time from where the traveller is to the next stop.
    @State private var legFromHere: TravelLeg?
    @State private var isRunningLate = false

    private var trip: Trip? { store.trip(id: tripID) }

    /// One way of getting to the next stop, and where it was timed from.
    private struct Hop {
        var minutes: Int
        var symbol: String
        var text: String
    }

    private struct LegKey: Hashable {
        var stopID: ItineraryStop.ID?
        var here: Coordinate?
    }

    var body: some View {
        // Ticks every half minute so the countdown keeps up.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            ScrollView {
                if let trip, trip.days.indices.contains(dayIndex) {
                    content(trip, trip.days[dayIndex], now: context.date.minuteOfDay)
                }
            }
            .scrollIndicators(.hidden)
            .refreshable { location.refresh() }
        }
        .background(Palette.canvas)
        .navigationTitle("Today")
        .sheet(isPresented: $isRunningLate) {
            RunningLateSheet(tripID: tripID, dayIndex: dayIndex)
        }
        .task(id: tripID) {
            location.refresh()
            guard let trip, trip.days.indices.contains(dayIndex) else { return }
            await catalog.resolve(trip.days[dayIndex].stops.map(\.placeID), cityID: trip.cityID)
            await weather.load(trip: trip, city: CityDirectory.city(id: trip.cityID))
        }
    }

    private func content(_ trip: Trip, _ day: ItineraryDay, now: Int) -> some View {
        let status = TodayStatus.make(stops: day.stops, now: now)
        let forecast = weather.forecast(for: trip, on: day.date)

        return VStack(alignment: .leading, spacing: 20) {
            header(trip, day, forecast: forecast)

            if let current = status.current {
                nowCard(current)
            }
            if let next = status.next {
                nextCard(next, in: trip, day: day, now: now, forecast: forecast)
                SecondaryButton(title: "Running late?", systemImage: "clock.arrow.circlepath") {
                    isRunningLate = true
                }
            } else if status.isDone {
                EmptyStateView(
                    symbol: "checkmark.circle",
                    title: day.stops.isEmpty ? "Nothing planned today" : "That's everything for today",
                    message: day.stops.isEmpty
                        ? "Add places to this day from the trip's itinerary."
                        : "Nothing else is planned. Tomorrow's stops are on the trip."
                )
                .padding(.top, 24)
            }

            if !status.later.isEmpty {
                later(status.later, date: day.date, forecast: forecast)
            }
        }
        .padding(.horizontal, Metric.gutter)
        .padding(.top, 8)
        .padding(.bottom, 32)
        .task(id: LegKey(stopID: status.next?.id, here: location.coordinate)) {
            await loadLegFromHere(to: status.next)
        }
    }

    // MARK: Blocks

    private func header(_ trip: Trip, _ day: ItineraryDay, forecast: DayForecast?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Day \(dayIndex + 1) in \(CityDirectory.city(id: trip.cityID).name)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Brand.rausch)
                .textCase(.uppercase)
                .tracking(0.8)
            Text(day.date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .sectionTitleStyle()
            if let forecast {
                Label("\(forecast.summary) · \(forecast.temperatureLabel)", systemImage: forecast.symbol)
                    .metaStyle()
            }
        }
    }

    private func nowCard(_ stop: ItineraryStop) -> some View {
        HStack(spacing: 10) {
            Circle().fill(Brand.babu).frame(width: 8, height: 8)
            Text("At \(PlaceDirectory.place(id: stop.placeID)?.name ?? "your stop")")
                .cardTitleStyle()
                .lineLimit(1)
            Spacer(minLength: 8)
            Text("until \(DayForecast.clockLabel(stop.startMinute + stop.durationMinutes))")
                .captionStyle()
        }
        .padding(14)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous))
    }

    private func nextCard(_ stop: ItineraryStop, in trip: Trip, day: ItineraryDay,
                          now: Int, forecast: DayForecast?) -> some View {
        let place = PlaceDirectory.place(id: stop.placeID)
        let hop = travel(to: stop, in: trip, day: day)
        let leave = hop.map { LeaveBy(start: stop.startMinute, travelMinutes: $0.minutes) }

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                if let place {
                    PlacePhoto(place: place, showsGlyph: false)
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Next").captionStyle()
                    Text(place?.name ?? "Loading this place").cardTitleStyle().lineLimit(2)
                    Text("Starts \(stop.timeLabel)").captionStyle()
                }
                Spacer(minLength: 0)
            }

            if let leave, let hop {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Leave by \(DayForecast.clockLabel(leave.minute))")
                            .font(.system(size: 24, weight: .bold))
                            .tracking(-0.5)
                            .foregroundStyle(Palette.ink)
                        Spacer(minLength: 8)
                        Text(leave.countdown(at: now))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(leave.minutesBehind(at: now) > 0 ? Brand.rausch : Brand.babu)
                    }
                    .monospacedDigit()
                    Label(hop.text, systemImage: hop.symbol)
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.inkMuted)
                }
            }

            if let place, let warning = VisitWarning.make(place: place, on: day.date, start: stop.startMinute,
                                                          minutes: stop.durationMinutes, forecast: forecast) {
                Label(warning.text, systemImage: warning.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Brand.rausch)
            }

            HStack(spacing: 10) {
                SecondaryButton(title: "Directions", systemImage: "arrow.triangle.turn.up.right.diamond") {
                    openDirections(to: place)
                }
                if location.canAsk {
                    SecondaryButton(title: "Use my location", systemImage: "location") {
                        location.requestPermission()
                    }
                }
            }
        }
        .padding(16)
        .background(Palette.elevated, in: RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 1)
        }
    }

    private func later(_ stops: [ItineraryStop], date: Date, forecast: DayForecast?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Later today").sectionTitleStyle().padding(.bottom, 4)
            ForEach(stops) { stop in
                let place = PlaceDirectory.place(id: stop.placeID)
                HStack(alignment: .top, spacing: 14) {
                    Text(stop.timeLabel)
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Palette.inkMuted)
                        .lineLimit(1)
                        .frame(width: 72, alignment: .leading)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(place?.name ?? "Loading this place").cardTitleStyle().lineLimit(1)
                        if let place, let warning = VisitWarning.make(place: place, on: date, start: stop.startMinute,
                                                                      minutes: stop.durationMinutes, forecast: forecast) {
                            Label(warning.text, systemImage: warning.symbol)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Brand.rausch)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 12)
                Hairline()
            }
        }
    }

    // MARK: Getting there

    /// The best idea of the hop to `stop`: MapKit from where you are; else
    /// the hop from the stop before, measured or estimated; else from where
    /// you're staying. Nil when there's nothing to time it from.
    private func travel(to stop: ItineraryStop, in trip: Trip, day: ItineraryDay) -> Hop? {
        guard let place = PlaceDirectory.place(id: stop.placeID) else { return nil }
        if let legFromHere, legFromHere.toPlaceID == place.id {
            return Hop(minutes: legFromHere.minutes, symbol: legFromHere.mode.symbol,
                       text: "\(legFromHere.minutes) min \(legFromHere.mode.verb) from here")
        }
        if let index = day.stops.firstIndex(where: { $0.id == stop.id }), index > 0,
           let previous = PlaceDirectory.place(id: day.stops[index - 1].placeID) {
            if let leg = routes.leg(from: previous, to: place) {
                return Hop(minutes: leg.minutes, symbol: leg.mode.symbol,
                           text: "\(leg.minutes) min \(leg.mode.verb) from \(previous.name)")
            }
            let minutes = TravelEstimate.minutes(from: previous.coordinate, to: place.coordinate)
            return Hop(minutes: minutes, symbol: "clock", text: "About \(minutes) min from \(previous.name)")
        }
        if let lodging = trip.lodging {
            let minutes = TravelEstimate.minutes(from: lodging.coordinate, to: place.coordinate)
            return Hop(minutes: minutes, symbol: "bed.double", text: "About \(minutes) min from \(lodging.name)")
        }
        return nil
    }

    private func loadLegFromHere(to stop: ItineraryStop?) async {
        guard let stop, let here = location.coordinate,
              let place = PlaceDirectory.place(id: stop.placeID)
        else {
            legFromHere = nil
            return
        }
        legFromHere = await RouteService().leg(fromHere: here, to: place)
    }

    private func openDirections(to place: Place?) {
        guard let place else { return }
        let item = MKMapItem(placemark: MKPlacemark(coordinate: place.coordinate.clLocation))
        item.name = place.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
    }
}
