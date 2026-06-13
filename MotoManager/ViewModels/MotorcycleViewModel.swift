import Foundation
import Combine

@MainActor
class MotorcycleViewModel: ObservableObject {
    @Published var motorcycles: [Motorcycle] = []
    @Published var selectedMotorcycle: Motorcycle?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let lastSelectedIdKey = "com.motomanager.lastSelectedId"
    private let recentIdsKey = "com.motomanager.recentBikeIds"
    /// Recent motorcycle IDs in MRU order (most-recently-used first), excluding the
    /// currently-selected bike. Capped to 5. Used by the picker's "Zuletzt verwendet".
    var recentMotorcycleIds: [Int] {
        UserDefaults.standard.array(forKey: recentIdsKey) as? [Int] ?? []
    }

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
        let previousId = selectedMotorcycle?.id
        selectedMotorcycle = motorcycle
        UserDefaults.standard.set(motorcycle.id, forKey: lastSelectedIdKey)

        // Push the previously-selected bike to the front of the recents list
        // (the new active bike doesn't belong in "recently used").
        if let prev = previousId, prev != motorcycle.id {
            var recents = recentMotorcycleIds.filter { $0 != prev && $0 != motorcycle.id }
            recents.insert(prev, at: 0)
            UserDefaults.standard.set(Array(recents.prefix(5)), forKey: recentIdsKey)
        }
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
