import Combine
import Foundation
import SwiftData

/// The server calls the link store needs; `NetworkManager` in the app, a fake
/// in tests.
protocol IssuePartLinkAPI {
    func fetchIssuePartLinks() async throws -> [ServerIssuePartLink]
    func linkIssuePart(issueId: Int, partId: Int) async throws
    func unlinkIssuePart(issueId: Int, partId: Int) async throws
}

extension NetworkManager: IssuePartLinkAPI {}

/// Part ↔ defect links ("this part fixes that Mangel"), backed by the server
/// (`/api/issue-parts`, migration 063) and usable offline.
///
/// - The last server snapshot (server ids) is cached in UserDefaults and
///   resolved to the client ids of the local `SDIssue`/`SDPart` rows on every
///   recompute, so links appear as soon as their issue/part is on the device.
/// - Changes are optimistic: they land in a persisted queue (client ids) and
///   show at once; `sync()` flushes the queue when both ends have a server id
///   (else the change waits), then refetches the snapshot.
/// - `sync()` runs after every successful `SyncEngine` sync (links don't bump
///   `issues.updatedAt`, so the issue pull can't notice them) and after each
///   local change.
@MainActor
final class IssuePartLinkStore: ObservableObject {
    static let shared: IssuePartLinkStore = {
        let store = IssuePartLinkStore()
        // One-time move of the links the device used to keep on its own.
        store.importLegacy(PartsPlanningStore.shared.takeLegacyLinks())
        return store
    }()

    /// Effective links, by client ids.
    @Published private(set) var links: Set<IssuePartLink> = []

    private(set) var serverLinks: [ServerIssuePartLink]
    private(set) var pending: [IssuePartLinkOp]

    private let defaults: UserDefaults
    private let api: IssuePartLinkAPI
    private let index: @MainActor () -> IssuePartLinks.Index
    private static let key = "com.motomanager.issuePartLinks"

    private var isSyncing = false
    private var needsAnotherSync = false

    private struct Snapshot: Codable {
        var server: [ServerIssuePartLink] = []
        var pending: [IssuePartLinkOp] = []
    }

