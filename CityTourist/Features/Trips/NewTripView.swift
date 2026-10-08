import SwiftUI

struct NewTripView: View {
    var presetCityID: String? = nil
    var onCreate: ((Trip) -> Void)? = nil

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var city: City?
    @State private var title = ""
    @State private var isPlanningFirstDay = false
    @State private var startDate = Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now
    @State private var endDate = Calendar.current.date(byAdding: .day, value: 10, to: .now) ?? .now

    private var dayCount: Int {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: startDate),
                                      to: cal.startOfDay(for: endDate)).day ?? 0
        return max(0, days) + 1
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Where are you going?").displayStyle()
                        Text("Get a suggested first day, or start with an empty itinerary.")
                            .metaStyle()
                    }

                    citySection
                    dates
                    nameField
                }
                .padding(.horizontal, Metric.gutter)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .background(Palette.canvas)
            .scrollIndicators(.hidden)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Palette.ink)
                }
            }
            .safeAreaInset(edge: .bottom) {
                StickyBottomBar {
                    VStack(spacing: 12) {
                        PrimaryButton(title: "Plan my first day", isEnabled: city != nil && endDate >= startDate) {
                            isPlanningFirstDay = true
                        }
                        Button("Create empty itinerary") { createTrip(stops: []) }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                            .disabled(city == nil || endDate < startDate)
                    }
                }
            }
            .navigationDestination(isPresented: $isPlanningFirstDay) {
                if let city {
                    FirstDayPlanView(city: city, date: startDate) { createTrip(stops: $0) }
                }
            }
        }
        .onAppear {
            if city == nil {
                city = CityDirectory.city(id: presetCityID ?? store.browsingCityID)
            }
        }
    }

    private func createTrip(stops: [ItineraryStop]) {
        guard let city, endDate >= startDate else { return }
        var trip = store.createTrip(city: city, start: startDate, end: endDate,
                                    title: title.trimmingCharacters(in: .whitespaces))
        if !stops.isEmpty, !trip.days.isEmpty {
            trip.days[0].stops = stops
            store.update(trip)
        }
        onCreate?(trip)
        dismiss()
    }

    private var citySection: some View {
        CitySearchView(
            recents: recentCities,
            selection: city
        ) { picked in
            withAnimation(.snappy(duration: 0.2)) { city = picked }
        }
    }

    /// The preset or currently browsed city, offered as a one-tap recent.
    private var recentCities: [City] {
        var cities = store.recentCities
        let current = CityDirectory.city(id: presetCityID ?? store.browsingCityID)
        if !cities.contains(where: { $0.id == current.id }) { cities.insert(current, at: 0) }
        return cities
    }

    private var dates: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Dates")
            VStack(spacing: 12) {
                DatePicker(selection: $startDate, in: Date.now..., displayedComponents: .date) {
                    Text("Start").bodyStyle()
                }
                Hairline()
                DatePicker(selection: $endDate, in: startDate..., displayedComponents: .date) {
                    Text("End").bodyStyle()
                }
            }
            .tint(Brand.rausch)
            .padding(16)
            .overlay {
                RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: 1)
            }
            Text("\(dayCount) \(dayCount == 1 ? "day" : "days")").captionStyle()
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Trip name")
            TextField(city?.name ?? "Trip name", text: $title)
                .bodyStyle()
                .padding(16)
                .overlay {
                    RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous)
                        .strokeBorder(Palette.hairline, lineWidth: 1)
                }
        }
    }
}

#Preview {
    NewTripView().environment(AppStore(loadFromDisk: false))
        .environment(PlaceCatalog())
}
