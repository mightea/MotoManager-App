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
        // Hydrate from cache instantly so the UI is usable offline / before the network responds.
        if motorcycles.isEmpty,
           let cached = CacheStore.shared.load([Motorcycle].self, key: CacheKey.motorcycles) {
            self.motorcycles = cached
            restoreSelection()
        }

        isLoading = true

        do {
            let fetched = try await NetworkManager.shared.fetchMotorcycles()
            self.motorcycles = fetched
            restoreSelection()
            errorMessage = nil
        } catch {
            // Only surface an error when we have nothing cached to show.
            if motorcycles.isEmpty {
                errorMessage = "Failed to load fleet: \(error.localizedDescription)"
            }
        }

        isLoading = false
    }

    func selectMotorcycle(_ motorcycle: Motorcycle) {
        selectedMotorcycle = motorcycle
        UserDefaults.standard.set(motorcycle.id, forKey: lastSelectedIdKey)
    }

    private func restoreSelection() {
        let lastId = UserDefaults.standard.integer(forKey: lastSelectedIdKey)
        if let lastMoto = motorcycles.first(where: { $0.id == lastId }) {
            self.selectedMotorcycle = lastMoto
        } else if selectedMotorcycle == nil, let first = motorcycles.first {
            self.selectedMotorcycle = first
        }
    }
}
