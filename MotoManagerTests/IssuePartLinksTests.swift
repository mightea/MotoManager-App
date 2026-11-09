import Foundation
import Testing
@testable import MotoManager

@MainActor
struct IssuePartLinksTests {
    private let brake = UUID(), chain = UUID(), offline = UUID()
    private let pads = UUID(), kit = UUID(), fresh = UUID()

    /// brake/chain and pads/kit are on the server (ids 1/2 and 10/20);
    /// `offline` (issue) and `fresh` (part) wait for their first push.
    private var index: IssuePartLinks.Index {
        IssuePartLinks.Index(
            issues: [(brake, 1), (chain, 2), (offline, nil)],
            parts: [(pads, 10), (kit, 20), (fresh, nil)])
    }

    private func op(_ kind: IssuePartLinkOp.Kind, _ issue: UUID, _ part: UUID) -> IssuePartLinkOp {
        IssuePartLinkOp(kind: kind, issueId: issue, partId: part)
    }

    @Test func serverLinksResolveToClientIds() {
        let links = IssuePartLinks.effective(
            server: [.init(issueId: 1, partId: 10, createdAt: nil),
                     .init(issueId: 2, partId: 20, createdAt: nil),
                     .init(issueId: 99, partId: 10, createdAt: nil)], // issue not on device
            pending: [], index: index)
        #expect(links == [IssuePartLink(issueId: brake, partId: pads), IssuePartLink(issueId: chain, partId: kit)])
    }

    @Test func pendingChangesWinOverTheSnapshot() {
        let links = IssuePartLinks.effective(
            server: [.init(issueId: 1, partId: 10, createdAt: nil)],
            pending: [op(.unlink, brake, pads), op(.link, offline, fresh), op(.link, UUID(), pads)],
            index: index)
        // Unlinked locally; linked locally (not yet pushed); a link to an
        // issue that no longer exists is left out.
        #expect(links == [IssuePartLink(issueId: offline, partId: fresh)])
    }

    @Test func enqueueKeepsOnlyTheLatestIntentPerPair() {
        var queue: [IssuePartLinkOp] = []
        queue = IssuePartLinks.enqueue(op(.link, brake, pads), into: queue)
        queue = IssuePartLinks.enqueue(op(.link, chain, kit), into: queue)
        queue = IssuePartLinks.enqueue(op(.unlink, brake, pads), into: queue)
        #expect(queue == [op(.link, chain, kit), op(.unlink, brake, pads)])
    }

    @Test func flushStepsSendWaitOrDrop() {
        #expect(IssuePartLinks.step(for: op(.link, brake, kit), in: index) == .send(issueId: 1, partId: 20))
        #expect(IssuePartLinks.step(for: op(.link, offline, pads), in: index) == .wait)
        #expect(IssuePartLinks.step(for: op(.unlink, chain, fresh), in: index) == .wait)
        #expect(IssuePartLinks.step(for: op(.link, UUID(), pads), in: index) == .drop)
        #expect(IssuePartLinks.step(for: op(.link, brake, UUID()), in: index) == .drop)
    }

