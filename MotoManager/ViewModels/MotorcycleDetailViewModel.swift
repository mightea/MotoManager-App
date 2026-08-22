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
    /// Motorcycle details (Title/Value pairs) backed by SwiftData (offline-first source of truth).
    @Published var details: [SDMotorcycleDetail] = []

    /// Recommended tire pressures (1:1 record, online-first like documents).
    @Published var tirePressure: TirePressure?
    @Published var documents: [Document] = []
    /// Documents that aren't bound to any motorcycle — surfaced as
    /// "Allgemein" in the Workshop screen's document filter.
    @Published var commonDocuments: [Document] = []
    /// User places (garages, MFK stations, fuel stops) for resolving a
    /// maintenance record's `locationId` to a name/coordinates. Cached for
    /// offline use.
    @Published var userLocations: [Location] = []
    
    @Published var isLoading = false
    /// Blocking error — set only when there is nothing cached to show.
    @Published var errorMessage: String?
    /// Non-blocking flag: a refresh failed but cached data is still on screen.
    @Published var refreshFailed = false

    var hasDisplayData: Bool {
        !fuelRecords.isEmpty || !serviceRecords.isEmpty || !issues.isEmpty
            || !torque.isEmpty || !details.isEmpty || !documents.isEmpty
            || !commonDocuments.isEmpty || tirePressure != nil
    }
    
    private var cancellables = Set<AnyCancellable>()

    init(motorcycle: Motorcycle) {
        self.motorcycle = motorcycle
        // Re-publish the SwiftData-backed lists whenever a sync finishes, so
        // remotely pulled changes (incl. deletions, which the pushed detail
        // pages' auto-pop guards watch for) reach the UI without a manual
        // refresh.
        SyncEngine.shared.$status
            .scan((SyncStatus.idle, SyncStatus.idle)) { pair, next in (pair.1, next) }
            .filter { pair in pair.0 == .syncing && pair.1 != .syncing }
            .sink { [weak self] _ in self?.reloadLocal() }
            .store(in: &cancellables)
    }
    
    /// Pull-to-refresh / reconnect: reload the display data, then re-run the sync
    /// engine so pending writes flush and the "Offline" status clears once the
    /// backend is reachable again. A pull while offline simply refreshes the
    /// (cached) data and leaves the offline pill in place. Mirrors the initial
    /// load sequence in `MainTabView`.
    ///
    /// The body runs in an unstructured `Task` (which does not inherit the
    /// caller's cancellation) because SwiftUI cancels the `.refreshable` action
    /// as its control retracts — that would otherwise abort our in-flight
    /// requests, surfacing them as `URLError.cancelled` (a spurious failure) and
    /// leaving the reconnect half-done. Awaiting `.value` keeps the pull spinner
    /// up until the work actually finishes.
    func reconnect() async {
        await Task {
            await loadAllData()
            await SyncEngine.shared.sync(motorcycleIds: [motorcycle.id])
            reloadLocal()
            if errorMessage != nil {
                switch SyncEngine.shared.status {
                case .idle, .pending:
                    // The authoritative SwiftData pull succeeded. A failed
                    // auxiliary endpoint (documents/pressure/locations) is
                    // non-blocking even when this is a brand-new empty bike.
                    errorMessage = nil
                    refreshFailed = true
                case .syncing, .offline, .error:
                    break
                }
            }
        }.value
    }

    func loadAllData() async {
        // Hydrate from cache instantly so the UI works offline / while the network is in flight.
        hydrateFromCache()
        reloadLocal()

        isLoading = true

        async let documentsRequest = NetworkManager.shared.fetchDocuments()
        async let pressureRequest = NetworkManager.shared.fetchTirePressure(motorcycleId: motorcycle.id)
        async let locationsRequest = NetworkManager.shared.fetchLocations()
        var failures: [Error] = []

        do {
            let allDocs = try await documentsRequest
            documents = allDocs.filter { $0.motorcycleIds?.contains(motorcycle.id) ?? false }
            commonDocuments = allDocs.filter { ($0.motorcycleIds ?? []).isEmpty }
        } catch { failures.append(error) }
        do { tirePressure = try await pressureRequest } catch { failures.append(error) }
        do { userLocations = try await locationsRequest } catch { failures.append(error) }

        if failures.isEmpty {
            AppLog.debug("Loaded detail data for motorcycle \(motorcycle.id)")
            errorMessage = nil
            refreshFailed = false
        } else if let first = failures.first {
            AppLog.error("Some detail data failed to load: \(first.localizedDescription)")
            if hasDisplayData {
                refreshFailed = true
            } else {
                errorMessage = first.localizedDescription
            }
        }

        isLoading = false
    }

    /// Upload a document and refresh the shared document list. Documents remain
    /// online-only, unlike the SwiftData-backed write entities.
    func uploadDocument(
        title: String,
        fileName: String,
        mimeType: String,
        data: Data
    ) async throws {
        _ = try await NetworkManager.shared.createDocument(
            title: title,
            motorcycleIds: [motorcycle.id],
            fileName: fileName,
            mimeType: mimeType,
            data: data
        )
        let allDocs = try await NetworkManager.shared.fetchDocuments()
        documents = allDocs.filter { $0.motorcycleIds?.contains(motorcycle.id) ?? false }
        commonDocuments = allDocs.filter { ($0.motorcycleIds ?? []).isEmpty }
    }

    private func hydrateFromCache() {
        if documents.isEmpty,
           let cached = CacheStore.shared.load([Document].self, key: CacheKey.documents) {
            self.documents = cached.filter { $0.motorcycleIds?.contains(motorcycle.id) ?? false }
            self.commonDocuments = cached.filter { ($0.motorcycleIds ?? []).isEmpty }
        }
        if tirePressure == nil,
           let cached = CacheStore.shared.load(TirePressure.self, key: CacheKey.tirePressure(motorcycleId: motorcycle.id)) {
            self.tirePressure = cached
        }
        if userLocations.isEmpty,
           let cached = CacheStore.shared.load([Location].self, key: CacheKey.locations) {
            self.userLocations = cached
        }
    }

    /// Resolve a maintenance record's `locationId` to the cached place.
    func location(id: Int?) -> Location? {
        guard let id else { return nil }
        return userLocations.first { $0.id == id }
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
        locationName: String?, notes: String?,
        fuelAdditiveAdded: Bool = false, leadSubstituteAdded: Bool = false,
        locationId: Int? = nil, latitude: Double? = nil, longitude: Double? = nil
    ) -> Bool {
        let record = SDMaintenanceRecord(
            motorcycleId: motorcycle.id,
            date: Self.isoDay(date),
            odo: odo,
            recordType: "fuel",
            syncState: .pendingCreate
        )
        applyFuelFields(record, amount: amount, cost: cost, pricePerUnit: pricePerUnit,
                        currency: currency, fuelType: fuelType, locationName: locationName, notes: notes,
                        fuelAdditiveAdded: fuelAdditiveAdded, leadSubstituteAdded: leadSubstituteAdded,
                        locationId: locationId, latitude: latitude, longitude: longitude)
        modelContext.insert(record)
        return persistAndSync()
    }

    @discardableResult
    func updateFuelRecord(
        _ record: SDMaintenanceRecord,
        odo: Int, amount: Double, cost: Double, pricePerUnit: Double,
        currency: String, date: Date, fuelType: String,
        locationName: String?, notes: String?,
        fuelAdditiveAdded: Bool = false, leadSubstituteAdded: Bool = false
    ) -> Bool {
        record.odo = odo
        record.date = Self.isoDay(date)
        applyFuelFields(record, amount: amount, cost: cost, pricePerUnit: pricePerUnit,
                        currency: currency, fuelType: fuelType, locationName: locationName, notes: notes,
                        fuelAdditiveAdded: fuelAdditiveAdded, leadSubstituteAdded: leadSubstituteAdded)
        // A record still waiting to be created stays pendingCreate.
        if record.syncState != .pendingCreate { record.syncState = .pendingUpdate }
        record.updatedAtLocal = Date()
        return persistAndSync()
    }

    @discardableResult
    func deleteFuelRecord(_ record: SDMaintenanceRecord) -> Bool {
        if record.serverId == nil {
            // Never reached the server — drop it locally.
            modelContext.delete(record)
        } else {
            record.syncState = .pendingDelete
            record.updatedAtLocal = Date()
        }
        return persistAndSync()
    }

    private func applyFuelFields(
        _ record: SDMaintenanceRecord,
        amount: Double, cost: Double, pricePerUnit: Double,
        currency: String, fuelType: String, locationName: String?, notes: String?,
        fuelAdditiveAdded: Bool = false, leadSubstituteAdded: Bool = false,
        locationId: Int? = nil, latitude: Double? = nil, longitude: Double? = nil
    ) {
        record.fuelAdditiveAdded = fuelAdditiveAdded
        record.leadSubstituteAdded = leadSubstituteAdded
        record.fuelAmount = amount
        record.cost = cost > 0 ? cost : nil
        record.pricePerUnit = pricePerUnit > 0 ? pricePerUnit : nil
        record.currency = (cost > 0 || pricePerUnit > 0) ? currency : record.currency
        record.fuelType = fuelType
        record.locationName = (locationName?.isEmpty == false) ? locationName : nil
        record.recordDescription = (notes?.isEmpty == false) ? notes : nil
        // Server links fuel records to a station by locationId; lat/lon/name are
        // kept locally so the detail map can show it immediately (nil-preserving
        // so an edit that doesn't re-detect keeps the existing link).
        if let locationId { record.locationId = locationId }
        if let latitude { record.latitude = latitude }
        if let longitude { record.longitude = longitude }
    }

    @discardableResult
    private func persistAndSync() -> Bool {
        guard PersistenceMonitor.shared.save(modelContext, operation: "Lokale Änderung speichern") else {
            reloadLocal()
            return false
        }
        reloadLocal()
        SyncEngine.shared.requestSync(motorcycleIds: [motorcycle.id])
        return true
    }

    /// Refresh all SwiftData-backed lists from the store.
    func reloadLocal() {
        reloadFuel()
        reloadIssues()
        reloadTorque()
        reloadService()
        reloadDetails()
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

    /// Everything the maintenance form captures. Type-specific fields stay nil
    /// for categories they don't apply to — `updateMaintenance` writes them
    /// unconditionally so clearing a field syncs to the server.
    struct MaintenanceDraft {
        var type: String
        var odo: Int
        var date: Date
        var cost: Double
        var currency: String
        var description: String?
        var brand: String?
        var model: String?
        var tirePosition: String?
        var tireSize: String?
        var dotCode: String?
        var batteryType: String?
        var fluidType: String?
        var viscosity: String?
        var oilType: String?
    }

    /// Returns the created record so callers can link follow-up entities
    /// (e.g. part consumptions) to its clientId.
    @discardableResult
    func createMaintenance(_ draft: MaintenanceDraft) -> SDMaintenanceRecord? {
        let record = SDMaintenanceRecord(
            motorcycleId: motorcycle.id,
            date: Self.isoDay(draft.date),
            odo: draft.odo,
            recordType: draft.type,
            syncState: .pendingCreate
        )
        apply(draft, to: record)
        modelContext.insert(record)
        return persistAndSync() ? record : nil
    }

    @discardableResult
    func updateMaintenance(_ record: SDMaintenanceRecord, draft: MaintenanceDraft) -> Bool {
        record.recordType = draft.type
        record.odo = draft.odo
        record.date = Self.isoDay(draft.date)
        apply(draft, to: record)
        if record.syncState != .pendingCreate { record.syncState = .pendingUpdate }
        record.updatedAtLocal = Date()
        return persistAndSync()
    }

    private func apply(_ draft: MaintenanceDraft, to record: SDMaintenanceRecord) {
        record.cost = draft.cost > 0 ? draft.cost : nil
        record.currency = draft.cost > 0 ? draft.currency : record.currency
        record.recordDescription = (draft.description?.isEmpty == false) ? draft.description : nil
        record.brand = (draft.brand?.isEmpty == false) ? draft.brand : nil
        record.model = (draft.model?.isEmpty == false) ? draft.model : nil
        record.tirePosition = draft.tirePosition
        record.tireSize = (draft.tireSize?.isEmpty == false) ? draft.tireSize : nil
        record.dotCode = (draft.dotCode?.isEmpty == false) ? draft.dotCode : nil
        record.batteryType = draft.batteryType
        record.fluidType = draft.fluidType
        record.viscosity = (draft.viscosity?.isEmpty == false) ? draft.viscosity : nil
        record.oilType = draft.oilType
    }

    @discardableResult
    func deleteMaintenance(_ record: SDMaintenanceRecord) -> Bool {
        if record.serverId == nil {
            modelContext.delete(record)
        } else {
            record.syncState = .pendingDelete
            record.updatedAtLocal = Date()
        }
        return persistAndSync()
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
    func createTorque(category: String, name: String, torque value: Double, torqueEnd: Double?, variation: Double?, toolSize: String?, description: String?, unverified: Bool) -> Bool {
        let spec = SDTorqueSpec(
            motorcycleId: motorcycle.id,
            category: category,
            name: name,
            torque: value,
            torqueEnd: torqueEnd,
            variation: variation,
            toolSize: (toolSize?.isEmpty == false) ? toolSize : nil,
            recordDescription: (description?.isEmpty == false) ? description : nil,
            unverified: unverified,
            createdAt: Self.isoDay(Date()),
            syncState: .pendingCreate
        )
        modelContext.insert(spec)
        return persistAndSync()
    }

    @discardableResult
    func updateTorque(_ spec: SDTorqueSpec, category: String, name: String, torque value: Double, torqueEnd: Double?, variation: Double?, toolSize: String?, description: String?, unverified: Bool) -> Bool {
        spec.category = category
        spec.name = name
        spec.torque = value
        spec.torqueEnd = torqueEnd
        spec.variation = variation
        spec.toolSize = (toolSize?.isEmpty == false) ? toolSize : nil
        spec.recordDescription = (description?.isEmpty == false) ? description : nil
        spec.unverified = unverified
        if spec.syncState != .pendingCreate { spec.syncState = .pendingUpdate }
        spec.updatedAtLocal = Date()
        return persistAndSync()
    }

    @discardableResult
    func deleteTorque(_ spec: SDTorqueSpec) -> Bool {
        if spec.serverId == nil {
            modelContext.delete(spec)
        } else {
            spec.syncState = .pendingDelete
            spec.updatedAtLocal = Date()
        }
        return persistAndSync()
    }

    // MARK: - Motorcycle detail writes (offline-first via SwiftData + SyncEngine)

    func reloadDetails() {
        let mid = motorcycle.id
        let descriptor = FetchDescriptor<SDMotorcycleDetail>(
            predicate: #Predicate { $0.motorcycleId == mid },
            sortBy: [SortDescriptor(\.title)]
        )
        let scoped = (try? modelContext.fetch(descriptor)) ?? []
        details = scoped.filter { $0.syncState != .pendingDelete }
    }

    @discardableResult
    func createDetail(title: String, value: String) -> Bool {
        let detail = SDMotorcycleDetail(
            motorcycleId: motorcycle.id,
            title: title,
            value: value,
            createdAt: Self.isoDay(Date()),
            syncState: .pendingCreate
        )
        modelContext.insert(detail)
        return persistAndSync()
    }

    @discardableResult
    func updateDetail(_ detail: SDMotorcycleDetail, title: String, value: String) -> Bool {
        detail.title = title
        detail.value = value
        if detail.syncState != .pendingCreate { detail.syncState = .pendingUpdate }
        detail.updatedAtLocal = Date()
        return persistAndSync()
    }

    @discardableResult
    func deleteDetail(_ detail: SDMotorcycleDetail) -> Bool {
        if detail.serverId == nil {
            modelContext.delete(detail)
        } else {
            detail.syncState = .pendingDelete
            detail.updatedAtLocal = Date()
        }
        return persistAndSync()
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
        return persistAndSync()
    }

    @discardableResult
    func updateIssue(_ issue: SDIssue, odo: Int, title: String, description: String?, priority: String, status: String, date: Date) -> Bool {
        issue.odo = odo
        issue.title = title
        issue.recordDescription = (description?.isEmpty == false) ? description : nil
        issue.priority = priority
        issue.status = status
        issue.date = Self.isoDay(date)
        if issue.syncState != .pendingCreate { issue.syncState = .pendingUpdate }
        issue.updatedAtLocal = Date()
        return persistAndSync()
    }

    @discardableResult
    func deleteIssue(_ issue: SDIssue) -> Bool {
        if issue.serverId == nil {
            modelContext.delete(issue)
        } else {
            issue.syncState = .pendingDelete
            issue.updatedAtLocal = Date()
        }
        return persistAndSync()
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
        vm.details = [
            {
                let d = SDMotorcycleDetail(serverId: 1, motorcycleId: 1, title: "Zündkerze", value: "NGK DPR8EA-9", createdAt: "2024-01-01", syncState: .synced)
                return d
            }(),
            {
                let d = SDMotorcycleDetail(serverId: 2, motorcycleId: 1, title: "Ölfilter", value: "HiFlo HF303", createdAt: "2024-01-01", syncState: .synced)
                return d
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
