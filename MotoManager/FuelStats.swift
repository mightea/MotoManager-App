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
}
