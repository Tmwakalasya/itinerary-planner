import SwiftUI

/// "1 hr 40 min free before Tram 28", with a few places that fit and one tap
/// each to drop them into the gap.
struct FreeTimeCard: View {
    let gap: FreeTime
    let suggestions: [GapSuggestion]
    /// The stop after the gap, if there is one.
    var nextName: String?
    /// Shown as "More places" when set, for browsing beyond these few.
    var onBrowse: (() -> Void)? = nil
    let onAdd: (GapSuggestion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Label(title, systemImage: "sparkles")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Text("Open then, and near enough to fit.").captionStyle()
            }

            ForEach(suggestions) { suggestion in
                HStack(spacing: 12) {
                    PlacePhoto(place: suggestion.place, showsGlyph: false)
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(suggestion.place.name).cardTitleStyle().lineLimit(1)
                        Text(timeRange(suggestion)).captionStyle().lineLimit(1)
                        if suggestion.travelMinutes > 0 {
                            Text("\(suggestion.travelMinutes) min away").captionStyle().lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    Button {
                        onAdd(suggestion)
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(Brand.rausch)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add \(suggestion.place.name) at \(DayForecast.clockLabel(suggestion.start))")
                }
            }

            if let onBrowse {
                Button("More places", action: onBrowse)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .underline()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous))
    }

    private var title: String {
        guard let nextName else { return "Free for the rest of the day" }
        return "\(Self.duration(gap.minutes)) free before \(nextName)"
    }

    /// "1:40 PM – 2:55 PM": the visit's length, without spelling it out.
    private func timeRange(_ suggestion: GapSuggestion) -> String {
        "\(DayForecast.clockLabel(suggestion.start)) – \(DayForecast.clockLabel(suggestion.start + suggestion.place.typicalMinutes))"
    }

    private static func duration(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) hr" : "\(h) hr \(m) min"
    }
}
