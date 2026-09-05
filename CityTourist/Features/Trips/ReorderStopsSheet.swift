import SwiftUI

/// Drag to reorder, swipe to delete. Times stay where they are and slide onto
/// whichever stop lands in that position, so the day never ends up out of order.
struct ReorderStopsSheet: View {
    let tripID: Trip.ID
    let dayIndex: Int

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private var stops: [ItineraryStop] {
        guard let trip = store.trip(id: tripID), trip.days.indices.contains(dayIndex) else { return [] }
        return trip.days[dayIndex].stops
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(stops) { stop in
                        if let place = PlaceDirectory.place(id: stop.placeID) {
                            HStack(spacing: 12) {
                                Text(stop.timeLabel)
                                    .font(.system(size: 13, weight: .semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(Palette.inkMuted)
                                    .lineLimit(1)
                                    .frame(width: 72, alignment: .leading)
                                PlaceRow(place: place)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .onMove { source, destination in
                        store.moveStops(from: source, to: destination, in: tripID, dayIndex: dayIndex)
                    }
                    .onDelete { offsets in
                        store.removeStops(at: offsets, in: tripID, dayIndex: dayIndex)
                    }
                } footer: {
                    Text("Times stay in order — move a place and it takes that slot's time.")
                }
            }
            .listStyle(.plain)
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Reorder day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                }
            }
        }
    }
}
