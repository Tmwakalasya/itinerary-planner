import SwiftUI

/// Edit one stop: time, how long you'll stay, a note, and a reminder.
struct StopEditorSheet: View {
    let tripID: Trip.ID
    let dayIndex: Int
    let stop: ItineraryStop

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var startTime = Date()
    @State private var durationMinutes = 60
    @State private var note = ""
    @State private var remindMe = false

    private var place: Place? { PlaceDirectory.place(id: stop.placeID) }

    private let durationChoices = [30, 45, 60, 90, 120, 150, 180, 240, 300]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let place {
                        NavigationLink {
                            PlaceDetailView(place: place)
                        } label: {
                            HStack {
                                PlaceRow(place: place)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Palette.inkFaint)
                            }
                            .padding(14)
                            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        DatePicker(selection: $startTime, displayedComponents: .hourAndMinute) {
                            Text("Start time").bodyStyle()
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("How long").bodyStyle()
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(durationChoices, id: \.self) { minutes in
                                        Button {
                                            withAnimation(.snappy(duration: 0.18)) { durationMinutes = minutes }
                                        } label: {
                                            Chip(title: label(for: minutes), isSelected: durationMinutes == minutes)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .scrollClipDisabled()
                        }

                        Toggle(isOn: $remindMe) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Remind me").bodyStyle()
                                Text("A nudge 30 minutes before").captionStyle()
                            }
                        }
                        .tint(Brand.rausch)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Note").bodyStyle()
                            TextField("Booking reference, who's meeting you…", text: $note, axis: .vertical)
                                .lineLimit(3...6)
                                .padding(12)
                                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                    .tint(Brand.rausch)

                    Button(role: .destructive) {
                        removeStop()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "trash")
                            Text("Remove from this day")
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Brand.rausch)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .overlay {
                            RoundedRectangle(cornerRadius: Metric.buttonRadius, style: .continuous)
                                .strokeBorder(Brand.rausch.opacity(0.4), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, Metric.gutter)
                .padding(.vertical, 20)
            }
            .background(Palette.canvas)
            .scrollIndicators(.hidden)
            .navigationTitle(place?.name ?? "Stop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Palette.ink)
                }
            }
            .safeAreaInset(edge: .bottom) {
                StickyBottomBar {
                    PrimaryButton(title: "Save") { save() }
                }
            }
        }
        .onAppear(perform: load)
    }

    private func label(for minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) hr" : "\(h)h \(m)m"
    }

    private func load() {
        startTime = Calendar.current.date(bySettingHour: stop.startMinute / 60,
                                          minute: stop.startMinute % 60, second: 0, of: .now) ?? .now
        durationMinutes = stop.durationMinutes
        note = stop.note
        remindMe = stop.remindMe
    }

    private func save() {
        var updated = stop
        let components = Calendar.current.dateComponents([.hour, .minute], from: startTime)
        updated.startMinute = (components.hour ?? 9) * 60 + (components.minute ?? 0)
        updated.durationMinutes = durationMinutes
        updated.note = note
        updated.remindMe = remindMe
        if remindMe { store.requestNotificationPermission() }
        store.updateStop(updated, in: tripID, dayIndex: dayIndex)
        dismiss()
    }

    private func removeStop() {
        guard let trip = store.trip(id: tripID), trip.days.indices.contains(dayIndex),
              let index = trip.days[dayIndex].stops.firstIndex(where: { $0.id == stop.id })
        else { return }
        store.removeStops(at: IndexSet(integer: index), in: tripID, dayIndex: dayIndex)
        dismiss()
    }
}
