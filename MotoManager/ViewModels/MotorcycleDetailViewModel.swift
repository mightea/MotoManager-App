import Foundation
import Combine
import SwiftData

@MainActor
class MotorcycleDetailViewModel: ObservableObject {
    let motorcycle: Motorcycle

    /// Shared with the SyncEngine so local writes and pulled changes stay consistent.
    private let modelContext = PersistenceController.shared.mainContext

    /// Fuel records backed by SwiftData (offline-first source of truth).
    @Published var fuelRecords: [SDMaintenanceRecord] = []
    /// Issues backed by SwiftData (offline-first source of truth).
    @Published var issues: [SDIssue] = []
    /// Torque specs backed by SwiftData (offline-first source of truth).
    @Published var torque: [SDTorqueSpec] = []
    /// Non-fuel maintenance records backed by SwiftData (offline-first source of truth).
    @Published var serviceRecords: [SDMaintenanceRecord] = []

    @Published var maintenanceRecords: [MaintenanceRecord] = []
    @Published var torqueSpecs: [TorqueSpec] = []
    /// Recommended tire pressures (1:1 record, online-first like documents).
    @Published var tirePressure: TirePressure?
    @Published var documents: [Document] = []
    /// Documents that aren't bound to any motorcycle — surfaced as
    /// "Allgemein" in the Workshop screen's document filter.
    @Published var commonDocuments: [Document] = []
    
    @Published var isLoading = false
    /// Blocking error — set only when there is nothing cached to show.
    @Published var errorMessage: String?
    /// Non-blocking flag: a refresh failed but cached data is still on screen.
    @Published var refreshFailed = false
    
    init(motorcycle: Motorcycle) {
        self.motorcycle = motorcycle
    }
    
    func loadAllData() async {
        // Hydrate from cache instantly so the UI works offline / while the network is in flight.
        hydrateFromCache()
        reloadLocal()

        isLoading = true

        do {
            // Run in parallel
            async let maintenanceTask = NetworkManager.shared.fetchMaintenance(motorcycleId: motorcycle.id)
            async let torqueTask = NetworkManager.shared.fetchTorqueSpecs(motorcycleId: motorcycle.id)
            async let documentsTask = NetworkManager.shared.fetchDocuments()
            async let pressureTask = NetworkManager.shared.fetchTirePressure(motorcycleId: motorcycle.id)

            let (maintenance, torque, allDocs, pressure) = try await (maintenanceTask, torqueTask, documentsTask, pressureTask)

            self.maintenanceRecords = maintenance.sorted(by: { $0.date > $1.date })
            self.torqueSpecs = torque
            self.tirePressure = pressure

            // Filter documents for this motorcycle
            self.documents = allDocs.filter { doc in
                doc.motorcycleIds?.contains(motorcycle.id) ?? false
            }
            // Documents not bound to any motorcycle are surfaced under "Allgemein".
            self.commonDocuments = allDocs.filter { doc in
                (doc.motorcycleIds ?? []).isEmpty
            }
            AppLog.debug("Loaded detail data for motorcycle \(motorcycle.id)")
            errorMessage = nil
            refreshFailed = false

        } catch is CancellationError {
            // Ignore normal Swift concurrency cancellations (e.g. from refreshable)
        } catch {
            AppLog.error("Failed to load detail data: \(error.localizedDescription)")
            if maintenanceRecords.isEmpty && torqueSpecs.isEmpty && documents.isEmpty {
                // Nothing cached to show — surface a blocking error.
                errorMessage = error.localizedDescription
            } else {
                // We have cached data on screen; flag the stale refresh non-blockingly.
                refreshFailed = true
            }
        }

        isLoading = false
    }

