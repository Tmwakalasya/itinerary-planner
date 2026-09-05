import Foundation

/// Where the Google Places key comes from.
///
/// Order: `Secrets.plist` in the app bundle, then a `GOOGLE_PLACES_API_KEY`
/// environment variable on the scheme. The key never goes in source control —
/// `Secrets.plist` is gitignored and `Secrets.example.plist` shows the shape.
enum Secrets {
    static let googlePlacesAPIKey: String? = {
        if let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
           let data = try? Data(contentsOf: url),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let key = plist["GooglePlacesAPIKey"] as? String,
           isUsable(key) {
            return key
        }
        if let key = ProcessInfo.processInfo.environment["GOOGLE_PLACES_API_KEY"], isUsable(key) {
            return key
        }
        return nil
    }()

    static var hasGooglePlacesKey: Bool { googlePlacesAPIKey != nil }

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
        // Ignore the placeholder that ships in Secrets.example.plist.
        return !trimmed.isEmpty && !trimmed.hasPrefix("PASTE_")
    }
}
