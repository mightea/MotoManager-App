import Foundation
import Testing
@testable import MotoManager

struct OdometerChangeTests {
    private let swap = OdometerChange(
        id: 1, motorcycleId: 39, date: "2018-11-22", readingBefore: 70_000, readingAfter: 7_000, kind: "replacement")
    private let rollover = OdometerChange(
        id: 2, motorcycleId: 39, date: "2010-05-01", readingBefore: 99_999, readingAfter: 0, kind: "rollover")

    @Test func offsetCountsChangesOnOrBeforeTheDay() {
        #expect(Odometer.offset([swap], on: "2018-11-21") == 0)
        #expect(Odometer.offset([swap], on: "2018-11-22") == 63_000)
        #expect(Odometer.offset([swap], on: "2026-11-15T08:30:00Z") == 63_000)
        #expect(Odometer.offset([], on: "2026-11-15") == 0)
    }

    @Test func offsetsOfSeveralChangesAddUp() {
        #expect(Odometer.offset([rollover, swap], on: "2012-01-01") == 99_999)
        #expect(Odometer.offset([rollover, swap], on: "2020-01-01") == 162_999)
    }

    @Test func readingIsTheTotalMinusTheOffset() {
        #expect(Odometer.reading(total: 71_402, changes: [swap], on: "2023-02-02") == 8_402)
        #expect(Odometer.reading(total: 68_420, changes: [swap], on: "2007-03-15") == 68_420)
        // Never negative, even for inconsistent data.
        #expect(Odometer.reading(total: 100, changes: [swap], on: "2023-02-02") == 0)
    }

    @Test func motorcycleDecodesWithAndWithoutChanges() throws {
        let base = """
        "id":39,"make":"BMW","model":"R 100/7","fabricationDate":"1978","userId":1,"vin":null,\
        "engineNumber":null,"vehicleNr":null,"numberPlate":null,"image":null,"isVeteran":true,\
        "firstRegistration":null,"initialOdo":52300,"manualOdo":null,"purchaseDate":null,\
        "purchasePrice":null,"normalizedPurchasePrice":null,"currencyCode":"CHF","fuelTankSize":null
        """
        let old = try JSONDecoder().decode(Motorcycle.self, from: Data("{\(base)}".utf8))
        #expect(old.odometerChangeList.isEmpty)
        #expect(old.odometerOffset(on: "2026-11-15") == 0)

        let changes = """
        ,"odometerOffset":63000,"odometerChanges":[{"id":1,"motorcycleId":39,"date":"2018-11-22",\
        "readingBefore":70000,"readingAfter":7000,"kind":"replacement","offset":63000,\
        "createdAt":"x","updatedAt":"x"}]
        """
        let new = try JSONDecoder().decode(Motorcycle.self, from: Data("{\(base)\(changes)}".utf8))
        #expect(new.odometerChangeList == [swap])
        #expect(new.odometerOffset(on: "2026-11-15") == 63_000)
        // Round-trips through the cache encoding.
        let cached = try JSONDecoder().decode(Motorcycle.self, from: JSONEncoder().encode(new))
        #expect(cached.odometerChangeList == [swap])
    }

    @Test func pushPayloadCarriesTheAppliedOffsetOnlyForLocalValues() {
        let record = SDMaintenanceRecord(motorcycleId: 39, date: "2026-11-15", odo: 71_560, recordType: "fuel")
        #expect(record.toPayload()["odoOffset"] == nil)
        record.odoOffset = 63_000
        #expect(record.toPayload()["odoOffset"] as? Int == 63_000)
        #expect(record.toPayload()["odo"] as? Int == 71_560)

        let issue = SDIssue(
            motorcycleId: 39, odo: 71_500, title: "Leck", priority: "medium", status: "new", date: "2026-11-15")
        #expect(issue.toPayload()["odoOffset"] == nil)
        issue.odoOffset = 0
        #expect(issue.toPayload()["odoOffset"] as? Int == 0)
    }
}