    private func hydrateFromCache() {
        if maintenanceRecords.isEmpty,
           let cached = CacheStore.shared.load([MaintenanceRecord].self, key: CacheKey.maintenance(motorcycleId: motorcycle.id)) {
            self.maintenanceRecords = cached.sorted(by: { $0.date > $1.date })
        }
        if torqueSpecs.isEmpty,
           let cached = CacheStore.shared.load([TorqueSpec].self, key: CacheKey.torque(motorcycleId: motorcycle.id)) {
            self.torqueSpecs = cached
        }
        if documents.isEmpty,
           let cached = CacheStore.shared.load([Document].self, key: CacheKey.documents) {
            self.documents = cached.filter { $0.motorcycleIds?.contains(motorcycle.id) ?? false }
            self.commonDocuments = cached.filter { ($0.motorcycleIds ?? []).isEmpty }
        }
        if tirePressure == nil,
           let cached = CacheStore.shared.load(TirePressure.self, key: CacheKey.tirePressure(motorcycleId: motorcycle.id)) {
            self.tirePressure = cached
        }
    }

    // MARK: - Tire pressure writes (online-only; the record has no sync metadata)

    /// Upsert with the given payload; the server clears configurations absent
    /// from it. Throws so the editor sheet can surface the failure.
    func saveTirePressure(payload: [String: Any]) async throws {
        tirePressure = try await NetworkManager.shared.upsertTirePressure(
            motorcycleId: motorcycle.id, payload: payload)
    }

    /// Remove the whole record (used when the last configuration is deleted).
    func deleteTirePressure() async throws {
        try await NetworkManager.shared.deleteTirePressure(motorcycleId: motorcycle.id)
        tirePressure = nil
    }
    
    // MARK: - Fuel writes (offline-first via SwiftData + SyncEngine)

