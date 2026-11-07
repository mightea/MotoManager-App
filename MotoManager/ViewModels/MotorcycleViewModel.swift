import Foundation
import Combine

@MainActor
class MotorcycleViewModel: ObservableObject {
    @Published var motorcycles: [Motorcycle] = []
    @Published var selectedMotorcycle: Motorcycle?
    @Published var isLoading = false
    /// False until `loadMotorcycles()` has finished once (success or failure).
    /// The tab root shows a spinner instead of the empty-garage screen before
    /// that, since the first frame after login renders before the load task
    /// has even set `isLoading`.
    @Published private(set) var hasLoadedOnce = false
    @Published var errorMessage: String?

    private let lastSelectedIdKey = "com.motomanager.lastSelectedId"
    private let recentIdsKey = "com.motomanager.recentBikeIds"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }
    /// Recent motorcycle IDs in MRU order (most-recently-used first), excluding the
    /// currently-selected bike. Capped to 5. Used by the picker's "Zuletzt verwendet".
    var recentMotorcycleIds: [Int] {
        defaults.array(forKey: recentIdsKey) as? [Int] ?? []
    }

    func loadMotorcycles() async {
        // Hydrate from cache instantly so the UI is usable offline / before the network responds.
        if motorcycles.isEmpty,
           let cached = CacheStore.shared.load([Motorcycle].self, key: CacheKey.motorcycles) {
            applyFleet(cached)
        }

        isLoading = true

        do {
            let fetched = try await NetworkManager.shared.fetchMotorcycles()
            applyFleet(fetched)
            errorMessage = nil
        } catch {
            // Only surface an error when we have nothing cached to show.
            if motorcycles.isEmpty {
                errorMessage = "Garage konnte nicht geladen werden: \(error.localizedDescription)"
            }
        }

        hasLoadedOnce = true
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

    /// Online-only edit; the confirmed server copy replaces the bike in the
    /// fleet, the cache and (when active) the selection, so the header and
    /// every workspace pick the change up at once.
    @discardableResult
    func updateMotorcycle(
        _ motorcycle: Motorcycle,
        fields: [(name: String, value: String)],
        image: (data: Data, mimeType: String)?
    ) async -> Bool {
        errorMessage = nil
        do {
            let updated = try await NetworkManager.shared.updateMotorcycle(id: motorcycle.id, fields: fields, image: image)
            if let index = motorcycles.firstIndex(where: { $0.id == updated.id }) {
                motorcycles[index] = updated
            } else {
                motorcycles.append(updated)
            }
            motorcycles.sort {
                "\($0.make) \($0.model)".localizedCaseInsensitiveCompare("\($1.make) \($1.model)") == .orderedAscending
            }
            CacheStore.shared.save(motorcycles, key: CacheKey.motorcycles)
            if selectedMotorcycle?.id == updated.id { selectedMotorcycle = updated }
            return true
        } catch {
            errorMessage = "Motorrad konnte nicht gespeichert werden: \(error.localizedDescription)"
            return false
        }
    }

    /// Deletes the bike and its whole server-side history, then drops the
    /// local SwiftData rows that belonged to it so no orphaned record is
    /// ever pushed against the vanished id.
    @discardableResult
    func deleteMotorcycle(_ motorcycle: Motorcycle) async -> Bool {
        errorMessage = nil
        do {
            try await NetworkManager.shared.deleteMotorcycle(id: motorcycle.id)
        } catch {
            errorMessage = "Motorrad konnte nicht gelöscht werden: \(error.localizedDescription)"
            return false
        }
        SyncEngine.shared.purgeLocalRecords(motorcycleId: motorcycle.id)
        motorcycles.removeAll { $0.id == motorcycle.id }
        CacheStore.shared.save(motorcycles, key: CacheKey.motorcycles)
        defaults.set(recentMotorcycleIds.filter { $0 != motorcycle.id }, forKey: recentIdsKey)
        if selectedMotorcycle?.id == motorcycle.id {
            selectedMotorcycle = motorcycles.first
            if let next = motorcycles.first {
                defaults.set(next.id, forKey: lastSelectedIdKey)
            } else {
                defaults.removeObject(forKey: lastSelectedIdKey)
            }
        }
        return true
    }

    func selectMotorcycle(_ motorcycle: Motorcycle) {
        let previousId = selectedMotorcycle?.id
        selectedMotorcycle = motorcycle
        defaults.set(motorcycle.id, forKey: lastSelectedIdKey)

        // Push the previously-selected bike to the front of the recents list
        // (the new active bike doesn't belong in "recently used").
        if let prev = previousId, prev != motorcycle.id {
            var recents = recentMotorcycleIds.filter { $0 != prev && $0 != motorcycle.id }
            recents.insert(prev, at: 0)
            defaults.set(Array(recents.prefix(5)), forKey: recentIdsKey)
        }
    }

    /// Full user-state reset for logout: published fleet state plus the
    /// persisted selection/recents — a different account must not inherit
    /// another user's bike ids or see the previous fleet flash on login.
    func clearUserState() {
        motorcycles = []
        selectedMotorcycle = nil
        hasLoadedOnce = false
        errorMessage = nil
        defaults.removeObject(forKey: lastSelectedIdKey)
        defaults.removeObject(forKey: recentIdsKey)
    }

    /// Resolve identity against each new snapshot, even when the ID is unchanged.
    /// A cached object may contain an old name, photo or mileage; a removed
    /// motorcycle must not remain selected after a successful fleet refresh.
    func applyFleet(_ motorcycles: [Motorcycle]) {
        self.motorcycles = motorcycles
        let selectedId = selectedMotorcycle?.id ?? defaults.integer(forKey: lastSelectedIdKey)
        selectedMotorcycle = motorcycles.first(where: { $0.id == selectedId }) ?? motorcycles.first
    }
}
