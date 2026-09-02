import Testing
import Foundation
@testable import MotoManager

// MARK: - Personal API token decoding

/// Fixtures mirror the live responses of GET/POST /api/settings/api-tokens
/// and GET /api/settings/mcp-audit.
struct ApiTokenModelTests {
    @Test func decodesTokenList() throws {
        let json = """
        {"apiTokens":[
          {"id":7,"userId":3,"name":"Claude Code","tokenPrefix":"mm_3f9a2b","scope":"write",
           "createdAt":"2026-09-01T10:15:00Z","lastUsedAt":"2026-09-02T08:00:00Z",
           "expiresAt":"2026-12-01T10:15:00Z","revokedAt":null},
          {"id":8,"userId":3,"name":"Desktop","tokenPrefix":"mm_aa11bb","scope":"read",
           "createdAt":"2026-09-02T09:00:00.123Z","lastUsedAt":null,"expiresAt":null,"revokedAt":null}
        ]}
        """
        let response = try JSONDecoder().decode(ApiTokenListResponse.self, from: Data(json.utf8))
        #expect(response.apiTokens.count == 2)

        let first = response.apiTokens[0]
        #expect(first.id == 7)
        #expect(first.name == "Claude Code")
        #expect(first.tokenPrefix == "mm_3f9a2b")
        #expect(first.scopeValue == .write)
        #expect(first.scopeLabel == "Lesen & Schreiben")
        #expect(first.lastUsedAt == "2026-09-02T08:00:00Z")
        #expect(first.isRevoked == false)

        let second = response.apiTokens[1]
        #expect(second.scopeValue == .read)
        #expect(second.lastUsedAt == nil)
        #expect(second.expiresAt == nil)
    }

    @Test func decodesCreatedTokenWithSecret() throws {
        let json = """
        {"apiToken":{"id":9,"userId":3,"name":"Neu","tokenPrefix":"mm_0123ab","scope":"read",
          "createdAt":"2026-09-02T12:00:00Z","lastUsedAt":null,"expiresAt":null,"revokedAt":null},
         "token":"mm_0123abcdef0123abcdef0123abcdef0123abcdef01234567"}
        """
        let created = try JSONDecoder().decode(ApiTokenCreated.self, from: Data(json.utf8))
        #expect(created.apiToken.id == 9)
        #expect(created.token.hasPrefix("mm_"))
        #expect(created.token.count == 51)
    }

    @Test func decodesAuditEntries() throws {
        let json = """
        {"entries":[
          {"id":42,"tokenId":7,"tokenName":"Claude Code","tool":"list_motorcycles","arguments":null,
           "outcome":"ok","detail":null,"createdAt":"2026-09-02T08:00:00Z"},
          {"id":41,"tokenId":8,"tokenName":null,"tool":"create_issue","arguments":"{\\"title\\":\\"x\\"}",
           "outcome":"denied","detail":"scope read","createdAt":"2026-09-02T07:59:00Z"}
        ]}
        """
        let response = try JSONDecoder().decode(McpAuditListResponse.self, from: Data(json.utf8))
        #expect(response.entries.count == 2)
        #expect(response.entries[0].outcomeValue == .ok)
        #expect(response.entries[1].outcomeValue == .denied)
        #expect(response.entries[1].tokenName == nil)
        #expect(response.entries[1].detail == "scope read")
    }

    @Test @MainActor func parsesRfc3339Timestamps() {
        #expect(Formatters.parseTimestamp("2026-09-02T08:00:00Z") != nil)
        #expect(Formatters.parseTimestamp("2026-09-02T08:00:00.123Z") != nil)
        #expect(Formatters.parseTimestamp("2026-09-02T10:00:00+02:00") != nil)
        #expect(Formatters.parseTimestamp("not a date") == nil)
    }
}
