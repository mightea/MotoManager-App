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
                errorMessage = "Garage konnte nicht geladen werden: \(error.localizedDescription)"
            }
        }

        isLoading = false
    }

    @discardableResult
    func createMotorcycle(
        make: String,
        model: String,
        fabricationDate: String?,
        initialOdo: Int,
        currencyCode: String,
        isVeteran: Bool
    ) async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let created = try await NetworkManager.shared.createMotorcycle(
                make: make,
                model: model,
                fabricationDate: fabricationDate,
                initialOdo: initialOdo,
                currencyCode: currencyCode,
                isVeteran: isVeteran
            )
            motorcycles.append(created)
            motorcycles.sort {
                "\($0.make) \($0.model)".localizedCaseInsensitiveCompare("\($1.make) \($1.model)") == .orderedAscending
            }
            CacheStore.shared.save(motorcycles, key: CacheKey.motorcycles)
            selectMotorcycle(created)
            return true
        } catch {
            errorMessage = "Motorrad konnte nicht angelegt werden: \(error.localizedDescription)"
            return false
        }
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

    /// Full user-state reset for logout: published fleet state plus the
    /// persisted selection/recents — a different account must not inherit
    /// another user's bike ids or see the previous fleet flash on login.
    func clearUserState() {
        motorcycles = []
        selectedMotorcycle = nil
        errorMessage = nil
        UserDefaults.standard.removeObject(forKey: lastSelectedIdKey)
        UserDefaults.standard.removeObject(forKey: recentIdsKey)
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