    /// Reload the fuel list from the local store. Cheap; call after writes and sync.
    func reloadFuel() {
        let mid = motorcycle.id
        // Scope the fetch to this motorcycle (with a DB-side sort) instead of
        // fetching every record for every bike and filtering/sorting in Swift.
        // The record-type/tombstone filters stay in Swift — they operate on this
        // one bike's small slice now, and keep the predicate reliably translatable.
        let descriptor = FetchDescriptor<SDMaintenanceRecord>(
            predicate: #Predicate { $0.motorcycleId == mid },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let scoped = (try? modelContext.fetch(descriptor)) ?? []
        fuelRecords = scoped.filter {
            $0.recordType.lowercased() == "fuel" && $0.syncState != .pendingDelete
        }
    }

    /// Per-liter price of the most recent fuel entry, used to seed the form.
    var lastFuelPerLiter: Double? {
        fuelRecords.compactMap { $0.pricePerUnit }.first
    }

    @discardableResult
    func createFuelRecord(
        odo: Int, amount: Double, cost: Double, pricePerUnit: Double,
        currency: String, date: Date, fuelType: String,
        locationName: String?, notes: String?
    ) -> Bool {
        let record = SDMaintenanceRecord(
            motorcycleId: motorcycle.id,
            date: Self.isoDay(date),
            odo: odo,
            recordType: "fuel",
            syncState: .pendingCreate
        )
        applyFuelFields(record, amount: amount, cost: cost, pricePerUnit: pricePerUnit,
                        currency: currency, fuelType: fuelType, locationName: locationName, notes: notes)
        modelContext.insert(record)
        persistAndSync()
        return true
    }

    func updateFuelRecord(
        _ record: SDMaintenanceRecord,
        odo: Int, amount: Double, cost: Double, pricePerUnit: Double,
        currency: String, date: Date, fuelType: String,
        locationName: String?, notes: String?
    ) {
        record.odo = odo
        record.date = Self.isoDay(date)
        applyFuelFields(record, amount: amount, cost: cost, pricePerUnit: pricePerUnit,
                        currency: currency, fuelType: fuelType, locationName: locationName, notes: notes)
        // A record still waiting to be created stays pendingCreate.
        if record.syncState != .pendingCreate { record.syncState = .pendingUpdate }
        record.updatedAtLocal = Date()
        persistAndSync()
    }

    func deleteFuelRecord(_ record: SDMaintenanceRecord) {
        if record.serverId == nil {
            // Never reached the server — drop it locally.
            modelContext.delete(record)
        } else {
            record.syncState = .pendingDelete
            record.updatedAtLocal = Date()
        }
        persistAndSync()
    }

    private func applyFuelFields(
        _ record: SDMaintenanceRecord,
        amount: Double, cost: Double, pricePerUnit: Double,
        currency: String, fuelType: String, locationName: String?, notes: String?
    ) {
        record.fuelAmount = amount
        record.cost = cost > 0 ? cost : nil
        record.pricePerUnit = pricePerUnit > 0 ? pricePerUnit : nil
        record.currency = (cost > 0 || pricePerUnit > 0) ? currency : record.currency
        record.fuelType = fuelType
        record.locationName = (locationName?.isEmpty == false) ? locationName : nil
        record.recordDescription = (notes?.isEmpty == false) ? notes : nil
    }

    private func persistAndSync() {
        try? modelContext.save()
        reloadLocal()
        SyncEngine.shared.requestSync(motorcycleIds: [motorcycle.id])
    }

    /// Refresh all SwiftData-backed lists from the store.
    func reloadLocal() {
        reloadFuel()
        reloadIssues()
        reloadTorque()
        reloadService()
    }

    // MARK: - Maintenance (non-fuel) writes (offline-first via SwiftData + SyncEngine)

    func reloadService() {
        let mid = motorcycle.id
        let descriptor = FetchDescriptor<SDMaintenanceRecord>(
            predicate: #Predicate { $0.motorcycleId == mid },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let scoped = (try? modelContext.fetch(descriptor)) ?? []
        serviceRecords = scoped.filter {
            $0.recordType.lowercased() != "fuel" && $0.syncState != .pendingDelete
        }
    }

    /// Returns the created record so callers can link follow-up entities
    /// (e.g. part consumptions) to its clientId.
    @discardableResult
    func createMaintenance(type: String, odo: Int, date: Date, cost: Double, currency: String, description: String?) -> SDMaintenanceRecord {
        let record = SDMaintenanceRecord(
            motorcycleId: motorcycle.id,
            date: Self.isoDay(date),
            odo: odo,
            recordType: type,
            syncState: .pendingCreate
        )
        record.cost = cost > 0 ? cost : nil
        record.currency = cost > 0 ? currency : nil
        record.recordDescription = (description?.isEmpty == false) ? description : nil
        modelContext.insert(record)
        persistAndSync()
        return record
    }

    func updateMaintenance(_ record: SDMaintenanceRecord, type: String, odo: Int, date: Date, cost: Double, currency: String, description: String?) {
        record.recordType = type
        record.odo = odo
        record.date = Self.isoDay(date)
        record.cost = cost > 0 ? cost : nil
        record.currency = cost > 0 ? currency : record.currency
        record.recordDescription = (description?.isEmpty == false) ? description : nil
        if record.syncState != .pendingCreate { record.syncState = .pendingUpdate }
        record.updatedAtLocal = Date()
        persistAndSync()
    }

    func deleteMaintenance(_ record: SDMaintenanceRecord) {
        if record.serverId == nil {
            modelContext.delete(record)
        } else {
            record.syncState = .pendingDelete
            record.updatedAtLocal = Date()
        }
        persistAndSync()
    }

    // MARK: - Torque writes (offline-first via SwiftData + SyncEngine)

    func reloadTorque() {
        let mid = motorcycle.id
        let descriptor = FetchDescriptor<SDTorqueSpec>(
            predicate: #Predicate { $0.motorcycleId == mid },
            sortBy: [SortDescriptor(\.category), SortDescriptor(\.name)]
        )
        let scoped = (try? modelContext.fetch(descriptor)) ?? []
        torque = scoped.filter { $0.syncState != .pendingDelete }
    }

    @discardableResult
    func createTorque(category: String, name: String, torque value: Double, torqueEnd: Double?, variation: Double?, toolSize: String?, description: String?) -> Bool {
        let spec = SDTorqueSpec(
            motorcycleId: motorcycle.id,
            category: category,
            name: name,
            torque: value,
            torqueEnd: torqueEnd,
            variation: variation,
            toolSize: (toolSize?.isEmpty == false) ? toolSize : nil,
            recordDescription: (description?.isEmpty == false) ? description : nil,
            createdAt: Self.isoDay(Date()),
            syncState: .pendingCreate
        )
        modelContext.insert(spec)
        persistAndSync()
        return true
    }

    func updateTorque(_ spec: SDTorqueSpec, category: String, name: String, torque value: Double, torqueEnd: Double?, variation: Double?, toolSize: String?, description: String?) {
        spec.category = category
        spec.name = name
        spec.torque = value
        spec.torqueEnd = torqueEnd
        spec.variation = variation
        spec.toolSize = (toolSize?.isEmpty == false) ? toolSize : nil
        spec.recordDescription = (description?.isEmpty == false) ? description : nil
        if spec.syncState != .pendingCreate { spec.syncState = .pendingUpdate }
        spec.updatedAtLocal = Date()
        persistAndSync()
    }

    func deleteTorque(_ spec: SDTorqueSpec) {
        if spec.serverId == nil {
            modelContext.delete(spec)
        } else {
            spec.syncState = .pendingDelete
            spec.updatedAtLocal = Date()
        }
        persistAndSync()
    }

    // MARK: - Issue writes (offline-first via SwiftData + SyncEngine)

    func reloadIssues() {
        let mid = motorcycle.id
        let descriptor = FetchDescriptor<SDIssue>(
            predicate: #Predicate { $0.motorcycleId == mid },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let scoped = (try? modelContext.fetch(descriptor)) ?? []
        issues = scoped.filter { $0.syncState != .pendingDelete }
    }

    var openIssuesCount: Int {
        issues.filter { $0.status.lowercased() != "done" }.count
    }

    @discardableResult
    func createIssue(odo: Int, title: String, description: String?, priority: String, status: String, date: Date) -> Bool {
        let issue = SDIssue(
            motorcycleId: motorcycle.id,
            odo: odo,
            title: title,
            recordDescription: (description?.isEmpty == false) ? description : nil,
            priority: priority,
            status: status,
            date: Self.isoDay(date),
            syncState: .pendingCreate
        )
        modelContext.insert(issue)
        persistAndSync()
        return true
    }

    func updateIssue(_ issue: SDIssue, odo: Int, title: String, description: String?, priority: String, status: String, date: Date) {
        issue.odo = odo
        issue.title = title
        issue.recordDescription = (description?.isEmpty == false) ? description : nil
        issue.priority = priority
        issue.status = status
        issue.date = Self.isoDay(date)
        if issue.syncState != .pendingCreate { issue.syncState = .pendingUpdate }
        issue.updatedAtLocal = Date()
        persistAndSync()
    }

    func deleteIssue(_ issue: SDIssue) {
        if issue.serverId == nil {
            modelContext.delete(issue)
        } else {
            issue.syncState = .pendingDelete
            issue.updatedAtLocal = Date()
        }
        persistAndSync()
    }

    private static func isoDay(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.string(from: date)
    }
    
    static var mock: MotorcycleDetailViewModel {
        let vm = MotorcycleDetailViewModel(motorcycle: .mock)
        vm.fuelRecords = [
            {
                let r = SDMaintenanceRecord(serverId: 1, motorcycleId: 1, date: "2023-10-15", odo: 12000, recordType: "fuel", syncState: .synced)
                r.fuelAmount = 18.5; r.pricePerUnit = 2.45; r.cost = 45.5; r.currency = "EUR"; r.fuelConsumption = 5.2; r.fuelType = "98"; r.locationName = "Shell Munich"
                return r
            }(),
            {
                let r = SDMaintenanceRecord(serverId: 2, motorcycleId: 1, date: "2023-09-20", odo: 11650, recordType: "fuel", syncState: .synced)
                r.fuelAmount = 16.0; r.pricePerUnit = 2.39; r.cost = 38.24; r.currency = "EUR"; r.fuelConsumption = 4.8; r.fuelType = "98"
                return r
            }()
        ]
        vm.maintenanceRecords = [
            MaintenanceRecord(id: 1, date: "2023-10-15", odo: 12000, motorcycleId: 1, cost: 45.50, normalizedCost: 45.5, currency: "EUR", description: "Shell V-Power", recordType: "fuel", brand: nil, model: nil, tirePosition: nil, tireSize: nil, dotCode: nil, batteryType: nil, fluidType: nil, viscosity: nil, oilType: nil, inspectionLocation: nil, locationId: nil, fuelType: "98", fuelAmount: 18.5, pricePerUnit: 2.45, latitude: nil, longitude: nil, locationName: "Shell Munich", fuelConsumption: 5.2, tripDistance: 350, summary: "Tankstopp bei Shell", parentId: nil, clientId: nil, updatedAt: nil, deletedAt: nil),
            MaintenanceRecord(id: 2, date: "2023-09-01", odo: 10000, motorcycleId: 1, cost: 250.00, normalizedCost: 250.0, currency: "EUR", description: "", recordType: "service", brand: nil, model: nil, tirePosition: nil, tireSize: nil, dotCode: nil, batteryType: nil, fluidType: nil, viscosity: "15W-50", oilType: "Synthetic", inspectionLocation: nil, locationId: nil, fuelType: nil, fuelAmount: nil, pricePerUnit: nil, latitude: nil, longitude: nil, locationName: "BMW Service", fuelConsumption: nil, tripDistance: nil, summary: "Regulärer 10k Service", parentId: nil, clientId: nil, updatedAt: nil, deletedAt: nil)
        ]
        vm.torqueSpecs = [
            TorqueSpec(id: 1, motorcycleId: 1, category: "Engine", name: "Oil Drain Plug", torque: 42, torqueEnd: nil, variation: nil, toolSize: "17mm", description: nil, createdAt: "2023-01-01", clientId: nil, updatedAt: nil, deletedAt: nil),
            TorqueSpec(id: 2, motorcycleId: 1, category: "Wheels", name: "Rear Axle Nut", torque: 100, torqueEnd: nil, variation: nil, toolSize: "34mm", description: nil, createdAt: "2023-01-01", clientId: nil, updatedAt: nil, deletedAt: nil)
        ]
        vm.torque = [
            {
                let t = SDTorqueSpec(serverId: 1, motorcycleId: 1, category: "Engine", name: "Oil Drain Plug", torque: 42, toolSize: "17mm", createdAt: "2023-01-01", syncState: .synced)
                return t
            }(),
            {
                let t = SDTorqueSpec(serverId: 2, motorcycleId: 1, category: "Wheels", name: "Rear Axle Nut", torque: 100, toolSize: "34mm", createdAt: "2023-01-01", syncState: .synced)
                return t
            }()
        ]
        vm.issues = [
            {
                let i = SDIssue(serverId: 1, motorcycleId: 1, odo: 12500, title: "Bremsbeläge prüfen", priority: "high", status: "new", date: "2024-02-01", syncState: .synced)
                return i
            }()
        ]
        vm.documents = [
            Document(id: 1, title: "Registration Part I", filePath: "", previewPath: nil, uploadedBy: nil, ownerId: 1, isPrivate: false, createdAt: "2023-01-01", updatedAt: "2023-01-01", motorcycleIds: [1]),
            Document(id: 2, title: "Service Manual", filePath: "", previewPath: nil, uploadedBy: nil, ownerId: 1, isPrivate: false, createdAt: "2023-01-01", updatedAt: "2023-01-01", motorcycleIds: [1])
        ]
        vm.tirePressure = TirePressure(
            id: 1, motorcycleId: 1,
            frontBar: 2.2, rearBar: 2.4,
            frontPassengerBar: 2.3, rearPassengerBar: 2.8,
            frontOffroadBar: 1.5, rearOffroadBar: 1.7,
            sidecarBar: nil, sidecarPassengerBar: nil, sidecarOffroadBar: nil,
            preferredUnit: "bar", createdAt: "2024-01-01", updatedAt: "2024-01-01"
        )
        return vm
    }
}
