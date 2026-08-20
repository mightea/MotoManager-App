import SwiftUI

extension View {
    /// Standard glass chrome for all app sheets (forms, pickers, scanners,
    /// viewers, Garage, Settings). Sheets are reserved for quick actions;
    /// hierarchical drill-downs push onto the tab's `NavigationStack` instead.
    ///
    /// The system material is the sheet's only background — sheet content must
    /// not paint its own canvas on top, so the material (and the user's iOS 27
    /// glass-intensity preference) stays in charge of the look in both
    /// appearances. Quick single-purpose forms should pass compact `detents`
    /// (e.g. `[.medium]`) instead of the full-height default.
    func glassSheet(detents: Set<PresentationDetent> = [.large]) -> some View {
        self.presentationDetents(detents)
            .presentationCornerRadius(Theme.Radius.sheet)
            .presentationBackground(.regularMaterial)
            .presentationDragIndicator(.visible)
    }
}