    @Test func legacyLinksBecomeLinkOps() {
        let ops = IssuePartLinks.migrationOps(from: [brake: [pads, kit], chain: [kit]])
        #expect(ops.count == 3)
        #expect(ops.allSatisfy { $0.kind == .link })
        #expect(Set(ops.map(\.pair)) == [IssuePartLink(issueId: brake, partId: pads),
                                         IssuePartLink(issueId: brake, partId: kit),
                                         IssuePartLink(issueId: chain, partId: kit)])
        #expect(ops == IssuePartLinks.migrationOps(from: [chain: [kit], brake: [kit, pads]]))
    }

    @Test func confirmedChangesUpdateTheSnapshot() {
        let server: [ServerIssuePartLink] = [.init(issueId: 1, partId: 10, createdAt: "x")]
        let linked = IssuePartLinks.applying(.link, issueId: 2, partId: 20, to: server)
        #expect(linked.map { [$0.issueId, $0.partId] } == [[1, 10], [2, 20]])
        #expect(IssuePartLinks.applying(.link, issueId: 1, partId: 10, to: server).count == 1)
        #expect(IssuePartLinks.applying(.unlink, issueId: 1, partId: 10, to: server).isEmpty)
    }

    // MARK: - Store

    @MainActor private final class FakeAPI: IssuePartLinkAPI {
        var server: [ServerIssuePartLink] = []
        var calls: [String] = []
        var fetchError: Error?
        var linkError: Error?

        func fetchIssuePartLinks() async throws -> [ServerIssuePartLink] {
            calls.append("GET")
            if let fetchError { throw fetchError }
            return server
        }

        func linkIssuePart(issueId: Int, partId: Int) async throws {
            calls.append("PUT \(issueId)/\(partId)")
            if let linkError { throw linkError }
            if !server.contains(where: { $0.issueId == issueId && $0.partId == partId }) {
                server.append(.init(issueId: issueId, partId: partId, createdAt: nil))
            }
        }

        func unlinkIssuePart(issueId: Int, partId: Int) async throws {
            calls.append("DELETE \(issueId)/\(partId)")
            guard server.contains(where: { $0.issueId == issueId && $0.partId == partId }) else {
                throw APIError.http(status: 404, message: "Link not found")
            }
            server.removeAll { $0.issueId == issueId && $0.partId == partId }
        }
    }

    private func withDefaults(_ body: (UserDefaults) async throws -> Void) async rethrows {
        let name = "issueLinks-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try await body(defaults)
    }

    @Test func storeFlushesQueueAndKeepsUnpushedOnes() async {
        await withDefaults { defaults in
            let api = FakeAPI()
            api.server = [.init(issueId: 2, partId: 20, createdAt: nil)]
            let index = self.index
            let store = IssuePartLinkStore(defaults: defaults, api: api, index: { index })
            store.importLegacy([brake: [pads], offline: [kit]])
            #expect(store.isLinked(issue: brake, part: pads))
            #expect(store.isLinked(issue: offline, part: kit))

            await store.sync()
            #expect(api.calls == ["GET", "PUT 1/10", "GET"])
            #expect(store.pending == [op(.link, offline, kit)]) // waits for the issue's push
            #expect(store.links == [IssuePartLink(issueId: brake, partId: pads),
                                    IssuePartLink(issueId: chain, partId: kit),
                                    IssuePartLink(issueId: offline, partId: kit)])

            // Survives a relaunch: snapshot and queue are persisted.
            let reloaded = IssuePartLinkStore(defaults: defaults, api: api, index: { index })
            #expect(reloaded.links == store.links)
            #expect(reloaded.pending == store.pending)
        }
    }

    @Test func unlinkOfMissingLinkCountsAsDone() async {
        await withDefaults { defaults in
            let api = FakeAPI()
            let index = self.index
            let store = IssuePartLinkStore(defaults: defaults, api: api, index: { index })
            store.importLegacy([:])
            // Queue directly through the public API, then let the sync run.
            store.setLinked(false, issue: brake, part: pads)
            await store.sync()
            #expect(store.pending.isEmpty)
            #expect(api.calls.contains("DELETE 1/10"))
        }
    }

    @Test func serverWithoutEndpointKeepsTheQueue() async {
        await withDefaults { defaults in
            let api = FakeAPI()
            api.fetchError = APIError.http(status: 404, message: nil)
            let index = self.index
            let store = IssuePartLinkStore(defaults: defaults, api: api, index: { index })
            store.importLegacy([brake: [pads]])
            await store.sync()
            #expect(api.calls == ["GET"])
            #expect(store.pending == [op(.link, brake, pads)])
            #expect(store.isLinked(issue: brake, part: pads))
        }
    }

    @Test func offlineStopsTheFlush() async {
        await withDefaults { defaults in
            let api = FakeAPI()
            api.linkError = APIError.offline
            let index = self.index
            let store = IssuePartLinkStore(defaults: defaults, api: api, index: { index })
            store.importLegacy([brake: [pads], chain: [kit]])
            await store.sync()
            #expect(api.calls.filter { $0.hasPrefix("PUT") }.count == 1)
            #expect(store.pending.count == 2)
        }
    }

    @Test func clearAllForgetsEverything() async {
        await withDefaults { defaults in
            let api = FakeAPI()
            api.server = [.init(issueId: 1, partId: 10, createdAt: nil)]
            let index = self.index
            let store = IssuePartLinkStore(defaults: defaults, api: api, index: { index })
            store.importLegacy([chain: [kit]])
            await store.sync()
            store.clearAll()
            #expect(store.links.isEmpty)
            let reloaded = IssuePartLinkStore(defaults: defaults, api: api, index: { index })
            #expect(reloaded.links.isEmpty)
            #expect(reloaded.pending.isEmpty)
        }
    }
}
