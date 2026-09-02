import Foundation
import Combine

/// Drives the "KI-Zugriff (MCP)" screen: the user's personal API tokens plus
/// the recent MCP audit trail. Online-only — there is no offline store for
/// tokens, so a failed load surfaces as an error/empty state.
@MainActor
final class ApiTokensViewModel: ObservableObject {
    @Published var tokens: [ApiToken] = []
    @Published var auditEntries: [McpAuditEntry] = []
    @Published var isLoading = false
    @Published var hasLoaded = false
    /// Error of the last full load (shown as the screen's empty state when
    /// nothing could be fetched).
    @Published var loadError: String?
    @Published var isOffline = false
    /// One-shot error for actions (revoke) — bound to an alert.
    @Published var actionError: String?

    func load() async {
        isLoading = true
        defer { isLoading = false; hasLoaded = true }
        do {
            async let tokens = NetworkManager.shared.fetchApiTokens()
            async let audit = NetworkManager.shared.fetchMcpAudit(limit: 50)
            let (fetchedTokens, fetchedAudit) = try await (tokens, audit)
            self.tokens = fetchedTokens
            self.auditEntries = fetchedAudit
            loadError = nil
            isOffline = false
        } catch {
            if case APIError.offline = error { isOffline = true } else { isOffline = false }
            loadError = error.localizedDescription
        }
    }

    /// Called by the create sheet on success so the list reflects the new
    /// token without a round trip.
    func insert(_ token: ApiToken) {
        tokens.insert(token, at: 0)
        loadError = nil
        isOffline = false
    }

    func revoke(_ token: ApiToken) async {
        do {
            try await NetworkManager.shared.revokeApiToken(id: token.id)
            tokens.removeAll { $0.id == token.id }
        } catch {
            actionError = error.localizedDescription
        }
    }
}
