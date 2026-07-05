import Testing
import Foundation
import SwiftData
@testable import MotoManager

// MARK: - DTO decoding

struct PartDecodingTests {

    @Test func decodesPartWithMeta() throws {
        let json = """
        {"id":3,"userId":1,"partNumber":"11 42 7 673 541","name":"Ölfilter",
         "manufacturer":"BMW","description":"mit O-Ring","isPublic":true,
         "createdAt":"2026-07-01T10:00:00.000Z","seriesIds":[12,14],
         "onHand":2,"stockCount":1,
         "clientId":"11111111-1111-1111-1111-111111111111",
         "updatedAt":"2026-07-01T10:00:00.000Z","deletedAt":null}
        """
        let part = try JSONDecoder().decode(Part.self, from: Data(json.utf8))
        #expect(part.partNumber == "11 42 7 673 541")
        #expect(part.seriesIds == [12, 14])
        #expect(part.onHand == 2)
        #expect(part.stockCount == 1)
        #expect(part.isPublic)
        #expect(part.deletedAt == nil)
    }

    @Test func decodesPublicPartWithoutPrivateFields() throws {
        let json = """
        {"id":5,"partNumber":"PN-1","name":"Tachowelle","manufacturer":"BMW",
         "description":null,"seriesIds":[19],"ownerName":"testuser",
         "hasStock":true,"totalQuantity":3}
        """
        let part = try JSONDecoder().decode(PublicPart.self, from: Data(json.utf8))
        #expect(part.ownerName == "testuser")
        #expect(part.hasStock)
        #expect(part.totalQuantity == 3)
    }

    @Test func modelSeriesDisplayNamePrefixesNonBMWManufacturer() throws {
        let bmw = ModelSeries(id: 1, name: "R 1150 GS", manufacturer: "BMW", parentId: nil, userId: nil, createdAt: "")
        let other = ModelSeries(id: 2, name: "XSR 700", manufacturer: "Yamaha", parentId: nil, userId: 3, createdAt: "")
        #expect(bmw.displayName == "R 1150 GS")
        #expect(other.displayName == "Yamaha XSR 700")
    }
}

// MARK: - Model catalog hierarchy

struct ModelSeriesCatalogTests {
    private func node(_ id: Int, _ name: String, _ parentId: Int?) -> ModelSeries {
        ModelSeries(id: id, name: name, manufacturer: "BMW", parentId: parentId, userId: nil, createdAt: "")
    }

    // Familie(1) -> Serie(2) -> Modell(3); Familie(1) -> Serie(4); Familie(5)
    private var catalog: [ModelSeries] {
        [
            node(1, "R-Modelle 2V", nil),
            node(2, "R 80 GS, R 100 GS, PD (90-95)", 1),
            node(3, "R 100 GS (ECE, 04/1990-07/1996)", 2),
            node(4, "R 100 RS, R 100 RT (87-95)", 1),
            node(5, "K-Modelle 3-Zyl.", nil),
        ]
    }

    @Test func depthAndPath() {
        #expect(ModelSeriesCatalog.depth(of: catalog[0], in: catalog) == 0)
        #expect(ModelSeriesCatalog.depth(of: catalog[2], in: catalog) == 2)
        #expect(ModelSeriesCatalog.path(of: catalog[2], in: catalog)
            == "R-Modelle 2V › R 80 GS, R 100 GS, PD (90-95) › R 100 GS (ECE, 04/1990-07/1996)")
    }

    @Test func treeOrdersChildrenUnderParents() {
        let flattened = ModelSeriesCatalog.tree(catalog).map { "\($0.depth):\($0.node.id)" }
        // Siblings sort lexically: "K-Modelle…" < "R-Modelle…", "R 100…" < "R 80…".
        #expect(flattened == ["0:5", "0:1", "1:4", "1:2", "2:3"])
    }

    @Test func hierarchyAwareMatching() {
        // Bike on the Serie level: Familie link and Modell link fit, siblings don't.
        #expect(ModelSeriesCatalog.matches(partSeriesIds: [1], bikeSeriesId: 2, in: catalog))
        #expect(ModelSeriesCatalog.matches(partSeriesIds: [3], bikeSeriesId: 2, in: catalog))
        #expect(!ModelSeriesCatalog.matches(partSeriesIds: [4], bikeSeriesId: 2, in: catalog))
        #expect(!ModelSeriesCatalog.matches(partSeriesIds: [5], bikeSeriesId: 2, in: catalog))
        // Bike on the Familie level matches everything below.
        #expect(ModelSeriesCatalog.matches(partSeriesIds: [3], bikeSeriesId: 1, in: catalog))
    }
}

