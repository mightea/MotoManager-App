import SwiftUI

extension View {
    /// Standard glass chrome for all app sheets (forms, pickers, scanners,
    /// viewers, Garage, Settings). Sheets are reserved for quick actions;
    /// hierarchical drill-downs push onto the tab's `NavigationStack` instead.
    ///
    /// The system material is the sheet's only background — sheet content must
    /// not paint its own canvas on top, so the material (and the user's iOS 27
    /// glass-intensity preference) stays in charge of the look in both
    /// appearances. Every sheet is full height — no half-height detents — so
    /// all of them open the same way.
    func glassSheet() -> some View {
        self.presentationDetents([.large])
            .presentationCornerRadius(Theme.Radius.sheet)
            .presentationBackground(.regularMaterial)
            .presentationDragIndicator(.visible)
    }
}
