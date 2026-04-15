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
        isLoading = true
        errorMessage = nil
        
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
            
        } catch {
            print("MotorcycleDetailViewModel: ERROR: \(error.localizedDescription)")
            errorMessage = "Failed to load details: \(error.localizedDescription)"
        }
        
        isLoading = false
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
}
