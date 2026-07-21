import Foundation
import Combine
import SwiftData

/// Drives the "Teile" tab: the user-scoped parts inventory (SwiftData,
/// offline-first) plus the online-only public browse and the cached series
/// lookup. Mirrors MotorcycleDetailViewModel's write pattern: mutate SwiftData
/// with a pending state, then persistAndSync().
@MainActor
class PartsViewModel: ObservableObject {
    private let modelContext = PersistenceController.shared.mainContext

    @Published var parts: [SDPart] = []
    @Published var storageLocations: [SDStorageLocation] = []
    @Published var series: [ModelSeries] = []

    @Published var publicParts: [PublicPart] = []
    @Published var isLoadingPublic = false
    @Published var publicError: String?

    private var cancellables = Set<AnyCancellable>()

    init() {
        // Re-publish the local arrays whenever a sync finishes, so remotely
        // pulled changes (incl. deletions, which the pushed detail pages'
        // auto-pop guards watch for) reach the UI without a manual refresh.
        SyncEngine.shared.$status
            .scan((SyncStatus.idle, SyncStatus.idle)) { pair, next in (pair.1, next) }
            .filter { pair in pair.0 == .syncing && pair.1 != .syncing }
            .sink { [weak self] _ in self?.reloadLocal() }
            .store(in: &cancellables)
    }

    // MARK: - Local reads

    func reloadLocal() {
        let allParts = (try? modelContext.fetch(FetchDescriptor<SDPart>(
            sortBy: [SortDescriptor(\.name)]
        ))) ?? []
        parts = allParts.filter { $0.syncState != .pendingDelete }

        let allLocations = (try? modelContext.fetch(FetchDescriptor<SDStorageLocation>(
            sortBy: [SortDescriptor(\.name)]
        ))) ?? []
        storageLocations = allLocations.filter { $0.syncState != .pendingDelete }
    }

    func onHand(for part: SDPart) -> Int {
        PartsInventory.onHand(for: part.clientId, in: modelContext)
    }

    func stocks(for part: SDPart) -> [SDPartStock] {
        PartsInventory.stocks(for: part.clientId, in: modelContext)
    }

    func consumptions(for part: SDPart) -> [SDPartConsumption] {
        PartsInventory.consumptions(for: part.clientId, in: modelContext)
    }

    /// Parts used by a maintenance record ("Verwendete Teile" on its detail page).
    func consumptions(forMaintenance record: SDMaintenanceRecord) -> [SDPartConsumption] {
        PartsInventory.consumptions(forMaintenance: record, in: modelContext)
    }

    /// Resolve a consumption's part by client id, falling back to server id.
    func part(clientId: UUID?, serverId: Int? = nil) -> SDPart? {
        if let clientId, let match = parts.first(where: { $0.clientId == clientId }) {
            return match
        }
        if let serverId { return parts.first { $0.serverId == serverId } }
        return nil
    }

    func storageLocation(clientId: UUID?) -> SDStorageLocation? {
        guard let clientId else { return nil }
        return storageLocations.first { $0.clientId == clientId }
    }

    /// Resolve a scanned part label (the QR encodes the server id).
    func part(serverId: Int) -> SDPart? {
        parts.first { $0.serverId == serverId }
    }

    /// Resolve a scanned storage-location label (the QR encodes the server id).
    func storageLocation(serverId: Int) -> SDStorageLocation? {
        storageLocations.first { $0.serverId == serverId }
    }

    /// Parts stocked at a location with their summed stocked quantity there
    /// (stock only — consumptions are not location-scoped), sorted by name.
    func stockedParts(at location: SDStorageLocation) -> [(part: SDPart, quantity: Int)] {
        let allStocks = ((try? modelContext.fetch(FetchDescriptor<SDPartStock>())) ?? [])
            .filter { stock in
                guard stock.syncState != .pendingDelete else { return false }
                // Pulled stock updates refresh storageLocationServerId but not
                // the clientId, so match either identity.
                return stock.storageLocationClientId == location.clientId
                    || (stock.storageLocationServerId != nil
                        && stock.storageLocationServerId == location.serverId)
            }
        var quantities: [UUID: Int] = [:]
        for stock in allStocks {
            quantities[stock.partClientId, default: 0] += stock.quantity
        }
        return quantities
            .compactMap { partClientId, quantity in
                parts.first { $0.clientId == partClientId }.map { (part: $0, quantity: quantity) }
            }
            .sorted { $0.part.name < $1.part.name }
    }

    /// Ancestors only ("Garage › Regal A" for "Kiste 3"); nil for roots.
    /// Used where the location's own name is already shown as the title
    /// (list rows, printed labels) so the name isn't duplicated.
    func locationParentPath(_ location: SDStorageLocation) -> String? {
        guard let path = locationPath(location) else { return nil }
        let ancestors = path.components(separatedBy: " › ").dropLast()
        return ancestors.isEmpty ? nil : ancestors.joined(separator: " › ")
    }

