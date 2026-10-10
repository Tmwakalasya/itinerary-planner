import SwiftUI

/// The itinerary itself: a day rail across the top and a vertical timeline of
/// stops beneath it.
struct TripDetailView: View {
    let tripID: Trip.ID

    @Environment(AppStore.self) private var store
    @Environment(PlaceCatalog.self) private var catalog
    @Environment(WeatherStore.self) private var weather
    @Environment(RouteStore.self) private var routes
    @Environment(EventCatalog.self) private var eventCatalog
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var dayIndex = 0
    @State private var editingStop: ItineraryStop?
    @State private var isReordering = false
    @State private var isSharing = false
    @State private var isBrowsing = false
    /// Set when the browse sheet should open pre-filtered, e.g. to indoor
    /// options on a wet day.
    @State private var browseCategory: PlaceCategory?
    @State private var isMapPresented = false
    @State private var isFixing = false
    @State private var isChoosingLodging = false
    @State private var isConfirmingDelete = false
    @State private var selectedEvent: Place?

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
        .navigationTitle(trip?.title ?? "Trip")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Share trip", systemImage: "square.and.arrow.up") { isSharing = true }
                Menu("More", systemImage: "ellipsis") {
                    Button("Delete trip", systemImage: "trash", role: .destructive) {
                        isConfirmingDelete = true
                    }
                }
            }
        }
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
        .sheet(isPresented: $isFixing) {
            FixDaySheet(tripID: tripID, dayIndex: dayIndex)
        }
        .sheet(isPresented: $isChoosingLodging) {
            LodgingSheet(tripID: tripID)
        }
        .sheet(item: $selectedEvent) { event in
            NavigationStack {
                EventDetailView(place: event, tripID: tripID, dayIndex: dayIndex)
            }
        }
        .fullScreenCover(isPresented: $isMapPresented) {
            if let trip, trip.days.indices.contains(dayIndex) {
                ItineraryMapView(trip: trip, dayIndex: dayIndex)
            }
        }
        .confirmationDialog("Delete \(trip?.title ?? "this trip")?", isPresented: $isConfirmingDelete,
                            titleVisibility: .visible) {
            Button("Delete trip", role: .destructive) {
                guard let trip else { return }
                dismiss()
                store.deleteTrip(trip)
            }
        } message: {
            Text("Its stops and reminders go with it. This can't be undone.")
        }
        .onAppear(perform: selectMostRelevantDay)
        .task(id: tripID) {
            guard let trip else { return }
            await resolvePlaces(trip)
        }
        .task(id: tripID) {
            guard let trip else { return }
            await weather.load(trip: trip, city: CityDirectory.city(id: trip.cityID))
        }
        .task(id: tripID) {
            guard let trip else { return }
            await eventCatalog.load(trip: trip, city: CityDirectory.city(id: trip.cityID))
        }
        .task(id: routeKey) {
            guard let trip, trip.days.indices.contains(dayIndex) else { return }
            let day = trip.days[dayIndex]
            await routes.loadLegs(for: day.stops, on: day.date, by: trip.gettingAround)
        }
    }

    /// The day's resolved places, in timeline order, and how the trip gets
    /// around. Travel times reload when this changes: once places from an
    /// earlier session arrive, after a reorder puts different stops next to
    /// each other, and when the trip switches between transit and a car.
    private var routeKey: String {
        guard let trip, trip.days.indices.contains(dayIndex) else { return "\(tripID)" }
        let placeIDs = trip.days[dayIndex].stops.map(\.placeID)
            .filter { PlaceDirectory.place(id: $0) != nil }
        return "\(tripID)-\(dayIndex)-\(trip.gettingAround.rawValue)-\(placeIDs.joined(separator: ","))"
    }

    /// Fetches any of the trip's places this session hasn't seen yet — after a
    /// relaunch, that's every stop outside the bundled samples.
    private func resolvePlaces(_ trip: Trip) async {
        await catalog.resolve(trip.days.flatMap(\.stops).map(\.placeID), cityID: trip.cityID)
    }

    // MARK: Layout

    private func content(_ trip: Trip) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    hero(trip)
                    Section {
                        timeline(trip)
                            .id(dayIndex)
                    } header: {
                        dayRail(trip)
                            .background(Palette.canvas)
                            .id("day-controls")
                    }
                }
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .onChange(of: dayIndex) { _, _ in
                proxy.scrollTo("day-controls", anchor: .top)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 8) {
                    if let undo = store.pendingUndo, undo.tripID == tripID {
                        UndoBar(undo: undo)
                            .padding(.horizontal, Metric.gutter)
                    }
                    StickyBottomBar {
                        HStack(spacing: 12) {
                            PrimaryButton(title: dynamicTypeSize.isAccessibilitySize ? "Add" : "Add place") {
                                browseCategory = nil
                                isBrowsing = true
                            }
                            .accessibilityLabel("Add place")
                            SecondaryButton(title: "Map", systemImage: "map") { isMapPresented = true }
                                .disabled(currentStops(trip).isEmpty)
                                .opacity(currentStops(trip).isEmpty ? 0.4 : 1)
                        }
                    }
                }
                .background(.bar)
            }
        }
    }

    private func hero(_ trip: Trip) -> some View {
        PlacePhoto(seed: "trip-\(trip.cityID)", category: .attraction,
                       photoURL: CityDirectory.city(id: trip.cityID).photoURL)
            .frame(height: 180)
            .clipped()
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(trip.title)
                        .font(.title.weight(.bold))
                        .tracking(-0.6)
                    Text("\(trip.dateRangeLabel) · \(trip.days.count) \(trip.days.count == 1 ? "day" : "days")")
                        .font(.subheadline.weight(.medium))
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
            ScrollViewReader { proxy in
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
                            .id(index)
                            .accessibilityAddTraits(dayIndex == index ? .isSelected : [])
                        }
                    }
                    .padding(.horizontal, Metric.gutter)
                }
                .scrollClipDisabled()
                .padding(.vertical, 16)
                .onAppear { proxy.scrollTo(dayIndex, anchor: .center) }
                .onChange(of: dayIndex) { _, index in
                    proxy.scrollTo(index, anchor: .center)
                }
            }
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
            fixBanner(trip, stops: stops)
            lodgingRow(trip)
            gettingAroundRow(trip)

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
                        date: trip.days[dayIndex].date,
                        forecast: weather.forecast(for: trip, on: trip.days[dayIndex].date),
                        travelNote: travelNote(from: stop, to: index + 1 < stops.count ? stops[index + 1] : nil),
                        placeFailedToLoad: catalog.failedPlaceIDs.contains(stop.placeID),
                        placePaused: catalog.pausedPlaceIDs.contains(stop.placeID),
                        onRetry: { Task { await resolvePlaces(trip) } }
                    ) {
                        editingStop = stop
                    }
                }

            }

            whatsOn(trip, stops: stops)
        }
    }

    /// Ticketed events near the city that day, for adding as booked stops.
    /// Only there when something's on (and there's a Ticketmaster key).
    @ViewBuilder
    private func whatsOn(_ trip: Trip, stops: [ItineraryStop]) -> some View {
        let planned = Set(stops.map(\.placeID))
        let events = trip.days.indices.contains(dayIndex)
            ? eventCatalog.events(for: trip, on: trip.days[dayIndex].date).filter { !planned.contains($0.id) }
            : []
        if !events.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("What's on").sectionTitleStyle()
                    .padding(.horizontal, Metric.gutter)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(events) { event in
                            Button { selectedEvent = event } label: { EventCard(place: event) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Metric.gutter)
                }
                .scrollClipDisabled()
            }
            .padding(.top, 28)
        }
    }

    /// Today's conditions, plus a nudge when the plan is mostly outdoors and
    /// the forecast disagrees.
    @ViewBuilder
    private func forecastBlock(_ trip: Trip, stops: [ItineraryStop]) -> some View {
        if trip.days.indices.contains(dayIndex),
           let forecast = weather.forecast(for: trip, on: trip.days[dayIndex].date) {

            // A booked stop can't be swapped for something indoors.
            let outdoor = stops.filter { !$0.isBooked }.compactMap { PlaceDirectory.place(id: $0.placeID) }
                .filter(\.category.isOutdoors)

            VStack(alignment: .leading, spacing: 10) {
                weatherLine(forecast)

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

    /// One line when it fits. When it doesn't, the rain chance and sunset
    /// drop to a second line rather than every part being cut short.
    private func weatherLine(_ forecast: DayForecast) -> some View {
        let main = "\(forecast.summary) · \(forecast.temperatureLabel)"
        var details: [String] = []
        if forecast.precipitationChance > 0 { details.append("\(forecast.precipitationChance)% rain") }
        if let sunset = forecast.sunsetLabel { details.append("sunset \(sunset)") }
        let icon = Image(systemName: forecast.symbol)
            .font(.system(size: 15))
            .foregroundStyle(forecast.isWet ? Brand.rausch : Brand.babu)

        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                icon
                Text(([main] + details).joined(separator: " · ")).metaStyle().fixedSize()
            }
            HStack(alignment: .top, spacing: 8) {
                icon
                VStack(alignment: .leading, spacing: 2) {
                    Text(main).metaStyle()
                    if !details.isEmpty {
                        Text(details.joined(separator: " · ")).captionStyle()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Only shown when something on the day doesn't work, so a good day's
    /// timeline stays quiet.
    @ViewBuilder
    private func fixBanner(_ trip: Trip, stops: [ItineraryStop]) -> some View {
        let troubled = troubledStops(trip, stops: stops)
        if troubled > 0 {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 13))
                    .foregroundStyle(Brand.rausch)
                VStack(alignment: .leading, spacing: 6) {
                    Text(troubled == 1 ? "1 stop doesn't work as planned" : "\(troubled) stops don't work as planned")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Palette.ink)
                    Button("Fix this day") { isFixing = true }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Brand.rausch)
                        .underline()
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(Brand.rausch.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.horizontal, Metric.gutter)
            .padding(.bottom, 16)
        }
    }

    /// Stops the timeline is already warning about: shut, out in the dark, or
    /// without enough time to get there.
    private func troubledStops(_ trip: Trip, stops: [ItineraryStop]) -> Int {
        guard trip.days.indices.contains(dayIndex) else { return 0 }
        let date = trip.days[dayIndex].date
        let forecast = weather.forecast(for: trip, on: date)
        return stops.indices.filter { index in
            let stop = stops[index]
            guard let place = PlaceDirectory.place(id: stop.placeID) else { return false }
            let rushed = index > 0 && travelNote(from: stops[index - 1], to: stop)?.isTight == true
            // The planner holds a booking to its time, so only reaching it is
            // something "Fix this day" can change.
            guard !stop.isBooked else { return rushed }
            return rushed
                || HoursNote.make(on: date, startMinute: stop.startMinute,
                                  durationMinutes: stop.durationMinutes, hours: place.weeklyHours) != nil
                || DaylightNote.make(startMinute: stop.startMinute, durationMinutes: stop.durationMinutes,
                                     category: place.category, forecast: forecast) != nil
        }.count
    }

    /// Where each day starts and ends; tap to set or change it.
    private func lodgingRow(_ trip: Trip) -> some View {
        Button { isChoosingLodging = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "bed.double")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.inkMuted)
                    .frame(width: 20)
                if let lodging = trip.lodging {
                    Text("From \(lodging.name)")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.inkMuted)
                        .lineLimit(1)
                    Text("Change")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .underline()
                } else {
                    Text("Add where you're staying")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .underline()
                }
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Metric.gutter)
        .padding(.bottom, 12)
    }

    /// How hops too long to walk are timed, for every day of the trip.
    private func gettingAroundRow(_ trip: Trip) -> some View {
        Menu {
            Picker("Getting around", selection: Binding(
                get: { trip.gettingAround },
                set: { store.setGettingAround($0, for: tripID) }
            )) {
                ForEach(GettingAround.allCases, id: \.self) { option in
                    Label(option.title, systemImage: option.symbol).tag(option)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: trip.gettingAround.symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.inkMuted)
                    .frame(width: 20, height: 16)
                Text(trip.gettingAround.title)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.inkMuted)
                Text("Change")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .underline()
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Metric.gutter)
        .padding(.bottom, 12)
    }

    // MARK: Helpers

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
            leg = routes.leg(from: a, to: b, by: trip?.gettingAround ?? .transit)
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let stop: ItineraryStop
    let isFirst: Bool
    let isLast: Bool
    /// The itinerary day, for checking the place's opening hours.
    var date: Date?
    var forecast: DayForecast?
    var travelNote: TravelNote?
    /// The stop's place couldn't be looked up, as opposed to still loading.
    var placeFailedToLoad = false
    /// It wasn't looked up because the phone was over its request allowance.
    var placePaused = false
    var onRetry: (() -> Void)?
    let onTap: () -> Void

    private var place: Place? { PlaceDirectory.place(id: stop.placeID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            rowLayout {
                if dynamicTypeSize.isAccessibilitySize {
                    Text(stop.timeLabel)
                        .font(.headline)
                        .foregroundStyle(Palette.ink)
                } else {
                    railColumn
                }
                if let place {
                    card(place)
                } else {
                    placeholderCard
                }
            }
            .padding(.horizontal, Metric.gutter)

            if let travelNote {
                HStack(spacing: 14) {
                    // Keep the connector aligned under the timeline rail.
                    if !dynamicTypeSize.isAccessibilitySize {
                        VStack(spacing: 0) {
                            Rectangle()
                                .fill(Palette.hairline)
                                .frame(width: 1.5, height: 22)
                        }
                        .frame(width: 64)
                    }
                    HStack(spacing: 5) {
                        Image(systemName: travelNote.symbol)
                            .font(.system(size: 11, weight: .medium))
                        Text(travelNote.text)
                            .font(.footnote)
                    }
                    .foregroundStyle(travelNote.isTight ? Brand.rausch : Palette.inkMuted)
                    Spacer()
                }
                .padding(.horizontal, Metric.gutter)
            }
        }
    }

    private var rowLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 14))
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
                    if !dynamicTypeSize.isAccessibilitySize {
                        PlacePhoto(place: place, showsGlyph: false)
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(place.name).cardTitleStyle()
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        Text(place.neighborhood).captionStyle()
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                        HStack(spacing: 6) {
                            // Events have no rating to show.
                            if place.rating > 0 {
                                RatingLabel(rating: place.rating, size: 12)
                                Text("·").foregroundStyle(Palette.inkFaint)
                            }
                            Text(durationLabel).captionStyle()
                            if stop.isBooked {
                                Text("·").foregroundStyle(Palette.inkFaint)
                                Text("Booked").captionStyle()
                            }
                            if stop.remindMe {
                                Image(systemName: "bell.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Brand.rausch)
                            }

                        }
                    }
                    Spacer(minLength: 0)
                }

                // Ahead of daylight: a closed door rules the stop out entirely.
                // Neither applies to a booking, which is trusted over both.
                if !stop.isBooked, let date, let hours = HoursNote.make(
                    on: date,
                    startMinute: stop.startMinute,
                    durationMinutes: stop.durationMinutes,
                    hours: place.weeklyHours
                ) {
                    Label(hours.text, systemImage: hours.symbol)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Brand.rausch)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                }

                if !stop.isBooked, let daylight = DaylightNote.make(
                    startMinute: stop.startMinute,
                    durationMinutes: stop.durationMinutes,
                    category: place.category,
                    forecast: forecast
                ) {
                    Label(daylight.text, systemImage: daylight.symbol)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Brand.rausch)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                }

                if !stop.note.isEmpty {
                    Text(stop.note)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkMuted)
                        .italic()
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                }
            }
            .timelineCard()
        }
        .buttonStyle(.plain)
    }

    /// Holds the stop's slot while its place is looked up, or after the lookup
    /// failed, so a day never silently loses a stop.
    private var placeholderCard: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Palette.surface)
                .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 6) {
                if placeFailedToLoad {
                    Text(placePaused ? "Paused for a moment" : "Couldn't load this place").cardTitleStyle()
                    if placePaused {
                        Text("Too many lookups at once. Try again in a minute.").captionStyle()
                    }
                    HStack(spacing: 16) {
                        Button("Try again") { onRetry?() }
                        Button("Edit stop", action: onTap)
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .underline()
                    .buttonStyle(.plain)
                } else {
                    // Redacted into skeleton bars while the lookup runs.
                    Text("Loading this place").cardTitleStyle()
                    Text(durationLabel).captionStyle()
                }
            }
            Spacer(minLength: 0)
        }
        .redacted(reason: placeFailedToLoad ? [] : .placeholder)
        .timelineCard()
    }

    private var durationLabel: String {
        let h = stop.durationMinutes / 60, m = stop.durationMinutes % 60
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) hr" : "\(h) hr \(m) min"
    }
}

private extension View {
    /// The bordered card every timeline stop sits in.
    func timelineCard() -> some View {
        padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.elevated, in: RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: 1)
            }
            .padding(.bottom, 14)
    }
}
