import SwiftUI

/// Sectioned settings sheet: server + connection info, sync status with
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
        NavigationStack {
            List {
                serverSection
                syncSection
                aiAccessSection
                logoutSection
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        .confirmationDialog("Abmelden?", isPresented: $confirmingLogout, titleVisibility: .visible) {
            Button("Abmelden", role: .destructive) {
                authVM.logout()
            }
            Button("Abbrechen", role: .cancel) { }
        } message: {
            Text("Lokale Daten werden entfernt. Noch nicht synchronisierte Änderungen gehen verloren.")
        }
    }

    // MARK: - Server

    private var serverSection: some View {
        Section("Server") {
            LabeledContent("Adresse", value: serverDisplay)
            LabeledContent("Verbindung") {
                Text(connectivity.isOnline ? "Online" : "Offline")
                    .foregroundStyle(connectivity.isOnline ? Color.green : Color.orange)
            }
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
        Section("Synchronisierung") {
            LabeledContent("Status") {
                Text(syncStatusText)
                    .foregroundStyle(syncStatusColor ?? .secondary)
            }
            LabeledContent("Letzte Synchronisierung", value: lastSyncText)
            Button {
                engine.requestSync(motorcycleIds: [])
            } label: {
                HStack(spacing: 8) {
                    if case .syncing = engine.status {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    Text("Jetzt synchronisieren")
                }
            }
            .tint(Theme.Colors.primary)
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

    // MARK: - AI access (MCP)

    private var aiAccessSection: some View {
        Section {
            NavigationLink {
                ApiTokensView()
            } label: {
                Label("KI-Zugriff (MCP)", systemImage: "sparkles")
            }
        } footer: {
            Text("Persönliche Zugangs-Tokens für KI-Assistenten wie Claude.")
        }
    }

    // MARK: - Logout

    private var logoutSection: some View {
        Section {
            Button(role: .destructive) {
                confirmingLogout = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                    Text("Abmelden")
                }
                .frame(maxWidth: .infinity)
            }
        } footer: {
            Text(versionString)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
        }
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
