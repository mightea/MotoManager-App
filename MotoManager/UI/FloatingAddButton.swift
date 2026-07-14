import SwiftUI

/// The app-wide "new record" affordance: a compact circular Liquid Glass button
/// docked in the bottom-trailing thumb zone, just above the tab bar. Used on
/// every home tab that creates a record (Fuel, Service, Parts).
struct FloatingAddButton: View {
    var systemImage: String = "plus"
    var tint: Color = Theme.Colors.primary
    var accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .glassEffect(.regular.tint(tint).interactive(), in: Circle())
                .shadow(color: tint.opacity(0.5), radius: 14, x: 0, y: 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

extension View {
    /// Floats the offline `RefreshBanner` (bottom-leading, compact — never
    /// full-width) and an optional `FloatingAddButton` (bottom-trailing) just
    /// above the tab bar as background-free overlays. Two independent corner
    /// anchors so the button stays put whether or not the banner is showing.
    /// Pass no `addLabel`/`addAction` for a banner-only tab (e.g. Workshop).
    func bottomActionBar(
        detailVM: MotorcycleDetailViewModel,
        addTint: Color = Theme.Colors.primary,
        addLabel: String? = nil,
        addAction: (() -> Void)? = nil
    ) -> some View {
        self
            .overlay(alignment: .bottomLeading) {
                RefreshBanner(viewModel: detailVM)
                    .padding(.leading, Theme.Spacing.pageH)
                    .padding(.trailing, 88)   // never reach the trailing button
                    .padding(.bottom, 12)
            }
            .overlay(alignment: .bottomTrailing) {
                if let addLabel, let addAction {
                    FloatingAddButton(
                        tint: addTint,
                        accessibilityLabel: addLabel,
                        action: addAction
                    )
                    .padding(.trailing, Theme.Spacing.pageH)
                    .padding(.bottom, 12)
                }
            }
    }
}
