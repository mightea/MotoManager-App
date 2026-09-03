import SwiftUI
import UIKit

/// Two-step sheet: a small form (name, scope, expiry) that turns into the
/// one-time secret screen once the backend has created the token. The secret
/// is never retrievable again, so the second step disables interactive
/// dismissal and offers copy, share, and a ready-made Claude Code command.
struct CreateApiTokenView: View {
    /// Called once with the created token's metadata (never the secret) so
    /// the list can update without a reload.
    let onCreated: (ApiToken) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var scope: ApiTokenScope = .read
    @State private var expiry: Expiry = .never
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var created: ApiTokenCreated?

    private enum Expiry: Int, CaseIterable, Identifiable {
        case never = 0
        case days30 = 30
        case days90 = 90
        case days365 = 365

        var id: Int { rawValue }
        var label: String {
            switch self {
            case .never: "Unbegrenzt"
            case .days30: "30 Tage"
            case .days90: "90 Tage"
            case .days365: "365 Tage"
            }
        }
        var days: Int? { self == .never ? nil : rawValue }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let created {
                    ApiTokenSecretView(created: created)
                } else {
                    form
                }
            }
            .navigationTitle(created == nil ? "Token erstellen" : "Neuer Token")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if created == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Abbrechen") { dismiss() }
                            .disabled(isCreating)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        if isCreating {
                            ProgressView().controlSize(.small)
                        } else {
                            Button("Erstellen") { create() }
                                .disabled(trimmedName.isEmpty)
                        }
                    }
                } else {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fertig") { dismiss() }
                    }
                }
            }
            .alert("Token konnte nicht erstellt werden", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        // Once the secret is on screen, an accidental swipe-down must not
        // throw it away — it can never be shown again.
        .interactiveDismissDisabled(created != nil)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Form

    private var form: some View {
        Form {
            Section {
                TextField("Name", text: $name, prompt: Text("z. B. Claude Code auf dem Mac"))
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.done)
            } header: {
                Text("Name")
            } footer: {
                Text("Hilft dir später zu erkennen, welcher Client den Token verwendet.")
            }

            Section {
                Picker("Berechtigung", selection: $scope) {
                    ForEach(ApiTokenScope.allCases) { scope in
                        Text(scope.label).tag(scope)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Berechtigung")
            } footer: {
                Text(scope == .read
                     ? "Der Assistent kann Daten nur abfragen."
                     : "Der Assistent kann zusätzlich Wartungen, Tankstopps, Probleme, Ausgaben und Teile anlegen – nie löschen, nie Admin.")
            }

            Section {
                Picker("Gültigkeit", selection: $expiry) {
                    ForEach(Expiry.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.menu)
            } footer: {
                Text("Abgelaufene Tokens werden automatisch abgelehnt. Du kannst jeden Token jederzeit widerrufen.")
            }
        }
        .scrollContentBackground(.hidden)
        .disabled(isCreating)
    }

    private func create() {
        let tokenName = trimmedName
        guard !tokenName.isEmpty, !isCreating else { return }
        isCreating = true
        Task {
            defer { isCreating = false }
            do {
                let result = try await NetworkManager.shared.createApiToken(
                    name: tokenName,
                    scope: scope,
                    expiresInDays: expiry.days
                )
                onCreated(result.apiToken)
                withAnimation { created = result }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - One-time secret

/// Shows the freshly created secret with copy/share actions, the warning that
/// it can't be shown again, and a copy-pasteable Claude Code setup command.
private struct ApiTokenSecretView: View {
    let created: ApiTokenCreated
    @State private var copiedToken = false
    @State private var copiedCommand = false

    private var mcpURL: String { NetworkManager.shared.mcpEndpointURL }

    private var claudeCommand: String {
        "claude mcp add --transport http motomanager \(mcpURL) --header \"Authorization: Bearer \(created.token)\""
    }

    var body: some View {
        List {
            Section {
                Label {
                    Text("Dieser Token wird nur **jetzt** angezeigt. Kopiere ihn an einen sicheren Ort – danach kann er nicht mehr abgerufen werden, nur noch widerrufen.")
                        .font(.subheadline)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                .padding(.vertical, Theme.Spacing.xs)
            }

            Section {
                Text(created.token)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Theme.Spacing.xs)
                HStack(spacing: Theme.Spacing.m) {
                    Button {
                        copy(created.token, flag: $copiedToken)
                    } label: {
                        Label(copiedToken ? "Kopiert" : "Kopieren",
                              systemImage: copiedToken ? "checkmark" : "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(copiedToken ? .green : Theme.Colors.primary)

                    ShareLink(item: created.token, subject: Text("MotoManager API-Token „\(created.apiToken.name)“")) {
                        Label("Teilen", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.Colors.primary)
                }
                .buttonBorderShape(.roundedRectangle(radius: Theme.Radius.control))
                .listRowSeparator(.hidden)
            } header: {
                Text("Token „\(created.apiToken.name)“ · \(created.apiToken.scopeLabel)")
            }

            Section {
                Text(claudeCommand)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    copy(claudeCommand, flag: $copiedCommand)
                } label: {
                    Label(copiedCommand ? "Befehl kopiert" : "Befehl kopieren",
                          systemImage: copiedCommand ? "checkmark" : "terminal")
                }
                .tint(copiedCommand ? .green : Theme.Colors.primary)
            } header: {
                Text("Claude Code einrichten")
            } footer: {
                Text("Im Terminal ausführen. Die Claude-API nutzt denselben Token als authorization_token für den MCP-Endpunkt \(mcpURL). Claude Desktop, claude.ai und die Claude-App brauchen keinen Token — sie verbinden sich per Connector mit Anmeldung.")
            }
        }
        .scrollContentBackground(.hidden)
        .sensoryFeedback(.success, trigger: copiedToken) { _, new in new }
        .sensoryFeedback(.success, trigger: copiedCommand) { _, new in new }
    }

    private func copy(_ text: String, flag: Binding<Bool>) {
        UIPasteboard.general.string = text
        flag.wrappedValue = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            flag.wrappedValue = false
        }
    }
}

#Preview("Formular") {
    CreateApiTokenView { _ in }
}

#Preview("Secret") {
    NavigationStack {
        ApiTokenSecretView(created: ApiTokenCreated(
            apiToken: ApiToken(
                id: 1, userId: 1, name: "Claude Code", tokenPrefix: "mm_3f9a2b", scope: "write",
                createdAt: "2026-09-02T12:00:00Z", lastUsedAt: nil, expiresAt: nil, revokedAt: nil,
                kind: "personal"
            ),
            token: "mm_3f9a2b1c4d5e6f708192a3b4c5d6e7f8091a2b3c4d5e6f708192a3b4"
        ))
    }
}
