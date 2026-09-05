import SwiftUI

// MARK: - Palette
//
// Airbnb's brand colours. "Rausch" is the coral-red they name after the street
// their first apartment was on; "Babu" is the teal accent.
enum Brand {
    static let rausch     = Color(hex: 0xFF385C)
    static let rauschDeep = Color(hex: 0xD70466)
    static let babu       = Color(hex: 0x008489)
    static let arches     = Color(hex: 0xFC642D)
}

/// Semantic colours that adapt to light/dark. Airbnb's app is light-first, so
/// dark mode is a deliberately soft charcoal rather than pure black.
enum Palette {
    static let ink        = dynamic(light: 0x222222, dark: 0xF7F7F7)
    static let inkMuted   = dynamic(light: 0x717171, dark: 0xB0B0B0)
    static let inkFaint   = dynamic(light: 0x9C9C9C, dark: 0x8A8A8A)
    static let hairline   = dynamic(light: 0xDDDDDD, dark: 0x3A3A3C)
    static let surface    = dynamic(light: 0xF7F7F7, dark: 0x1C1C1E)
    static let canvas     = dynamic(light: 0xFFFFFF, dark: 0x0E0E10)
    static let elevated   = dynamic(light: 0xFFFFFF, dark: 0x1C1C1E)

    /// Chrome that floats over photography reads against the photo, not the
    /// page, so it must NOT follow the theme — a badge that flips to near-white
    /// text in dark mode is invisible on its own white capsule.
    static let onPhoto = Color.white
    static let onPhotoInk = Color(hex: 0x222222)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(rgb: dark) : UIColor(rgb: light)
        })
    }
}

// MARK: - Metrics

enum Metric {
    /// Airbnb's cards use a 12pt radius; sheets and hero images use 16.
    static let cardRadius: CGFloat  = 12
    static let sheetRadius: CGFloat = 16
    static let buttonRadius: CGFloat = 10
    static let gutter: CGFloat      = 24
    static let cardGap: CGFloat     = 28
    /// Photo aspect on the explore feed. Square, as Airbnb sets it.
    static let photoAspect: CGFloat = 1.0
}

// MARK: - Typography
//
// Airbnb ships "Cereal", a geometric sans we can't bundle. SF Pro with tightened
// tracking and Airbnb's weight/size ramp gets very close to the same texture.

extension View {
    /// Display title — the "Where to?" / screen-title scale.
    func displayStyle() -> some View {
        font(.system(size: 32, weight: .bold))
            .tracking(-0.6)
            .foregroundStyle(Palette.ink)
    }

    func sectionTitleStyle() -> some View {
        font(.system(size: 22, weight: .semibold))
            .tracking(-0.4)
            .foregroundStyle(Palette.ink)
    }

    func cardTitleStyle() -> some View {
        font(.system(size: 15, weight: .semibold))
            .tracking(-0.1)
            .foregroundStyle(Palette.ink)
    }

    func bodyStyle() -> some View {
        font(.system(size: 15, weight: .regular))
            .foregroundStyle(Palette.ink)
    }

    func metaStyle() -> some View {
        font(.system(size: 15, weight: .regular))
            .foregroundStyle(Palette.inkMuted)
    }

    func captionStyle() -> some View {
        font(.system(size: 13, weight: .regular))
            .foregroundStyle(Palette.inkMuted)
    }
}

// MARK: - Shadows

extension View {
    /// The soft, wide, low-opacity lift Airbnb puts under floating controls.
    func floatingShadow(y: CGFloat = 3, radius: CGFloat = 10, opacity: Double = 0.14) -> some View {
        shadow(color: .black.opacity(opacity), radius: radius, x: 0, y: y)
    }
}

// MARK: - Hex helpers

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8)  & 0xFF) / 255,
            blue:  Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red:   CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8)  & 0xFF) / 255,
            blue:  CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
