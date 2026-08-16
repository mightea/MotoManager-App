import Foundation

/// Minimal shape the fuel math needs — implemented by both the API DTO
/// (`MaintenanceRecord`, used in tests) and the SwiftData model
/// (`SDMaintenanceRecord`, used by the views).
protocol FuelStatRecord {
    var recordType: String { get }
    var fuelConsumption: Double? { get }
    var fuelAmount: Double? { get }
    var date: String { get }
}

extension MaintenanceRecord: FuelStatRecord {}
extension SDMaintenanceRecord: FuelStatRecord {}

/// Pure fuel-consumption aggregation, extracted from `FuelListView` so it can be
/// unit-tested without instantiating a view. All functions are side-effect free.
enum FuelStats {
    /// The fuel records out of a mixed maintenance list (case-insensitive `type`).
    static func fuelRecords<T: FuelStatRecord>(_ records: [T]) -> [T] {
        records.filter { $0.recordType.lowercased() == "fuel" }
    }

    /// Average of the per-fill consumption values (L/100 km). Returns 0 when no
    /// record carries a consumption value.
    static func averageConsumption<T: FuelStatRecord>(_ records: [T]) -> Double {
        let consumptions = records.compactMap { $0.fuelConsumption }
        guard !consumptions.isEmpty else { return 0 }
        return consumptions.reduce(0, +) / Double(consumptions.count)
    }

    /// Total litres filled during the given calendar year (matched on the
    /// `yyyy` prefix of the record's date string).
    static func litersInYear<T: FuelStatRecord>(_ records: [T], year: Int) -> Double {
        records
            .filter { Int($0.date.prefix(4)) == year }
            .compactMap { $0.fuelAmount }
            .reduce(0, +)
    }

    /// Average of the most recent `count` per-fill consumption values
    /// (records must be date-descending, which is how the view models hand
    /// them over). Matches the trend sparkline's window, so the headline
    /// average and the chart tell the same story.
    ///
    /// Robust against artifacts: a missed fill-up or odometer glitch produces
    /// a consumption several times the real one, and a single such value
    /// would drag a plain mean far away from every number visible in the
    /// list. Values further than 2× from the window's median are dropped
    /// before averaging.
    static func trailingAverageConsumption<T: FuelStatRecord>(_ records: [T], count: Int = 10) -> Double {
        let consumptions = Array(records.compactMap { $0.fuelConsumption }.prefix(count))
        guard !consumptions.isEmpty else { return 0 }
        let sorted = consumptions.sorted()
        let median = sorted[sorted.count / 2]
        let plausible = consumptions.filter { $0 <= median * 2 && $0 >= median * 0.4 }
        guard !plausible.isEmpty else { return median }
        return plausible.reduce(0, +) / Double(plausible.count)
    }

    /// Total litres filled in the 12 months before `now`. Unlike the
    /// calendar-year sum this stays meaningful early in the year, when a
    /// seasonal vehicle hasn't been fueled yet.
    static func litersInTrailingYear<T: FuelStatRecord>(_ records: [T], now: Date = Date()) -> Double {
        guard let cutoffDate = Calendar.current.date(byAdding: .month, value: -12, to: now) else { return 0 }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        let cutoff = formatter.string(from: cutoffDate)
        return records
            .filter { String($0.date.prefix(10)) >= cutoff }
            .compactMap { $0.fuelAmount }
            .reduce(0, +)
    }
}
