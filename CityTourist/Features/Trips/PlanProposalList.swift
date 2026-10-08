import SwiftUI

/// A re-planned day, stop by stop: the new time, the old one struck through
/// when it changed, and anything still wrong at the new time.
struct PlanProposalList: View {
    let proposal: PlanProposal
    let stops: [ItineraryStop]
    let date: Date
    var forecast: DayForecast?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(proposal.after.visits, id: \.id) { visit in
                if let stop = stops.first(where: { $0.id == visit.id }) {
                    row(stop, visit: visit)
                    Hairline()
                }
            }
        }
    }

    private func row(_ stop: ItineraryStop, visit: DayPlanner.Visit) -> some View {
        let start = visit.start
        let place = PlaceDirectory.place(id: stop.placeID)
        let oldStart = proposal.planned[stop.id] ?? start
        let moved = oldStart != start

        return HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(DayForecast.clockLabel(start))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(moved ? Brand.rausch : Palette.ink)
                if moved {
                    Text(DayForecast.clockLabel(oldStart))
                        .font(.system(size: 12))
                        .strikethrough()
                        .foregroundStyle(Palette.inkFaint)
                }
            }
            .monospacedDigit()
            .lineLimit(1)
            .frame(width: 72, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(place?.name ?? "Place unavailable").cardTitleStyle().lineLimit(1)
                Text(Self.duration(stop.durationMinutes) + (stop.isBooked ? " · Booked" : "")).captionStyle()
                if let warning = warning(stop, visit: visit, place: place) {
                    Label(warning.text, systemImage: warning.symbol)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Brand.rausch)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
    }

    /// A booking's time stands whatever the place's usual hours say, so the
    /// only thing to warn about is getting there late.
    private func warning(_ stop: ItineraryStop, visit: DayPlanner.Visit,
                         place: Place?) -> (text: String, symbol: String)? {
        if case .lateForBooking(let minutes) = visit.problem {
            return ("\(minutes) min late for your booking", "clock.badge.exclamationmark")
        }
        guard let place, !stop.isBooked else { return nil }
        return VisitWarning.make(place: place, on: date, start: visit.start,
                                 minutes: stop.durationMinutes, forecast: forecast)
    }

    private static func duration(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) hr" : "\(h) hr \(m) min"
    }
}
