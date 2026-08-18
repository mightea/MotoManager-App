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
        ZStack {
            Theme.Colors.background.ignoresSafeArea()

            // Blue halo — top-left
            Circle()
                .fill(Theme.Colors.primary.opacity(0.25 * haloStrength))
                .frame(width: 360, height: 360)
                .blur(radius: 90)
                .offset(x: -120, y: -260)

            // Violet halo — middle-right
            Circle()
                .fill(Theme.Colors.primaryDark.opacity(0.45 * haloStrength))
                .frame(width: 380, height: 380)
                .blur(radius: 100)
                .offset(x: 160, y: 60)

            // Red halo — bottom-left
            Circle()
                .fill(Theme.Colors.accent.opacity(0.18 * haloStrength))
                .frame(width: 320, height: 320)
                .blur(radius: 90)
                .offset(x: -80, y: 280)
        }
        .accessibilityHidden(true)
    }
}
