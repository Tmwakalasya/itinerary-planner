import SwiftUI

/// The itinerary itself: a day rail across the top and a vertical timeline of
/// stops beneath it.
struct TripDetailView: View {
    let tripID: Trip.ID

    @Environment(AppStore.self) private var store
    @Environment(WeatherStore.self) private var weather
    @Environment(RouteStore.self) private var routes
    @Environment(\.dismiss) private var dismiss

    @State private var dayIndex = 0
    @State private var editingStop: ItineraryStop?
    @State private var isReordering = false
    @State private var isSharing = false
    @State private var isBrowsing = false
    /// Set when the browse sheet should open pre-filtered, e.g. to indoor
    /// options on a wet day.
    @State private var browseCategory: PlaceCategory?
    @State private var isMapPresented = false

    private var trip: Trip? { store.trip(id: tripID) }

    var body: some View {
        Group {
            if let trip {
                content(trip)
            } else {
                // The trip was deleted out from under this screen.
                EmptyStateView(symbol: "questionmark.folder", title: "Trip not found",
                               message: "It may have been deleted.")
            }
        }
        .background(Palette.canvas)
        .navigationBarBackButtonHidden()
        .ignoresSafeArea(edges: .top)
        .overlay(alignment: .topLeading) { floatingControls }
        .sheet(item: $editingStop) { stop in
            StopEditorSheet(tripID: tripID, dayIndex: dayIndex, stop: stop)
        }
        .sheet(isPresented: $isReordering) {
            ReorderStopsSheet(tripID: tripID, dayIndex: dayIndex)
        }
        .sheet(isPresented: $isSharing) {
            ShareTripSheet(tripID: tripID)
        }
        .sheet(isPresented: $isBrowsing) {
            AddPlaceSheet(tripID: tripID, dayIndex: dayIndex, initialCategory: browseCategory)
        }
        .fullScreenCover(isPresented: $isMapPresented) {
            if let trip, trip.days.indices.contains(dayIndex) {
                ItineraryMapView(trip: trip, dayIndex: dayIndex)
            }
        }
        .onAppear(perform: selectMostRelevantDay)
        .task(id: tripID) {
            guard let trip else { return }
            await weather.load(trip: trip, city: CityDirectory.city(id: trip.cityID))
        }
        .task(id: "\(tripID)-\(dayIndex)-\(trip?.stopCount ?? 0)") {
            guard let trip, trip.days.indices.contains(dayIndex) else { return }
            await routes.loadLegs(for: trip.days[dayIndex].stops)
        }
    }

    // MARK: Layout

