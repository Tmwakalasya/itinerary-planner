import Foundation

/// Where the API keys come from.
///
/// Order: `Secrets.plist` in the app bundle, then an environment variable on
/// the scheme. Keys never go in source control — `Secrets.plist` is gitignored
/// and `Secrets.example.plist` shows the shape.
enum Secrets {
    static let googlePlacesAPIKey: String? = key("GooglePlacesAPIKey", orEnvironment: "GOOGLE_PLACES_API_KEY")

    static var hasGooglePlacesKey: Bool { googlePlacesAPIKey != nil }

    /// Optional: without it the trip screen just doesn't show what's on.
    static let ticketmasterAPIKey: String? = key("TicketmasterAPIKey", orEnvironment: "TICKETMASTER_API_KEY")

    private static func key(_ name: String, orEnvironment variable: String) -> String? {
        if let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
           let data = try? Data(contentsOf: url),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let key = plist[name] as? String,
           isUsable(key) {
            return key
        }
        if let key = ProcessInfo.processInfo.environment[variable], isUsable(key) {
            return key
        }
        return nil
    }

    /// Where the web viewer is hosted. Set `ShareBaseURL` in Secrets.plist to
    /// your own deployment; share links are built against it.
    static let shareBaseURL: String = {
        if let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
           let data = try? Data(contentsOf: url),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let base = plist["ShareBaseURL"] as? String,
           isUsable(base) {
            return base.hasSuffix("/") ? String(base.dropLast()) : base
        }
        return "https://example.invalid/citytourist"
    }()

    static var hasShareBaseURL: Bool { !shareBaseURL.contains("example.invalid") }

    private static func isUsable(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        // Ignore the placeholders that ship in Secrets.example.plist.
        return !trimmed.isEmpty && !trimmed.hasPrefix("PASTE_") && !trimmed.contains("YOUR-USERNAME")
    }
}
