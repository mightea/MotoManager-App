import Foundation
import Combine
import SwiftData

/// User-facing sync state, surfaced by the status pill.
enum SyncStatus: Equatable {
    case idle                    // online, nothing pending
    case syncing                 // a push/pull is in flight
    case pending(Int)            // online, N local changes waiting for the next sync
    case offline(pending: Int)   // no connectivity (pending may be 0)
    case error(String)           // last sync attempt failed
}

/// Drives offline-first sync: pushes locally-changed records to the server, then
/// pulls server changes via `?since`. Reconciles by `clientId` so retried creates
/// never duplicate, and resolves conflicts last-write-wins (local pending wins,
/// since the user just made the change).
@MainActor
final class SyncEngine: ObservableObject {
    static let shared = SyncEngine()

    @Published private(set) var status: SyncStatus = .idle

    /// Shared with the view models so local writes and pulled changes are consistent.
    private let context: ModelContext = PersistenceController.shared.mainContext
    private let net = NetworkManager.shared
    private let connectivity = ConnectivityMonitor.shared
    private var cancellables = Set<AnyCancellable>()
    private var isSyncing = false
    /// Motorcycle IDs to pull on the next connectivity-triggered sync.
    private var knownMotorcycleIds: [Int] = []
    /// After this many consecutive failed pushes a record is treated as poisoned:
    /// it stops retrying every sync (which would pin the pending badge forever) and
    /// is surfaced as a failure the user can retry or clear.
    private let maxSyncAttempts = 5

    private init() {
        context.autosaveEnabled = true

        // Flush the moment connectivity returns; just refresh the badge when it drops.
        connectivity.$isOnline
            .removeDuplicates()
            .sink { [weak self] online in
                guard let self else { return }
                if online {
                    Task { await self.sync(motorcycleIds: self.knownMotorcycleIds) }
                } else {
                    self.refreshStatus()
                }
            }
            .store(in: &cancellables)

        refreshStatus()
    }

    // MARK: - Public API

    /// Push all pending changes, then pull updates for the given motorcycles.
    func sync(motorcycleIds: [Int]) async {
        if !motorcycleIds.isEmpty { knownMotorcycleIds = motorcycleIds }
        guard connectivity.isOnline else { refreshStatus(); return }
        guard !isSyncing else { return }

        isSyncing = true
        status = .syncing
        do {
            try await push()
            try await pull(motorcycleIds: motorcycleIds.isEmpty ? knownMotorcycleIds : motorcycleIds)
            isSyncing = false
            refreshStatus()
        } catch {
            isSyncing = false
            AppLog.error("Sync failed: \(error.localizedDescription)")
            status = .error(error.localizedDescription)
        }
    }

    /// Fire-and-forget trigger after a local write.
    func requestSync(motorcycleIds: [Int]) {
        Task { await sync(motorcycleIds: motorcycleIds) }
    }

    // MARK: - Push

    private func push() async throws {
        try await pushMaintenance()
        try await pushTorque()
        try await pushIssues()
    }

    private func pushMaintenance() async throws {
        let pending = (try? context.fetch(FetchDescriptor<SDMaintenanceRecord>()))?
            .filter { $0.syncState.isPending && $0.syncAttempts < maxSyncAttempts } ?? []
        for record in pending {
            do {
                switch record.syncState {
                case .pendingDelete:
                    if let sid = record.serverId {
                        try await net.deleteMaintenanceRecord(motorcycleId: record.motorcycleId, recordId: sid)
                    }
                    context.delete(record)
                case .pendingUpdate where record.serverId != nil:
                    let dto = try await net.updateMaintenanceRecord(
                        motorcycleId: record.motorcycleId, recordId: record.serverId!, payload: record.toPayload())
                    record.apply(dto)
                    record.clearSyncFailure()
                default: // pendingCreate (or pendingUpdate with no serverId yet)
                    let dto = try await net.createMaintenanceRecord(
                        motorcycleId: record.motorcycleId, payload: record.toPayload())
                    record.apply(dto)
                    record.clearSyncFailure()
                }
            } catch let error as APIError where isFatal(error) {
                throw error
            } catch {
                record.recordSyncFailure(error)
                AppLog.error("Push maintenance \(record.clientId) failed (attempt \(record.syncAttempts)): \(error.localizedDescription)")
            }
        }
        try? context.save()
    }

