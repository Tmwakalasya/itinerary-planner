import UIKit

/// Loads Places photos for `PlacePhoto`.
///
/// AsyncImage can't set request headers, and a key restricted to this iOS app
/// is only honoured on requests that carry the app's bundle id. Images are
/// kept in memory for the session too, so scrolling back past a photo doesn't
/// fetch it again.
enum PhotoLoader {
    private static let cache = NSCache<NSURL, UIImage>()

    static func cachedImage(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    /// Nil when the photo can't be fetched; the caller keeps its gradient.
    static func image(for url: URL, session: URLSession = .shared,
                      budget: RequestBudget = .googlePhotos) async -> UIImage? {
        if let cached = cachedImage(for: url) { return cached }
        // Only Places photos bill the Google key; an event's poster doesn't.
        // Over this phone's allowance, the gradient stands in.
        let billed = url.host() == "places.googleapis.com"
        guard !billed || budget.spend() else { return nil }

        var request = URLRequest(url: url)
        GooglePlacesService.identifyApp(&request)

        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            // Offline, or the cell scrolled away: nothing reached Google.
            if billed { budget.refund() }
            return nil
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              // Decoded here, off the main thread, rather than on first draw.
              let image = await UIImage(data: data)?.byPreparingForDisplay()
        else { return nil }

        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}
