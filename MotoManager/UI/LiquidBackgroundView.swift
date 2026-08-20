import SwiftUI

/// App-wide canvas with three colored halo blobs — matches the motorsport
/// design system. Halos use the primary blue, violet, and brand red; subtle
/// and static so they give the glass primitives something to lift off without
/// distracting. Adaptive: navy base in dark mode, cool light gray in light
/// mode with softer halos.
struct LiquidBackgroundView: View {
    @Environment(\.colorScheme) private var colorScheme

    /// Halos are quieter in light mode — saturated blobs on a light canvas
    /// read as stains rather than glow.
    private var haloStrength: Double { colorScheme == .dark ? 1.0 : 0.35 }

    var body: some View {
        // Proportional halo placement/size so the blobs spread across any
        // canvas (iPad, Split View) instead of clustering at phone-tuned
        // pixel offsets.
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let size = max(320, min(w, h) * 0.6)
            ZStack {
                Theme.Colors.background.ignoresSafeArea()

                // Blue halo — top-left
                Circle()
                    .fill(Theme.Colors.primary.opacity(0.25 * haloStrength))
                    .frame(width: size, height: size)
                    .blur(radius: 90)
                    .position(x: w * 0.2, y: h * 0.14)

                // Violet halo — middle-right
                Circle()
                    .fill(Theme.Colors.primaryDark.opacity(0.45 * haloStrength))
                    .frame(width: size * 1.05, height: size * 1.05)
                    .blur(radius: 100)
                    .position(x: w * 0.9, y: h * 0.55)

                // Red halo — bottom-left
                Circle()
                    .fill(Theme.Colors.accent.opacity(0.18 * haloStrength))
                    .frame(width: size * 0.9, height: size * 0.9)
                    .blur(radius: 90)
                    .position(x: w * 0.3, y: h * 0.85)
            }
        }
        .accessibilityHidden(true)
    }
}
