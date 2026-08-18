import SwiftUI
import UIKit

enum Theme {
    enum Colors {
        // Motorsport palette — primary brand. Appearance-independent.
        static let primary = Color(hex: 0x008AC9)         // Motorsport blue
        static let primaryDark = Color(hex: 0x2B115A)     // Violet
        static let accent = Color(hex: 0xF11A22)          // Motorsport red

        // Adaptive canvas: cool light gray by day, the motorsport navy by night.
        // The dark values are the original navy scale; nothing changes in dark mode.
        static let background = Color(light: Color(hex: 0xF2F3F7), dark: Color(hex: 0x0A0711))
        static let backgroundElevated = Color(light: .white, dark: Color(hex: 0x120E1D))

        // Dark navy scale — reserved for photo scrims and other surfaces that sit
        // on top of imagery (appearance-independent by design, like the photos).
        static let navy900 = Color(hex: 0x120E1D)
        static let navy950 = Color(hex: 0x0A0711)
        static let navy800 = Color(hex: 0x1B1627)

        // Ink used on top of photos. Photos don't adapt to appearance, so this
        // stays white in both modes — never use it on adaptive surfaces.
        static let onPhoto = Color.white
        static let onPhotoSecondary = Color.white.opacity(0.78)
        static let onPhotoMuted = Color.white.opacity(0.6)

        static let glassBackground = Color.primary.opacity(0.05)
        static let glassBorder = Color.primary.opacity(0.2)

        static let gradientStart = primary
        static let gradientEnd = primaryDark

        // Three stripes — used for the motorsport accent
        static let stripeBlue = primary
        static let stripeViolet = primaryDark
        static let stripeRed = accent
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
        /// Horizontal gutter for the main tab screens' content. Tighter than
        /// `m` so cards get more width; tweak here to re-flow every home view.
        static let pageH: CGFloat = 12
    }

    /// The single corner-radius scale. Values nest concentrically:
    /// sheet > card > field > control > controlInner > badge, so a shape inside
    /// another shape always uses the next-smaller step. Don't hardcode radii in
    /// view code — pick the step that matches the container level.
    enum Radius {
        static let sheet: CGFloat = 32
        static let card: CGFloat = 22
        static let field: CGFloat = 18
        static let chip: CGFloat = 14
        static let control: CGFloat = 12
        static let controlInner: CGFloat = 10
        static let badge: CGFloat = 8
    }

    /// Line colors used by the glass component layer. All adaptive: they are
    /// built on `Color.primary` (label color), so they flip with appearance.
    enum Glass {
        static let hairline = Color.primary.opacity(0.08)
        static let border = Color.primary.opacity(0.10)
        static let strongBorder = Color.primary.opacity(0.15)
        /// Secondary label color — kept as a named token because the glass
        /// components read it heavily.
        static let mutedText = Color.secondary
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }

    /// Adaptive color that resolves per appearance, so hardcoded brand surfaces
    /// can carry an explicit light-mode counterpart.
    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
}
