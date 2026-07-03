import SwiftUI

/// Compact, always-visible indicator of sync state — the "transparent to the
/// user" surface. Bound to `SyncEngine.status`.
struct SyncStatusPill: View {
    @EnvironmentObject private var engine: SyncEngine

    private var isError: Bool {
        if case .error = engine.status { return true }
        return false
    }

    var body: some View {
        let style = style(for: engine.status)
        HStack(spacing: 5) {
            if case .syncing = engine.status {
                ProgressView().controlSize(.mini).tint(.white)
            } else {
                Image(systemName: style.icon)
                    .font(.system(size: 11, weight: .bold))
            }
            Text(style.label)
                .font(.system(size: 11, weight: .heavy))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(style.tint.opacity(0.9)))
        .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 2)
        .animation(.easeInOut(duration: 0.25), value: engine.status)
        // Tap to retry when a sync has failed (clears the poison counters and
        // re-runs the outbox) — otherwise the pill is purely informational.
        .contentShape(Capsule())
        .onTapGesture {
            if isError { engine.retryFailed(motorcycleIds: []) }
        }
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
            return ("wifi.slash", n > 0 ? "Offline · \(n)" : "Offline", .orange)
        case .error:
            return ("exclamationmark.icloud.fill", "Fehler", Theme.Colors.accent)
        }
    }
}
