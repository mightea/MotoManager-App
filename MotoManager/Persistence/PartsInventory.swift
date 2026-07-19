import Foundation
import SwiftData

/// Shared inventory derivations over the local store, usable from any view
/// model (PartsViewModel, AddMaintenanceView's parts section). On-hand is
/// always derived — live stock minus live consumption — mirroring the server.
@MainActor
enum PartsInventory {
    /// Live (non-pending-delete) stock entries of a part.
    static func stocks(for partClientId: UUID, in context: ModelContext) -> [SDPartStock] {
        ((try? context.fetch(FetchDescriptor<SDPartStock>())) ?? [])
            .filter { $0.partClientId == partClientId && $0.syncState != .pendingDelete }
            .sorted { ($0.purchaseDate ?? "") > ($1.purchaseDate ?? "") }
    }

    /// Live (non-pending-delete) consumption entries of a part.
    static func consumptions(for partClientId: UUID, in context: ModelContext) -> [SDPartConsumption] {
        ((try? context.fetch(FetchDescriptor<SDPartConsumption>())) ?? [])
            .filter { $0.partClientId == partClientId && $0.syncState != .pendingDelete }
            .sorted { $0.date > $1.date }
    }

    /// Reverse lookup: the parts consumed by a maintenance record ("Verwendete
    /// Teile"). Matches by clientId first (offline-created links), then by
    /// server id (links pulled from the server).
    static func consumptions(forMaintenance record: SDMaintenanceRecord, in context: ModelContext) -> [SDPartConsumption] {
        ((try? context.fetch(FetchDescriptor<SDPartConsumption>())) ?? [])
            .filter { consumption in
                guard consumption.syncState != .pendingDelete else { return false }
                if consumption.maintenanceClientId == record.clientId { return true }
                if let serverId = record.serverId, consumption.maintenanceServerId == serverId { return true }
                return false
            }
            .sorted { $0.date > $1.date }
    }

    static func onHand(for partClientId: UUID, in context: ModelContext) -> Int {
        let stocked = stocks(for: partClientId, in: context).reduce(0) { $0 + $1.quantity }
        let consumed = consumptions(for: partClientId, in: context).reduce(0) { $0 + $1.quantity }
        return stocked - consumed
    }

    /// All live parts with a positive on-hand — the pick list for "Verwendete
    /// Teile" in the maintenance form.
    static func availableParts(in context: ModelContext) -> [SDPart] {
        ((try? context.fetch(FetchDescriptor<SDPart>())) ?? [])
            .filter { $0.syncState != .pendingDelete && onHand(for: $0.clientId, in: context) > 0 }
            .sorted { $0.name < $1.name }
    }

    /// Record a consumption (offline-first). Validates on-hand locally, exactly
    /// like the server does, so the pending record can't be rejected later.
    @discardableResult
    static func recordConsumption(
        part: SDPart,
        quantity: Int,
        date: String,
        notes: String? = nil,
        maintenanceClientId: UUID? = nil,
        maintenanceServerId: Int? = nil,
        in context: ModelContext
    ) -> SDPartConsumption? {
        guard quantity >= 1, quantity <= onHand(for: part.clientId, in: context) else { return nil }
        let consumption = SDPartConsumption(
            partClientId: part.clientId,
            partServerId: part.serverId,
            maintenanceClientId: maintenanceClientId,
            maintenanceServerId: maintenanceServerId,
            quantity: quantity,
            date: date,
            notes: (notes?.isEmpty == false) ? notes : nil,
            syncState: .pendingCreate
        )
        context.insert(consumption)
        return consumption
    }
}
