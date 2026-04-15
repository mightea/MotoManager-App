import Foundation
import Combine

@MainActor
class MotorcycleViewModel: ObservableObject {
    @Published var motorcycles: [Motorcycle] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    func loadMotorcycles() async {
        isLoading = true
        errorMessage = nil
        
        do {
            motorcycles = try await NetworkManager.shared.fetchMotorcycles()
        } catch {
            errorMessage = "Failed to load motorcycles: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
}
