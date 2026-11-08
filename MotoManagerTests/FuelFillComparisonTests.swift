import Foundation
import Testing
@testable import MotoManager

struct FuelFillComparisonTests {
    private let ids = (0..<5).map { _ in UUID() }

    /// Newest first, like the fuel list.
    private var fills: [FuelFillComparison.Fill] {
        [
            .init(id: ids[0], date: "2026-07-05", odo: 85_078, liters: 9.41, cost: 17.60, price: 1.87, consumption: 5.8, station: "Socar"),
            .init(id: ids[1], date: "2026-06-04", odo: 84_917, liters: 16.0, cost: 29.60, price: 1.85, consumption: 5.4, station: "Socar"),
            .init(id: ids[2], date: "2026-05-04", odo: 84_620, liters: 12.2, cost: 24.09, price: 1.97, consumption: 5.9, station: "Coop"),
            .init(id: ids[3], date: "2026-02-04", odo: 84_081, liters: 14.3, cost: 29.23, price: 2.05, consumption: nil, station: "Socar"),
            .init(id: ids[4], date: "2026-01-06", odo: 83_838, liters: 10.7, cost: 19.87, price: 1.85, consumption: nil, station: nil)
        ]
    }

    @Test func neighboursAndPosition() {
        let c = FuelFillComparison(fills: fills, id: ids[1])!
        #expect(c.previous?.id == ids[2])
        #expect(c.next?.id == ids[0])
        #expect(c.position == (2, 5))
        #expect(FuelFillComparison(fills: fills, id: ids[4])!.isOldest)
    }

    @Test func distanceAndCostPerKm() {
        let c = FuelFillComparison(fills: fills, id: ids[0])!
        #expect(c.distance == 161)
        #expect(c.costPerKilometer.map { abs($0 - 17.60 / 161) < 0.0001 } == true)
        #expect(FuelFillComparison(fills: fills, id: ids[4])!.distance == nil)
    }

    @Test func consumptionAndPriceAgainstTheOthers() {
        let c = FuelFillComparison(fills: fills, id: ids[0])!
        #expect(c.consumptionDelta.map { abs($0 - (5.8 - 5.65)) < 0.0001 } == true)
        let dear = FuelFillComparison(fills: fills, id: ids[3])!
        let avg = (1.87 + 1.85 + 1.97 + 1.85) / 4
        #expect(dear.priceDelta.map { abs($0 - (2.05 / avg - 1)) < 0.0001 } == true)
        #expect(dear.consumptionDelta == nil)
    }

    @Test func stationHistoryCountsUpToThisFill() {
        let c = FuelFillComparison(fills: fills, id: ids[1])!
        let history = c.stationHistory!
        #expect(history.visits == 2)
        #expect(history.lastBefore == "2026-02-04")
        #expect(FuelFillComparison(fills: fills, id: ids[4])!.stationHistory == nil)
    }

    @Test func trendWindowIsChronologicalWithHighlight() {
        let c = FuelFillComparison(fills: fills, id: ids[1])!
        let window = c.trendWindow
        #expect(window.values.map(\.value) == [5.9, 5.4, 5.8])
        #expect(window.highlight == 1)
    }
}
