import SwiftUI

/// Semantic variants for the app's action buttons, mapped onto the native
/// iOS 26 Liquid Glass button styles. Replaces the hand-rolled
/// `RoundedRectangle().fill()` + fake-shadow chrome that predated glass.
enum GlassButtonVariant {
    /// Filled primary glass in the motorsport blue accent.
    case primary
    /// Clear glass — for lower-emphasis / cancel-style actions.
    case secondary
    /// Filled prominent glass in the red accent — destructive actions.
    case danger
    /// Filled prominent glass in green — confirmations.
    case success
}

extension View {
    /// Applies a native Liquid Glass button style to a `Button`, tinted per the
    /// semantic `variant`. Pass a `shape` to match the call site (full-width
    /// CTAs use `.roundedRectangle`, icon buttons use `.circle`).
    ///
    /// Prominent variants render as a filled, tinted glass surface; `.secondary`
    /// renders as clear glass. All variants get the system's built-in press
    /// interactivity, so no manual scale/opacity handling is needed.
    @ViewBuilder
    func glassActionButton(
        _ variant: GlassButtonVariant = .primary,
        in shape: ButtonBorderShape = .capsule
    ) -> some View {
        switch variant {
        case .primary:
            self.buttonStyle(.glassProminent)
                .tint(Theme.Colors.primary)
                .buttonBorderShape(shape)
        case .success:
            self.buttonStyle(.glassProminent)
                .tint(.green)
                .buttonBorderShape(shape)
        case .danger:
            self.buttonStyle(.glassProminent)
                .tint(Theme.Colors.accent)
                .buttonBorderShape(shape)
        case .secondary:
            self.buttonStyle(.glass)
                .buttonBorderShape(shape)
        }
    }
}