    private func pushTorque() async throws {
        let pending = (try? context.fetch(FetchDescriptor<SDTorqueSpec>()))?
            .filter { $0.syncState.isPending && $0.syncAttempts < maxSyncAttempts } ?? []
        for spec in pending {
            do {
                switch spec.syncState {
                case .pendingDelete:
                    if let sid = spec.serverId {
                        try await net.deleteTorqueSpec(motorcycleId: spec.motorcycleId, specId: sid)
                    }
                    context.delete(spec)
                case .pendingUpdate where spec.serverId != nil:
                    let dto = try await net.updateTorqueSpec(
                        motorcycleId: spec.motorcycleId, specId: spec.serverId!, payload: spec.toPayload())
                    spec.apply(dto)
                    spec.clearSyncFailure()
                default:
                    let dto = try await net.createTorqueSpec(
                        motorcycleId: spec.motorcycleId, payload: spec.toPayload())
                    spec.apply(dto)
                    spec.clearSyncFailure()
                }
            } catch let error as APIError where isFatal(error) {
                throw error
            } catch {
                spec.recordSyncFailure(error)
                AppLog.error("Push torque \(spec.clientId) failed (attempt \(spec.syncAttempts)): \(error.localizedDescription)")
            }
        }
        try? context.save()
    }

    private func pushIssues() async throws {
        let pending = (try? context.fetch(FetchDescriptor<SDIssue>()))?
            .filter { $0.syncState.isPending && $0.syncAttempts < maxSyncAttempts } ?? []
        for issue in pending {
            do {
                switch issue.syncState {
                case .pendingDelete:
                    if let sid = issue.serverId {
                        try await net.deleteIssue(motorcycleId: issue.motorcycleId, issueId: sid)
                    }
                    context.delete(issue)
                case .pendingUpdate where issue.serverId != nil:
                    let dto = try await net.updateIssue(
                        motorcycleId: issue.motorcycleId, issueId: issue.serverId!, payload: issue.toPayload())
                    issue.apply(dto)
                    issue.clearSyncFailure()
                default:
                    let dto = try await net.createIssue(
                        motorcycleId: issue.motorcycleId, payload: issue.toPayload())
                    issue.apply(dto)
                    issue.clearSyncFailure()
                }
            } catch let error as APIError where isFatal(error) {
                throw error
            } catch {
                issue.recordSyncFailure(error)
                AppLog.error("Push issue \(issue.clientId) failed (attempt \(issue.syncAttempts)): \(error.localizedDescription)")
            }
        }
        try? context.save()
    }

    /// Transport/auth failures should abort the whole run (we're offline or the
    /// session is dead); per-record server errors are logged and left pending.
    private func isFatal(_ error: APIError) -> Bool {
        switch error {
        case .unauthorized, .notAuthenticated: return true
        default: return false
        }
    }

    // MARK: - Pull

    private func pull(motorcycleIds: [Int]) async throws {
        for id in motorcycleIds {
            try await pullMaintenance(motorcycleId: id)
            try await pullTorque(motorcycleId: id)
            try await pullIssues(motorcycleId: id)
        }
    }

    private func pullMaintenance(motorcycleId: Int) async throws {
        let cursorKey = SyncCursor.key("maintenance", motorcycleId)
        let dtos = try await net.fetchMaintenance(motorcycleId: motorcycleId, since: SyncCursor.get(cursorKey))
        let existing = (try? context.fetch(FetchDescriptor<SDMaintenanceRecord>(
            predicate: #Predicate { $0.motorcycleId == motorcycleId }
        ))) ?? []
        for dto in dtos {
            let local = match(dto.clientId, dto.id, in: existing, clientId: \.clientId, serverId: \.serverId)
            if let local {
                if local.syncState.isPending { continue } // local change wins (LWW)
                if dto.deletedAt != nil { context.delete(local) } else { local.apply(dto) }
            } else if dto.deletedAt == nil {
                context.insert(SDMaintenanceRecord.make(from: dto))
            }
        }
        // Persist the pulled rows BEFORE advancing the cursor. If the save (or a
        // later resource, or an app kill) fails, the cursor must not have moved
        // past records that were never durably written — otherwise the next pull
        // skips them forever. A throw here aborts the run and leaves the cursor put.
        try context.save()
        SyncCursor.advance(cursorKey, with: dtos.compactMap(\.updatedAt))
    }

    private func pullTorque(motorcycleId: Int) async throws {
        let cursorKey = SyncCursor.key("torque", motorcycleId)
        let dtos = try await net.fetchTorqueSpecs(motorcycleId: motorcycleId, since: SyncCursor.get(cursorKey))
        let existing = (try? context.fetch(FetchDescriptor<SDTorqueSpec>(
            predicate: #Predicate { $0.motorcycleId == motorcycleId }
        ))) ?? []
        for dto in dtos {
            let local = match(dto.clientId, dto.id, in: existing, clientId: \.clientId, serverId: \.serverId)
            if let local {
                if local.syncState.isPending { continue }
                if dto.deletedAt != nil { context.delete(local) } else { local.apply(dto) }
            } else if dto.deletedAt == nil {
                context.insert(SDTorqueSpec.make(from: dto))
            }
        }
        try context.save() // durable before cursor advance — see pullMaintenance
        SyncCursor.advance(cursorKey, with: dtos.compactMap(\.updatedAt))
    }

