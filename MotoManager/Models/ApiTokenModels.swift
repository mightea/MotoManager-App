import Foundation

/// Personal API tokens for the backend's MCP (Model Context Protocol) server
/// at `<baseURL>/mcp`. They let AI clients (Claude Code, Claude Desktop, the
/// Claude API) read — and with `write` scope, add to — the user's own garage
/// data. DTOs for `/api/settings/api-tokens` and `/api/settings/mcp-audit`.

/// Token scope as accepted by the backend. `write` allows creating records
/// (maintenance, fuel stops, issues, expenses, parts) — never deleting, never
/// admin operations.
nonisolated enum ApiTokenScope: String, CaseIterable, Identifiable, Codable {
    case read
    case write

    var id: String { rawValue }

    var label: String {
        switch self {
        case .read: "Lesen"
        case .write: "Lesen & Schreiben"
        }
    }

    var shortLabel: String {
        switch self {
        case .read: "Lesen"
        case .write: "Schreiben"
        }
    }
}

nonisolated struct ApiToken: Codable, Identifiable, Hashable {
    let id: Int
    let userId: Int
    let name: String
    /// First characters of the secret (e.g. `mm_3f9a…`) — the only part the
    /// backend keeps in clear text after creation.
    let tokenPrefix: String
    /// `"read"` or `"write"`.
    let scope: String
    /// RFC3339 timestamps.
    let createdAt: String
    let lastUsedAt: String?
    let expiresAt: String?
    let revokedAt: String?

    var scopeValue: ApiTokenScope? { ApiTokenScope(rawValue: scope) }

    var scopeLabel: String { scopeValue?.label ?? scope }

    var isRevoked: Bool { revokedAt != nil }

    /// Uses the shared (main-actor) formatter cache; read from views only.
    @MainActor var isExpired: Bool {
        guard let expiresAt, let date = Formatters.parseTimestamp(expiresAt) else { return false }
        return date < Date()
    }
}

/// `POST /api/settings/api-tokens` — the only place the secret is ever
/// returned. Present it once; it cannot be fetched again.
nonisolated struct ApiTokenCreated: Codable {
    let apiToken: ApiToken
    /// `mm_` + 48 hex characters.
    let token: String
}

nonisolated struct ApiTokenListResponse: Codable {
    let apiTokens: [ApiToken]
}

/// One MCP tool call, as logged by the backend (newest first).
nonisolated struct McpAuditEntry: Codable, Identifiable, Hashable {
    let id: Int
    let tokenId: Int
    let tokenName: String?
    let tool: String
    let arguments: String?
    /// `"ok"`, `"error"` or `"denied"`.
    let outcome: String
    let detail: String?
    let createdAt: String

    enum Outcome: String {
        case ok, error, denied

        var label: String {
            switch self {
            case .ok: "OK"
            case .error: "Fehler"
            case .denied: "Abgelehnt"
            }
        }
    }

    var outcomeValue: Outcome? { Outcome(rawValue: outcome) }
}

nonisolated struct McpAuditListResponse: Codable {
    let entries: [McpAuditEntry]
}
