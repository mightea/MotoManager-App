import SwiftUI

/// The app-wide "new record" affordance: a compact circular Liquid Glass button
/// docked in the bottom-trailing thumb zone, just above the tab bar. Used on
/// every home tab that creates a record (Fuel, Service, Parts).
struct FloatingAddButton: View {
    /// Transparent hit slop grown around the 60pt glass circle. Two adjacent
    /// buttons' tap targets meet exactly in the middle of the 12pt visual gap,
    /// so a near-miss can never fall through to the tappable row underneath.
    /// `bottomActionBar` subtracts it again from the container spacing/padding,
    /// so the rendered geometry is unchanged.
    static let hitSlop: CGFloat = 6

    var systemImage: String = "plus"
    var tint: Color = Theme.Colors.primary
    var accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .scaledFont(24, weight: .bold)
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .glassEffect(.regular.tint(tint).interactive(), in: Circle())
                .shadow(color: tint.opacity(0.5), radius: 14, x: 0, y: 8)
                .padding(Self.hitSlop)
                // `.frame` and `.glassEffect` draw but claim no touches, and
                // `.plain` adds no background: without this the button is only
                // tappable on the rendered glyph (a 20pt box) and the rest of
                // the circle falls through to the row beneath. Must stay last
                // so it resolves against the padded bounds.
                .contentShape(Rectangle())
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
    /// An optional secondary button (e.g. the parts QR scanner) docks leading
    /// of the primary one so "+" keeps its corner spot.
    func bottomActionBar(
        detailVM: MotorcycleDetailViewModel,
        addTint: Color = Theme.Colors.primary,
        addLabel: String? = nil,
        addAction: (() -> Void)? = nil,
        secondaryIcon: String? = nil,
        secondaryLabel: String? = nil,
        secondaryAction: (() -> Void)? = nil
    ) -> some View {
        let hasSecondary = secondaryIcon != nil && secondaryLabel != nil && secondaryAction != nil
        let slop = FloatingAddButton.hitSlop
        return self
            .overlay(alignment: .bottomLeading) {
                RefreshBanner(viewModel: detailVM)
                    .padding(.leading, Theme.Spacing.pageH)
                    .padding(.trailing, hasSecondary ? 160 : 88)   // never reach the trailing buttons
                    .padding(.bottom, 12)
            }
            .overlay(alignment: .bottomTrailing) {
                // Spacing and padding are reduced by the buttons' hit slop, so
                // the visual gap stays 12pt and the circles keep their exact
                // position while the tap targets tile the space between them.
                HStack(spacing: 12 - 2 * slop) {
                    if let secondaryIcon, let secondaryLabel, let secondaryAction {
                        FloatingAddButton(
                            systemImage: secondaryIcon,
                            tint: Color.white.opacity(0.2),
                            accessibilityLabel: secondaryLabel,
                            action: secondaryAction
                        )
                    }
                    if let addLabel, let addAction {
                        FloatingAddButton(
                            tint: addTint,
                            accessibilityLabel: addLabel,
                            action: addAction
                        )
                    }
                }
                .padding(.trailing, Theme.Spacing.pageH - slop)
                .padding(.bottom, 12 - slop)
            }
    }
}
