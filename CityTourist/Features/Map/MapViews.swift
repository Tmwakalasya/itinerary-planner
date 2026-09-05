import SwiftUI
import MapKit

/// Numbered teardrop marker. Airbnb's map pins are white pills with a dark
/// label; ours carry the stop's position in the day.
struct MapPin: View {
    var number: Int?
    var isSelected: Bool = false

    var body: some View {
        Group {
            if let number {
                Text("\(number)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(isSelected ? Palette.ink : Brand.rausch, in: Circle())
            } else {
                Circle()
                    .fill(Brand.rausch)
                    .frame(width: 18, height: 18)
            }
        }
        .overlay(Circle().strokeBorder(.white, lineWidth: 2.5))
        .floatingShadow(y: 2, radius: 4, opacity: 0.3)
        .scaleEffect(isSelected ? 1.15 : 1)
        .animation(.snappy(duration: 0.2), value: isSelected)
    }
}

/// Everything currently showing on Explore, plotted.
struct CityMapView: View {
    let city: City
    let places: [Place]

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPlaceID: String?

    private var selectedPlace: Place? {
        places.first { $0.id == selectedPlaceID }
    }

    var body: some View {
        NavigationStack {
            Map(initialPosition: .region(MKCoordinateRegion(
                center: city.coordinate.clLocation,
                span: MKCoordinateSpan(latitudeDelta: 0.09, longitudeDelta: 0.09)
            ))) {
                ForEach(places) { place in
                    Annotation(place.name, coordinate: place.coordinate.clLocation) {
                        Button {
                            withAnimation(.snappy) {
                                selectedPlaceID = selectedPlaceID == place.id ? nil : place.id
                            }
                        } label: {
                            PriceMapPin(text: place.priceLabel, isSelected: selectedPlaceID == place.id)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .mapControls { MapCompass() }
            .ignoresSafeArea(edges: .bottom)
            .overlay(alignment: .bottom) {
                if let selectedPlace {
                    NavigationLink(value: selectedPlace) {
                        MapPlaceCard(place: selectedPlace, isSaved: store.isSaved(selectedPlace)) {
                            store.toggleSaved(selectedPlace)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationTitle(city.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }.foregroundStyle(Palette.ink)
                }
            }
            .navigationDestination(for: Place.self) { PlaceDetailView(place: $0) }
        }
    }
}

/// White pill pin with the price inside — Airbnb's signature map marker.
struct PriceMapPin: View {
    let text: String
    var isSelected: Bool

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isSelected ? .white : Palette.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isSelected ? Palette.ink : Palette.elevated, in: Capsule())
            .floatingShadow(y: 2, radius: 5, opacity: 0.22)
            .scaleEffect(isSelected ? 1.08 : 1)
            .animation(.snappy(duration: 0.2), value: isSelected)
    }
}

struct MapPlaceCard: View {
    let place: Place
    let isSaved: Bool
    let onToggleSaved: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            PlacePhoto(place: place, showsGlyph: false)
                .frame(width: 90, height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(place.name).cardTitleStyle().lineLimit(1)
                Text(place.blurb).captionStyle().lineLimit(2)
                RatingLabel(rating: place.rating, reviewCount: place.reviewCount, size: 12)
                Text("\(place.durationLabel) · \(place.priceLabel)").captionStyle()
            }
            Spacer(minLength: 0)
            HeartButton(isSaved: isSaved, size: 20, action: onToggleSaved)
                .padding(.trailing, 4)
        }
        .padding(10)
        .background(Palette.elevated, in: RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous))
        .floatingShadow(y: 4, radius: 16, opacity: 0.18)
    }
}

/// One day of an itinerary drawn in order, with a line joining the stops.
struct ItineraryMapView: View {
    let trip: Trip
    let dayIndex: Int

    @Environment(\.dismiss) private var dismiss
    @State private var selectedStopID: ItineraryStop.ID?

    private var stops: [ItineraryStop] {
        trip.days.indices.contains(dayIndex) ? trip.days[dayIndex].stops : []
    }

    private var resolved: [(stop: ItineraryStop, place: Place)] {
        stops.compactMap { stop in
            PlaceDirectory.place(id: stop.placeID).map { (stop, $0) }
        }
    }

    private var route: [CLLocationCoordinate2D] {
        resolved.map(\.place.coordinate.clLocation)
    }

    var body: some View {
        NavigationStack {
            Map(initialPosition: .region(region)) {
                if route.count > 1 {
                    MapPolyline(coordinates: route)
                        .stroke(Brand.rausch.opacity(0.85),
                                style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [1, 9]))
                }
                ForEach(Array(resolved.enumerated()), id: \.element.stop.id) { index, entry in
                    Annotation(entry.place.name, coordinate: entry.place.coordinate.clLocation) {
                        Button {
                            withAnimation(.snappy) {
                                selectedStopID = selectedStopID == entry.stop.id ? nil : entry.stop.id
                            }
                        } label: {
                            MapPin(number: index + 1, isSelected: selectedStopID == entry.stop.id)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .safeAreaInset(edge: .bottom) { stopCarousel }
            .navigationTitle("Day \(dayIndex + 1)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }.foregroundStyle(Palette.ink)
                }
            }
        }
    }

    private var stopCarousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(resolved.enumerated()), id: \.element.stop.id) { index, entry in
                    Button {
                        withAnimation(.snappy) { selectedStopID = entry.stop.id }
                    } label: {
                        HStack(spacing: 10) {
                            MapPin(number: index + 1, isSelected: selectedStopID == entry.stop.id)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.place.name)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Palette.ink)
                                    .lineLimit(1)
                                Text(entry.stop.timeLabel).captionStyle()
                            }
                        }
                        .padding(12)
                        .frame(width: 210, alignment: .leading)
                        .background(Palette.elevated, in: RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous)
                                .strokeBorder(selectedStopID == entry.stop.id ? Palette.ink : .clear, lineWidth: 1.5)
                        }
                        .floatingShadow(y: 3, radius: 10, opacity: 0.14)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(.thinMaterial)
    }

    private var region: MKCoordinateRegion {
        guard !route.isEmpty else {
            return MKCoordinateRegion(
                center: CityDirectory.city(id: trip.cityID).coordinate.clLocation,
                span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
            )
        }
        let lats = route.map(\.latitude), lons = route.map(\.longitude)
        let center = CLLocationCoordinate2D(
            latitude: (lats.min()! + lats.max()!) / 2,
            longitude: (lons.min()! + lons.max()!) / 2
        )
        // Pad the bounding box so pins aren't flush against the screen edge.
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.01, (lats.max()! - lats.min()!) * 1.6),
            longitudeDelta: max(0.01, (lons.max()! - lons.min()!) * 1.6)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}
