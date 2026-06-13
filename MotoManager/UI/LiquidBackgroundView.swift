import SwiftUI

/// Navy base with three colored halo blobs — matches the motorsport design system.
/// Halos use the primary blue, violet, and brand red; subtle and static so they
/// give the glass primitives something to lift off without distracting.
struct LiquidBackgroundView: View {
    var body: some View {
        ZStack {
            Theme.Colors.navy950.ignoresSafeArea()

            // Blue halo — top-left
            Circle()
                .fill(Theme.Colors.primary.opacity(0.25))
                .frame(width: 360, height: 360)
                .blur(radius: 90)
                .offset(x: -120, y: -260)

            // Violet halo — middle-right
            Circle()
                .fill(Theme.Colors.primaryDark.opacity(0.45))
                .frame(width: 380, height: 380)
                .blur(radius: 100)
                .offset(x: 160, y: 60)

            // Red halo — bottom-left
            Circle()
                .fill(Theme.Colors.accent.opacity(0.18))
                .frame(width: 320, height: 320)
                .blur(radius: 90)
                .offset(x: -80, y: 280)
        }
        .accessibilityHidden(true)
    }
}
