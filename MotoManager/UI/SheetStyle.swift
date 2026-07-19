import SwiftUI

extension View {
    /// Standard glass chrome for all app sheets (forms, pickers, scanners,
    /// viewers, Garage, Settings). Sheets are reserved for quick actions;
    /// hierarchical drill-downs push onto the tab's `NavigationStack` instead.
    func glassSheet(detents: Set<PresentationDetent> = [.large]) -> some View {
        self.presentationDetents(detents)
            .presentationCornerRadius(Theme.Glass.sheetRadius)
            .presentationBackground(.regularMaterial)
            .presentationDragIndicator(.visible)
    }
}