    init(defaults: UserDefaults = .standard,
         api: IssuePartLinkAPI? = nil,
         index: @escaping @MainActor () -> IssuePartLinks.Index = IssuePartLinkStore.localIndex) {
        self.defaults = defaults
        self.api = api ?? NetworkManager.shared
        self.index = index
        let snapshot = defaults.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) } ?? Snapshot()
        serverLinks = snapshot.server
        pending = snapshot.pending
        recompute()
    }

    // MARK: - Reads

    func isLinked(issue: UUID, part: UUID) -> Bool {
        links.contains(IssuePartLink(issueId: issue, partId: part))
    }

    /// Part client ids by issue client id (for `PartNeeds`).
    var partsByIssue: [UUID: Set<UUID>] {
        links.reduce(into: [:]) { $0[$1.issueId, default: []].insert($1.partId) }
    }

    func parts(forIssue issue: UUID) -> Set<UUID> {
        Set(links.filter { $0.issueId == issue }.map(\.partId))
    }

    func issues(forPart part: UUID) -> Set<UUID> {
        Set(links.filter { $0.partId == part }.map(\.issueId))
    }

    // MARK: - Writes

    func setLinked(_ linked: Bool, issue: UUID, part: UUID) {
        let op = IssuePartLinkOp(kind: linked ? .link : .unlink, issueId: issue, partId: part)
        pending = IssuePartLinks.enqueue(op, into: pending)
        persist()
        recompute()
        Task { await sync() }
    }

    func toggle(issue: UUID, part: UUID) {
        setLinked(!isLinked(issue: issue, part: part), issue: issue, part: part)
    }

    /// Queues links kept on the device before they moved to the server. A
    /// pair already queued keeps its newer intent.
    func importLegacy(_ legacy: [UUID: Set<UUID>]) {
        let ops = IssuePartLinks.migrationOps(from: legacy)
        guard !ops.isEmpty else { return }
        let queued = Set(pending.map(\.pair))
        pending += ops.filter { !queued.contains($0.pair) }
        persist()
        recompute()
    }

    /// Logout: drop everything (the next account starts empty).
    func clearAll() {
        serverLinks = []
        pending = []
        links = []
        defaults.removeObject(forKey: Self.key)
    }

    // MARK: - Sync

    /// Re-resolve the links against the local issues/parts (e.g. after a pull
    /// brought in the issue a cached link points to).
    func recompute() {
        let resolved = IssuePartLinks.effective(server: serverLinks, pending: pending, index: index())
        if resolved != links { links = resolved }
    }

    /// Fetch the snapshot, flush the queue, refetch if anything was sent.
    /// Never throws: failures leave the queue for the next run.
    func sync() async {
        // Signed out: the fetch fails locally (notAuthenticated), no request.
        guard !isSyncing else { needsAnotherSync = true; return }
        isSyncing = true
        defer { isSyncing = false }
        repeat {
            needsAnotherSync = false
            await syncOnce()
        } while needsAnotherSync
    }

    private func syncOnce() async {
        // Fetch first: it doubles as the probe for a server without the
        // endpoint (404), where sending would wrongly drop queued links.
        do {
            serverLinks = try await api.fetchIssuePartLinks()
            persist()
        } catch {
            AppLog.debug("Issue-part links not fetched: \(error.localizedDescription)")
            recompute()
            return
        }
        if await flush() {
            if let fresh = try? await api.fetchIssuePartLinks() {
                serverLinks = fresh
                persist()
            }
        }
        recompute()
    }

    /// Sends what can be sent. Returns whether anything reached the server.
    private func flush() async -> Bool {
        var sentAny = false
        let local = index()
        queue: for op in pending {
            switch IssuePartLinks.step(for: op, in: local) {
            case .wait:
                continue
            case .drop:
                remove(op)
            case .send(let issueId, let partId):
                do {
                    switch op.kind {
                    case .link: try await api.linkIssuePart(issueId: issueId, partId: partId)
                    case .unlink: try await api.unlinkIssuePart(issueId: issueId, partId: partId)
                    }
                    serverLinks = IssuePartLinks.applying(op.kind, issueId: issueId, partId: partId, to: serverLinks)
                    remove(op)
                    sentAny = true
                } catch APIError.http(status: 404, _) {
                    // Unlink: already gone. Link: the issue or part is gone on
                    // the server. Either way there's nothing left to do.
                    serverLinks = IssuePartLinks.applying(.unlink, issueId: issueId, partId: partId, to: serverLinks)
                    remove(op)
                    sentAny = true
                } catch APIError.offline, APIError.unauthorized, APIError.notAuthenticated {
                    break queue // no point trying the rest now
                } catch {
                    // Server-side failure: keep it queued for the next sync.
                    AppLog.error("Issue-part link \(op.kind.rawValue) failed: \(error.localizedDescription)")
                }
            }
        }
        persist()
        return sentAny
    }

    /// Removes the op only if it is still the queued intent for its pair (the
    /// user may have changed it while the request was in flight).
    private func remove(_ op: IssuePartLinkOp) {
        if let i = pending.firstIndex(of: op) { pending.remove(at: i) }
    }

    private func persist() {
        let snapshot = Snapshot(server: serverLinks, pending: pending)
        if let data = try? JSONEncoder().encode(snapshot) { defaults.set(data, forKey: Self.key) }
    }

    /// The live issues and parts in SwiftData (pending deletes count as gone).
    static func localIndex() -> IssuePartLinks.Index {
        let context = PersistenceController.shared.mainContext
        let issues = ((try? context.fetch(FetchDescriptor<SDIssue>())) ?? [])
            .filter { $0.syncState != .pendingDelete }
            .map { (clientId: $0.clientId, serverId: $0.serverId) }
        let parts = ((try? context.fetch(FetchDescriptor<SDPart>())) ?? [])
            .filter { $0.syncState != .pendingDelete }
            .map { (clientId: $0.clientId, serverId: $0.serverId) }
        return IssuePartLinks.Index(issues: issues, parts: parts)
    }
}
