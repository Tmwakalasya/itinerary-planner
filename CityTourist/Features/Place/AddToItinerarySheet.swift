import SwiftUI

/// Puts a discovered place onto a specific day at a specific time — the bridge
/// between browsing and the itinerary.
struct AddToItinerarySheet: View {
    let place: Place

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTripID: Trip.ID?
    @State private var selectedDayIndex = 0
    @State private var startTime = Date()
    @State private var note = ""
    @State private var isCreatingTrip = false

    /// Only trips to this place's city can hold it.
    private var eligibleTrips: [Trip] {
        store.trips.filter { $0.cityID == place.cityID }
    }

    private var selectedTrip: Trip? {
        guard let selectedTripID else { return nil }
        return store.trip(id: selectedTripID)
    }

    var body: some View {
        NavigationStack {
            Group {
                if eligibleTrips.isEmpty {
                    noTripState
                } else {
                    form
                }
            }
            .background(Palette.canvas)
            .navigationTitle("Add to itinerary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Palette.ink)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !eligibleTrips.isEmpty {
                    StickyBottomBar {
                        PrimaryButton(title: "Add to \(selectedTrip?.title ?? "trip")",
                                      isEnabled: selectedTrip != nil) {
                            addStop()
                        }
                    }
                }
            }
            .sheet(isPresented: $isCreatingTrip) {
                NewTripView(presetCityID: place.cityID) { trip in
                    select(trip)
                }
            }
        }
        .presentationDetents([.large])
        .onAppear(perform: prepare)
    }

    // MARK: States

    private var noTripState: some View {
        VStack {
            Spacer()
            EmptyStateView(
                symbol: "suitcase",
                title: "No \(CityDirectory.city(id: place.cityID).name) trip yet",
                message: "Create a trip with your dates and this place will be the first thing on it.",
                actionTitle: "Plan a trip"
            ) {
                isCreatingTrip = true
            }
            Spacer()
        }
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PlaceRow(place: place, trailingText: place.durationLabel)
                    .padding(16)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous))

                tripPicker
                if selectedTrip != nil { dayPicker; timeAndNote }
            }
            .padding(.horizontal, Metric.gutter)
            .padding(.vertical, 20)
        }
        .scrollIndicators(.hidden)
    }

    private var tripPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Trip", actionTitle: "New") { isCreatingTrip = true }
            ForEach(eligibleTrips) { trip in
                Button {
                    withAnimation(.snappy(duration: 0.2)) { select(trip) }
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(trip.title).cardTitleStyle()
                            Text("\(trip.dateRangeLabel) · \(trip.stopCount) stops").captionStyle()
                        }
                        Spacer(minLength: 8)
                        Image(systemName: selectedTripID == trip.id ? "largecircle.fill.circle" : "circle")
                            .font(.system(size: 20))
                            .foregroundStyle(selectedTripID == trip.id ? Brand.rausch : Palette.hairline)
                    }
                    .padding(14)
                    .overlay {
                        RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous)
                            .strokeBorder(selectedTripID == trip.id ? Palette.ink : Palette.hairline,
                                          lineWidth: selectedTripID == trip.id ? 1.5 : 1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var dayPicker: some View {
        if let trip = selectedTrip {
            VStack(alignment: .leading, spacing: 12) {
                Text("Day").sectionTitleStyle()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(trip.days.enumerated()), id: \.element.id) { index, day in
                            Button {
                                withAnimation(.snappy(duration: 0.2)) {
                                    selectedDayIndex = index
                                    startTime = minuteToDate(
                                        store.suggestedStartMinute(tripID: trip.id, dayIndex: index)
                                    )
                                }
                            } label: {
                                Chip(
                                    title: "Day \(index + 1) · \(day.date.formatted(.dateTime.weekday(.abbreviated).day()))",
                                    isSelected: selectedDayIndex == index
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollClipDisabled()
            }
        }
    }

    private var timeAndNote: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Details").sectionTitleStyle()

            DatePicker(selection: $startTime, displayedComponents: .hourAndMinute) {
                Text("Start time").bodyStyle()
            }
            .tint(Brand.rausch)

            // Said here, while the day and time can still change, not only
            // once the stop is on the timeline.
            if let hoursNote {
                Label(hoursNote.text, systemImage: hoursNote.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Brand.rausch)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Note").bodyStyle()
                TextField("Tickets booked, meet at the gate…", text: $note, axis: .vertical)
                    .lineLimit(2...4)
                    .padding(12)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    // MARK: Actions

    private func prepare() {
        guard selectedTripID == nil else { return }
        // A trip that's under way is almost certainly the one being added to.
        if let trip = eligibleTrips.first(where: { todayIndex(in: $0) != nil }) ?? eligibleTrips.first {
            select(trip)
        }
    }

    /// Opens a trip on today if it's under way, since its first days are
    /// already over, at a time that hasn't passed.
    private func select(_ trip: Trip) {
        selectedTripID = trip.id
        selectedDayIndex = todayIndex(in: trip) ?? 0
        startTime = minuteToDate(store.suggestedStartMinute(tripID: trip.id, dayIndex: selectedDayIndex))
    }

    private func todayIndex(in trip: Trip) -> Int? {
        trip.days.firstIndex { Calendar.current.isDateInToday($0.date) }
    }

    private func addStop() {
        guard let trip = selectedTrip else { return }
        store.addStop(place: place, to: trip.id, dayIndex: selectedDayIndex,
                      startMinute: minute(of: startTime), note: note)
        dismiss()
    }

    /// Whether the place is open on the chosen day at the chosen time.
    private var hoursNote: HoursNote? {
        guard let trip = selectedTrip, trip.days.indices.contains(selectedDayIndex) else { return nil }
        return HoursNote.make(on: trip.days[selectedDayIndex].date,
                              startMinute: minute(of: startTime),
                              durationMinutes: place.typicalMinutes,
                              hours: place.weeklyHours)
    }

    private func minute(of time: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: time)
        return (components.hour ?? 9) * 60 + (components.minute ?? 0)
    }

    private func minuteToDate(_ minute: Int) -> Date {
        Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: .now) ?? .now
    }
}

#Preview {
    AddToItinerarySheet(place: SampleData.places[0])
        .environment(AppStore(loadFromDisk: false))
        .environment(PlaceCatalog())
}
