import Foundation

// MARK: - Part ↔ defect links (server-backed)

/// "This part fixes that open Mangel", keyed by the local client ids the UI
/// works with.
struct IssuePartLink: Hashable, Codable {
    let issueId: UUID
    let partId: UUID
}

/// One row of `GET /api/issue-parts` — server ids on both ends.
struct ServerIssuePartLink: Hashable, Codable {
    let issueId: Int
    let partId: Int
    let createdAt: String?
}

struct IssuePartLinksResponse: Decodable {
    let links: [ServerIssuePartLink]
}

/// A link change made on this device and not yet confirmed by the server.
/// Keyed by client ids so it survives the issue/part not having a server id
/// yet (created offline); the ids are resolved when the queue is flushed.
struct IssuePartLinkOp: Hashable, Codable {
    enum Kind: String, Codable { case link, unlink }
    let kind: Kind
    let issueId: UUID
    let partId: UUID

    var pair: IssuePartLink { IssuePartLink(issueId: issueId, partId: partId) }
}

/// The pure rules behind `IssuePartLinkStore`: queueing, resolving server ids
/// to client ids and the overlay of pending changes. Kept free of SwiftData
/// and networking so it can be tested.
enum IssuePartLinks {
    /// What the local store knows about issues and parts: client id → server
    /// id (`nil` while waiting for its first push). Records absent here are
    /// gone (deleted, or pending delete).
    struct Index {
        var issueServerIds: [UUID: Int?] = [:]
        var partServerIds: [UUID: Int?] = [:]
        private(set) var issueByServer: [Int: UUID] = [:]
        private(set) var partByServer: [Int: UUID] = [:]

        init(issues: [(clientId: UUID, serverId: Int?)], parts: [(clientId: UUID, serverId: Int?)]) {
            for issue in issues {
                issueServerIds[issue.clientId] = .some(issue.serverId)
                if let sid = issue.serverId { issueByServer[sid] = issue.clientId }
            }
            for part in parts {
                partServerIds[part.clientId] = .some(part.serverId)
                if let sid = part.serverId { partByServer[sid] = part.clientId }
            }
        }
    }

    /// What to do with a queued change right now.
    enum FlushStep: Equatable {
        /// Both ends are on the server: send it.
        case send(issueId: Int, partId: Int)
        /// One end has not been pushed yet: keep it queued.
        case wait
        /// One end no longer exists locally: the change is moot.
        case drop
    }

    /// Adds a change, replacing any earlier queued change for the same pair
    /// (the latest intent wins; link → unlink before a flush just unlinks).
    static func enqueue(_ op: IssuePartLinkOp, into queue: [IssuePartLinkOp]) -> [IssuePartLinkOp] {
        queue.filter { $0.pair != op.pair } + [op]
    }

    static func step(for op: IssuePartLinkOp, in index: Index) -> FlushStep {
        guard let issue = index.issueServerIds[op.issueId], let part = index.partServerIds[op.partId] else {
            return .drop
        }
        guard let issueId = issue, let partId = part else { return .wait }
        return .send(issueId: issueId, partId: partId)
    }

    /// The links to show: the last server snapshot resolved to client ids
    /// (rows whose issue or part is not on this device are left out), with
    /// the queued local changes on top — local pending wins, like the sync.
    static func effective(server: [ServerIssuePartLink], pending: [IssuePartLinkOp],
                          index: Index) -> Set<IssuePartLink> {
        var links = Set(server.compactMap { link -> IssuePartLink? in
            guard let issue = index.issueByServer[link.issueId],
                  let part = index.partByServer[link.partId] else { return nil }
            return IssuePartLink(issueId: issue, partId: part)
        })
        for op in pending {
            switch op.kind {
            case .link:
                // A link to a record that is gone locally would never show anyway.
                if index.issueServerIds[op.issueId] != nil, index.partServerIds[op.partId] != nil {
                    links.insert(op.pair)
                }
            case .unlink:
                links.remove(op.pair)
            }
        }
        return links
    }

    /// The links the device kept before they moved to the server
    /// (`PartsPlanningStore.links`), as queued link operations. Sorted so the
    /// queue order is stable.
    static func migrationOps(from legacy: [UUID: Set<UUID>]) -> [IssuePartLinkOp] {
        legacy.flatMap { issue, parts in parts.map { IssuePartLinkOp(kind: .link, issueId: issue, partId: $0) } }
            .sorted { ($0.issueId.uuidString, $0.partId.uuidString) < ($1.issueId.uuidString, $1.partId.uuidString) }
    }

    /// Applies a confirmed change to the cached server snapshot, so the
    /// overlay stays right between the flush and the next fetch.
    static func applying(_ kind: IssuePartLinkOp.Kind, issueId: Int, partId: Int,
                         to server: [ServerIssuePartLink]) -> [ServerIssuePartLink] {
        let rest = server.filter { !($0.issueId == issueId && $0.partId == partId) }
        switch kind {
        case .link: return rest + [ServerIssuePartLink(issueId: issueId, partId: partId, createdAt: nil)]
        case .unlink: return rest
        }
    }
}
