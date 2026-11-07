import SwiftUI

extension View {
    /// The shared density of the workspace lists and detail pages.
    /// `insetGrouped` alone brings ~20 pt side margins and ~35 pt gaps
    /// between sections; this pins both to the theme's spacing scale so every
    /// screen tightens together instead of patching insets per row.
    func workspaceListStyle() -> some View {
        listStyle(.insetGrouped)
            .listSectionSpacing(Theme.Spacing.listSection)
            .contentMargins(.horizontal, Theme.Spacing.pageH, for: .scrollContent)
    }
}
