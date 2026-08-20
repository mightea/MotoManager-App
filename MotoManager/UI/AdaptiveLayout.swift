import SwiftUI

/// Size-class-driven layout constants for iPad (regular-width) layouts.
/// Branching is always on `horizontalSizeClass`, never on the device idiom,
/// so Split View / Stage Manager windows get the correct compact layout.
enum AdaptiveLayout {
    /// Max width for single-column screen content (the tab lists and detail
    /// pages). Wide enough for two-up card grids, narrow enough that rows
    /// don't degenerate into content pinned to opposite edges.
    static let contentMaxWidth: CGFloat = 700
    /// Max width for standalone forms (login).
    static let formMaxWidth: CGFloat = 560
}

/// Set on the detail column of a regular-width split layout: detail pages
/// normally hide the tab bar (phone convention), but inside a split column
/// that would rip away the iPad top tab strip.
private struct KeepsTabBarKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var keepsTabBar: Bool {
        get { self[KeepsTabBarKey.self] }
        set { self[KeepsTabBarKey.self] = newValue }
    }
}

/// Empty-selection placeholder for the detail column of a split layout.
struct DetailColumnPlaceholder: View {
    let icon: String
    let text: String

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()
            ContentUnavailableView {
                Label(text, systemImage: icon)
            }
        }
    }
}

private struct ContentColumn: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let maxWidth: CGFloat

    func body(content: Content) -> some View {
        if horizontalSizeClass == .regular {
            content
                .frame(maxWidth: maxWidth)
                .frame(maxWidth: .infinity)
        } else {
            content
        }
    }
}

extension View {
    /// Constrains the view to a centered readable column on regular-width
    /// layouts; a no-op on compact. Apply to whole screens (the `List` of a
    /// tab or detail page) — the app background shows through on the sides.
    func contentColumn(maxWidth: CGFloat = AdaptiveLayout.contentMaxWidth) -> some View {
        modifier(ContentColumn(maxWidth: maxWidth))
    }

    /// Card chrome for grid cells that replace list rows on regular width —
    /// mirrors the insetGrouped row background so grids and lists read as one
    /// family.
    func gridCardChrome() -> some View {
        self
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.field)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            // Hairline so the card reads as a bounded cell even where the
            // fill barely differs from the page background (light mode).
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.field)
                    .stroke(Theme.Glass.hairline, lineWidth: 0.5)
            )
    }
}
