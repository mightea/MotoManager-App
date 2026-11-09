import Foundation
import Testing
@testable import MotoManager

@MainActor
struct PartsPlanningTests {
    private let carb = UUID(), filter = UUID(), plug = UUID(), regulator = UUID(), r68 = UUID()
    private let now = Date(timeIntervalSince1970: 1_794_000_000)

    private var parts: [PartNeeds.Part] {
        [.init(id: carb, name: "Vergaser-Dichtsatz", fitsBike: true),
         .init(id: filter, name: "Ölfilter", fitsBike: true),
         .init(id: plug, name: "Zündkerze W8AC", fitsBike: true),
         .init(id: regulator, name: "Regler Wehrle", fitsBike: true),
         .init(id: r68, name: "Vergaser-Dichtsatz R 68", fitsBike: false)]
    }

    @Test func issuesMatchOnNamesAndLinks() {
        let leak = UUID(), light = UUID()
        let needs = PartNeeds.needs(
            parts: parts,
            issues: [.init(id: leak, title: "Vergaser tropft nach Standzeit", text: "Schwimmernadelventil bestellen"),
                     .init(id: light, title: "Rücklicht flackert", text: "Massekontakt prüfen")],
            intervals: [], links: [light: [regulator]], now: now)
        #expect(Set(needs.map(\.partId)) == [carb, regulator])
        #expect(needs.first { $0.partId == carb }?.reason == .issue(title: "Vergaser tropft nach Standzeit"))
    }

    @Test func intervalsMatchWithinHorizonOnly() {
        let soon = Calendar.current.date(byAdding: .month, value: 6, to: now)!
        let later = Calendar.current.date(byAdding: .month, value: 30, to: now)!
        let needs = PartNeeds.needs(
            parts: parts, issues: [],
            intervals: [.init(key: "fluid-engineoil", label: "Motoröl", due: soon, isDue: false),
                        .init(key: "battery", label: "Batterie", due: later, isDue: false)],
            now: now)
        #expect(needs == [PartNeed(partId: filter, reason: .interval(label: "Motoröl", due: soon))])
    }

    @Test func issueBeatsIntervalForTheSamePart() {
        let issue = UUID()
        let needs = PartNeeds.needs(
            parts: parts,
            issues: [.init(id: issue, title: "Ölfilter undicht", text: "")],
            intervals: [.init(key: "fluid-engineoil", label: "Motoröl", due: now, isDue: true)], now: now)
        #expect(needs.count == 1)
        #expect(needs[0].reason == .issue(title: "Ölfilter undicht"))
    }

    @Test func shoppingListGroupsAndSuggestsQuantities() {
        let items = ShoppingList.items(
            parts: [.init(id: carb, name: "Vergaser-Dichtsatz", onHand: 1, unitPrice: 38),
                    .init(id: plug, name: "Zündkerze W8AC", onHand: 4, unitPrice: 5),
                    .init(id: filter, name: "Ölfilter", onHand: 0, unitPrice: 12.5, repairUses: 4),
                    .init(id: regulator, name: "Regler Wehrle", onHand: 3, unitPrice: nil)],
            neededForIssue: [carb], manual: [regulator], dismissed: [:], quantities: [:])
        #expect(items.map(\.name) == ["Vergaser-Dichtsatz", "Ölfilter", "Regler Wehrle"])
        #expect(items.map(\.group) == [.issue, .low, .manual])
        #expect(items.map(\.quantity) == [1, 2, 1])
        #expect(items[1].estimate == 25)
    }

    /// Low stock alone is no reason to buy: only parts booked in more than
    /// three repairs land in "Knapp im Lager".
    @Test func lowGroupOnlyHoldsFrequentlyUsedParts() {
        let items = ShoppingList.items(
            parts: [.init(id: filter, name: "Ölfilter", onHand: 0, unitPrice: nil, repairUses: 3),
                    .init(id: plug, name: "Zündkerze W8AC", onHand: 1, unitPrice: nil, repairUses: 4),
                    .init(id: regulator, name: "Regler Wehrle", onHand: 2, unitPrice: nil, repairUses: 9)],
            neededForIssue: [], manual: [], dismissed: [:], quantities: [:])
        #expect(items.map(\.name) == ["Zündkerze W8AC"])
        #expect(items.map(\.group) == [.low])
    }

