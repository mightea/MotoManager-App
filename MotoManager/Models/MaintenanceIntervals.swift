import Foundation

/// Service-interval insights, ported from the webapp's
/// `app/utils/maintenance-intervals.ts`. Interval rules come from the user's
/// server settings (`UserSettings`, years per item plus optional km limits);
/// the webapp defaults apply until those have been fetched.
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
    /// The rule behind the status ("alle N Jahre") — shown on the row so an
    /// overdue/ok verdict is explainable, not just a colored icon.
    let intervalYears: Int
    /// Optional km rule ("alle N km"); nil when the user set no km limit.
    let intervalKms: Int?
    let lastOdo: Int?
    let kmsSinceLast: Int?
    /// km left under the km rule (negative when exceeded); nil without one.
    var kmsRemaining: Int? {
        guard let intervalKms, let kmsSinceLast else { return nil }
        return intervalKms - kmsSinceLast
    }

    var id: String { key }
}

enum MaintenanceIntervalsEngine {
    /// Display order of fluid items (matches `fluidTypeLabels` insertion order
    /// in the webapp).
    private static let fluidOrder = [
        "engineoil", "gearboxoil", "finaldriveoil", "finaldrivegearboxoil",
        "forkoil", "brakefluid", "coolant",
    ]

    static func insights(
        records: [SDMaintenanceRecord],
        currentOdo: Int,
        settings: UserSettings = .defaults,
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
            intervalKms: Int? = nil,
            baseDateOverride: Date? = nil
        ) {
            // A zero/negative rule means "don't track" (webapp: `!intervalYears`).
            guard intervalYears > 0 else { return }
            let kmRule = intervalKms.flatMap { $0 > 0 ? $0 : nil }
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
                status: Self.status(nextDate: nextDate, now: now, kmsSinceLast: kmsSinceLast, intervalKms: kmRule),
                lastDate: baseDate,
                nextDate: nextDate,
                intervalYears: intervalYears,
                intervalKms: kmRule,
                lastOdo: record?.odo,
                kmsSinceLast: kmsSinceLast
            ))
        }

        // 1. Tires — base date prefers the DOT production date.
        for (position, label) in [("front", "Vorderreifen"), ("rear", "Hinterreifen")] {
            let record = latest { $0.category == .tire && $0.tirePosition == position }
            append(
                key: "tire-\(position)", category: .reifen, label: label,
                record: record, intervalYears: settings.tireInterval,
                intervalKms: settings.tireKmInterval,
                baseDateOverride: record.flatMap { MaintenanceSummarizer.parseDotCode($0.dotCode) }
            )
        }

        // 2. Battery — lithium-ion lasts longer.
        let battery = latest { $0.category == .battery }
        let batteryYears = battery?.batteryType == "lithium-ion"
            ? settings.batteryLithiumInterval : settings.batteryDefaultInterval
        append(key: "battery", category: .batterie, label: "Batterie",
               record: battery, intervalYears: batteryYears)

        // 3. Fluids — normalized, so legacy "oil"/"coolant" records count.
        for fluidType in fluidOrder {
            guard let rule = settings.fluidInterval(fluidType) else { continue }
            let record = latest { $0.category == .fluid && $0.effectiveFluidType == fluidType }
            append(
                key: "fluid-\(fluidType)", category: .fluessigkeiten,
                label: SDMaintenanceRecord.fluidTypeLabels[fluidType] ?? fluidType,
                record: record, intervalYears: rule.years, intervalKms: rule.kms
            )
        }

        // 4. Chain.
        let chain = latest { $0.category == .chain }
        append(key: "chain", category: .wartung, label: "Kette reinigen/fetten",
               record: chain, intervalYears: settings.chainInterval,
               intervalKms: settings.chainKmInterval)

        return insights
    }

    /// Webapp `getStatus`: the time rule (overdue past the due date, due
    /// within 90 days) and the km rule (overdue at the limit, due within
    /// 1000 km or at 90 %) — the more urgent verdict wins.
    static func status(
        nextDate: Date, now: Date, kmsSinceLast: Int? = nil, intervalKms: Int? = nil
    ) -> MaintenanceInsight.Status {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let due = calendar.startOfDay(for: nextDate)
        let timeStatus: MaintenanceInsight.Status
        if due < today {
            timeStatus = .overdue
        } else {
            let days = calendar.dateComponents([.day], from: today, to: due).day ?? Int.max
            timeStatus = days <= 90 ? .due : .ok
        }

        var kmStatus = MaintenanceInsight.Status.ok
        if let intervalKms, intervalKms > 0, let kmsSinceLast {
            if kmsSinceLast >= intervalKms {
                kmStatus = .overdue
            } else if intervalKms - kmsSinceLast <= 1000 || Double(kmsSinceLast) / Double(intervalKms) >= 0.9 {
                kmStatus = .due
            }
        }
        return min(timeStatus, kmStatus)
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

    /// Forward-looking counterpart of `relativeAge`: "in 3 Monaten" /
    /// "seit 2 Jahren" depending on whether `date` is ahead of or behind `now`.
    /// Used to spell out how far an interval is overdue or how soon it's due.
    static func relativeSpan(from now: Date, to date: Date) -> String {
        let (earlier, later) = date >= now ? (now, date) : (date, now)
        let components = Calendar.current.dateComponents([.year, .month, .day], from: earlier, to: later)
        if let years = components.year, years >= 1 {
            return years == 1 ? "1 Jahr" : "\(years) Jahren"
        }
        if let months = components.month, months >= 1 {
            return months == 1 ? "1 Monat" : "\(months) Monaten"
        }
        let days = max(components.day ?? 0, 1)
        return days == 1 ? "1 Tag" : "\(days) Tagen"
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
