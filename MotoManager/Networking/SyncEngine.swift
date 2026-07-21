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

    /// Push all pending changes, then pull updates for the given motorcycles
    /// and the user-scoped parts inventory.
    func sync(motorcycleIds: [Int]) async {
        if !motorcycleIds.isEmpty { knownMotorcycleIds = motorcycleIds }
        guard connectivity.isOnline else { refreshStatus(); return }
        guard !isSyncing else { return }

        isSyncing = true
        status = .syncing
        do {
            try await push()
            try await pull(motorcycleIds: motorcycleIds.isEmpty ? knownMotorcycleIds : motorcycleIds)
            // Parts inventory is user-scoped, so it pulls once per sync (not per
            // motorcycle). Runs after the per-motorcycle pull so consumption
            // records can link to freshly pulled maintenance records.
            try await pullPartsInventory()
            isSyncing = false
            refreshStatus()
        } catch is CancellationError {
            // A superseded/cancelled sync is not a failure — recompute the badge
            // rather than leaving it stuck on ".syncing" or flagging an error.
            isSyncing = false
            refreshStatus()
        } catch let urlError as URLError where urlError.code == .cancelled {
            // URLSession surfaces task cancellation as URLError.cancelled, which
            // isn't a CancellationError; treat it the same — not a real failure.
            isSyncing = false
            refreshStatus()
        } catch {
            isSyncing = false
            if case APIError.offline = error {
                // No connection or the backend is unreachable — this isn't a
                // failure the user must act on; show "Offline" and retry when
                // connectivity returns. Set it explicitly (not via refreshStatus)
                // since the device may still report online when only the backend
                // is down.
                AppLog.debug("Sync deferred: offline")
                status = .offline(pending: pendingCount() + failedCount())
            } else {
                AppLog.error("Sync failed: \(error.localizedDescription)")
                status = .error(error.localizedDescription)
            }
        }
    }

    /// Wipe all synced local data and cursors. Called on logout so a different
    /// account never inherits stale user-level cursors (which would silently
    /// skip that account's records) or another user's parts inventory.
    func resetLocalState() {
        func deleteAll<T: PersistentModel>(_ type: T.Type) {
            for item in (try? context.fetch(FetchDescriptor<T>())) ?? [] {
                context.delete(item)
            }
        }
        deleteAll(SDMaintenanceRecord.self)
        deleteAll(SDTorqueSpec.self)
        deleteAll(SDIssue.self)
        deleteAll(SDMotorcycleDetail.self)
        deleteAll(SDPart.self)
        deleteAll(SDPartStock.self)
        deleteAll(SDPartConsumption.self)
        deleteAll(SDStorageLocation.self)
        guard PersistenceMonitor.shared.save(context, operation: "Lokale Daten beim Abmelden löschen") else {
            status = .error("Lokale Daten konnten nicht gelöscht werden.")
            return
        }
        SyncCursor.clearAll()
        knownMotorcycleIds = []
        refreshStatus()
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
        try await pushDetails()
        // Parts inventory: dependencies push first (locations before stocks
        // that reference them, parts before stocks/consumptions). Maintenance
        // already pushed above, so consumption→repair links resolve.
        try await pushStorageLocations()
        try await pushParts()
        try await pushPartStocks()
        try await pushPartConsumptions()
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
        try context.save()
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
        try context.save()
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
        try context.save()
    }

    private func pushDetails() async throws {
        let pending = (try? context.fetch(FetchDescriptor<SDMotorcycleDetail>()))?
            .filter { $0.syncState.isPending && $0.syncAttempts < maxSyncAttempts } ?? []
        for detail in pending {
            do {
                switch detail.syncState {
                case .pendingDelete:
                    if let sid = detail.serverId {
                        try await net.deleteMotorcycleDetail(motorcycleId: detail.motorcycleId, detailId: sid)
                    }
                    context.delete(detail)
                case .pendingUpdate where detail.serverId != nil:
                    let dto = try await net.updateMotorcycleDetail(
                        motorcycleId: detail.motorcycleId, detailId: detail.serverId!, payload: detail.toPayload())
                    detail.apply(dto)
                    detail.clearSyncFailure()
                default:
                    let dto = try await net.createMotorcycleDetail(
                        motorcycleId: detail.motorcycleId, payload: detail.toPayload())
                    detail.apply(dto)
                    detail.clearSyncFailure()
                }
            } catch let error as APIError where isFatal(error) {
                throw error
            } catch {
                detail.recordSyncFailure(error)
                AppLog.error("Push detail \(detail.clientId) failed (attempt \(detail.syncAttempts)): \(error.localizedDescription)")
            }
        }
        try context.save()
    }

    private func pushStorageLocations() async throws {
        // Parents must reach the server before children (the payload carries the
        // parent's serverId), so loop until a pass makes no progress: each pass
        // pushes every node whose parent is already resolved.
        var pending = (try? context.fetch(FetchDescriptor<SDStorageLocation>()))?
            .filter { $0.syncState.isPending && $0.syncAttempts < maxSyncAttempts } ?? []
        var progressed = true
        while progressed, !pending.isEmpty {
            progressed = false
            var deferred: [SDStorageLocation] = []
            for location in pending {
                // Resolve the parent reference just-in-time. A parent that exists
                // locally but has no serverId yet is deferred (not a failure).
                var parentServerId: Int?
                if let pcid = location.parentClientId {
                    if let parent = fetchStorageLocation(clientId: pcid) {
                        guard let sid = parent.serverId else {
                            deferred.append(location)
                            continue
                        }
                        parentServerId = sid
                    } else {
                        parentServerId = location.parentServerId
                    }
                }
                do {
                    switch location.syncState {
                    case .pendingDelete:
                        if let sid = location.serverId {
                            try await net.deleteStorageLocation(locationId: sid)
                        }
                        context.delete(location)
                    case .pendingUpdate where location.serverId != nil:
                        let dto = try await net.updateStorageLocation(
                            locationId: location.serverId!,
                            payload: location.toPayload(parentServerId: parentServerId))
                        location.apply(dto)
                        location.clearSyncFailure()
                    default:
                        let dto = try await net.createStorageLocation(
                            payload: location.toPayload(parentServerId: parentServerId))
                        location.apply(dto)
                        location.clearSyncFailure()
                    }
                    progressed = true
                } catch let error as APIError where isFatal(error) {
                    throw error
                } catch {
                    location.recordSyncFailure(error)
                    AppLog.error("Push storage location \(location.clientId) failed (attempt \(location.syncAttempts)): \(error.localizedDescription)")
                }
            }
            pending = deferred
        }
        try context.save()
    }

    private func pushParts() async throws {
        let pending = (try? context.fetch(FetchDescriptor<SDPart>()))?
            .filter { $0.syncState.isPending && $0.syncAttempts < maxSyncAttempts } ?? []
        for part in pending {
            do {
                switch part.syncState {
                case .pendingDelete:
                    if let sid = part.serverId {
                        try await net.deletePart(partId: sid)
                    }
                    context.delete(part)
                case .pendingUpdate where part.serverId != nil:
                    let dto = try await net.updatePart(partId: part.serverId!, payload: part.toPayload())
                    part.apply(dto)
                    part.clearSyncFailure()
                default:
                    let dto = try await net.createPart(payload: part.toPayload())
                    part.apply(dto)
                    part.clearSyncFailure()
                }
            } catch let error as APIError where isFatal(error) {
                throw error
            } catch {
                part.recordSyncFailure(error)
                AppLog.error("Push part \(part.clientId) failed (attempt \(part.syncAttempts)): \(error.localizedDescription)")
            }
        }
        try context.save()
    }

    private func pushPartStocks() async throws {
        let pending = (try? context.fetch(FetchDescriptor<SDPartStock>()))?
            .filter { $0.syncState.isPending && $0.syncAttempts < maxSyncAttempts } ?? []
        for stock in pending {
            // The parent part must be on the server first; if its create is still
            // pending (or just failed this run) the stock waits for the next run
            // without burning a retry attempt.
            guard let partServerId = resolvePartServerId(for: stock.partClientId, fallback: stock.partServerId) else {
                if stock.syncState == .pendingDelete, stock.serverId == nil {
                    context.delete(stock) // never reached the server; nothing to delete remotely
                }
                continue
            }
            var storageLocationServerId: Int?
            if let lcid = stock.storageLocationClientId,
               let location = fetchStorageLocation(clientId: lcid) {
                storageLocationServerId = location.serverId
            } else {
                storageLocationServerId = stock.storageLocationServerId
            }
            do {
                switch stock.syncState {
                case .pendingDelete:
                    if let sid = stock.serverId {
                        try await net.deletePartStock(stockId: sid)
                    }
                    context.delete(stock)
                case .pendingUpdate where stock.serverId != nil:
                    let dto = try await net.updatePartStock(
                        stockId: stock.serverId!,
                        payload: stock.toPayload(partServerId: partServerId, storageLocationServerId: storageLocationServerId))
                    stock.apply(dto)
                    stock.clearSyncFailure()
                default:
                    let dto = try await net.createPartStock(
                        payload: stock.toPayload(partServerId: partServerId, storageLocationServerId: storageLocationServerId))
                    stock.apply(dto)
                    stock.clearSyncFailure()
                }
            } catch let error as APIError where isFatal(error) {
                throw error
            } catch {
                stock.recordSyncFailure(error)
                AppLog.error("Push part stock \(stock.clientId) failed (attempt \(stock.syncAttempts)): \(error.localizedDescription)")
            }
        }
        try context.save()
    }

    private func pushPartConsumptions() async throws {
        let pending = (try? context.fetch(FetchDescriptor<SDPartConsumption>()))?
            .filter { $0.syncState.isPending && $0.syncAttempts < maxSyncAttempts } ?? []
        for consumption in pending {
            guard let partServerId = resolvePartServerId(for: consumption.partClientId, fallback: consumption.partServerId) else {
                if consumption.syncState == .pendingDelete, consumption.serverId == nil {
                    context.delete(consumption)
                }
                continue
            }
            // Resolve the repair link; a local repair that hasn't pushed yet
            // defers the consumption to the next run (maintenance pushes first,
            // so this only happens when the repair's own push failed).
            var maintenanceRecordId = consumption.maintenanceServerId
            if let mcid = consumption.maintenanceClientId {
                if let record = fetchMaintenanceRecord(clientId: mcid) {
                    guard let sid = record.serverId else { continue }
                    maintenanceRecordId = sid
                }
            }
            do {
                switch consumption.syncState {
                case .pendingDelete:
                    if let sid = consumption.serverId {
                        try await net.deletePartConsumption(consumptionId: sid)
                    }
                    context.delete(consumption)
                case .pendingUpdate where consumption.serverId != nil:
                    let dto = try await net.updatePartConsumption(
                        consumptionId: consumption.serverId!,
                        payload: consumption.toPayload(partServerId: partServerId, maintenanceRecordId: maintenanceRecordId))
                    consumption.apply(dto)
                    consumption.clearSyncFailure()
                default:
                    let dto = try await net.createPartConsumption(
                        payload: consumption.toPayload(partServerId: partServerId, maintenanceRecordId: maintenanceRecordId))
                    consumption.apply(dto)
                    consumption.clearSyncFailure()
                }
            } catch let error as APIError where isFatal(error) {
                throw error
            } catch {
                consumption.recordSyncFailure(error)
                AppLog.error("Push part consumption \(consumption.clientId) failed (attempt \(consumption.syncAttempts)): \(error.localizedDescription)")
            }
        }
        try context.save()
    }

    // MARK: - Cross-entity resolution (clientId graph -> server ids)

    /// The parent part's serverId, via the local clientId link when the part
    /// still exists locally, else the stored fallback. `nil` means "not on the
    /// server yet" and the dependent record should wait.
    private func resolvePartServerId(for partClientId: UUID, fallback: Int?) -> Int? {
        if let part = fetchPart(clientId: partClientId) {
            return part.serverId
        }
        return fallback
    }

    private func fetchPart(clientId: UUID) -> SDPart? {
        ((try? context.fetch(FetchDescriptor<SDPart>())) ?? [])
            .first(where: { $0.clientId == clientId })
    }

    private func fetchStorageLocation(clientId: UUID) -> SDStorageLocation? {
        ((try? context.fetch(FetchDescriptor<SDStorageLocation>())) ?? [])
            .first(where: { $0.clientId == clientId })
    }

    private func fetchMaintenanceRecord(clientId: UUID) -> SDMaintenanceRecord? {
        ((try? context.fetch(FetchDescriptor<SDMaintenanceRecord>())) ?? [])
            .first(where: { $0.clientId == clientId })
    }

    /// Transport/auth failures should abort the whole run (we're offline or the
    /// session is dead); per-record server errors are logged and left pending.
    private func isFatal(_ error: APIError) -> Bool {
        switch error {
        case .unauthorized, .notAuthenticated, .offline: return true
        default: return false
        }
    }

    // MARK: - Pull

    private func pull(motorcycleIds: [Int]) async throws {
        for id in motorcycleIds {
            try await pullMaintenance(motorcycleId: id)
            try await pullTorque(motorcycleId: id)
            try await pullIssues(motorcycleId: id)
            try await pullDetails(motorcycleId: id)
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

    private func pullDetails(motorcycleId: Int) async throws {
        let cursorKey = SyncCursor.key("details", motorcycleId)
        let dtos = try await net.fetchMotorcycleDetails(motorcycleId: motorcycleId, since: SyncCursor.get(cursorKey))
        let existing = (try? context.fetch(FetchDescriptor<SDMotorcycleDetail>(
            predicate: #Predicate { $0.motorcycleId == motorcycleId }
        ))) ?? []
        for dto in dtos {
            let local = match(dto.clientId, dto.id, in: existing, clientId: \.clientId, serverId: \.serverId)
            if let local {
                if local.syncState.isPending { continue }
                if dto.deletedAt != nil { context.delete(local) } else { local.apply(dto) }
            } else if dto.deletedAt == nil {
                context.insert(SDMotorcycleDetail.make(from: dto))
            }
        }
        try context.save() // durable before cursor advance — see pullMaintenance
        SyncCursor.advance(cursorKey, with: dtos.compactMap(\.updatedAt))
    }

    /// Pull the user-scoped parts inventory. Order matters: storage locations
    /// and parts land before the stock/consumption rows that reference them.
    private func pullPartsInventory() async throws {
        try await pullStorageLocations()
        try await pullParts()
        try await pullPartStocks()
        try await pullPartConsumptions()
    }

    private func pullStorageLocations() async throws {
        let cursorKey = SyncCursor.userKey("storageLocations")
        let dtos = try await net.fetchStorageLocations(since: SyncCursor.get(cursorKey))
        let existing = (try? context.fetch(FetchDescriptor<SDStorageLocation>())) ?? []
        // Two passes so a child can resolve its parent's clientId even when both
        // arrive in the same batch: insert/update everything first, link after.
        for dto in dtos {
            let local = match(dto.clientId, dto.id, in: existing, clientId: \.clientId, serverId: \.serverId)
            if let local {
                if local.syncState.isPending { continue }
                if dto.deletedAt != nil { context.delete(local) } else { local.apply(dto) }
            } else if dto.deletedAt == nil {
                context.insert(SDStorageLocation.make(from: dto, parentClientId: nil))
            }
        }
        let all = (try? context.fetch(FetchDescriptor<SDStorageLocation>())) ?? []
        for location in all where !location.syncState.isPending {
            if let psid = location.parentServerId {
                location.parentClientId = all.first(where: { $0.serverId == psid })?.clientId
            } else {
                location.parentClientId = nil
            }
        }
        try context.save() // durable before cursor advance — see pullMaintenance
        SyncCursor.advance(cursorKey, with: dtos.compactMap(\.updatedAt))
    }

    private func pullParts() async throws {
        let cursorKey = SyncCursor.userKey("parts")
        let dtos = try await net.fetchParts(since: SyncCursor.get(cursorKey))
        let existing = (try? context.fetch(FetchDescriptor<SDPart>())) ?? []
        for dto in dtos {
            let local = match(dto.clientId, dto.id, in: existing, clientId: \.clientId, serverId: \.serverId)
            if let local {
                if local.syncState.isPending { continue }
                if dto.deletedAt != nil { context.delete(local) } else { local.apply(dto) }
            } else if dto.deletedAt == nil {
                context.insert(SDPart.make(from: dto))
            }
        }
        try context.save() // durable before cursor advance — see pullMaintenance
        SyncCursor.advance(cursorKey, with: dtos.compactMap(\.updatedAt))
    }

    private func pullPartStocks() async throws {
        let cursorKey = SyncCursor.userKey("partStocks")
        let dtos = try await net.fetchPartStocks(since: SyncCursor.get(cursorKey))
        let existing = (try? context.fetch(FetchDescriptor<SDPartStock>())) ?? []
        let parts = (try? context.fetch(FetchDescriptor<SDPart>())) ?? []
        let locations = (try? context.fetch(FetchDescriptor<SDStorageLocation>())) ?? []
        for dto in dtos {
            let local = match(dto.clientId, dto.id, in: existing, clientId: \.clientId, serverId: \.serverId)
            if let local {
                if local.syncState.isPending { continue }
                if dto.deletedAt != nil { context.delete(local) } else { local.apply(dto) }
            } else if dto.deletedAt == nil {
                // Parts pulled first in this run, so the parent should be local;
                // if it isn't (inconsistent server data), skip rather than crash.
                guard let partClientId = parts.first(where: { $0.serverId == dto.partId })?.clientId else {
                    AppLog.error("Pulled stock \(dto.id) references unknown part \(dto.partId); skipping")
                    continue
                }
                let locationClientId = dto.storageLocationId.flatMap { sid in
                    locations.first(where: { $0.serverId == sid })?.clientId
                }
                context.insert(SDPartStock.make(
                    from: dto, partClientId: partClientId, storageLocationClientId: locationClientId))
            }
        }
        try context.save() // durable before cursor advance — see pullMaintenance
        SyncCursor.advance(cursorKey, with: dtos.compactMap(\.updatedAt))
    }

    private func pullPartConsumptions() async throws {
        let cursorKey = SyncCursor.userKey("partConsumptions")
        let dtos = try await net.fetchPartConsumptions(since: SyncCursor.get(cursorKey))
        let existing = (try? context.fetch(FetchDescriptor<SDPartConsumption>())) ?? []
        let parts = (try? context.fetch(FetchDescriptor<SDPart>())) ?? []
        let maintenance = (try? context.fetch(FetchDescriptor<SDMaintenanceRecord>())) ?? []
        for dto in dtos {
            let local = match(dto.clientId, dto.id, in: existing, clientId: \.clientId, serverId: \.serverId)
            if let local {
                if local.syncState.isPending { continue }
                if dto.deletedAt != nil { context.delete(local) } else { local.apply(dto) }
            } else if dto.deletedAt == nil {
                guard let partClientId = parts.first(where: { $0.serverId == dto.partId })?.clientId else {
                    AppLog.error("Pulled consumption \(dto.id) references unknown part \(dto.partId); skipping")
                    continue
                }
                let maintenanceClientId = dto.maintenanceRecordId.flatMap { mid in
                    maintenance.first(where: { $0.serverId == mid })?.clientId
                }
                context.insert(SDPartConsumption.make(
                    from: dto, partClientId: partClientId, maintenanceClientId: maintenanceClientId))
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
        func count<T: PersistentModel & SyncFailureTracking>(
            _ type: T.Type, isPending: (T) -> Bool
        ) -> Int {
            ((try? context.fetch(FetchDescriptor<T>())) ?? [])
                .filter { isPending($0) && attempts($0.syncAttempts) }.count
        }
        return count(SDMaintenanceRecord.self) { $0.syncState.isPending }
            + count(SDTorqueSpec.self) { $0.syncState.isPending }
            + count(SDIssue.self) { $0.syncState.isPending }
            + count(SDMotorcycleDetail.self) { $0.syncState.isPending }
            + count(SDPart.self) { $0.syncState.isPending }
            + count(SDPartStock.self) { $0.syncState.isPending }
            + count(SDPartConsumption.self) { $0.syncState.isPending }
            + count(SDStorageLocation.self) { $0.syncState.isPending }
    }

    /// Clear the failure counters on poisoned records so the next sync retries
    /// them. Wired to a user-facing "retry" affordance (Stage 4 UX).
    func retryFailed(motorcycleIds: [Int]) {
        func clear<T: PersistentModel & SyncFailureTracking>(_ type: T.Type) {
            for r in (try? context.fetch(FetchDescriptor<T>())) ?? [] where r.syncAttempts > 0 {
                r.clearSyncFailure()
            }
        }
        clear(SDMaintenanceRecord.self)
        clear(SDTorqueSpec.self)
        clear(SDIssue.self)
        clear(SDMotorcycleDetail.self)
        clear(SDPart.self)
        clear(SDPartStock.self)
        clear(SDPartConsumption.self)
        clear(SDStorageLocation.self)
        guard PersistenceMonitor.shared.save(context, operation: "Synchronisierung erneut vorbereiten") else {
            status = .error("Synchronisierung konnte nicht vorbereitet werden.")
            return
        }
        requestSync(motorcycleIds: motorcycleIds)
    }
}

/// Per-resource `?since` cursor persisted in UserDefaults. Motorcycle-scoped
/// resources key by motorcycle id; user-scoped resources (parts inventory)
/// share a single `.user` cursor per resource.
enum SyncCursor {
    private static let prefix = "com.motomanager.sync."

    static func key(_ resource: String, _ motorcycleId: Int) -> String {
        "\(prefix)\(resource).\(motorcycleId)"
    }
    static func userKey(_ resource: String) -> String {
        "\(prefix)\(resource).user"
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
    /// Drop every sync cursor (all resources, all scopes). Called on logout so
    /// the next account starts from a full pull instead of inheriting cursors
    /// that would silently skip its records.
    static func clearAll() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
        }
    }
}
