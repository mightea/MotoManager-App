import SwiftUI

/// Empty state for a `List` section with an action beneath it.
///
/// `ContentUnavailableView`'s own `actions` slot is unusable inside a list
/// row on iOS 26/27: the row proposes the actions a width of a few dozen
/// points, so a button lays its title out one glyph per line and renders as
/// a tall, label-less pillar (prominent styles paint it as a blue column
/// stretching past the tab bar). Stacking the actions outside the system
/// view sidesteps the slot entirely.
struct ListEmptyState<Label: View, Description: View, Actions: View>: View {
    @ViewBuilder var label: () -> Label
    @ViewBuilder var description: () -> Description
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            ContentUnavailableView(label: label, description: description)
            actions()
        }
        .frame(maxWidth: .infinity)
    }
}
