import SwiftUI

/// Browse the city's places from inside an itinerary and drop one straight onto
/// the day you're looking at.
struct AddPlaceSheet: View {
    let tripID: Trip.ID
    let dayIndex: Int
    /// Opens the sheet already filtered, e.g. to museums on a wet day.
    var initialCategory: PlaceCategory? = nil

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private var trip: Trip? { store.trip(id: tripID) }

    private var alreadyOnThisDay: Set<String> {
        guard let trip, trip.days.indices.contains(dayIndex) else { return [] }
        return Set(trip.days[dayIndex].stops.map(\.placeID))
    }

    var body: some View {
        if let trip {
            PlaceSearchView(city: CityDirectory.city(id: trip.cityID),
                            title: "Add to day \(dayIndex + 1)",
                            initialCategory: initialCategory,
                            excludedPlaceIDs: alreadyOnThisDay,
                            onAdd: add)
        }
    }

    private func add(_ place: Place) {
        let minute = store.suggestedStartMinute(tripID: tripID, dayIndex: dayIndex)
        store.addStop(place: place, to: tripID, dayIndex: dayIndex, startMinute: minute)
        dismiss()
    }
}
