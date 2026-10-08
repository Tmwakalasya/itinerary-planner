import SwiftUI

/// One event in the trip day's "What's on" row.
struct EventCard: View {
    let place: Place

    private static let width: CGFloat = 220

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PlacePhoto(place: place, showsGlyph: false)
                .frame(width: Self.width, height: 124)
                .clipShape(RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(place.name).cardTitleStyle().lineLimit(2)
                if let event = place.event {
                    Text("\(DayForecast.clockLabel(event.startMinute)) · \(event.venue)")
                        .captionStyle()
                        .lineLimit(1)
                }
            }
        }
        .frame(width: Self.width, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// An event's details, with tickets on Ticketmaster and, when there's a trip
/// day to put it on, adding it there as a booked stop at its start time.
struct EventDetailView: View {
    let place: Place
    /// Where "Add" puts it. Nil when it's opened from a stop already planned.
    var tripID: Trip.ID? = nil
    var dayIndex: Int? = nil

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PlacePhoto(place: place)
                    .frame(height: 220)
                    .clipped()
                if let event = place.event {
                    details(event)
                        .padding(.horizontal, Metric.gutter)
                        .padding(.vertical, 20)
                }
            }
        }
        .background(Palette.canvas)
        .scrollIndicators(.hidden)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if tripID != nil {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }.foregroundStyle(Palette.ink)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let tripID, let dayIndex, let event = place.event {
                StickyBottomBar {
                    if isPlanned(in: tripID, dayIndex: dayIndex) {
                        PrimaryButton(title: "On this day's plan", isEnabled: false) {}
                    } else {
                        PrimaryButton(title: "Add to Day \(dayIndex + 1) at \(DayForecast.clockLabel(event.startMinute))") {
                            // Booked: the planner works around it rather than moving it.
                            store.addStop(place: place, to: tripID, dayIndex: dayIndex,
                                          startMinute: event.startMinute, isBooked: true)
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    private func details(_ event: EventInfo) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(event.kind)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Brand.rausch)
                    .textCase(.uppercase)
                    .tracking(0.8)
                Text(place.name)
                    .font(.title2.weight(.bold))
                    .tracking(-0.4)
                    .foregroundStyle(Palette.ink)
                Text(when(event)).metaStyle()
            }

            Hairline()

            VStack(alignment: .leading, spacing: 12) {
                Label(event.venue, systemImage: "mappin.and.ellipse")
                Label("About \(duration(place.typicalMinutes))", systemImage: "clock")
                if let price = event.price {
                    Label(price, systemImage: "ticket")
                }
            }
            .font(.system(size: 15))
            .foregroundStyle(Palette.ink)

            if let url = event.ticketURL {
                Link(destination: url) {
                    Label("Tickets on Ticketmaster", systemImage: "arrow.up.right.square")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .underline()
                }
            }

            Text("Event details from Ticketmaster. Times are the venue's local time.")
                .captionStyle()
        }
    }

    private func isPlanned(in tripID: Trip.ID, dayIndex: Int) -> Bool {
        guard let trip = store.trip(id: tripID), trip.days.indices.contains(dayIndex) else { return false }
        return trip.days[dayIndex].stops.contains { $0.placeID == place.id }
    }

    /// "Thursday, October 8 · 8:00 PM"
    private func when(_ event: EventInfo) -> String {
        let time = DayForecast.clockLabel(event.startMinute)
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: event.localDate) else { return time }
        return "\(date.formatted(.dateTime.weekday(.wide).month(.wide).day())) · \(time)"
    }

    private func duration(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) hr" : "\(h) hr \(m) min"
    }
}
