import SwiftUI

/// Content of the tab view's bottom accessory (the system slot above the tab
/// bar that morphs into the minimized bar on scroll — the same chrome Music
/// uses for Now Playing). Consolidates the two transient status surfaces that
/// used to float as custom overlays:
///
/// - the sync state (syncing / pending / offline / error) — silence means
///   synced, so the accessory is only enabled when something is happening.
///   A failed sync is tappable to retry (clears the poison counters and
///   re-runs the outbox).
/// - the "refresh failed, showing cached data" notice, dismissable.
///
/// The system draws the accessory's glass capsule; this view supplies plain
/// content only — no `glassEffect` of its own.
struct StatusAccessoryBar: View {
    @ObservedObject var viewModel: MotorcycleDetailViewModel
    @EnvironmentObject private var engine: SyncEngine

    /// Drives `tabViewBottomAccessory(isEnabled:)` — accessory only exists
    /// while there is something to report.
    static func isActive(engine: SyncEngine, viewModel: MotorcycleDetailViewModel?) -> Bool {
        if let viewModel, viewModel.refreshFailed { return true }
        if case .idle = engine.status { return false }
        return true
    }

    private var isError: Bool {
        if case .error = engine.status { return true }
        return false
    }

    var body: some View {
        if viewModel.refreshFailed {
            refreshFailedContent
        } else {
            syncContent
        }
    }

    // MARK: - Refresh failure

    private var refreshFailedContent: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.exclamationmark")
                .scaledFont(13, weight: .semibold)
                .foregroundStyle(Theme.Colors.accent)
            Text("Aktualisierung fehlgeschlagen – gespeicherte Daten werden angezeigt.")
                .scaledFont(12, weight: .semibold)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            Button {
                withAnimation(.spring(duration: 0.3)) {
                    viewModel.refreshFailed = false
                }
            } label: {
                Image(systemName: "xmark")
                    .scaledFont(12, weight: .bold)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Hinweis schließen")
        }
        .padding(.horizontal, 12)
    }

    // MARK: - Sync status

    @ViewBuilder
    private var syncContent: some View {
        let style = style(for: engine.status)
        HStack(spacing: 6) {
            if case .syncing = engine.status {
                ProgressView().controlSize(.mini)
            } else {
                Image(systemName: style.icon)
                    .scaledFont(12, weight: .bold)
                    .foregroundStyle(style.tint)
            }
            Text(style.label)
                .scaledFont(12, weight: .semibold)
            if isError {
                Spacer(minLength: 4)
                Text("Erneut versuchen")
                    .scaledFont(12, weight: .bold)
                    .foregroundStyle(Theme.Colors.primary)
            } else {
                Spacer(minLength: 4)
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            if isError { engine.retryFailed(motorcycleIds: []) }
        }
        .animation(.easeInOut(duration: 0.25), value: engine.status)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Synchronisierung: \(style.label)")
        .accessibilityHint(isError ? "Tippen, um die Synchronisierung erneut zu versuchen" : "")
        .accessibilityAddTraits(isError ? .isButton : [])
    }

    private func style(for status: SyncStatus) -> (icon: String, label: String, tint: Color) {
        switch status {
        case .idle:
            return ("checkmark.icloud.fill", "Synchron", .green)
        case .syncing:
            return ("arrow.triangle.2.circlepath", "Synchronisiere…", Theme.Colors.primary)
        case .pending(let n):
            return ("clock.badge.fill", "\(n) ausstehend", Theme.Colors.primary)
        case .offline(let n):
            return ("wifi.slash", n > 0 ? "Offline · \(n) ausstehend" : "Offline", .orange)
        case .error:
            return ("exclamationmark.icloud.fill", "Synchronisierung fehlgeschlagen", Theme.Colors.accent)
        }
    }
}
