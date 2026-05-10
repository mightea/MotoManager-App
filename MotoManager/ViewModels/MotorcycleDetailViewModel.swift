import Foundation
import Combine

@MainActor
class MotorcycleDetailViewModel: ObservableObject {
    let motorcycle: Motorcycle
    
    @Published var maintenanceRecords: [MaintenanceRecord] = []
    @Published var torqueSpecs: [TorqueSpec] = []
    @Published var documents: [Document] = []
    
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    init(motorcycle: Motorcycle) {
        self.motorcycle = motorcycle
    }
    
    func loadAllData() async {
        print("MotorcycleDetailViewModel: Starting load for motorcycle \(motorcycle.id)")

        // Hydrate from cache instantly so the UI works offline / while the network is in flight.
        hydrateFromCache()

        isLoading = true

        do {
            // Run in parallel
            async let maintenanceTask = NetworkManager.shared.fetchMaintenance(motorcycleId: motorcycle.id)
            async let torqueTask = NetworkManager.shared.fetchTorqueSpecs(motorcycleId: motorcycle.id)
            async let documentsTask = NetworkManager.shared.fetchDocuments()

            let (maintenance, torque, allDocs) = try await (maintenanceTask, torqueTask, documentsTask)

            print("MotorcycleDetailViewModel: Received \(maintenance.count) maintenance records")
            print("MotorcycleDetailViewModel: Received \(torque.count) torque specs")
            print("MotorcycleDetailViewModel: Received \(allDocs.count) total documents")

            self.maintenanceRecords = maintenance.sorted(by: { $0.date > $1.date })
            self.torqueSpecs = torque

            // Filter documents for this motorcycle
            self.documents = allDocs.filter { doc in
                doc.motorcycleIds?.contains(motorcycle.id) ?? false
            }
            print("MotorcycleDetailViewModel: Filtered down to \(self.documents.count) documents for this bike")
            errorMessage = nil

        } catch is CancellationError {
            // Ignore normal Swift concurrency cancellations (e.g. from refreshable)
            print("MotorcycleDetailViewModel: Load cancelled")
        } catch {
            print("MotorcycleDetailViewModel: ERROR: \(error.localizedDescription)")
            // Only surface an error when we have nothing cached to show.
            if maintenanceRecords.isEmpty && torqueSpecs.isEmpty && documents.isEmpty {
                errorMessage = "Failed to load details: \(error.localizedDescription)"
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
        }
    }
    
    func addFuelRecord(odo: Int, amount: Double, cost: Double, date: Date) async -> Bool {
        isLoading = true
        defer { isLoading = false }
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        
        let record: [String: Any] = [
            "date": formatter.string(from: date),
            "odo": odo,
            "type": "fuel",
            "fuelAmount": amount,
            "cost": cost,
            "currency": motorcycle.currencyCode ?? "EUR"
        ]
        
        do {
            try await NetworkManager.shared.createMaintenance(motorcycleId: motorcycle.id, record: record)
            await loadAllData() // Refresh
            return true
        } catch {
            errorMessage = "Failed to add fuel: \(error.localizedDescription)"
            return false
        }
    }
    
    static var mock: MotorcycleDetailViewModel {
        let vm = MotorcycleDetailViewModel(motorcycle: .mock)
        vm.maintenanceRecords = [
            MaintenanceRecord(id: 1, date: "2023-10-15", odo: 12000, motorcycleId: 1, cost: 45.50, normalizedCost: 45.5, currency: "EUR", description: "Shell V-Power", recordType: "fuel", brand: nil, model: nil, tirePosition: nil, tireSize: nil, dotCode: nil, batteryType: nil, fluidType: nil, viscosity: nil, oilType: nil, inspectionLocation: nil, locationId: nil, fuelType: "98", fuelAmount: 18.5, pricePerUnit: 2.45, latitude: nil, longitude: nil, locationName: "Shell Munich", fuelConsumption: 5.2, tripDistance: 350, summary: "Tankstopp bei Shell", parentId: nil),
            MaintenanceRecord(id: 2, date: "2023-09-01", odo: 10000, motorcycleId: 1, cost: 250.00, normalizedCost: 250.0, currency: "EUR", description: "", recordType: "service", brand: nil, model: nil, tirePosition: nil, tireSize: nil, dotCode: nil, batteryType: nil, fluidType: nil, viscosity: "15W-50", oilType: "Synthetic", inspectionLocation: nil, locationId: nil, fuelType: nil, fuelAmount: nil, pricePerUnit: nil, latitude: nil, longitude: nil, locationName: "BMW Service", fuelConsumption: nil, tripDistance: nil, summary: "Regulärer 10k Service", parentId: nil)
        ]
        vm.torqueSpecs = [
            TorqueSpec(id: 1, motorcycleId: 1, category: "Engine", name: "Oil Drain Plug", torque: 42, torqueEnd: nil, variation: nil, toolSize: "17mm", description: nil, createdAt: "2023-01-01"),
            TorqueSpec(id: 2, motorcycleId: 1, category: "Wheels", name: "Rear Axle Nut", torque: 100, torqueEnd: nil, variation: nil, toolSize: "34mm", description: nil, createdAt: "2023-01-01")
        ]
        vm.documents = [
            Document(id: 1, title: "Registration Part I", filePath: "", previewPath: nil, uploadedBy: nil, ownerId: 1, isPrivate: false, createdAt: "2023-01-01", updatedAt: "2023-01-01", motorcycleIds: [1]),
            Document(id: 2, title: "Service Manual", filePath: "", previewPath: nil, uploadedBy: nil, ownerId: 1, isPrivate: false, createdAt: "2023-01-01", updatedAt: "2023-01-01", motorcycleIds: [1])
        ]
        return vm
    }
}
