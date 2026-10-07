import SwiftUI

/// Listing photography.
///
/// When a place came back from Google Places it carries a photo resource name,
/// and that real image is what renders. Without one — sample data, or a photo
/// still loading — we draw a deterministic mesh gradient seeded off the place's
/// id and tinted to its category, so a card never looks like a broken image and
/// the same place always looks the same.
struct PlacePhoto: View {
    let seed: String
    var category: PlaceCategory = .attraction
    /// Faint glyph hinting at the subject, the way a photo would.
    var showsGlyph: Bool = true
    var photoURL: URL? = nil

    /// The fetched photo, tagged with its URL so a view handed a different
    /// place never shows the previous one's image.
    @State private var loaded: (url: URL, image: UIImage)?
    @State private var failedURL: URL?

    init(seed: String, category: PlaceCategory = .attraction, showsGlyph: Bool = true, photoURL: URL? = nil) {
        self.seed = seed
        self.category = category
        self.showsGlyph = showsGlyph
        self.photoURL = photoURL
    }

    /// Preferred call site — takes the photo from the place when there is one.
    init(place: Place, showsGlyph: Bool = true) {
        self.init(seed: place.id, category: place.category,
                  showsGlyph: showsGlyph, photoURL: place.photoURL)
    }

    var body: some View {
        // Color.clear accepts whatever size the caller proposes, so this view
        // never reports an intrinsic size of its own. The image fills that box
        // from inside an overlay and is cropped by .clipped(). Without this,
        // a scaledToFill image stacks with the caller's aspectRatio(.fill) and
        // the photo overflows its column.
        Color.clear
            .overlay {
                if let photoURL {
                    if let photo = photo(for: photoURL) {
                        Image(uiImage: photo).resizable().scaledToFill()
                    } else if failedURL == photoURL {
                        generated
                    } else {
                        generated.overlay(ProgressView().tint(.white.opacity(0.8)))
                    }
                } else {
                    generated
                }
            }
            .clipped()
            .task(id: photoURL) { await load() }
    }

    /// Checks the session cache as well, so a recycled list cell shows a photo
    /// it already has straight away instead of flashing the spinner.
    private func photo(for url: URL) -> UIImage? {
        if let loaded, loaded.url == url { return loaded.image }
        return PhotoLoader.cachedImage(for: url)
    }

    private func load() async {
        guard let photoURL, photo(for: photoURL) == nil else { return }
        let image = await PhotoLoader.image(for: photoURL)
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.25)) {
            if let image {
                loaded = (photoURL, image)
            } else {
                failedURL = photoURL
            }
        }
    }

    @ViewBuilder
    private var generated: some View {
        let rng = SeededGenerator(seed: seed)
        let colors = Self.palette(for: category, rng: rng)

        MeshGradient(
            width: 3,
            height: 3,
            points: Self.points(rng: rng),
            colors: colors,
            smoothsColors: true
        )
        .overlay {
            // A soft off-centre highlight, like light falling across a scene.
            RadialGradient(
                colors: [.white.opacity(0.28), .clear],
                center: UnitPoint(x: rng.double(0.15, 0.85), y: rng.double(0.1, 0.5)),
                startRadius: 0,
                endRadius: 220
            )
        }
        .overlay {
            if showsGlyph {
                Image(systemName: category.symbol)
                    .font(.system(size: 92, weight: .light))
                    .foregroundStyle(.white.opacity(0.09))
                    .rotationEffect(.degrees(rng.double(-12, 12)))
                    .offset(x: rng.double(-30, 30), y: rng.double(-20, 20))
                    .blendMode(.softLight)
            }
        }
        // Keeps the bottom edge from washing out under overlaid text.
        .overlay(alignment: .bottom) {
            LinearGradient(
                colors: [.clear, .black.opacity(0.18)],
                startPoint: .center,
                endPoint: .bottom
            )
        }
        .clipped()
    }

    // MARK: Palettes

    private static func palette(for category: PlaceCategory, rng: SeededGenerator) -> [Color] {
        let ramps: [[UInt32]]
        switch category {
        case .food:
            ramps = [[0xF6C177, 0xE8743B, 0xB33951], [0xFFD9A0, 0xF08A5D, 0x9E2A2B]]
        case .nature:
            ramps = [[0xBBE3C4, 0x4E9F6B, 0x1F4B3F], [0xD9E7A8, 0x6BA368, 0x244B36]]
        case .museum:
            ramps = [[0xE3D5F0, 0x9C7CC4, 0x4A3B6B], [0xF0E1E8, 0xB07CA8, 0x53355E]]
        case .nightlife:
            ramps = [[0x8E7BD4, 0x5B3A94, 0x1C1435], [0xE87AA8, 0x6C3FA0, 0x201A3E]]
        case .activity:
            ramps = [[0xA8DCE7, 0x3E8DA8, 0x17415C], [0xC7E9E2, 0x489D9B, 0x14454F]]
        case .attraction:
            ramps = [[0xF7D6B0, 0xD98E63, 0x7A4B36], [0xFBD3C4, 0xE0846B, 0x6E3B4A]]
        }
        let ramp = ramps[rng.int(0, ramps.count - 1)]
        let a = Color(hex: ramp[0]), b = Color(hex: ramp[1]), c = Color(hex: ramp[2])

        // 3x3 mesh: light at the top, saturated through the middle, deep at the base.
        return [a, a, b,
                a, b, c,
                b, c, c]
    }

    /// Jitters the six interior control points so no two photos share a shape.
    private static func points(rng: SeededGenerator) -> [SIMD2<Float>] {
        func j(_ v: Float, _ amount: Double = 0.16) -> Float {
            v + Float(rng.double(-amount, amount))
        }
        return [
            SIMD2(0.0, 0.0), SIMD2(j(0.5), 0.0), SIMD2(1.0, 0.0),
            SIMD2(0.0, j(0.5)), SIMD2(j(0.5), j(0.5)), SIMD2(1.0, j(0.5)),
            SIMD2(0.0, 1.0), SIMD2(j(0.5), 1.0), SIMD2(1.0, 1.0)
        ]
    }
}

/// Tiny deterministic PRNG so a given place always renders identically.
final class SeededGenerator {
    private var state: UInt64

    init(seed: String) {
        var h: UInt64 = 0xcbf29ce484222325
        for byte in seed.utf8 {
            h = (h ^ UInt64(byte)) &* 0x100000001b3
        }
        state = h == 0 ? 0x9E3779B97F4A7C15 : h
    }

    private func next() -> UInt64 {
        // xorshift64*
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 2685821657736338717
    }

    func double(_ lower: Double, _ upper: Double) -> Double {
        let unit = Double(next() >> 11) / Double(1 << 53)
        return lower + unit * (upper - lower)
    }

    func int(_ lower: Int, _ upper: Int) -> Int {
        guard upper > lower else { return lower }
        return lower + Int(next() % UInt64(upper - lower + 1))
    }
}
