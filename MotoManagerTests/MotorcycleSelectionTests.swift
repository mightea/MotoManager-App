import Foundation
import Testing
@testable import MotoManager

@MainActor
struct MotorcycleSelectionTests {
    private func motorcycle(id: Int, name: String, image: String? = nil) throws -> Motorcycle {
        var json: [String: Any] = ["id": id, "make": name, "model": "Test", "userId": 1,
                                   "isVeteran": false, "initialOdo": 0]
        if let image { json["image"] = image }
        return try JSONDecoder().decode(Motorcycle.self, from: JSONSerialization.data(withJSONObject: json))
    }

    @Test func refreshedFleetReplacesCachedIdentityWithoutChangingSelection() throws {
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let vm = MotorcycleViewModel(defaults: defaults)
        vm.applyFleet([try motorcycle(id: 1, name: "Cached")])
        vm.applyFleet([try motorcycle(id: 1, name: "Updated", image: "https://example.com/bike.jpg")])
        #expect(vm.selectedMotorcycle?.id == 1)
        #expect(vm.selectedMotorcycle?.make == "Updated")
        #expect(vm.selectedMotorcycle?.image == "https://example.com/bike.jpg")
    }

    @Test func refreshPreservesTheChosenBikeWhenFleetOrderChanges() throws {
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let vm = MotorcycleViewModel(defaults: defaults)
        let first = try motorcycle(id: 1, name: "First")
        let chosen = try motorcycle(id: 2, name: "Chosen")
        vm.applyFleet([first, chosen])
        vm.selectMotorcycle(chosen)
        vm.applyFleet([try motorcycle(id: 2, name: "Updated"), first])
        #expect(vm.selectedMotorcycle?.id == 2)
        #expect(vm.selectedMotorcycle?.make == "Updated")
        #expect(vm.recentMotorcycleIds == [1])
    }

    @Test func removedSelectionFallsBackAndEmptyFleetClearsIt() throws {
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let vm = MotorcycleViewModel(defaults: defaults)
        let first = try motorcycle(id: 1, name: "First")
        vm.applyFleet([first])
        vm.selectMotorcycle(first)
        vm.applyFleet([try motorcycle(id: 2, name: "Remaining")])
        #expect(vm.selectedMotorcycle?.id == 2)
        vm.applyFleet([])
        #expect(vm.selectedMotorcycle == nil)
    }

    @Test func restoresPersistedSelectionIntoTheCurrentSnapshot() throws {
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        defaults.set(2, forKey: "com.motomanager.lastSelectedId")
        let vm = MotorcycleViewModel(defaults: defaults)
        vm.applyFleet([try motorcycle(id: 1, name: "First"), try motorcycle(id: 2, name: "Saved")])
        #expect(vm.selectedMotorcycle?.make == "Saved")
    }
}
