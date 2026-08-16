import SwiftUI

/// Sectioned-card settings sheet: server + connection info, sync status with
/// a manual trigger, and the logout action. Logout sits at the bottom behind
/// a confirmation — it wipes local data, so it must not be the first thing a
/// stray tap can hit. The server URL is chosen on the login screen, not here.
struct SettingsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject private var engine: SyncEngine
    @EnvironmentObject private var connectivity: ConnectivityMonitor
    @Environment(\.dismiss) var dismiss
    @State private var confirmingLogout = false

    /// "v0.2.0 (302)" — CI stamps MARKETING_VERSION and the build number
    /// into the archive; local builds show the project defaults.
    private var versionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "MotoManager · v\(version) (\(build))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                serverSection
                syncSection
                logoutButton
                    .padding(.top, 10)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            header
        }
        // Pinned to the bottom of the sheet, independent of scroll content.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Text(versionString)
                .scaledFont(10, weight: .medium)
                .foregroundColor(.white.opacity(0.35))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .background(sheetBackground)
        .confirmationDialog("Abmelden?", isPresented: $confirmingLogout, titleVisibility: .visible) {
            Button("Abmelden", role: .destructive) {
                authVM.logout()
            }
            Button("Abbrechen", role: .cancel) { }
        } message: {
            Text("Lokale Daten werden entfernt. Noch nicht synchronisierte Änderungen gehen verloren.")
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Einstellungen")
                .scaledFont(17, weight: .bold)
                .foregroundColor(.white)
            Spacer(minLength: 8)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .scaledFont(12, weight: .bold)
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.white.opacity(0.12)))
            }
            .accessibilityLabel("Schliessen")
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .glassEffect(.regular, in: Rectangle())
    }

    // MARK: - Server

    private var serverSection: some View {
        DetailSection("SERVER") {
            DetailRow(label: "Adresse", value: serverDisplay, mono: false)
            sectionDivider
            DetailRow(
                label: "Verbindung",
                value: connectivity.isOnline ? "Online" : "Offline",
                accent: connectivity.isOnline ? .green : .orange,
                mono: false
            )
        }
    }

    /// The host is the part worth reading; the scheme is noise unless it's
    /// a non-standard setup (plain http / custom port), which stays visible.
    private var serverDisplay: String {
        let base = NetworkManager.shared.baseURL
        guard let url = URL(string: base), let host = url.host() else { return base }
        var display = host
        if let port = url.port { display += ":\(port)" }
        if url.scheme == "http" { display = "http://" + display }
        return display
    }

    // MARK: - Sync

    private var syncSection: some View {
        DetailSection("SYNCHRONISIERUNG") {
            DetailRow(label: "Status", value: syncStatusText, accent: syncStatusColor, mono: false)
            sectionDivider
            DetailRow(label: "Letzte Synchronisierung", value: lastSyncText, mono: false)
            sectionDivider
            Button {
                engine.requestSync(motorcycleIds: [])
            } label: {
                HStack(spacing: 8) {
                    if case .syncing = engine.status {
                        ProgressView().controlSize(.small).tint(.white)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .scaledFont(13, weight: .semibold)
                    }
                    Text("Jetzt synchronisieren")
                        .scaledFont(13, weight: .semibold)
                    Spacer(minLength: 0)
                }
                .foregroundColor(Theme.Colors.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!connectivity.isOnline || { if case .syncing = engine.status { return true }; return false }())
        }
    }

    private var syncStatusText: String {
        switch engine.status {
        case .idle: "Synchron"
        case .syncing: "Synchronisiere …"
        case .pending(let n): "\(n) ausstehend"
        case .offline(let n): n > 0 ? "Offline · \(n) ausstehend" : "Offline"
        case .error: "Fehler"
        }
    }

    private var syncStatusColor: Color? {
        switch engine.status {
        case .idle: .green
        case .syncing, .pending: Theme.Colors.primary
        case .offline: .orange
        case .error: Theme.Colors.accent
        }
    }

    private var lastSyncText: String {
        guard let date = engine.lastSyncDate else { return "—" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Formatters.displayLocale
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(Theme.Glass.hairline)
            .frame(height: 0.5)
            .padding(.leading, 14)
    }

    // MARK: - Logout

    private var logoutButton: some View {
        Button {
            confirmingLogout = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .scaledFont(14, weight: .semibold)
                Text("Abmelden")
                    .scaledFont(14, weight: .semibold)
            }
            .foregroundColor(Theme.Colors.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Theme.Colors.accent.opacity(0.16))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Theme.Colors.accent.opacity(0.3), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var sheetBackground: some View {
        LinearGradient(
            colors: [
                Theme.Colors.navy900.opacity(0.6),
                Theme.Colors.navy950.opacity(0.8)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .environmentObject(AuthViewModel())
            .environmentObject(SyncEngine.shared)
            .environmentObject(ConnectivityMonitor.shared)
    }
}