    /// "Garage › Regal A › Kiste 3" for a leaf location (depth-capped).
    func locationPath(_ location: SDStorageLocation?) -> String? {
        guard let location else { return nil }
        var names = [location.name]
        var current = location
        for _ in 0..<10 {
            guard let parentId = current.parentClientId,
                  let parent = storageLocations.first(where: { $0.clientId == parentId })
            else { break }
            names.insert(parent.name, at: 0)
            current = parent
        }
        return names.joined(separator: " › ")
    }

    func seriesName(_ id: Int) -> String {
        series.first(where: { $0.id == id })?.displayName ?? "Baureihe \(id)"
    }

    /// The repair a consumption is linked to, if it exists locally.
    func maintenanceRecord(for consumption: SDPartConsumption) -> SDMaintenanceRecord? {
        let all = (try? modelContext.fetch(FetchDescriptor<SDMaintenanceRecord>())) ?? []
        if let mcid = consumption.maintenanceClientId {
            return all.first { $0.clientId == mcid }
        }
        if let msid = consumption.maintenanceServerId {
            return all.first { $0.serverId == msid }
        }
        return nil
    }

    // MARK: - Lookups & public browse (network)

    /// Cache-first series load; refreshes from the network when online.
    func loadSeries() async {
        if series.isEmpty,
           let cached = CacheStore.shared.load([ModelSeries].self, key: CacheKey.modelSeries) {
            series = cached
        }
        if let fresh = try? await NetworkManager.shared.fetchModelSeries() {
            series = fresh
        }
    }

    /// Create a custom series entry (requires connectivity — the lookup is not
    /// offline-writable by design).
    func createSeries(name: String, manufacturer: String) async -> ModelSeries? {
        guard let created = try? await NetworkManager.shared.createModelSeries(
            name: name, manufacturer: manufacturer) else { return nil }
        await loadSeries()
        return created
    }

    func loadPublicParts(query: String? = nil, seriesId: Int? = nil) async {
        isLoadingPublic = true
        publicError = nil
        do {
            publicParts = try await NetworkManager.shared.fetchPublicParts(query: query, seriesId: seriesId)
        } catch {
            publicError = error.localizedDescription
        }
        isLoadingPublic = false
    }

    // MARK: - Part writes (offline-first via SwiftData + SyncEngine)

    @discardableResult
    func createPart(
        partNumber: String, name: String, manufacturer: String,
        description: String?, isPublic: Bool, seriesIds: [Int]
    ) -> SDPart? {
        let part = SDPart(
            partNumber: partNumber,
            name: name,
            manufacturer: manufacturer.isEmpty ? "BMW" : manufacturer,
            partDescription: (description?.isEmpty == false) ? description : nil,
            isPublic: isPublic,
            seriesIds: seriesIds,
            syncState: .pendingCreate
        )
        modelContext.insert(part)
        return persistAndSync() ? part : nil
    }

    /// Create the catalog entry, optional new location, and mandatory initial
    /// stock in one SwiftData transaction. A storage failure therefore leaves
    /// no half-created part that the user has to repair on the next attempt.
    @discardableResult
    func createPartWithInitialStock(
        partNumber: String, name: String, manufacturer: String,
        description: String?, isPublic: Bool, seriesIds: [Int],
        quantity: Int, price: Double?, currency: String?, purchaseDate: Date,
        storageLocation: SDStorageLocation?, newLocationName: String
    ) -> SDPart? {
        let part = SDPart(
            partNumber: partNumber,
            name: name,
            manufacturer: manufacturer.isEmpty ? "BMW" : manufacturer,
            partDescription: (description?.isEmpty == false) ? description : nil,
            isPublic: isPublic,
            seriesIds: seriesIds,
            syncState: .pendingCreate
        )
        modelContext.insert(part)

        var location = storageLocation
        let trimmedLocationName = newLocationName.trimmingCharacters(in: .whitespaces)
        if !trimmedLocationName.isEmpty {
            let createdLocation = SDStorageLocation(
                name: trimmedLocationName,
                parentClientId: storageLocation?.clientId,
                parentServerId: storageLocation?.serverId,
                syncState: .pendingCreate
            )
            modelContext.insert(createdLocation)
            location = createdLocation
        }

        let stock = SDPartStock(
            partClientId: part.clientId,
            partServerId: nil,
            quantity: max(1, quantity),
            syncState: .pendingCreate
        )
        stock.price = price
        stock.currency = price != nil ? currency : nil
        stock.purchaseDate = Self.isoDay(purchaseDate)
        stock.storageLocationClientId = location?.clientId
        stock.storageLocationServerId = location?.serverId
        modelContext.insert(stock)

        return persistAndSync() ? part : nil
    }

