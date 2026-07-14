import SwiftUI

enum Theme {
    enum Colors {
        // Motorsport palette — primary brand
        static let primary = Color(hex: 0x008AC9)         // Motorsport blue
        static let primaryDark = Color(hex: 0x2B115A)     // Violet
        static let accent = Color(hex: 0xF11A22)          // Motorsport red

        static let background = Color(UIColor.systemBackground)
        static let secondaryBackground = Color(UIColor.secondarySystemBackground)
        static let cardBackground = Color(UIColor.tertiarySystemBackground)

        // Dark navy scale (motomanager-dark)
        static let navy900 = Color(hex: 0x120E1D)
        static let navy950 = Color(hex: 0x0A0711)
        static let navy800 = Color(hex: 0x1B1627)

        static let glassBackground = Color.white.opacity(0.05)
        static let glassBorder = Color.white.opacity(0.2)

        static let gradientStart = primary
        static let gradientEnd = primaryDark

        // Three stripes — used for the motorsport accent
        static let stripeBlue = primary
        static let stripeViolet = primaryDark
        static let stripeRed = accent

        static let meshColors: [Color] = [
            primary.opacity(0.30),
            primaryDark.opacity(0.45),
            accent.opacity(0.18)
        ]
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

    enum Radius {
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 20
        static let xl: CGFloat = 30
    }

    /// Radii + line colors used by the glass component layer
    /// (segmented control, field row, sheet, document tile).
    /// Values mirror the design tokens in `colors_and_type.css`
    /// and `app.css` from the Claude Design handoff.
    enum Glass {
        static let sheetRadius: CGFloat = 32
        static let cardRadius: CGFloat = 22
        static let fieldRadius: CGFloat = 18
        static let segmentRadius: CGFloat = 12
        static let segmentInnerRadius: CGFloat = 10

        static let hairline = Color.white.opacity(0.06)
        static let border = Color.white.opacity(0.08)
        static let strongBorder = Color.white.opacity(0.12)
        static let mutedText = Color.white.opacity(0.55)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}

struct ModernButtonStyle: ButtonStyle {
    var isLoading: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.white)
            .padding()
            .frame(maxWidth: .infinity)
            .background(
                ZStack {
                    LinearGradient(
                        gradient: Gradient(colors: [Theme.Colors.gradientStart, Theme.Colors.gradientEnd]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )

                    if configuration.isPressed {
                        Color.black.opacity(0.1)
                    }
                }
            )
            .cornerRadius(Theme.Radius.m)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.2), value: configuration.isPressed)
            .opacity(isLoading ? 0.8 : 1.0)
    }
}

struct ModernTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding()
            .background(Theme.Colors.secondaryBackground)
            .cornerRadius(Theme.Radius.m)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.m)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
    }
}
