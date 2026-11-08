import Foundation
import Testing
@testable import MotoManager

struct BikeStatisticsTests {
    private func day(_ iso: String) -> Date {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withFullDate]
        return f.date(from: iso)!
    }

    private func rec(_ date: String, _ odo: Int, _ kind: CostKind?, _ cost: Double, bike: Int = 1,
                     price: Double? = nil, title: String = "") -> BikeStatistics.Record {
        .init(motorcycleId: bike, date: day(date), odo: odo, kind: kind, cost: cost,
              liters: kind == .fuel ? 10 : nil, consumption: kind == .fuel ? 5.5 : nil, price: price, title: title)
    }

    private var stats: BikeStatistics {
        BikeStatistics(records: [
            rec("2025-04-12", 83_100, .repair, 290, title: "Reifen"),
            rec("2025-04-12", 83_100, .repair, 95, title: "Batterie"),
            rec("2025-09-20", 83_700, .maintenance, 180),
            rec("2026-01-06", 83_838, .fuel, 20, price: 1.85),
            rec("2026-02-04", 84_081, .fuel, 29, price: 2.05),
            rec("2026-03-14", 84_250, .maintenance, 46),
            rec("2026-05-04", 84_620, .fuel, 24, price: 1.97),
            rec("2026-06-01", 84_700, nil, 0)
        ], now: day("2026-07-20"))
    }

    @Test func totalsByKindAndYear() {
        #expect(stats.total(.year(2026)) == 119)
        #expect(stats.total(.year(2026), kind: .fuel) == 73)
        #expect(stats.total(.year(2025), kind: .repair) == 385)
        #expect(stats.count(.year(2026), kind: .fuel) == 3)
    }

    @Test func distanceStartsAtTheReadingBeforeThePeriod() {
        #expect(stats.distance(.year(2026)) == 84_700 - 83_700)
        #expect(stats.costPerKilometer(.year(2026)).map { abs($0 - 0.119) < 0.0001 } == true)
    }

    @Test func changeAgainstPreviousYear() {
        let change = stats.change(.year(2026))!
        #expect(abs(change - (119.0 - 565.0) / 565.0) < 0.0001)
        #expect(stats.change(.all) == nil)
    }

    @Test func monthlyRunsThroughCurrentMonth() {
        let months = stats.monthly(year: 2026)
        #expect(months.count == 7)
        #expect(months[2].byKind[.maintenance] == 46)
        #expect(months[1].byKind[.fuel] == 29)
        #expect(months[6].byKind.isEmpty)
    }

    @Test func distanceSumsAcrossBikes() {
        let fleet = BikeStatistics(records: [
            rec("2026-01-01", 1_000, .fuel, 10, bike: 1), rec("2026-06-01", 1_500, .fuel, 10, bike: 1),
            rec("2026-02-01", 50_000, .fuel, 10, bike: 2), rec("2026-05-01", 50_200, .fuel, 10, bike: 2)
        ], now: day("2026-07-01"))
        #expect(fleet.distance(.year(2026)) == 700)
    }

    @Test func insightsMentionDearestFillAndExpensiveYear() {
        let lines = stats.insights(.year(2026))
        #expect(lines.contains { $0.hasPrefix("Teuerste Tankung") })
        #expect(lines.contains { $0.contains("2025 war teurer") && $0.contains("Reifen") })
    }

    @Test func kindsFromRecordTypes() {
        #expect(CostKind.of(recordType: "fuel") == .fuel)
        #expect(CostKind.of(recordType: "tire") == .repair)
        #expect(CostKind.of(recordType: "service") == .maintenance)
        #expect(CostKind.of(recordType: "location") == nil)
    }
}