    @discardableResult
    func updatePart(
        _ part: SDPart,
        partNumber: String, name: String, manufacturer: String,
        description: String?, isPublic: Bool, seriesIds: [Int]
    ) -> Bool {
        part.partNumber = partNumber
        part.name = name
        part.manufacturer = manufacturer.isEmpty ? "BMW" : manufacturer
        part.partDescription = (description?.isEmpty == false) ? description : nil
        part.isPublic = isPublic
        part.seriesIds = seriesIds
        if part.syncState != .pendingCreate { part.syncState = .pendingUpdate }
        part.updatedAtLocal = Date()
        return persistAndSync()
    }

    @discardableResult
    func deletePart(_ part: SDPart) -> Bool {
        // The server soft-cascades a part delete onto its stocks and
        // consumptions, so those must NOT push their own deletes (they would
        // 404 against already-tombstoned rows). Remove them locally only.
        for stock in PartsInventory.stocks(for: part.clientId, in: modelContext) {
            modelContext.delete(stock)
        }
        for consumption in PartsInventory.consumptions(for: part.clientId, in: modelContext) {
            modelContext.delete(consumption)
        }
        if part.serverId == nil {
            modelContext.delete(part)
        } else {
            part.syncState = .pendingDelete
            part.updatedAtLocal = Date()
        }
        return persistAndSync()
    }

    // MARK: - Stock writes

    @discardableResult
    func addStock(
        part: SDPart, quantity: Int, price: Double?, currency: String?,
        purchaseDate: Date, storageLocation: SDStorageLocation?, notes: String?,
        isUsed: Bool = false
    ) -> SDPartStock? {
        let stock = SDPartStock(
            partClientId: part.clientId,
            partServerId: part.serverId,
            quantity: max(1, quantity),
            syncState: .pendingCreate
        )
        stock.price = price
        stock.currency = price != nil ? currency : nil
        stock.purchaseDate = Self.isoDay(purchaseDate)
        stock.storageLocationClientId = storageLocation?.clientId
        stock.storageLocationServerId = storageLocation?.serverId
        stock.notes = (notes?.isEmpty == false) ? notes : nil
        stock.isUsed = isUsed
        modelContext.insert(stock)
        return persistAndSync() ? stock : nil
    }

    @discardableResult
    func updateStock(
        _ stock: SDPartStock, quantity: Int, price: Double?, currency: String?,
        purchaseDate: Date, storageLocation: SDStorageLocation?, notes: String?,
        isUsed: Bool = false
    ) -> Bool {
        stock.quantity = max(1, quantity)
        stock.price = price
        stock.currency = price != nil ? currency : nil
        stock.purchaseDate = Self.isoDay(purchaseDate)
        stock.storageLocationClientId = storageLocation?.clientId
        stock.storageLocationServerId = storageLocation?.serverId
        stock.notes = (notes?.isEmpty == false) ? notes : nil
        stock.isUsed = isUsed
        if stock.syncState != .pendingCreate { stock.syncState = .pendingUpdate }
        stock.updatedAtLocal = Date()
        return persistAndSync()
    }

    @discardableResult
    func deleteStock(_ stock: SDPartStock) -> Bool {
        if stock.serverId == nil {
            modelContext.delete(stock)
        } else {
            stock.syncState = .pendingDelete
            stock.updatedAtLocal = Date()
        }
        return persistAndSync()
    }

    // MARK: - Consumption writes

    /// Manual consumption ("Verbrauch erfassen"), validated against on-hand.
    /// Returns false when there is not enough stock.
    @discardableResult
    func addConsumption(part: SDPart, quantity: Int, date: Date, notes: String?) -> Bool {
        let created = PartsInventory.recordConsumption(
            part: part, quantity: quantity, date: Self.isoDay(date),
            notes: notes, in: modelContext)
        guard created != nil else { return false }
        return persistAndSync()
    }

    @discardableResult
    func deleteConsumption(_ consumption: SDPartConsumption) -> Bool {
        if consumption.serverId == nil {
            modelContext.delete(consumption)
        } else {
            consumption.syncState = .pendingDelete
            consumption.updatedAtLocal = Date()
        }
        return persistAndSync()
    }

    // MARK: - Storage location writes

    @discardableResult
    func createStorageLocation(name: String, parent: SDStorageLocation?) -> SDStorageLocation? {
        let location = SDStorageLocation(
            name: name,
            parentClientId: parent?.clientId,
            parentServerId: parent?.serverId,
            syncState: .pendingCreate
        )
        modelContext.insert(location)
        return persistAndSync() ? location : nil
    }

    @discardableResult
    func deleteStorageLocation(_ location: SDStorageLocation) -> Bool {
        if location.serverId == nil {
            modelContext.delete(location)
        } else {
            location.syncState = .pendingDelete
            location.updatedAtLocal = Date()
        }
        return persistAndSync()
    }

    // MARK: - Plumbing

    @discardableResult
    private func persistAndSync() -> Bool {
        guard PersistenceMonitor.shared.save(modelContext, operation: "Teilebestand speichern") else {
            reloadLocal()
            return false
        }
        reloadLocal()
        SyncEngine.shared.requestSync(motorcycleIds: [])
        return true
    }

    private static func isoDay(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.string(from: date)
    }
}
