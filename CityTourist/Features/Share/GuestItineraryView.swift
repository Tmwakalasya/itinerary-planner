import SwiftUI

/// What someone opening the share link sees: the whole plan, read-only, with a
/// prompt to sign up if they want to make it their own.
struct GuestItineraryView: View {
    let trip: Trip

    @Environment(\.dismiss) private var dismiss

    private var city: City { CityDirectory.city(id: trip.cityID) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    PlacePhoto(seed: "trip-\(trip.cityID)", category: .attraction,
                       photoURL: CityDirectory.city(id: trip.cityID).photoURL)
                        .frame(height: 220)
                        .clipped()
                        .overlay(alignment: .bottomLeading) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(trip.title)
                                    .font(.system(size: 28, weight: .bold))
                                    .tracking(-0.6)
                                Text("\(trip.dateRangeLabel) · \(city.country)")
                                    .font(.system(size: 14, weight: .medium))
                                    .opacity(0.92)
                            }
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.4), radius: 10, y: 2)
                            .padding(Metric.gutter)
                        }

                    VStack(alignment: .leading, spacing: 28) {
                        Label("Shared itinerary · view only", systemImage: "eye")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Palette.inkMuted)

                        ForEach(Array(trip.days.enumerated()), id: \.element.id) { index, day in
                            if !day.isEmpty {
                                VStack(alignment: .leading, spacing: 14) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Day \(index + 1)")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(Brand.rausch)
                                            .textCase(.uppercase)
                                            .tracking(0.8)
                                        Text(day.date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                                            .sectionTitleStyle()
                                    }
                                    ForEach(day.stops) { stop in
                                        if let place = PlaceDirectory.place(id: stop.placeID) {
                                            HStack(alignment: .top, spacing: 12) {
                                                Text(stop.timeLabel)
                                                    .font(.system(size: 13, weight: .semibold))
                                                    .monospacedDigit()
                                                    .foregroundStyle(Palette.inkMuted)
                                                    .lineLimit(1)
                                                    .frame(width: 70, alignment: .leading)
                                                    .padding(.top, 2)
                                                VStack(alignment: .leading, spacing: 3) {
                                                    Text(place.name).cardTitleStyle()
                                                    Text(place.blurb).captionStyle()
                                                    if !stop.note.isEmpty {
                                                        Text(stop.note)
                                                            .font(.system(size: 13))
                                                            .italic()
                                                            .foregroundStyle(Palette.inkMuted)
                                                    }
                                                }
                                                Spacer(minLength: 0)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Metric.gutter)
                    .padding(.vertical, 24)
                }
            }
            .background(Palette.canvas)
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    GlassCircleButton(systemImage: "xmark") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                StickyBottomBar {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Want to edit this?").cardTitleStyle()
                            Text("Sign up to save your own copy").captionStyle()
                        }
                        Spacer()
                        Text("Sign up")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .frame(height: 44)
                            .background(
                                LinearGradient(colors: [Brand.rausch, Brand.rauschDeep],
                                               startPoint: .leading, endPoint: .trailing),
                                in: RoundedRectangle(cornerRadius: Metric.buttonRadius, style: .continuous)
                            )
                    }
                }
            }
        }
    }
}
