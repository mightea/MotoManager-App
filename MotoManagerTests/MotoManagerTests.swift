//
//  MotoManagerTests.swift
//  MotoManagerTests
//
//  Created by Tobias Herrmann on 15.04.2026.
//

import Testing
import Foundation
@testable import MotoManager

// MARK: - Fixtures

/// A mixed maintenance list covering the polymorphic record types, decoded from
/// JSON shaped like the backend response (note `type` -> `recordType`).
private func decodeRecords() throws -> [MaintenanceRecord] {
    let json = """
    [
      {"id":1,"date":"2024-03-15","odo":12000,"motorcycleId":1,"type":"fuel",
       "fuelAmount":18.5,"fuelType":"98","fuelConsumption":5.2,"cost":40.0,"currency":"CHF"},
      {"id":2,"date":"2024-06-01","odo":12350,"motorcycleId":1,"type":"fuel",
       "fuelAmount":16.0,"fuelConsumption":4.8},
      {"id":3,"date":"2023-12-20","odo":11000,"motorcycleId":1,"type":"fuel",
       "fuelAmount":10.0},
      {"id":4,"date":"2024-02-01","odo":11800,"motorcycleId":1,"type":"tire",
       "brand":"Michelin","tireSize":"180/55","tirePosition":"rear"},
      {"id":5,"date":"2024-01-10","odo":11500,"motorcycleId":1,"type":"oil",
       "oilType":"Synthetic","viscosity":"15W-50","cost":120.0}
    ]
    """
    return try JSONDecoder().decode([MaintenanceRecord].self, from: Data(json.utf8))
}

// MARK: - Decoding

struct MaintenanceRecordDecodingTests {

    @Test func mapsTypeDiscriminatorToRecordType() throws {
        let records = try decodeRecords()
        #expect(records.map(\.recordType) == ["fuel", "fuel", "fuel", "tire", "oil"])
    }

    @Test func decodesFuelSpecificFields() throws {
        let fuel = try decodeRecords()[0]
        #expect(fuel.recordType == "fuel")
        #expect(fuel.fuelAmount == 18.5)
        #expect(fuel.fuelConsumption == 5.2)
        #expect(fuel.fuelType == "98")
        #expect(fuel.currency == "CHF")
        // Fields that don't apply to a fuel record stay nil.
        #expect(fuel.oilType == nil)
        #expect(fuel.tireSize == nil)
    }

    @Test func decodesTireSpecificFields() throws {
        let tire = try decodeRecords()[3]
        #expect(tire.recordType == "tire")
        #expect(tire.brand == "Michelin")
        #expect(tire.tireSize == "180/55")
        #expect(tire.tirePosition == "rear")
        #expect(tire.fuelAmount == nil)
    }

    @Test func decodesOilSpecificFields() throws {
        let oil = try decodeRecords()[4]
        #expect(oil.recordType == "oil")
        #expect(oil.oilType == "Synthetic")
        #expect(oil.viscosity == "15W-50")
        #expect(oil.cost == 120.0)
    }
}

// MARK: - Fuel statistics

struct FuelStatsTests {

    @Test func fuelRecordsFiltersOutNonFuel() throws {
        let fuel = FuelStats.fuelRecords(try decodeRecords())
        #expect(fuel.count == 3)
        #expect(fuel.allSatisfy { $0.recordType == "fuel" })
    }

    @Test func averageConsumptionIgnoresRecordsWithoutConsumption() throws {
        // Records 1 & 2 carry 5.2 and 4.8; record 3 has no consumption value.
        let fuel = FuelStats.fuelRecords(try decodeRecords())
        #expect(abs(FuelStats.averageConsumption(fuel) - 5.0) < 0.0001)
    }

    @Test func averageConsumptionIsZeroWhenEmpty() {
        #expect(FuelStats.averageConsumption([]) == 0)
    }