    @Test func repairUsesCountDistinctRepairs() {
        let repair = UUID()
        let uses = RestockRule.repairUses([
            .init(partId: plug, repairClientId: repair, repairServerId: nil),
            .init(partId: plug, repairClientId: repair, repairServerId: 7),
            .init(partId: plug, repairClientId: nil, repairServerId: 8),
            .init(partId: plug, repairClientId: nil, repairServerId: nil),
            .init(partId: filter, repairClientId: nil, repairServerId: 8)])
        #expect(uses[plug] == 2)
        #expect(uses[filter] == 1)
        #expect(uses[carb] == nil)
    }

    /// A hand-added part leaves the list once its stock rises (a scanned
    /// receipt), and the store forgets it for good.
    @Test func manualEntriesLeaveOnceStockRises() {
        let before = ShoppingList.Part(id: plug, name: "Zündkerze W8AC", onHand: 2, unitPrice: nil)
        let after = ShoppingList.Part(id: plug, name: "Zündkerze W8AC", onHand: 4, unitPrice: nil)
        #expect(ShoppingList.items(parts: [before], neededForIssue: [], manual: [plug], dismissed: [:],
                                   quantities: [:], manualOnHand: [plug: 2]).count == 1)
        #expect(ShoppingList.items(parts: [after], neededForIssue: [], manual: [plug], dismissed: [:],
                                   quantities: [:], manualOnHand: [plug: 2]).isEmpty)

        let name = "planning-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = PartsPlanningStore(defaults: defaults)
        store.addToList(plug, onHand: 2)
        store.addToList(filter, onHand: 0)
        store.removeBought(onHand: [plug: 2, filter: 0])
        #expect(store.manual == [plug, filter])
        store.removeBought(onHand: [plug: 4, filter: 0])
        #expect(PartsPlanningStore(defaults: defaults).manual == [filter])
    }

    @Test func clearedItemsStayOffUntilStockChanges() {
        let part = ShoppingList.Part(id: carb, name: "Vergaser-Dichtsatz", onHand: 1, unitPrice: nil, repairUses: 4)
        #expect(ShoppingList.items(parts: [part], neededForIssue: [], manual: [], dismissed: [carb: 1], quantities: [:]).isEmpty)
        let lower = ShoppingList.Part(id: carb, name: "Vergaser-Dichtsatz", onHand: 0, unitPrice: nil, repairUses: 4)
        #expect(ShoppingList.items(parts: [lower], neededForIssue: [], manual: [], dismissed: [carb: 1], quantities: [:]).count == 1)
    }

    @Test func storePersistsList() {
        let name = "planning-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = PartsPlanningStore(defaults: defaults)
        store.addToList(plug, onHand: 4)
        store.setQuantity(3, for: plug)
        let reloaded = PartsPlanningStore(defaults: defaults)
        #expect(reloaded.manual == [plug])
        #expect(reloaded.quantities[plug] == 3)
        reloaded.clear(plug, onHand: 4)
        #expect(PartsPlanningStore(defaults: defaults).manual.isEmpty)
    }

    /// Snapshots from before the links moved to the server still decode;
    /// their links are handed over once and then gone from the device.
    @Test func legacySnapshotHandsOverLinksOnce() throws {
        let name = "planning-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let issue = UUID()
        // The snapshot shape the app wrote before (links non-optional).
        struct OldSnapshot: Codable {
            var manual: Set<UUID>
            var dismissed: [UUID: Int]
            var quantities: [UUID: Int]
            var links: [UUID: Set<UUID>]
        }
        let old = OldSnapshot(manual: [plug], dismissed: [:], quantities: [:], links: [issue: [regulator]])
        defaults.set(try JSONEncoder().encode(old), forKey: "com.motomanager.partsPlanning")
        let store = PartsPlanningStore(defaults: defaults)
        #expect(store.manual == [plug])
        #expect(store.takeLegacyLinks() == [issue: [regulator]])
        #expect(store.takeLegacyLinks().isEmpty)
        let reloaded = PartsPlanningStore(defaults: defaults)
        #expect(reloaded.takeLegacyLinks().isEmpty)
        #expect(reloaded.manual == [plug])
    }

    @Test func shareTextListsGroups() {
        let text = ShoppingList.text([
            ShoppingItem(partId: carb, name: "Vergaser-Dichtsatz", group: .issue, onHand: 1, quantity: 1, unitPrice: nil),
            ShoppingItem(partId: filter, name: "Ölfilter", group: .low, onHand: 0, quantity: 2, unitPrice: nil)])
        #expect(text.contains("Für offene Mängel:\n• 1× Vergaser-Dichtsatz"))
        #expect(text.contains("Knapp im Lager:\n• 2× Ölfilter"))
    }
}
