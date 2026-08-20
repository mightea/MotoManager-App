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
    /// On regular-width layouts (iPad) detents are ignored by the system, so
    /// `presentationSizing(.form)` picks a deliberate centered form-sheet size
    /// there instead of the default full page sheet; on compact the detents
    /// stay in charge.
    func glassSheet(detents: Set<PresentationDetent> = [.large]) -> some View {
        self.presentationDetents(detents)
            .presentationSizing(.form)
            .presentationCornerRadius(Theme.Radius.sheet)
            .presentationBackground(.regularMaterial)
            .presentationDragIndicator(.visible)
    }
}