    private func pullIssues(motorcycleId: Int) async throws {
        let cursorKey = SyncCursor.key("issues", motorcycleId)
        let dtos = try await net.fetchIssues(motorcycleId: motorcycleId, since: SyncCursor.get(cursorKey))
        let existing = (try? context.fetch(FetchDescriptor<SDIssue>(
            predicate: #Predicate { $0.motorcycleId == motorcycleId }
        ))) ?? []
        for dto in dtos {
            let local = match(dto.clientId, dto.id, in: existing, clientId: \.clientId, serverId: \.serverId)
            if let local {
                if local.syncState.isPending { continue }
                if dto.deletedAt != nil { context.delete(local) } else { local.apply(dto) }
            } else if dto.deletedAt == nil {
                context.insert(SDIssue.make(from: dto))
            }
        }
        try context.save() // durable before cursor advance — see pullMaintenance
        SyncCursor.advance(cursorKey, with: dtos.compactMap(\.updatedAt))
    }

    /// Match a server DTO to a local model by clientId first, then serverId.
    private func match<T>(
        _ dtoClientId: String?, _ dtoServerId: Int,
        in items: [T], clientId: (T) -> UUID, serverId: (T) -> Int?
    ) -> T? {
        if let cid = dtoClientId.flatMap(UUID.init(uuidString:)),
           let hit = items.first(where: { clientId($0) == cid }) {
            return hit
        }
        return items.first(where: { serverId($0) == dtoServerId })
    }

    // MARK: - Status

    func refreshStatus() {
        let pending = pendingCount()
        let failed = failedCount()
        if !connectivity.isOnline {
            status = .offline(pending: pending + failed)
        } else if failed > 0 {
            // Poisoned records won't clear on their own — surface them as an error
            // instead of a perpetual "N pending" the user can't act on.
            status = .error("\(failed) fehlgeschlagen")
        } else if pending > 0 {
            status = .pending(pending)
        } else {
            status = .idle
        }
    }

    /// Records still retrying (attempts below the cap).
    func pendingCount() -> Int {
        countPending { $0 < maxSyncAttempts }
    }

    /// Poisoned records that have exhausted their retry budget.
    func failedCount() -> Int {
        countPending { $0 >= maxSyncAttempts }
    }

    private func countPending(_ attempts: (Int) -> Bool) -> Int {
        let m = (try? context.fetch(FetchDescriptor<SDMaintenanceRecord>()))?
            .filter { $0.syncState.isPending && attempts($0.syncAttempts) }.count ?? 0
        let t = (try? context.fetch(FetchDescriptor<SDTorqueSpec>()))?
            .filter { $0.syncState.isPending && attempts($0.syncAttempts) }.count ?? 0
        let i = (try? context.fetch(FetchDescriptor<SDIssue>()))?
            .filter { $0.syncState.isPending && attempts($0.syncAttempts) }.count ?? 0
        return m + t + i
    }

    /// Clear the failure counters on poisoned records so the next sync retries
    /// them. Wired to a user-facing "retry" affordance (Stage 4 UX).
    func retryFailed(motorcycleIds: [Int]) {
        for r in (try? context.fetch(FetchDescriptor<SDMaintenanceRecord>())) ?? [] where r.syncAttempts > 0 {
            r.clearSyncFailure()
        }
        for r in (try? context.fetch(FetchDescriptor<SDTorqueSpec>())) ?? [] where r.syncAttempts > 0 {
            r.clearSyncFailure()
        }
        for r in (try? context.fetch(FetchDescriptor<SDIssue>())) ?? [] where r.syncAttempts > 0 {
            r.clearSyncFailure()
        }
        try? context.save()
        requestSync(motorcycleIds: motorcycleIds)
    }
}

/// Per-resource, per-motorcycle `?since` cursor persisted in UserDefaults.
enum SyncCursor {
    static func key(_ resource: String, _ motorcycleId: Int) -> String {
        "com.motomanager.sync.\(resource).\(motorcycleId)"
    }
    static func get(_ key: String) -> String? {
        UserDefaults.standard.string(forKey: key)
    }
    /// Advance the cursor to the latest `updatedAt` seen (lexical max — the
    /// server uses a single RFC3339 millis-Z format so this is chronological).
    static func advance(_ key: String, with updatedAts: [String]) {
        guard let newest = updatedAts.max() else { return }
        if let current = get(key), current >= newest { return }
        UserDefaults.standard.set(newest, forKey: key)
    }
}
