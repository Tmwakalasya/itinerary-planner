import SwiftUI

/// The planner's best order for one day, set against what's planned, to take
/// or leave. A place that's shut all day can't be fixed by any order, so it's
/// offered a day of the trip when it's open instead.
struct FixDaySheet: View {
    let tripID: Trip.ID
    let dayIndex: Int

    @Environment(AppStore.self) private var store
    @Environment(WeatherStore.self) private var weather
    @Environment(RouteStore.self) private var routes
    @Environment(\.dismiss) private var dismiss

    @State private var proposal: PlanProposal?

    private var trip: Trip? { store.trip(id: tripID) }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let trip, trip.days.indices.contains(dayIndex), let proposal {
                    content(trip, trip.days[dayIndex], proposal)
                }
            }
            .background(Palette.canvas)
            .scrollIndicators(.hidden)
            .navigationTitle("Fix this day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Palette.ink)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let proposal, proposal.isChange {
                    StickyBottomBar {
                        PrimaryButton(title: "Use this plan") {
                            store.applyPlan(proposal.changes, in: tripID, dayIndex: dayIndex,
                                           message: "Day updated")
                            dismiss()
                        }
                    }
                }
            }
        }
        .onAppear(perform: plan)
    }

    private func plan() {
        guard let trip, trip.days.indices.contains(dayIndex) else { return }
        let day = trip.days[dayIndex]
        let planner = DayPlanning.planner(for: day.stops, on: day.date, lodging: trip.lodging,
                                          forecast: weather.forecast(for: trip, on: day.date), routes: routes)
        proposal = PlanProposal(planner: planner, stops: day.stops)
    }

    private func content(_ trip: Trip, _ day: ItineraryDay, _ proposal: PlanProposal) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                if proposal.isChange {
                    Text(proposal.summary.isEmpty ? "A better order" : proposal.summary)
                        .sectionTitleStyle()
                    Text("Your times stay put and stops swap between them. One only moves later when you couldn't get there sooner.")
                        .metaStyle()
                } else {
                    Text("This order already works best").sectionTitleStyle()
                    Text("Nothing a different order would improve.").metaStyle()
                }
            }

            PlanProposalList(proposal: proposal, stops: day.stops, date: day.date,
                             forecast: weather.forecast(for: trip, on: day.date))

            closedAllDay(trip, day, proposal)

            Text(estimateNote(trip)).captionStyle()
        }
        .padding(.horizontal, Metric.gutter)
        .padding(.vertical, 20)
    }

    /// Stops no order can save, each with the trip's days when it's open.
    @ViewBuilder
    private func closedAllDay(_ trip: Trip, _ day: ItineraryDay, _ proposal: PlanProposal) -> some View {
        let shut = proposal.after.visits.filter { $0.problem == .closedAllDay }
        ForEach(shut, id: \.id) { visit in
            if let stop = day.stops.first(where: { $0.id == visit.id }),
               let place = PlaceDirectory.place(id: stop.placeID) {
                let openDays = DayPlanning.openDays(for: place, in: trip, besides: dayIndex)
                VStack(alignment: .leading, spacing: 10) {
                    Label("\(place.name) is closed that day", systemImage: "xmark.circle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Brand.rausch)
                    if let target = openDays.first {
                        Button("Move it to Day \(target + 1), \(dayLabel(trip.days[target].date))") {
                            store.moveStop(stop.id, in: tripID, from: dayIndex, to: target)
                            plan()
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .underline()
                    } else {
                        Text("It isn't open on any other day of this trip.").captionStyle()
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Brand.rausch.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    private func estimateNote(_ trip: Trip) -> String {
        let note = "Hops are timed with Apple Maps where the app has measured them, and estimated where it hasn't"
        guard let lodging = trip.lodging else { return note + "." }
        return note + ", including to and from \(lodging.name)."
    }

    private func dayLabel(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day())
    }
}