// MARK: - Sync mapping round-trips

struct PartsSyncMappingTests {

    @Test func partPayloadCarriesClientIdAndFitment() {
        let part = SDPart(partNumber: "PN-1", name: "Ölfilter", seriesIds: [12, 14], syncState: .pendingCreate)
        part.isPublic = true
        part.partDescription = "mit O-Ring"

        let payload = part.toPayload()
        #expect(payload["clientId"] as? String == part.clientId.uuidString)
        #expect(payload["partNumber"] as? String == "PN-1")
        #expect(payload["seriesIds"] as? [Int] == [12, 14])
        #expect(payload["isPublic"] as? Bool == true)
        #expect(payload["description"] as? String == "mit O-Ring")
    }

    @Test func partApplyReconcilesServerStateAndFitment() throws {
        let local = SDPart(partNumber: "PN-1", name: "Ölfilter", syncState: .pendingCreate)
        let json = """
        {"id":42,"userId":1,"partNumber":"PN-1","name":"Ölfilter Mahle",
         "manufacturer":"BMW","description":null,"isPublic":false,
         "createdAt":"2026-07-01T10:00:00.000Z","seriesIds":[7],
         "onHand":0,"stockCount":0,
         "clientId":"\(local.clientId.uuidString)",
         "updatedAt":"2026-07-01T10:00:00.000Z","deletedAt":null}
        """
        let dto = try JSONDecoder().decode(Part.self, from: Data(json.utf8))
        local.apply(dto)
        #expect(local.serverId == 42)
        #expect(local.name == "Ölfilter Mahle")
        #expect(local.seriesIds == [7])
        #expect(local.syncState == .synced)
        #expect(local.serverUpdatedAt == "2026-07-01T10:00:00.000Z")
    }

    @Test func stockPayloadResolvesForeignKeysAtCallTime() {
        let partClientId = UUID()
        let stock = SDPartStock(partClientId: partClientId, quantity: 3, syncState: .pendingCreate)
        stock.price = 14.9
        stock.currency = "CHF"
        stock.purchaseDate = "2026-06-01"

        let payload = stock.toPayload(partServerId: 42, storageLocationServerId: 7)
        #expect(payload["clientId"] as? String == stock.clientId.uuidString)
        #expect(payload["partId"] as? Int == 42)
        #expect(payload["storageLocationId"] as? Int == 7)
        #expect(payload["quantity"] as? Int == 3)
        #expect(payload["price"] as? Double == 14.9)
    }

    @Test func stockPayloadOmitsNilOptionals() {
        let stock = SDPartStock(partClientId: UUID(), quantity: 1, syncState: .pendingCreate)
        let payload = stock.toPayload(partServerId: 1, storageLocationServerId: nil)
        #expect(payload["price"] == nil)
        #expect(payload["storageLocationId"] == nil)
        #expect(payload["notes"] == nil)
    }

    @Test func consumptionPayloadCarriesMaintenanceLink() {
        let consumption = SDPartConsumption(
            partClientId: UUID(), quantity: 2, date: "2026-06-20", syncState: .pendingCreate)
        let payload = consumption.toPayload(partServerId: 42, maintenanceRecordId: 99)
        #expect(payload["partId"] as? Int == 42)
        #expect(payload["maintenanceRecordId"] as? Int == 99)
        #expect(payload["quantity"] as? Int == 2)
        #expect(payload["date"] as? String == "2026-06-20")
    }

    @Test func storageLocationMakeAdoptsServerClientId() throws {
        let json = """
        {"id":7,"userId":1,"name":"Regal A","parentId":3,
         "createdAt":"2026-07-01T10:00:00.000Z",
         "clientId":"22222222-2222-2222-2222-222222222222",
         "updatedAt":"2026-07-01T10:00:00.000Z","deletedAt":null}
        """
        let dto = try JSONDecoder().decode(StorageLocation.self, from: Data(json.utf8))
        let parentClientId = UUID()
        let model = SDStorageLocation.make(from: dto, parentClientId: parentClientId)
        #expect(model.clientId == UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        #expect(model.serverId == 7)
        #expect(model.parentServerId == 3)
        #expect(model.parentClientId == parentClientId)
        #expect(model.syncState == .synced)
    }
}

