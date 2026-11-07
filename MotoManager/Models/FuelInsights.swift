import Foundation

/// One fill-up reduced to the numbers the fuel charts need.
struct FuelPoint: Equatable {
    let date: Date
    let consumption: Double?
    let liters: Double?
    let cost: Double?
    let price: Double?
    let odo: Int
}

/// Which fill-ups the consumption chart shows.
enum FuelChartRange: String, CaseIterable, Identifiable {
    case recent, year, all
    var id: Self { self }

    var label: String {
        switch self {
        case .recent: "10 Tankungen"
        case .year: "12 Monate"
        case .all: "Alle"
        }
    }
}

/// Pure aggregation behind the Tanken summary card and the iPad overview,
/// kept free of SwiftData and SwiftUI so it can be tested.
struct FuelInsights {
    /// Date-descending, like the view models hand records over.
    let points: [FuelPoint]
    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }()

    init(points: [FuelPoint]) {
        self.points = points.sorted { $0.date > $1.date }
    }

    init(records: [SDMaintenanceRecord]) {
        self.init(points: records.compactMap { record in
            Formatters.parseDay(record.date).map {
                FuelPoint(date: $0, consumption: record.fuelConsumption, liters: record.fuelAmount,
                          cost: record.cost, price: record.pricePerUnit, odo: record.odo)
            }
        })
    }

    // MARK: Consumption

    /// Consumption values oldest→newest for the chart. Values more than 2×
    /// away from the median (a missed fill-up, an odometer glitch) are left
    /// out, so one artifact can't flatten every real value into a line.
    func consumptionSeries(_ range: FuelChartRange, now: Date = Date()) -> [(date: Date, value: Double)] {
        var values = points.compactMap { point in point.consumption.map { (date: point.date, value: $0) } }
        switch range {
        case .recent:
            values = Array(values.prefix(10))
        case .year:
            let start = calendar.date(byAdding: .month, value: -12, to: now) ?? now
            values = values.filter { $0.date >= start }
        case .all:
            break
        }
        let sorted = values.map(\.value).sorted()
        guard !sorted.isEmpty else { return [] }
        let median = sorted[sorted.count / 2]
        return values
            .filter { $0.value <= median * 2 && $0.value >= median * 0.4 }
            .reversed()
    }

    // MARK: Costs

    func cost(inYear year: Int) -> Double {
        points.filter { calendar.component(.year, from: $0.date) == year }
            .compactMap(\.cost).reduce(0, +)
    }

    func fillCount(inYear year: Int) -> Int {
        points.filter { calendar.component(.year, from: $0.date) == year }.count
    }

    /// Spend per month of `year`, January through the current month (or
    /// December for past years); months without a fill-up read 0.
    func monthlyCosts(year: Int, now: Date = Date()) -> [(month: Int, cost: Double)] {
        let lastMonth = calendar.component(.year, from: now) == year ? calendar.component(.month, from: now) : 12
        var totals = [Int: Double]()
        for point in points where calendar.component(.year, from: point.date) == year {
            totals[calendar.component(.month, from: point.date), default: 0] += point.cost ?? 0
        }
        return (1...max(1, lastMonth)).map { (month: $0, cost: totals[$0] ?? 0) }
    }

    /// km ridden during `year`: from the last reading before it (or the
    /// first one in it) to the last reading in it.
    func distance(inYear year: Int) -> Int? {
        let inYear = points.filter { calendar.component(.year, from: $0.date) == year }
        guard let last = inYear.map(\.odo).max() else { return nil }
        let before = points.first { calendar.component(.year, from: $0.date) < year }?.odo
        guard let start = before ?? inYear.map(\.odo).min(), last > start else { return nil }
        return last - start
    }

    /// Fuel spend per km in `year`; nil without a usable distance.
    func costPerKilometer(inYear year: Int) -> Double? {
        guard let distance = distance(inYear: year), distance > 0 else { return nil }
        let cost = cost(inYear: year)
        return cost > 0 ? cost / Double(distance) : nil
    }

    /// km between the oldest and newest reading of the last 12 months.
    func trailingYearDistance(now: Date = Date()) -> Int? {
        let start = calendar.date(byAdding: .month, value: -12, to: now) ?? now
        let odos = points.filter { $0.date >= start }.map(\.odo)
        guard let lo = odos.min(), let hi = odos.max(), hi > lo else { return nil }
        return hi - lo
    }

    // MARK: Price

    var latestPrice: Double? { points.first { ($0.price ?? 0) > 0 }?.price }

    /// Cheapest and dearest price per liter of the last 12 months, each with
    /// up to three dates on which it was paid (newest first).
    func priceExtremes(now: Date = Date()) -> (low: (price: Double, dates: [Date]), high: (price: Double, dates: [Date]))? {
        let start = calendar.date(byAdding: .month, value: -12, to: now) ?? now
        let priced = points.filter { $0.date >= start && ($0.price ?? 0) > 0 }
        guard let low = priced.compactMap(\.price).min(), let high = priced.compactMap(\.price).max() else { return nil }
        func dates(_ price: Double) -> [Date] {
            Array(priced.filter { abs(($0.price ?? 0) - price) < 0.005 }.map(\.date).prefix(3))
        }
        return ((low, dates(low)), (high, dates(high)))
    }
}