    @Test func litersInYearSumsOnlyMatchingYear() throws {
        let fuel = FuelStats.fuelRecords(try decodeRecords())
        // 2024 fuel fills: 18.5 + 16.0 (record 3 is 2023).
        #expect(abs(FuelStats.litersInYear(fuel, year: 2024) - 34.5) < 0.0001)
        #expect(abs(FuelStats.litersInYear(fuel, year: 2023) - 10.0) < 0.0001)
        #expect(FuelStats.litersInYear(fuel, year: 2020) == 0)
    }
}

// MARK: - Sync mapping & cursor

struct SyncMappingTests {

    @Test func createPayloadCarriesClientIdAndFields() {
        let r = SDMaintenanceRecord(motorcycleId: 7, date: "2026-06-16", odo: 15000, recordType: "fuel", syncState: .pendingCreate)
        r.fuelAmount = 12.3
        r.pricePerUnit = 1.95
        r.cost = 23.99
        r.currency = "CHF"

        let payload = r.toPayload()
        // clientId must be sent so retried creates are idempotent on the server.
        #expect(payload["clientId"] as? String == r.clientId.uuidString)
        #expect(payload["type"] as? String == "fuel")
        #expect(payload["odo"] as? Int == 15000)
        #expect(payload["fuelAmount"] as? Double == 12.3)
        #expect(payload["currency"] as? String == "CHF")
    }

    @Test func applyDTOReconcilesServerIdAndClearsPending() throws {
        // A locally-created record (no serverId) that the server has now acked.
        let local = SDMaintenanceRecord(motorcycleId: 1, date: "2026-06-16", odo: 100, recordType: "fuel", syncState: .pendingCreate)
        let clientId = local.clientId.uuidString

        let json = """
        {"id":555,"date":"2026-06-16","odo":100,"motorcycleId":1,"type":"fuel",
         "fuelAmount":10.0,"clientId":"\(clientId)","updatedAt":"2026-06-16T10:00:00.000Z"}
        """
        let dto = try JSONDecoder().decode(MaintenanceRecord.self, from: Data(json.utf8))

        local.apply(dto)
        #expect(local.serverId == 555)
        #expect(local.serverUpdatedAt == "2026-06-16T10:00:00.000Z")
        #expect(local.syncState == .synced)
    }

    @Test func makeFromDTOAdoptsServerClientId() throws {
        let json = """
        {"id":9,"date":"2026-06-16","odo":1,"motorcycleId":2,"type":"oil",
         "clientId":"11111111-1111-1111-1111-111111111111","updatedAt":"2026-06-16T09:00:00.000Z"}
        """
        let dto = try JSONDecoder().decode(MaintenanceRecord.self, from: Data(json.utf8))
        let model = SDMaintenanceRecord.make(from: dto)
        #expect(model.clientId == UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        #expect(model.serverId == 9)
        #expect(model.syncState == .synced)
    }
}

struct SyncCursorTests {

    @Test func advanceKeepsTheLexicalMax() {
        let key = "test.cursor.\(UUID().uuidString)"
        SyncCursor.advance(key, with: ["2026-06-16T10:00:00.000Z", "2026-06-16T12:00:00.000Z"])
        #expect(SyncCursor.get(key) == "2026-06-16T12:00:00.000Z")
        // An older batch must not move the cursor backwards.
        SyncCursor.advance(key, with: ["2026-06-16T08:00:00.000Z"])
        #expect(SyncCursor.get(key) == "2026-06-16T12:00:00.000Z")
        UserDefaults.standard.removeObject(forKey: key)
    }

    @Test func advanceWithEmptyKeepsCursor() {
        let key = "test.cursor.\(UUID().uuidString)"
        SyncCursor.advance(key, with: ["2026-06-16T10:00:00.000Z"])
        SyncCursor.advance(key, with: [])
        #expect(SyncCursor.get(key) == "2026-06-16T10:00:00.000Z")
        UserDefaults.standard.removeObject(forKey: key)
    }
}
