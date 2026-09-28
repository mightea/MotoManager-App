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

    @State private var created: ApiTokenCreated?

    var body: some View {
        // Step 1 is a FormSheet whose save never "succeeds" in the dismiss
        // sense: it returns false and swaps this view to step 2 instead.
        Group {
            if let created {
                ApiTokenSecretSheet(created: created)
                    .transition(.opacity)
            } else {
                ApiTokenFormSheet { result in
                    onCreated(result.apiToken)
                    withAnimation { created = result }
                }
            }
        }
        .sensoryFeedback(.success, trigger: created != nil) { _, new in new }
    }
}

// MARK: - Step 1: form

private struct ApiTokenFormSheet: View {
    let onCreated: (ApiTokenCreated) -> Void

    @State private var name = ""
    @State private var scope: ApiTokenScope = .read
    @State private var expiry: Expiry = .never
    @State private var errorMessage: String?

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

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        FormSheet(
            title: "Token hinzufügen",
            canSave: !trimmedName.isEmpty,
            tracked: [name, scope, expiry],
            error: errorMessage,
            onSave: create
        ) {
            FormField("Name", hint: "Hilft dir später zu erkennen, welcher Client den Token verwendet.") {
                TextField("", text: $name, prompt: formPrompt("z. B. Claude Code auf dem Mac"))
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.done)
            }

            VStack(alignment: .leading, spacing: 6) {
                FormLabel("Berechtigung")
                Picker("Berechtigung", selection: $scope) {
                    ForEach(ApiTokenScope.allCases) { scope in
                        Text(scope.label).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(scope == .read
                     ? "Der Assistent kann Daten nur abfragen."
                     : "Der Assistent kann zusätzlich Wartungen, Tankstopps, Probleme, Ausgaben und Teile anlegen – nie löschen, nie Admin.")
                    .scaledFont(11, weight: .medium)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            FormField(
                "Gültigkeit",
                hint: "Abgelaufene Tokens werden automatisch abgelehnt. Du kannst jeden Token jederzeit widerrufen."
            ) {
                Picker("Gültigkeit", selection: $expiry) {
                    ForEach(Expiry.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
        }
    }

    /// Always returns false: on success the parent replaces this sheet with
    /// the one-time secret screen instead of dismissing.
    private func create() async -> Bool {
        errorMessage = nil
        let tokenName = trimmedName
        guard !tokenName.isEmpty else { return false }
        do {
            let result = try await NetworkManager.shared.createApiToken(
                name: tokenName,
                scope: scope,
                expiresInDays: expiry.days
            )
            onCreated(result)
        } catch {
            errorMessage = "Token konnte nicht erstellt werden: \(error.localizedDescription)"
        }
        return false
    }
}

// MARK: - Step 2: one-time secret chrome

/// Same chrome as a FormSheet (inline title, ✓ confirm), but there is
/// nothing to save — ✓ just closes. Swipe-down stays blocked: the secret can
/// never be shown again.
private struct ApiTokenSecretSheet: View {
    let created: ApiTokenCreated
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ApiTokenSecretView(created: created)
                .navigationTitle("Neuer Token")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(role: .confirm) { dismiss() }
                            .keyboardShortcut(.defaultAction)
                            .accessibilityLabel("Fertig")
                    }
                }
        }
        .interactiveDismissDisabled()
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
                        .scaledFont(15)
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
                    .glassActionButton(copiedToken ? .success : .primary,
                                       in: .roundedRectangle(radius: Theme.Radius.control))

                    ShareLink(item: created.token, subject: Text("MotoManager API-Token „\(created.apiToken.name)“")) {
                        Label("Teilen", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .glassActionButton(.secondary, in: .roundedRectangle(radius: Theme.Radius.control))
                }
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
