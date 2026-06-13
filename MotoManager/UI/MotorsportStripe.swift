import SwiftUI

/// Thin three-band motorsport stripe (blue · violet · red).
/// Drop in at the very top of a screen for the BMW Motorsport accent.
struct MotorsportStripe: View {
    var height: CGFloat = 2

    var body: some View {
        HStack(spacing: 0) {
            Theme.Colors.stripeBlue
            Theme.Colors.stripeViolet
            Theme.Colors.stripeRed
        }
        .frame(height: height)
        .opacity(0.95)
    }
}
