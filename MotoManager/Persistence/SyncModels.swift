import Foundation
import SwiftData

// On-device source of truth for the syncable write entities (maintenance,
// torque, issues). Each carries a client-generated `clientId` (the stable
// identity + server idempotency key), an optional `serverId` (nil until the
// server acknowledges the create), and a `syncState` driving the SyncEngine.
//
// `description` is deliberately spelled `recordDescription` to avoid clashing
// with `CustomStringConvertible`.

@Model
final class SDMaintenanceRecord {
    @Attribute(.unique) var clientId: UUID
    var serverId: Int?
    var motorcycleId: Int

    var date: String
    var odo: Int
    var recordType: String
    var cost: Double?
    var normalizedCost: Double?
    var currency: String?
    var recordDescription: String?
    var summary: String?
    var brand: String?
    var model: String?
    var tirePosition: String?
    var tireSize: String?
    var dotCode: String?
    var batteryType: String?
    var fluidType: String?
    var viscosity: String?
    var oilType: String?
    var inspectionLocation: String?
    var locationId: Int?
    var fuelType: String?
    var fuelAmount: Double?
    var pricePerUnit: Double?
    var latitude: Double?
    var longitude: Double?
    var locationName: String?
    var fuelConsumption: Double?
    var tripDistance: Double?
    var parentId: Int?

    var syncState: SyncState
    var updatedAtLocal: Date
    var serverUpdatedAt: String?

    /// Push-failure tracking. Bounds retries so a permanently-rejected record
    /// (e.g. a 400/422) stops retrying every sync forever and can be surfaced to
    /// the user and cleared. Defaults make this a lightweight SwiftData migration.
    var syncAttempts: Int = 0
    var lastSyncError: String?

    init(
        clientId: UUID = UUID(),
        serverId: Int? = nil,
        motorcycleId: Int,
        date: String,
        odo: Int,
        recordType: String,
        syncState: SyncState = .pendingCreate,
        updatedAtLocal: Date = .init()
    ) {
        self.clientId = clientId
        self.serverId = serverId
        self.motorcycleId = motorcycleId
        self.date = date
        self.odo = odo
        self.recordType = recordType
        self.syncState = syncState
        self.updatedAtLocal = updatedAtLocal
    }
}

/// Shared push-failure bookkeeping for the syncable entities, so the SyncEngine
/// can bound retries and surface poisoned records uniformly.
protocol SyncFailureTracking: AnyObject {
    var syncAttempts: Int { get set }
    var lastSyncError: String? { get set }
}

extension SyncFailureTracking {
    /// Record a failed push attempt.
    func recordSyncFailure(_ error: Error) {
        syncAttempts += 1
        lastSyncError = error.localizedDescription
    }

    /// Reset after a successful push (or a manual retry).
    func clearSyncFailure() {
        syncAttempts = 0
        lastSyncError = nil
    }
}

extension SDMaintenanceRecord: SyncFailureTracking {}
extension SDTorqueSpec: SyncFailureTracking {}
extension SDIssue: SyncFailureTracking {}

@Model
final class SDTorqueSpec {
    @Attribute(.unique) var clientId: UUID
    var serverId: Int?
    var motorcycleId: Int

    var category: String
    var name: String
    var torque: Double
    var torqueEnd: Double?
    var variation: Double?
    var toolSize: String?
    var recordDescription: String?
    var createdAt: String

    var syncState: SyncState
    var updatedAtLocal: Date
    var serverUpdatedAt: String?

    /// Push-failure tracking. Bounds retries so a permanently-rejected record
    /// (e.g. a 400/422) stops retrying every sync forever and can be surfaced to
    /// the user and cleared. Defaults make this a lightweight SwiftData migration.
    var syncAttempts: Int = 0
    var lastSyncError: String?

    init(
        clientId: UUID = UUID(),
        serverId: Int? = nil,
        motorcycleId: Int,
        category: String,
        name: String,
        torque: Double,
        torqueEnd: Double? = nil,
        variation: Double? = nil,
        toolSize: String? = nil,
        recordDescription: String? = nil,
        createdAt: String = "",
        syncState: SyncState = .pendingCreate,
        updatedAtLocal: Date = .init()
    ) {
        self.clientId = clientId
        self.serverId = serverId
        self.motorcycleId = motorcycleId
        self.category = category
        self.name = name
        self.torque = torque
        self.torqueEnd = torqueEnd
        self.variation = variation
        self.toolSize = toolSize
        self.recordDescription = recordDescription
        self.createdAt = createdAt
        self.syncState = syncState
        self.updatedAtLocal = updatedAtLocal
    }
}

@Model
final class SDIssue {
    @Attribute(.unique) var clientId: UUID
    var serverId: Int?
    var motorcycleId: Int

    var odo: Int
    var title: String
    var recordDescription: String?
    var priority: String
    var status: String
    var date: String

    var syncState: SyncState
    var updatedAtLocal: Date
    var serverUpdatedAt: String?

    /// Push-failure tracking. Bounds retries so a permanently-rejected record
    /// (e.g. a 400/422) stops retrying every sync forever and can be surfaced to
    /// the user and cleared. Defaults make this a lightweight SwiftData migration.
    var syncAttempts: Int = 0
    var lastSyncError: String?

    init(
        clientId: UUID = UUID(),
        serverId: Int? = nil,
        motorcycleId: Int,
        odo: Int,
        title: String,
        recordDescription: String? = nil,
        priority: String = "medium",
        status: String = "new",
        date: String,
        syncState: SyncState = .pendingCreate,
        updatedAtLocal: Date = .init()
    ) {
        self.clientId = clientId
        self.serverId = serverId
        self.motorcycleId = motorcycleId
        self.odo = odo
        self.title = title
        self.recordDescription = recordDescription
        self.priority = priority
        self.status = status
        self.date = date
        self.syncState = syncState
        self.updatedAtLocal = updatedAtLocal
    }
}
