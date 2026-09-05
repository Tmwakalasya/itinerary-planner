import SwiftUI

/// "Where to?" — search any city, optionally add dates. Picking a city switches
/// the Explore feed; adding dates on top of it starts a new itinerary, which is
/// the brief's first must-have.
struct SearchSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var selectedCity: City?
    @State private var wantsDates = false
    @State private var startDate = Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now
    @State private var endDate = Calendar.current.date(byAdding: .day, value: 10, to: .now) ?? .now
    @State private var createdTrip: Trip?

    private var canStartTrip: Bool { selectedCity != nil && wantsDates && endDate >= startDate }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    whereCard
                    whenCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Palette.surface)
            .scrollIndicators(.hidden)
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    GlassCircleButton(systemImage: "xmark") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) { bottomBar }
            .navigationDestination(item: $createdTrip) { trip in
                TripDetailView(tripID: trip.id)
            }
        }
        .onAppear {
            // Default to the city already being browsed so the CTA is live,
            // but never hide the search field behind it.
            if selectedCity == nil { selectedCity = store.browsingCity }
        }
    }

    // MARK: Cards

    private var whereCard: some View {
        card {
            VStack(alignment: .leading, spacing: 16) {
                Text("Where to?").displayStyle()

                CitySearchView(
                    recents: store.recentCities,
                    selection: selectedCity
                ) { city in
                    withAnimation(.snappy(duration: 0.2)) { selectedCity = city }
                }
            }
        }
    }

    private var whenCard: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("When").sectionTitleStyle()
                    Spacer()
                    Toggle("", isOn: $wantsDates.animation(.snappy(duration: 0.22)))
                        .labelsHidden()
                        .tint(Brand.rausch)
                }

                if wantsDates {
                    VStack(spacing: 0) {
                        DatePicker(selection: $startDate, in: Date.now..., displayedComponents: .date) {
                            Text("Start").bodyStyle()
                        }
                        Hairline().padding(.vertical, 4)
                        DatePicker(selection: $endDate, in: startDate..., displayedComponents: .date) {
                            Text("End").bodyStyle()
                        }
                    }
                    .tint(Brand.rausch)
                    Text("We'll build one day in your itinerary for each date.")
                        .captionStyle()
                } else {
                    Text("Add dates to turn this into an itinerary you can fill in day by day.")
                        .captionStyle()
                }
            }
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.elevated, in: RoundedRectangle(cornerRadius: Metric.sheetRadius, style: .continuous))
            .floatingShadow(y: 2, radius: 10, opacity: 0.06)
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        StickyBottomBar {
            HStack {
                Button("Clear all") {
                    selectedCity = nil
                    wantsDates = false
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .underline()

                Spacer()

                Button {
                    guard let city = selectedCity else { return }
                    if canStartTrip {
                        createdTrip = store.createTrip(city: city, start: startDate, end: endDate)
                    } else {
                        store.browse(city)
                        dismiss()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: canStartTrip ? "calendar" : "magnifyingglass")
                            .font(.system(size: 15, weight: .bold))
                        Text(canStartTrip ? "Start itinerary" : "Search")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .frame(height: 48)
                    .background(
                        LinearGradient(colors: [Brand.rausch, Brand.rauschDeep],
                                       startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: Metric.buttonRadius, style: .continuous)
                    )
                    .opacity(selectedCity == nil ? 0.4 : 1)
                }
                .buttonStyle(.plain)
                .disabled(selectedCity == nil)
            }
        }
    }
}

#Preview {
    SearchSheet().environment(AppStore(loadFromDisk: false))
        .environment(PlaceCatalog())
}
