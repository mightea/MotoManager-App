import Foundation
import Combine

@MainActor
class MotorcycleViewModel: ObservableObject {
    @Published var motorcycles: [Motorcycle] = []
    @Published var selectedMotorcycle: Motorcycle?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    func loadMotorcycles() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let fetched = try await NetworkManager.shared.fetchMotorcycles()
            self.motorcycles = fetched
            // Default selection to the first bike if none selected
            if selectedMotorcycle == nil, let first = fetched.first {
                self.selectedMotorcycle = first
            }
        } catch {
            errorMessage = "Failed to load fleet: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    func selectMotorcycle(_ motorcycle: Motorcycle) {
        selectedMotorcycle = motorcycle
    }
}
