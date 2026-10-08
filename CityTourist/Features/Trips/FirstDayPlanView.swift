import SwiftUI

/// Everything stays local to this preview until the traveller accepts it.
struct FirstDayPlanView: View {
    let city: City
    let date: Date
    let onAccept: ([ItineraryStop]) -> Void

    @Environment(PlaceCatalog.self) private var catalog
    @State private var interests: Set<PlaceCategory> = [.attraction, .museum]
    @State private var pace: FirstDayPlanner.Pace = .relaxed
    @State private var mustSeeID: String? = nil
    @State private var proposal: [FirstDayPlanner.Suggestion]? = nil
    @State private var places: [Place] = []
    @State private var loading = true
    @State private var sourceNote = ""
    @State private var message: String?
    @State private var skipped: Set<String> = []

    private var planner: FirstDayPlanner {
        FirstDayPlanner(city: city, date: date, interests: interests, pace: pace,
                        availableFrom: Calendar.current.isDateInToday(date) ? max(540, Date.now.minuteOfDay + 5) : 540)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("A first day in \(city.name)").displayStyle()
                    Text(date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())).metaStyle()
                    Text("Start around the city centre. Pick what you enjoy and leave the timing to us.").metaStyle()
                }
                preferences
                if loading {
                    ProgressView("Finding places…")
                } else {
                    Text(sourceNote).captionStyle()
                    if let proposal {
                        preview(proposal)
                    }
                }
                if let message {
                    Text(message).metaStyle().accessibilityIdentifier("firstDayMessage")
                }
            }
            .padding(Metric.gutter)
            .padding(.bottom, 24)
        }
        .background(Palette.canvas)
        .navigationTitle("Plan my first day")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            StickyBottomBar {
                if let proposal, !proposal.isEmpty {
                    PrimaryButton(title: "Use this day") {
                        // If time has passed while previewing today's plan, ask
                        // for a fresh proposal instead of saving past stops.
                        if Calendar.current.isDateInToday(date), proposal[0].start < Date.now.minuteOfDay {
                            self.proposal = nil
                            message = "The first stop's time has passed. Suggest a fresh day."
                        } else {
                            onAccept(proposal.map(\.stop))
                        }
                    }
                } else {
                    PrimaryButton(title: "Suggest a day", isEnabled: !loading && !interests.isEmpty && !places.isEmpty) {
                        generate()
                    }
                }
            }
        }
        .task { await loadPlaces() }
        .onChange(of: interests) { _, _ in reset() }
        .onChange(of: pace) { _, _ in reset() }
    }

    private var preferences: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeader(title: "What sounds good?")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], alignment: .leading, spacing: 10) {
                ForEach(FirstDayPlanner.interests) { interest in
                    Button {
                        if interests.contains(interest) { interests.remove(interest) }
                        else { interests.insert(interest) }
                    } label: {
                        Label(interest.title, systemImage: interest.symbol)
                            .font(.system(size: 14, weight: .medium))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .foregroundStyle(interests.contains(interest) ? Color.white : Palette.ink)
                            .background(interests.contains(interest) ? Brand.rausch : Palette.surface,
                                        in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(interests.contains(interest) ? .isSelected : [])
                }
            }
            Picker("Pace", selection: $pace) {
                ForEach(FirstDayPlanner.Pace.allCases) { pace in Text(pace.title).tag(pace) }
            }
            .pickerStyle(.segmented)
            Text("Up to \(pace.slots.count) stops, including lunch, with \(pace.buffer)-minute breathing room between visits. Finish by 6 pm.").captionStyle()
            if !places.isEmpty {
                Picker("One must-see", selection: Binding(get: { mustSeeID }, set: { mustSeeID = $0; reset() })) {
                    Text("Choose for me").tag(String?.none)
                    ForEach(places.filter { $0.category != .nightlife && $0.event == nil }.sorted { $0.name < $1.name }) { place in
                        Text(place.name).tag(Optional(place.id))
                    }
                }
                .tint(Brand.rausch)
            }
        }
    }

    @ViewBuilder
    private func preview(_ suggestions: [FirstDayPlanner.Suggestion]) -> some View {
        if suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("No day fits yet").sectionTitleStyle()
                Text(mustSeeID == nil
                     ? "Try other interests or another date. We'll leave space rather than suggest a visit that doesn't fit."
                     : "Your must-see doesn't fit the available hours. Try another date or choose another place.").metaStyle()
            }
        } else {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(title: "Your day, ready to adjust")
                Text("\(suggestions.count) of up to \(pace.slots.count) stops. Travel times are estimates for walking and transit; check routes and opening hours before leaving.").captionStyle()
                ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                    proposalCard(suggestion, index: index, suggestions: suggestions)
                }
            }
        }
    }

    private func proposalCard(_ suggestion: FirstDayPlanner.Suggestion, index: Int,
                              suggestions: [FirstDayPlanner.Suggestion]) -> some View {
        let previous = index == 0 ? city.coordinate : suggestions[index - 1].place.coordinate
        let hop = TravelEstimate.minutes(from: previous, to: suggestion.place.coordinate)
        return VStack(alignment: .leading, spacing: 10) {
            Text("About \(hop) min from \(index == 0 ? "the city centre" : "the previous stop")").captionStyle()
            HStack(alignment: .top, spacing: 12) {
                PlacePhoto(place: suggestion.place, showsGlyph: false)
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 4) {
                    Text(suggestion.place.name).cardTitleStyle()
                    Text("\(DayForecast.clockLabel(suggestion.start)) · \(suggestion.place.durationLabel)").metaStyle()
                    Text(suggestion.reason).captionStyle()
                    Text(suggestion.place.weeklyHours == nil ? "Opening hours unknown" : "Fits listed opening hours")
                        .captionStyle()
                }
            }
            HStack(spacing: 24) {
                if suggestion.id != mustSeeID {
                    Button("Swap") {
                        if let replacement = planner.replacing(suggestion.id, in: suggestions, among: places, excluding: skipped) {
                            skipped.insert(suggestion.id)
                            proposal = replacement
                            message = nil
                        } else {
                            message = "No other place fits this slot and your interests. Try removing it or changing your preferences."
                        }
                    }
                    .accessibilityLabel("Swap \(suggestion.place.name)")
                }
                Button("Remove", role: .destructive) {
                    proposal = suggestions.filter { $0.id != suggestion.id }
                    if suggestion.id == mustSeeID { mustSeeID = nil }
                    message = nil
                }
                .accessibilityLabel("Remove \(suggestion.place.name)")
            }
            .font(.system(size: 14, weight: .semibold))
            .tint(Brand.rausch)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metric.cardRadius))
    }

    private func reset() {
        proposal = nil
        message = nil
        skipped = []
    }

    private func generate() {
        message = nil
        skipped = []
        proposal = planner.propose(among: places, mustSee: places.first { $0.id == mustSeeID })
    }

    private func loadPlaces() async {
        await catalog.load(city: city)
        guard !Task.isCancelled else { return }
        // Capture one city's results, since Explore shares the catalog's state.
        places = catalog.places(in: city.id).filter { $0.cityID == city.id }
        switch catalog.state {
        case .failed:
            sourceNote = "Live places couldn't be loaded. Using available places for this city."
        default:
            sourceNote = catalog.source.isLive ? "Places from Google Places" : "Sample places — a starting point to explore"
        }
        if places.isEmpty {
            message = "No places are available for this city. Go back to choose a sample city, or create an empty itinerary."
        }
        loading = false
    }
}
