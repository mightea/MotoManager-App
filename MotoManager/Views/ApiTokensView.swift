import SwiftUI
import UIKit

/// Personal API tokens for the backend's MCP server ("KI-Zugriff"). Pushed
/// from Settings. Lists the tokens with swipe-to-revoke, shows the MCP
/// endpoint, and the latest audit entries. Creating a token opens
/// `CreateApiTokenView`, which presents the secret exactly once.
struct ApiTokensView: View {
    @StateObject private var viewModel = ApiTokensViewModel()
    @State private var showCreate = false
    @State private var tokenToRevoke: ApiToken?
    @State private var copiedURL = false

    private var mcpURL: String { NetworkManager.shared.mcpEndpointURL }

    var body: some View {
        List {
            introSection
            endpointSection
            connectorSection
            tokensSection
            auditSection
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("KI-Zugriff")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showCreate = true
                } label: {
                    Label("Token erstellen", systemImage: "plus")
                }
            }
        }
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .sheet(isPresented: $showCreate) {
            CreateApiTokenView { created in
                viewModel.insert(created)
            }
        }
        .confirmationDialog(
            "Token widerrufen?",
            isPresented: Binding(
                get: { tokenToRevoke != nil },
                set: { if !$0 { tokenToRevoke = nil } }
            ),
            titleVisibility: .visible,
            presenting: tokenToRevoke
        ) { token in
            Button("„\(token.name)“ widerrufen", role: .destructive) {
                Task { await viewModel.revoke(token) }
            }
            Button("Abbrechen", role: .cancel) { }
        } message: { _ in
            Text("KI-Clients, die diesen Token verwenden, verlieren sofort den Zugriff. Das kann nicht rückgängig gemacht werden.")
        }
        .alert("Fehler", isPresented: Binding(
            get: { viewModel.actionError != nil },
            set: { if !$0 { viewModel.actionError = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.actionError ?? "")
        }
        .sensoryFeedback(.success, trigger: copiedURL) { _, new in new }
    }

    // MARK: - Intro

    private var introSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("Tokens erlauben KI-Assistenten wie Claude Zugriff auf die eigenen Daten.")
                Text("**Lesen** – nur abfragen.\n**Lesen & Schreiben** – zusätzlich Wartungen, Tankstopps, Probleme, Ausgaben und Teile anlegen. Nie löschen, nie Admin.")
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
            .padding(.vertical, Theme.Spacing.xs)
        }
    }

    // MARK: - Connectors (OAuth)

    /// Claude Desktop, claude.ai and the Claude mobile apps connect through
    /// a custom connector that signs in via the webapp's consent page — no
    /// token is pasted. The grant then shows up in the token list below.
    private var connectorSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("Kein Token nötig — einmal verbinden, gilt für claude.ai, Claude Desktop und die Claude-App desselben Kontos.")
                    .foregroundStyle(.secondary)
                connectorStep(1, "In Claude **Einstellungen → Connectors → Benutzerdefinierten Connector hinzufügen** öffnen.")
                connectorStep(2, "Name z. B. „MotoManager“, als URL den MCP-Endpunkt einfügen. Client-ID und Secret leer lassen.")
                connectorStep(3, "**Verbinden** antippen, in der Garage anmelden, Berechtigung wählen und **Zugriff erlauben**.")
                connectorStep(4, "Den Connector im Chat aktivieren. Die Verbindung erscheint unten als „Verbunden“ und lässt sich dort widerrufen.")
            }
            .font(.subheadline)
            .padding(.vertical, Theme.Spacing.xs)
        } header: {
            Text("Claude Desktop, claude.ai & App")
        } footer: {
            Text("Claude Code und die Claude-API nutzen weiterhin einen persönlichen Token (unten erstellen).")
        }
    }

    private func connectorStep(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
            Text("\(number).")
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(Theme.Colors.primary)
            Text(text)
        }
    }

    // MARK: - Endpoint

    private var endpointSection: some View {
        Section("MCP-Endpunkt") {
            HStack(spacing: Theme.Spacing.m) {
                Text(mcpURL)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    UIPasteboard.general.string = mcpURL
                    copiedURL = true
                    Task {
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        copiedURL = false
                    }
                } label: {
                    Image(systemName: copiedURL ? "checkmark" : "doc.on.doc")
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.borderless)
                .tint(copiedURL ? .green : Theme.Colors.primary)
                .accessibilityLabel("Adresse kopieren")
            }
        }
    }

    // MARK: - Tokens

    @ViewBuilder
    private var tokensSection: some View {
        Section("Tokens") {
            if viewModel.isLoading && !viewModel.hasLoaded {
                ForEach(0..<2, id: \.self) { _ in
                    placeholderRow
                }
            } else if viewModel.tokens.isEmpty, let error = viewModel.loadError {
                errorState(error)
            } else if viewModel.tokens.isEmpty {
                ContentUnavailableView {
                    Label("Keine Tokens", systemImage: "key.horizontal")
                } description: {
                    Text("Erstelle einen Token, um einen KI-Assistenten mit deiner Garage zu verbinden.")
                } actions: {
                    Button("Token erstellen") { showCreate = true }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.Colors.primary)
                }
            } else {
                ForEach(viewModel.tokens) { token in
                    ApiTokenRow(token: token)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                tokenToRevoke = token
                            } label: {
                                Label("Widerrufen", systemImage: "trash")
                            }
                        }
                }
            }
        }
    }

    private var placeholderRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Platzhalter-Token").font(.headline)
            Text("mm_00000000…").font(.footnote.monospaced())
            Text("Erstellt am 01.01.2026").font(.caption)
        }
        .redacted(reason: .placeholder)
    }

    private func errorState(_ message: String) -> some View {
        ContentUnavailableView {
            Label(
                viewModel.isOffline ? "Offline" : "Laden fehlgeschlagen",
                systemImage: viewModel.isOffline ? "wifi.slash" : "exclamationmark.triangle"
            )
        } description: {
            Text(viewModel.isOffline
                 ? "Tokens sind nur mit Verbindung zum Server verfügbar."
                 : message)
        } actions: {
            Button("Erneut versuchen") {
                Task { await viewModel.load() }
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Audit

    @ViewBuilder
    private var auditSection: some View {
        Section {
            if viewModel.isLoading && !viewModel.hasLoaded {
                Text("Wird geladen …")
                    .foregroundStyle(.secondary)
                    .redacted(reason: .placeholder)
            } else if viewModel.auditEntries.isEmpty {
                Text(viewModel.loadError != nil && viewModel.tokens.isEmpty
                     ? "Nicht verfügbar."
                     : "Noch keine Zugriffe.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.auditEntries) { entry in
                    McpAuditRow(entry: entry)
                }
            }
        } header: {
            Text("Letzte Zugriffe")
        } footer: {
            if !viewModel.auditEntries.isEmpty {
                Text("Die letzten \(viewModel.auditEntries.count) Aufrufe über den MCP-Server, neueste zuerst.")
            }
        }
    }
}

// MARK: - Rows

private struct ApiTokenRow: View {
    let token: ApiToken

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(token.name)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: Theme.Spacing.s)
                if token.isOauth {
                    connectedChip
                }
                scopeChip
            }
            Text("\(token.tokenPrefix)…")
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                detail("Erstellt am", Formatters.mediumDate(token.createdAt))
                detail("Zuletzt verwendet", token.lastUsedAt.map(Formatters.dateTime) ?? "Nie")
                if token.isRevoked {
                    detail("Status", "Widerrufen", color: .orange)
                } else if let expiresAt = token.expiresAt {
                    detail("Läuft ab",
                           token.isExpired ? "Abgelaufen" : Formatters.mediumDate(expiresAt),
                           color: token.isExpired ? .orange : nil)
                } else {
                    detail("Läuft ab", "Unbegrenzt")
                }
            }
            .font(.caption)
            .padding(.top, 2)
        }
        .padding(.vertical, 2)
        .opacity(token.isRevoked || token.isExpired ? 0.6 : 1)
    }

    private var scopeChip: some View {
        let isWrite = token.scopeValue == .write
        return Text(token.scopeLabel)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.vertical, 3)
            .background(
                Capsule().fill((isWrite ? Theme.Colors.accent : Theme.Colors.primary).opacity(0.14))
            )
            .foregroundStyle(isWrite ? Theme.Colors.accent : Theme.Colors.primary)
    }

    /// Marks tokens that were issued through the OAuth consent flow rather
    /// than created by hand in Settings.
    private var connectedChip: some View {
        Label("Verbunden", systemImage: "link")
            .labelStyle(.titleAndIcon)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.purple.opacity(0.14)))
            .foregroundStyle(Color.purple)
            .accessibilityLabel("Über OAuth verbunden")
    }

    private func detail(_ label: String, _ value: String, color: Color? = nil) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Text(label).foregroundStyle(.secondary)
            Text(value).foregroundStyle(color ?? .primary)
        }
    }
}

private struct McpAuditRow: View {
    let entry: McpAuditEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.tool)
                    .font(.subheadline.weight(.semibold).monospaced())
                    .lineLimit(1)
                Spacer(minLength: Theme.Spacing.s)
                Text(entry.outcomeValue?.label ?? entry.outcome)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(outcomeColor)
            }
            HStack(spacing: Theme.Spacing.xs) {
                Text(Formatters.dateTime(entry.createdAt))
                Text("·")
                Text(entry.tokenName ?? "Token #\(entry.tokenId)")
                    .lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if let detail = entry.detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    private var outcomeColor: Color {
        switch entry.outcomeValue {
        case .ok: .green
        case .denied: .orange
        case .error: Theme.Colors.accent
        case nil: .secondary
        }
    }
}

#Preview {
    NavigationStack {
        ApiTokensView()
    }
}
