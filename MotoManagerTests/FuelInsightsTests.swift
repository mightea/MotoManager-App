import Foundation
import Testing
@testable import MotoManager

@MainActor
struct FuelInsightsTests {
    private func day(_ iso: String) -> Date { Formatters.parseDay(iso)! }

    private func point(_ iso: String, odo: Int, consumption: Double? = nil, cost: Double? = nil,
                       price: Double? = nil) -> FuelPoint {
        FuelPoint(date: day(iso), consumption: consumption, liters: nil, cost: cost, price: price, odo: odo)
    }

    private let now = Formatters.parseDay("2026-07-20")!

    @Test func seriesIsOldestFirstAndDropsArtifacts() {
        let insights = FuelInsights(points: [
            point("2026-07-05", odo: 85_078, consumption: 5.8),
            point("2026-06-04", odo: 84_917, consumption: 18.0),   // missed fill-up
            point("2026-05-04", odo: 84_620, consumption: 5.9),
            point("2026-04-05", odo: 84_413, consumption: 5.6)
        ])
        let series = insights.consumptionSeries(.recent, now: now)
        #expect(series.map(\.value) == [5.6, 5.9, 5.8])
    }

    @Test func yearRangeKeepsTheLastTwelveMonths() {
        let insights = FuelInsights(points: [
            point("2026-07-05", odo: 2, consumption: 5.8),
            point("2025-08-01", odo: 1, consumption: 5.5),
            point("2025-06-01", odo: 0, consumption: 5.4)
        ])
        #expect(insights.consumptionSeries(.year, now: now).count == 2)
        #expect(insights.consumptionSeries(.all, now: now).count == 3)
    }

    @Test func monthlyCostsRunThroughTheCurrentMonth() {
        let insights = FuelInsights(points: [
            point("2026-07-05", odo: 3, cost: 17.60),
            point("2026-07-01", odo: 2, cost: 10),
            point("2026-02-04", odo: 1, cost: 29.23),
            point("2025-12-01", odo: 0, cost: 50)
        ])
        let months = insights.monthlyCosts(year: 2026, now: now)
        #expect(months.count == 7)
        #expect(months[1].cost == 29.23)
        #expect(abs(months[6].cost - 27.60) < 0.001)
        #expect(months[0].cost == 0)
        #expect(abs(insights.cost(inYear: 2026) - 56.83) < 0.001)
    }

    @Test func distanceStartsAtTheLastReadingBeforeTheYear() {
        let insights = FuelInsights(points: [
            point("2026-07-05", odo: 85_078, cost: 20),
            point("2026-02-04", odo: 84_250, cost: 20),
            point("2025-10-01", odo: 83_838, cost: 20)
        ])
        #expect(insights.distance(inYear: 2026) == 1_240)
        #expect(insights.costPerKilometer(inYear: 2026).map { abs($0 - 40.0 / 1_240) < 0.0001 } == true)
    }

    @Test func priceExtremesListTheirDates() {
        let insights = FuelInsights(points: [
            point("2026-07-05", odo: 4, price: 1.87),
            point("2026-06-04", odo: 3, price: 1.85),
            point("2026-04-05", odo: 2, price: 1.85),
            point("2026-02-04", odo: 1, price: 2.05)
        ])
        #expect(insights.latestPrice == 1.87)
        let extremes = insights.priceExtremes(now: now)
        #expect(extremes?.low.price == 1.85)
        #expect(extremes?.low.dates.count == 2)
        #expect(extremes?.high.price == 2.05)
    }
}
