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
    static func image(for url: URL, session: URLSession = .shared) async -> UIImage? {
        if let cached = cachedImage(for: url) { return cached }

        var request = URLRequest(url: url)
        GooglePlacesService.identifyApp(&request)

        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
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
