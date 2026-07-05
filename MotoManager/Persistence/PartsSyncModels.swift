import Foundation
import SwiftData

// On-device source of truth for the parts inventory (parts, stock entries,
// consumptions, storage locations). Same sync scheme as SyncModels.swift:
// client-generated `clientId` as stable identity + idempotency key, optional
// `serverId` until the create is acknowledged, `syncState` driving the engine.
//
// Cross-entity references carry BOTH a clientId and an optional serverId
// (plain fields, no SwiftData relationships — codebase invariant): the
// clientId link works fully offline, and the engine resolves the serverId
// just-in-time when pushing.

@Model
final class SDPart {
    @Attribute(.unique) var clientId: UUID
    var serverId: Int?

    var partNumber: String
    var name: String
    var manufacturer: String
    var partDescription: String?
    var isPublic: Bool
    var seriesIds: [Int]
    /// Server-managed photo URL (uploads happen via the web client for now);
    /// default nil keeps this a lightweight SwiftData migration.
    var image: String?

    var syncState: SyncState
    var updatedAtLocal: Date
    var serverUpdatedAt: String?

    var syncAttempts: Int = 0
    var lastSyncError: String?

    init(
        clientId: UUID = UUID(),
        serverId: Int? = nil,
        partNumber: String,
        name: String,
        manufacturer: String = "BMW",
        partDescription: String? = nil,
        isPublic: Bool = false,
        seriesIds: [Int] = [],
        syncState: SyncState = .pendingCreate,
        updatedAtLocal: Date = .init()
    ) {
        self.clientId = clientId
        self.serverId = serverId
        self.partNumber = partNumber
        self.name = name
        self.manufacturer = manufacturer
        self.partDescription = partDescription
        self.isPublic = isPublic
        self.seriesIds = seriesIds
        self.syncState = syncState
        self.updatedAtLocal = updatedAtLocal
    }
}

@Model
final class SDPartStock {
    @Attribute(.unique) var clientId: UUID
    var serverId: Int?

    var partClientId: UUID
    var partServerId: Int?

    var quantity: Int
    var price: Double?
    var currency: String?
    var normalizedPrice: Double?
    var purchaseDate: String?
    var storageLocationClientId: UUID?
    var storageLocationServerId: Int?
    var notes: String?

    var syncState: SyncState
    var updatedAtLocal: Date
    var serverUpdatedAt: String?

    var syncAttempts: Int = 0
    var lastSyncError: String?

    init(
        clientId: UUID = UUID(),
        serverId: Int? = nil,
        partClientId: UUID,
        partServerId: Int? = nil,
        quantity: Int,
        syncState: SyncState = .pendingCreate,
        updatedAtLocal: Date = .init()
    ) {
        self.clientId = clientId
        self.serverId = serverId
        self.partClientId = partClientId
        self.partServerId = partServerId
        self.quantity = quantity
        self.syncState = syncState
        self.updatedAtLocal = updatedAtLocal
    }
}

@Model
final class SDPartConsumption {
    @Attribute(.unique) var clientId: UUID
    var serverId: Int?

    var partClientId: UUID
    var partServerId: Int?

    var maintenanceClientId: UUID?
    var maintenanceServerId: Int?

    var quantity: Int
    var date: String
    var notes: String?

    var syncState: SyncState
    var updatedAtLocal: Date
    var serverUpdatedAt: String?

    var syncAttempts: Int = 0
    var lastSyncError: String?

    init(
        clientId: UUID = UUID(),
        serverId: Int? = nil,
        partClientId: UUID,
        partServerId: Int? = nil,
        maintenanceClientId: UUID? = nil,
        maintenanceServerId: Int? = nil,
        quantity: Int,
        date: String,
        notes: String? = nil,
        syncState: SyncState = .pendingCreate,
        updatedAtLocal: Date = .init()
    ) {
        self.clientId = clientId
        self.serverId = serverId
        self.partClientId = partClientId
        self.partServerId = partServerId
        self.maintenanceClientId = maintenanceClientId
        self.maintenanceServerId = maintenanceServerId
        self.quantity = quantity
        self.date = date
        self.notes = notes
        self.syncState = syncState
        self.updatedAtLocal = updatedAtLocal
    }
}

@Model
final class SDStorageLocation {
    @Attribute(.unique) var clientId: UUID
    var serverId: Int?

    var name: String
    var parentClientId: UUID?
    var parentServerId: Int?

    var syncState: SyncState
    var updatedAtLocal: Date
    var serverUpdatedAt: String?

    var syncAttempts: Int = 0
    var lastSyncError: String?

    init(
        clientId: UUID = UUID(),
        serverId: Int? = nil,
        name: String,
        parentClientId: UUID? = nil,
        parentServerId: Int? = nil,
        syncState: SyncState = .pendingCreate,
        updatedAtLocal: Date = .init()
    ) {
        self.clientId = clientId
        self.serverId = serverId
        self.name = name
        self.parentClientId = parentClientId
        self.parentServerId = parentServerId
        self.syncState = syncState
        self.updatedAtLocal = updatedAtLocal
    }
}

extension SDPart: SyncFailureTracking {}
extension SDPartStock: SyncFailureTracking {}
extension SDPartConsumption: SyncFailureTracking {}
extension SDStorageLocation: SyncFailureTracking {}
