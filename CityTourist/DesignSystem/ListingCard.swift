import SwiftUI

/// The Explore feed card: full-bleed photo, heart in the corner, then a tight
/// four-line stack of title, subtitle, meta and price — with the rating pulled
/// out to the right of the title, exactly as Airbnb sets it.
struct ListingCard: View {
    let place: Place
    let isSaved: Bool
    var badge: String? = nil
    let onToggleSaved: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PlacePhoto(place: place)
                .aspectRatio(Metric.photoAspect, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    HeartButton(isSaved: isSaved, action: onToggleSaved)
                        .padding(12)
                }
                .overlay(alignment: .topLeading) {
                    if let badge {
                        Text(badge)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Palette.onPhotoInk)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Palette.onPhoto, in: Capsule())
                            .padding(12)
                    }
                }

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(place.name)
                        .cardTitleStyle()
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    RatingLabel(rating: place.rating)
                }
                Text(place.blurb)
                    .metaStyle()
                    .lineLimit(1)
                // With live data the third line carries opening status; with
                // sample data there is none, so it falls back to the area.
                HStack(spacing: 5) {
                    Text(place.durationLabel).metaStyle()
                    Text("·").foregroundStyle(Palette.inkFaint)
                    if let open = place.openLabel {
                        Text(open)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(place.isOpenNow == false ? Brand.rausch : Brand.babu)
                    } else {
                        Text(place.neighborhood).metaStyle()
                    }
                }
                .lineLimit(1)
                Text(place.priceLabel)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .padding(.top, 2)
            }
        }
        .contentShape(Rectangle())
    }
}

/// Compact horizontal variant used inside itineraries and the saved grid.
struct PlaceRow: View {
    let place: Place
    var trailingText: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            PlacePhoto(place: place, showsGlyph: false)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(place.name).cardTitleStyle().lineLimit(1)
                Text(place.blurb).captionStyle().lineLimit(1)
            }
            Spacer(minLength: 8)
            if let trailingText {
                Text(trailingText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.inkMuted)
            }
        }
    }
}
