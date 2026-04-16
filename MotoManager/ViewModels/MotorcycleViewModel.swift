import Foundation
import Combine

@MainActor
class MotorcycleViewModel: ObservableObject {
    @Published var motorcycles: [Motorcycle] = []
    @Published var selectedMotorcycle: Motorcycle?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let lastSelectedIdKey = "com.motomanager.lastSelectedId"
    
    func loadMotorcycles() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let fetched = try await NetworkManager.shared.fetchMotorcycles()
            self.motorcycles = fetched
            
            // Try to restore last selection
            let lastId = UserDefaults.standard.integer(forKey: lastSelectedIdKey)
            if let lastMoto = fetched.first(where: { $0.id == lastId }) {
                self.selectedMotorcycle = lastMoto
            } else if selectedMotorcycle == nil, let first = fetched.first {
                // Default to first bike
                self.selectedMotorcycle = first
            }
        } catch {
            errorMessage = "Failed to load fleet: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    func selectMotorcycle(_ motorcycle: Motorcycle) {
        selectedMotorcycle = motorcycle
        UserDefaults.standard.set(motorcycle.id, forKey: lastSelectedIdKey)
    }
}
