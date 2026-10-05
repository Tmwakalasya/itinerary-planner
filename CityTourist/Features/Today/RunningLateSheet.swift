import SwiftUI

/// "Running late?" Re-plans what's left of today around the delay. Gaps in
/// the day absorb it where they can, so only the stops that have to move do,
/// and a place that would now be shut can swap ahead of one that won't be.
struct RunningLateSheet: View {
    let tripID: Trip.ID
    let dayIndex: Int

    @Environment(AppStore.self) private var store
    @Environment(WeatherStore.self) private var weather
    @Environment(RouteStore.self) private var routes
    @Environment(\.dismiss) private var dismiss

    @State private var delay = 30
    @State private var keepOrder = false
    /// Fixed when the sheet opens, so the plan doesn't shift while it's read.
    @State private var now = Date.now.minuteOfDay

    private static let delays = [10, 20, 30, 45, 60, 90]

    private var trip: Trip? { store.trip(id: tripID) }

    var body: some View {
        let day = trip.flatMap { $0.days.indices.contains(dayIndex) ? $0.days[dayIndex] : nil }
        let remaining = day?.stops.filter { $0.startMinute > now } ?? []
        let best = proposal(for: remaining, on: day, keepOrder: false)
        let chosen = keepOrder ? proposal(for: remaining, on: day, keepOrder: true) : best

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    delayPicker
                    if let day, let chosen {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(summary(chosen)).metaStyle()
                            if best?.reorders == true {
                                Toggle(isOn: $keepOrder.animation(.snappy(duration: 0.2))) {
                                    Text("Keep my order").bodyStyle()
                                }
                                .tint(Brand.rausch)
                            }
                        }
                        PlanProposalList(proposal: chosen, stops: remaining, date: day.date,
                                         forecast: trip.flatMap { weather.forecast(for: $0, on: day.date) })
                    } else {
                        Text("Nothing else is planned today, so there's nothing to move.").metaStyle()
                    }
                }
                .padding(.horizontal, Metric.gutter)
                .padding(.vertical, 20)
            }
            .background(Palette.canvas)
            .scrollIndicators(.hidden)
            .navigationTitle("Running late")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Palette.ink)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let chosen, chosen.isChange {
                    StickyBottomBar {
                        PrimaryButton(title: "Update today's plan") {
                            store.retime(chosen.changes, in: tripID, dayIndex: dayIndex)
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    private var delayPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How far behind are you?").sectionTitleStyle()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Self.delays, id: \.self) { minutes in
                        Button {
                            withAnimation(.snappy(duration: 0.18)) { delay = minutes }
                        } label: {
                            Chip(title: "\(minutes) min", isSelected: delay == minutes)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollClipDisabled()
        }
    }

    /// You reach the next stop `delay` minutes after it was due; the planner
    /// works out what that does to the rest.
    private func proposal(for stops: [ItineraryStop], on day: ItineraryDay?, keepOrder: Bool) -> PlanProposal? {
        guard let trip, let day, let next = stops.first else { return nil }
        let planner = DayPlanning.planner(for: stops, on: day.date, lodging: nil,
                                          forecast: weather.forecast(for: trip, on: day.date),
                                          routes: routes, availableFrom: next.startMinute + delay)
        return PlanProposal(planner: planner, stops: stops, keepOrder: keepOrder)
    }

    private func summary(_ proposal: PlanProposal) -> String {
        let moved = proposal.changes.count
        let total = proposal.after.visits.count
        var line: String
        switch moved {
        case 0: line = "The gaps in your day absorb it, so nothing has to move."
        case total: line = total == 1 ? "Your next stop moves later." : "All \(total) stops change time."
        default: line = "\(moved) of \(total) stops change time; the rest absorb the delay."
        }
        if proposal.reorders { line += " Swapping the order keeps more of the day working." }
        let broken = proposal.after.fixableProblems
        if broken > 0 { line += broken == 1 ? " One stop no longer works." : " \(broken) stops no longer work." }
        return line
    }
}
