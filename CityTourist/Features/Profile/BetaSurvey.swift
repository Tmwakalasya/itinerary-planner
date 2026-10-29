import SwiftUI

/// The beta survey on the launch site. Its link carries the build and,
/// after a trip, the city, so each answer says what it's about.
enum BetaSurvey {
    static let base = URL(string: "https://citytourist.pages.dev/feedback")!

    /// How long after a trip ends the Trips list offers the survey.
    static let windowDays = 7

    @MainActor
    static func url(trip: Trip? = nil) -> URL {
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        var items = [URLQueryItem(name: "v", value: ProfileView.version)]
        if let trip {
            items.append(URLQueryItem(name: "trip", value: CityDirectory.city(id: trip.cityID).name))
        }
        components.queryItems = items
        return components.url!
    }

    /// The most recent trip that ended within the window and hasn't had its
    /// survey card answered or waved off.
    static func justEnded(_ trips: [Trip], dismissed: Set<String>, now: Date = .now,
                          calendar: Calendar = .current) -> Trip? {
        let today = calendar.startOfDay(for: now)
        guard let earliest = calendar.date(byAdding: .day, value: -windowDays, to: today) else { return nil }
        return trips
            .filter { $0.endDate < today && $0.endDate >= earliest && !dismissed.contains($0.id.uuidString) }
            .max { $0.endDate < $1.endDate }
    }

    /// Trip ids whose card is done with, kept as one comma-separated string.
    static func decode(_ stored: String) -> Set<String> {
        Set(stored.split(separator: ",").map(String.init))
    }

    static func encode(_ ids: Set<String>) -> String {
        ids.sorted().joined(separator: ",")
    }
}

/// After a trip: the survey, while the day is still fresh.
struct SurveyCard: View {
    let trip: Trip
    let onDone: () -> Void

    private var city: String { CityDirectory.city(id: trip.cityID).name }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "checklist")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Brand.rauschDeep)
                    .frame(width: 40, height: 40)
                    .background(Brand.rausch.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("How did it hold up in \(city)?")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Text("Your trip has ended. Tell us what worked and what broke. It takes about two minutes.")
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 16) {
                Link(destination: BetaSurvey.url(trip: trip)) {
                    Text("Take the survey")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 44)
                        .background(Palette.ink, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .simultaneousGesture(TapGesture().onEnded(onDone))
                Button("Not now", action: onDone)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.inkMuted)
            }
            .buttonStyle(.plain)
            .padding(.leading, 52)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.elevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.hairline))
    }
}