    private func content(_ trip: Trip) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero(trip)
                dayRail(trip)
                timeline(trip)
            }
            .padding(.bottom, 100)
        }
        .scrollIndicators(.hidden)
        .overlay(alignment: .bottom) {
            if currentStops(trip).count > 1 {
                CapsuleActionButton(title: "Day \(dayIndex + 1) map", systemImage: "map") {
                    isMapPresented = true
                }
                .padding(.bottom, 12)
            }
        }
    }

    private func hero(_ trip: Trip) -> some View {
        PlacePhoto(seed: "trip-\(trip.cityID)", category: .attraction,
                       photoURL: CityDirectory.city(id: trip.cityID).photoURL)
            .frame(height: 260)
            .clipped()
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(trip.title)
                        .font(.system(size: 30, weight: .bold))
                        .tracking(-0.6)
                    Text("\(trip.dateRangeLabel) · \(trip.days.count) days")
                        .font(.system(size: 15, weight: .medium))
                        .opacity(0.92)
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 10, y: 2)
                .padding(.horizontal, Metric.gutter)
                .padding(.bottom, 20)
            }
    }

    private func dayRail(_ trip: Trip) -> some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(trip.days.enumerated()), id: \.element.id) { index, day in
                        Button {
                            withAnimation(.snappy(duration: 0.22)) { dayIndex = index }
                        } label: {
                            VStack(spacing: 6) {
                                Chip(
                                    title: "Day \(index + 1) · \(day.date.formatted(.dateTime.weekday(.abbreviated).day()))",
                                    isSelected: dayIndex == index
                                )
                                // Seeing the whole trip's weather at a glance is
                                // the point — that's what prompts a swap.
                                if let forecast = weather.forecast(for: trip, on: day.date) {
                                    HStack(spacing: 4) {
                                        Image(systemName: forecast.symbol)
                                            .font(.system(size: 11))
                                            .foregroundStyle(forecast.isWet ? Brand.rausch : Palette.inkMuted)
                                        Text("\(Int(forecast.high.rounded()))\(forecast.unit)")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(Palette.inkMuted)
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Metric.gutter)
            }
            .scrollClipDisabled()
            .padding(.vertical, 16)
            Hairline()
        }
    }

    @ViewBuilder
    private func timeline(_ trip: Trip) -> some View {
        let stops = currentStops(trip)

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(dayTitle(trip)).sectionTitleStyle()
                Spacer()
                if stops.count > 1 {
                    Button("Reorder") { isReordering = true }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .underline()
                }
            }
            .padding(.horizontal, Metric.gutter)
            .padding(.top, 24)
            .padding(.bottom, 8)

            forecastBlock(trip, stops: stops)

            if stops.isEmpty {
                EmptyStateView(
                    symbol: "mappin.and.ellipse",
                    title: "Nothing planned yet",
                    message: "Add a place and it'll drop into this day at the time you choose.",
                    actionTitle: "Browse places"
                ) { isBrowsing = true }
                .padding(.top, 40)
            } else {
                ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                    StopTimelineRow(
                        stop: stop,
                        isFirst: index == 0,
                        isLast: index == stops.count - 1,
                        forecast: weather.forecast(for: trip, on: trip.days[dayIndex].date),
                        travelNote: travelNote(from: stop, to: index + 1 < stops.count ? stops[index + 1] : nil)
                    ) {
                        editingStop = stop
                    }
                }

                Button { isBrowsing = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "plus").font(.system(size: 15, weight: .semibold))
                        Text("Add a place").font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .overlay {
                        RoundedRectangle(cornerRadius: Metric.buttonRadius, style: .continuous)
                            .strokeBorder(Palette.hairline, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, Metric.gutter)
                .padding(.top, 12)
            }
        }
    }

    /// Today's conditions, plus a nudge when the plan is mostly outdoors and
    /// the forecast disagrees.
    @ViewBuilder
    private func forecastBlock(_ trip: Trip, stops: [ItineraryStop]) -> some View {
        if trip.days.indices.contains(dayIndex),
           let forecast = weather.forecast(for: trip, on: trip.days[dayIndex].date) {

            let outdoor = stops.compactMap { PlaceDirectory.place(id: $0.placeID) }
                .filter(\.category.isOutdoors)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: forecast.symbol)
                        .font(.system(size: 15))
                        .foregroundStyle(forecast.isWet ? Brand.rausch : Brand.babu)
                    Text(forecast.summary).metaStyle()
                    Text("·").foregroundStyle(Palette.inkFaint)
                    Text(forecast.temperatureLabel).metaStyle()
                    if forecast.precipitationChance > 0 {
                        Text("·").foregroundStyle(Palette.inkFaint)
                        Text("\(forecast.precipitationChance)% rain").metaStyle()
                    }
                    if let sunset = forecast.sunsetLabel {
                        Text("·").foregroundStyle(Palette.inkFaint)
                        Text("sunset \(sunset)").metaStyle()
                    }
                    Spacer(minLength: 0)
                }
                .lineLimit(1)

                if forecast.isWet && !outdoor.isEmpty {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "umbrella.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Brand.rausch)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(outdoor.count) of today's \(stops.count) stops are outdoors")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Palette.ink)
                            Button("Find something indoors") {
                                browseCategory = .museum
                                isBrowsing = true
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Brand.rausch)
                            .underline()
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .background(Brand.rausch.opacity(0.07),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .padding(.horizontal, Metric.gutter)
            .padding(.bottom, 16)
        }
    }

    private var floatingControls: some View {
        HStack {
            GlassCircleButton(systemImage: "chevron.left") { dismiss() }
            Spacer()
            HStack(spacing: 10) {
                GlassCircleButton(systemImage: offlineSymbol) { toggleOffline() }
                GlassCircleButton(systemImage: "square.and.arrow.up") { isSharing = true }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: Helpers

    private var offlineSymbol: String {
        (trip?.isDownloadedForOffline ?? false) ? "arrow.down.circle.fill" : "arrow.down.circle"
    }

    private func toggleOffline() {
        guard var trip else { return }
        trip.isDownloadedForOffline.toggle()
        store.update(trip)
    }

    private func currentStops(_ trip: Trip) -> [ItineraryStop] {
        trip.days.indices.contains(dayIndex) ? trip.days[dayIndex].stops : []
    }

    private func dayTitle(_ trip: Trip) -> String {
        guard trip.days.indices.contains(dayIndex) else { return "Day" }
        return trip.days[dayIndex].date.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    /// What sits between two stops: how long the hop takes and whether the
    /// plan actually allows for it.
    private func travelNote(from stop: ItineraryStop, to next: ItineraryStop?) -> TravelNote? {
        guard let next else { return nil }
        let gap = next.startMinute - (stop.startMinute + stop.durationMinutes)
        var leg: TravelLeg?
        if let a = PlaceDirectory.place(id: stop.placeID),
           let b = PlaceDirectory.place(id: next.placeID) {
            leg = routes.leg(from: a, to: b)
        }
        return TravelNote.make(gapMinutes: gap, leg: leg)
    }

    /// Opens on today if the trip is running, otherwise on day one.
    private func selectMostRelevantDay() {
        guard let trip else { return }
        let today = Calendar.current.startOfDay(for: .now)
        if let index = trip.days.firstIndex(where: { Calendar.current.isDate($0.date, inSameDayAs: today) }) {
            dayIndex = index
        }
    }
}

// MARK: - Timeline row

struct StopTimelineRow: View {
    let stop: ItineraryStop
    let isFirst: Bool
    let isLast: Bool
    var forecast: DayForecast?
    var travelNote: TravelNote?
    let onTap: () -> Void

    private var place: Place? { PlaceDirectory.place(id: stop.placeID) }

    var body: some View {
        if let place {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 14) {
                    railColumn
                    card(place)
                }
                .padding(.horizontal, Metric.gutter)

                if let travelNote {
                    HStack(spacing: 14) {
                        // Keep the connector aligned under the timeline rail.
                        VStack(spacing: 0) {
                            Rectangle()
                                .fill(Palette.hairline)
                                .frame(width: 1.5, height: 22)
                        }
                        .frame(width: 64)
                        HStack(spacing: 5) {
                            Image(systemName: travelNote.symbol)
                                .font(.system(size: 11, weight: .medium))
                            Text(travelNote.text)
                                .font(.system(size: 13))
                        }
                        .foregroundStyle(travelNote.isTight ? Brand.rausch : Palette.inkMuted)
                        Spacer()
                    }
                    .padding(.horizontal, Metric.gutter)
                }
            }
        }
    }

    private var railColumn: some View {
        VStack(spacing: 6) {
            Text(stop.timeLabel)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Circle()
                .fill(Brand.rausch)
                .frame(width: 9, height: 9)
            if !isLast {
                Rectangle()
                    .fill(Palette.hairline)
                    .frame(width: 1.5)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(width: 64)
    }

    private func card(_ place: Place) -> some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    PlacePhoto(place: place, showsGlyph: false)
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(place.name).cardTitleStyle().lineLimit(1)
                        Text(place.neighborhood).captionStyle().lineLimit(1)
                        HStack(spacing: 6) {
                            RatingLabel(rating: place.rating, size: 12)
                            Text("·").foregroundStyle(Palette.inkFaint)
                            Text(durationLabel).captionStyle()
                            if stop.remindMe {
                                Image(systemName: "bell.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Brand.rausch)
                            }

                        }
                    }
                    Spacer(minLength: 0)
                }

                if let daylight = DaylightNote.make(
                    startMinute: stop.startMinute,
                    durationMinutes: stop.durationMinutes,
                    category: place.category,
                    forecast: forecast
                ) {
                    Label(daylight.text, systemImage: daylight.symbol)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Brand.rausch)
                        .lineLimit(1)
                }

                if !stop.note.isEmpty {
                    Text(stop.note)
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.inkMuted)
                        .italic()
                        .lineLimit(2)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.elevated, in: RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: 1)
            }
            .padding(.bottom, 14)
        }
        .buttonStyle(.plain)
    }

    private var durationLabel: String {
        let h = stop.durationMinutes / 60, m = stop.durationMinutes % 60
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) hr" : "\(h) hr \(m) min"
    }
}
