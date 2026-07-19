import Foundation

/// Service-interval insights, ported from the webapp's
/// `app/utils/maintenance-intervals.ts` with the hard-coded default intervals
/// (no user-settings sync on iOS yet; km intervals are settings-only, so they
/// stay nil here and statuses derive from time alone).
struct MaintenanceInsight: Identifiable {
    enum Category: String, CaseIterable {
        case reifen = "Reifen"
        case batterie = "Batterie"
        case fluessigkeiten = "Flüssigkeiten"
        case wartung = "Wartung"
    }

    enum Status: Int, Comparable {
        case overdue = 0, due = 1, ok = 2

        static func < (lhs: Status, rhs: Status) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    let key: String
    let category: Category
    let label: String
    let status: Status
    /// Base date the interval counts from (record date or tire DOT date).
    let lastDate: Date
    let nextDate: Date
    let lastOdo: Int?
    let kmsSinceLast: Int?

    var id: String { key }
}

enum MaintenanceIntervalsEngine {
    /// Years per item, mirroring `DEFAULT_MAINTENANCE_INTERVALS`.
    static let tireIntervalYears = 8
    static let batteryDefaultYears = 6
    static let batteryLithiumYears = 10
    static let fluidIntervalYears: [String: Int] = [
        "engineoil": 2,
        "gearboxoil": 2,
        "finaldriveoil": 2,
        "finaldrivegearboxoil": 2,
        "forkoil": 4,
        "brakefluid": 4,
        "coolant": 4,
    ]
    static let chainIntervalYears = 1

    /// Display order of fluid items (matches `fluidTypeLabels` insertion order
    /// in the webapp).
    private static let fluidOrder = [
        "engineoil", "gearboxoil", "finaldriveoil", "finaldrivegearboxoil",
        "forkoil", "brakefluid", "coolant",
    ]

    static func insights(
        records: [SDMaintenanceRecord],
        currentOdo: Int,
        now: Date = Date()
    ) -> [MaintenanceInsight] {
        var insights: [MaintenanceInsight] = []

        // Latest record matching a predicate — records arrive date-descending
        // from the view model, but sort defensively (ISO strings compare fine).
        func latest(_ predicate: (SDMaintenanceRecord) -> Bool) -> SDMaintenanceRecord? {
            records.filter(predicate).max { $0.date < $1.date }
        }

        func append(
            key: String,
            category: MaintenanceInsight.Category,
            label: String,
            record: SDMaintenanceRecord?,
            intervalYears: Int,
            baseDateOverride: Date? = nil
        ) {
            let baseDate = baseDateOverride ?? record.flatMap { Self.parseISODate($0.date) }
            guard let baseDate,
                  let nextDate = Calendar.current.date(byAdding: .year, value: intervalYears, to: baseDate)
            else { return }

            let kmsSinceLast: Int? = record.flatMap { r in
                currentOdo >= r.odo ? currentOdo - r.odo : nil
            }

            insights.append(MaintenanceInsight(
                key: key,
                category: category,
                label: label,
                status: Self.status(nextDate: nextDate, now: now),
                lastDate: baseDate,
                nextDate: nextDate,
                lastOdo: record?.odo,
                kmsSinceLast: kmsSinceLast
            ))
        }

        // 1. Tires — base date prefers the DOT production date.
        for (position, label) in [("front", "Vorderreifen"), ("rear", "Hinterreifen")] {
            let record = latest { $0.category == .tire && $0.tirePosition == position }
            append(
                key: "tire-\(position)", category: .reifen, label: label,
                record: record, intervalYears: tireIntervalYears,
                baseDateOverride: record.flatMap { MaintenanceSummarizer.parseDotCode($0.dotCode) }
            )
        }

        // 2. Battery — lithium-ion lasts longer.
        let battery = latest { $0.category == .battery }
        let batteryYears = battery?.batteryType == "lithium-ion" ? batteryLithiumYears : batteryDefaultYears
        append(key: "battery", category: .batterie, label: "Batterie",
               record: battery, intervalYears: batteryYears)

        // 3. Fluids — normalized, so legacy "oil"/"coolant" records count.
        for fluidType in fluidOrder {
            guard let years = fluidIntervalYears[fluidType] else { continue }
            let record = latest { $0.category == .fluid && $0.effectiveFluidType == fluidType }
            append(
                key: "fluid-\(fluidType)", category: .fluessigkeiten,
                label: SDMaintenanceRecord.fluidTypeLabels[fluidType] ?? fluidType,
                record: record, intervalYears: years
            )
        }

        // 4. Chain.
        let chain = latest { $0.category == .chain }
        append(key: "chain", category: .wartung, label: "Kette reinigen/fetten",
               record: chain, intervalYears: chainIntervalYears)

        return insights
    }

    /// Webapp `getStatus`, time part: overdue when the due date has passed,
    /// due when within 90 days. (km thresholds are inert without km intervals.)
    static func status(nextDate: Date, now: Date) -> MaintenanceInsight.Status {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let due = calendar.startOfDay(for: nextDate)
        if due < today { return .overdue }
        let days = calendar.dateComponents([.day], from: today, to: due).day ?? Int.max
        return days <= 90 ? .due : .ok
    }

    /// "vor 2 Jahren" / "vor 3 Monaten" / "vor 5 Tagen" — webapp
    /// `maintenance-insights.tsx` relative formatter.
    static func relativeAge(from date: Date, to now: Date = Date()) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date, to: now)
        if let years = components.year, years >= 1 {
            return years == 1 ? "vor 1 Jahr" : "vor \(years) Jahren"
        }
        if let months = components.month, months >= 1 {
            return months == 1 ? "vor 1 Monat" : "vor \(months) Monaten"
        }
        let days = max(components.day ?? 0, 0)
        return days == 1 ? "vor 1 Tag" : "vor \(days) Tagen"
    }

    /// Parses the leading `yyyy-MM-dd` of the model's ISO date strings.
    static func parseISODate(_ iso: String) -> Date? {
        let day = String(iso.prefix(10))
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: day)
    }
}