// MARK: - On-hand derivation & overdraw guard

@MainActor
struct PartsInventoryTests {

    /// Fresh in-memory store per test so derivations start from zero.
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: SDPart.self, SDPartStock.self, SDPartConsumption.self, SDStorageLocation.self,
            configurations: config)
        return ModelContext(container)
    }

    @Test func onHandIsStockMinusConsumption() throws {
        let context = try makeContext()
        let part = SDPart(partNumber: "PN-1", name: "Zündkerze")
        context.insert(part)
        context.insert(SDPartStock(partClientId: part.clientId, quantity: 3))
        context.insert(SDPartStock(partClientId: part.clientId, quantity: 2))
        context.insert(SDPartConsumption(partClientId: part.clientId, quantity: 4, date: "2026-06-20"))
        try context.save()

        #expect(PartsInventory.onHand(for: part.clientId, in: context) == 1)
    }

    @Test func onHandIgnoresPendingDeletes() throws {
        let context = try makeContext()
        let part = SDPart(partNumber: "PN-1", name: "Zündkerze")
        context.insert(part)
        let stock = SDPartStock(partClientId: part.clientId, quantity: 5)
        context.insert(stock)
        let consumption = SDPartConsumption(partClientId: part.clientId, quantity: 2, date: "2026-06-20")
        context.insert(consumption)
        try context.save()
        #expect(PartsInventory.onHand(for: part.clientId, in: context) == 3)

        // A consumption marked for deletion restores stock by derivation.
        consumption.syncState = .pendingDelete
        try context.save()
        #expect(PartsInventory.onHand(for: part.clientId, in: context) == 5)

        // A stock entry marked for deletion stops counting.
        stock.syncState = .pendingDelete
        try context.save()
        #expect(PartsInventory.onHand(for: part.clientId, in: context) == 0)
    }

    @Test func recordConsumptionRejectsOverdraw() throws {
        let context = try makeContext()
        let part = SDPart(partNumber: "PN-1", name: "Zündkerze")
        context.insert(part)
        context.insert(SDPartStock(partClientId: part.clientId, quantity: 1))
        try context.save()

        // More than on-hand -> rejected, nothing recorded.
        #expect(PartsInventory.recordConsumption(
            part: part, quantity: 2, date: "2026-06-20", in: context) == nil)
        // Exactly on-hand -> accepted.
        #expect(PartsInventory.recordConsumption(
            part: part, quantity: 1, date: "2026-06-20", in: context) != nil)
        try context.save()
        #expect(PartsInventory.onHand(for: part.clientId, in: context) == 0)
        // Empty -> rejected again.
        #expect(PartsInventory.recordConsumption(
            part: part, quantity: 1, date: "2026-06-20", in: context) == nil)
    }

    @Test func availablePartsListsOnlyPositiveOnHand() throws {
        let context = try makeContext()
        let stocked = SDPart(partNumber: "PN-1", name: "Auf Lager")
        let empty = SDPart(partNumber: "PN-2", name: "Leer")
        context.insert(stocked)
        context.insert(empty)
        context.insert(SDPartStock(partClientId: stocked.clientId, quantity: 1))
        try context.save()

        let available = PartsInventory.availableParts(in: context)
        #expect(available.map(\.clientId) == [stocked.clientId])
    }
}

// MARK: - User-level sync cursor

struct UserSyncCursorTests {

    @Test func userKeyIsScopedPerResource() {
        #expect(SyncCursor.userKey("parts") == "com.motomanager.sync.parts.user")
        #expect(SyncCursor.userKey("partStocks") == "com.motomanager.sync.partStocks.user")
    }

    @Test func clearAllRemovesOnlySyncCursors() {
        let syncKey = SyncCursor.userKey("test-\(UUID().uuidString)")
        let unrelatedKey = "com.motomanager.other.\(UUID().uuidString)"
        UserDefaults.standard.set("2026-07-01T10:00:00.000Z", forKey: syncKey)
        UserDefaults.standard.set("keep-me", forKey: unrelatedKey)

        SyncCursor.clearAll()

        #expect(UserDefaults.standard.string(forKey: syncKey) == nil)
        #expect(UserDefaults.standard.string(forKey: unrelatedKey) == "keep-me")
        UserDefaults.standard.removeObject(forKey: unrelatedKey)
    }
}
