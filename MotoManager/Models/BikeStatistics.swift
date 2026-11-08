import Foundation

/// What a period's costs went to.
enum CostKind: Int, CaseIterable, Identifiable {
    case fuel, maintenance, repair

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .fuel: "Treibstoff"
        case .maintenance: "Wartung"
        case .repair: "Reparatur & Teile"
        }
    }

    /// Kind of a maintenance record type ("fuel", "fluid", "repair", …).
    static func of(recordType: String) -> CostKind? {
        switch MaintenanceCategory.normalize(type: recordType, fluidType: nil).category {
        case .fuel: .fuel
        case .repair, .tire, .battery, .brakepad, .brakerotor, .chain: .repair
        case .service, .fluid, .inspection, .general: .maintenance
        case .location: nil
        }
    }
}

/// The period the statistics cover.
enum StatsPeriod: Hashable, Identifiable {
    case year(Int)
    case trailingYear
    case all

    var id: String {
        switch self {
        case .year(let y): "y\(y)"
        case .trailingYear: "12m"
        case .all: "all"
        }
    }

    var label: String {
        switch self {
        case .year(let y): String(y)
        case .trailingYear: "12 Monate"
        case .all: "Alle Jahre"
        }
    }
}

/// Costs, kilometres and observations for one motorcycle or the whole
/// garage, from its maintenance and fuel records. Pure, so it can be tested.
struct BikeStatistics {
    struct Record {
        let motorcycleId: Int
        let date: Date
        let odo: Int
        let kind: CostKind?
        let cost: Double
        let liters: Double?
        let consumption: Double?
        let price: Double?
        let title: String
    }

    let records: [Record]
    let now: Date
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC") ?? .current
        return c
    }()

    init(records: [Record], now: Date = Date()) {
        self.records = records.sorted { $0.date < $1.date }
        self.now = now
    }

    // MARK: Period

    func range(_ period: StatsPeriod) -> ClosedRange<Date>? {
        switch period {
        case .year(let y):
            guard let start = calendar.date(from: DateComponents(year: y, month: 1, day: 1)),
                  let end = calendar.date(from: DateComponents(year: y + 1, month: 1, day: 1)) else { return nil }
            return start...end.addingTimeInterval(-1)
        case .trailingYear:
            let start = calendar.date(byAdding: .month, value: -12, to: now) ?? now
            return start...now
        case .all:
            return nil
        }
    }

    func inPeriod(_ period: StatsPeriod) -> [Record] {
        guard let range = range(period) else { return records }
        return records.filter { range.contains($0.date) }
    }

    /// The same span one year earlier (for "−58 % zu 2025"); nil for "all".
    func previous(_ period: StatsPeriod) -> StatsPeriod? {
        switch period {
        case .year(let y): .year(y - 1)
        case .trailingYear, .all: nil
        }
    }

    // MARK: Figures

    func total(_ period: StatsPeriod) -> Double {
        inPeriod(period).reduce(0) { $0 + $1.cost }
    }

    func total(_ period: StatsPeriod, kind: CostKind) -> Double {
        inPeriod(period).filter { $0.kind == kind }.reduce(0) { $0 + $1.cost }
    }

    func count(_ period: StatsPeriod, kind: CostKind) -> Int {
        inPeriod(period).filter { $0.kind == kind && ($0.cost > 0 || kind == .fuel) }.count
    }

    func liters(_ period: StatsPeriod) -> Double {
        inPeriod(period).compactMap(\.liters).reduce(0, +)
    }

    /// Change against the same span a year earlier, as a fraction; nil when
    /// there is nothing to compare with.
    func change(_ period: StatsPeriod) -> Double? {
        guard let prev = previous(period) else { return nil }
        let before = total(prev)
        guard before > 0 else { return nil }
        return (total(period) - before) / before
    }

    /// km ridden in the period, per motorcycle summed: from the last reading
    /// before the period (or the first in it) to the last in it.
    func distance(_ period: StatsPeriod) -> Int {
        Dictionary(grouping: records, by: \.motorcycleId).values.reduce(0) { sum, bikeRecords in
            sum + Self.distance(of: bikeRecords, in: range(period))
        }
    }

    private static func distance(of records: [Record], in range: ClosedRange<Date>?) -> Int {
        let inside = range.map { r in records.filter { r.contains($0.date) } } ?? records
        guard let last = inside.map(\.odo).max() else { return 0 }
        let before = range.flatMap { r in records.filter { $0.date < r.lowerBound }.map(\.odo).max() }
        let start = before ?? inside.map(\.odo).min() ?? last
        return max(0, last - start)
    }

    func costPerKilometer(_ period: StatsPeriod) -> Double? {
        let km = distance(period)
        let cost = total(period)
        return km > 0 && cost > 0 ? cost / Double(km) : nil
    }

    func averageConsumption(_ period: StatsPeriod) -> Double? {
        let values = inPeriod(period).compactMap(\.consumption)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Cost per month of a calendar year, split by kind; January through the
    /// current month for the current year.
    func monthly(year: Int) -> [(month: Int, byKind: [CostKind: Double])] {
        let lastMonth = calendar.component(.year, from: now) == year ? calendar.component(.month, from: now) : 12
        var result = (1...max(1, lastMonth)).map { (month: $0, byKind: [CostKind: Double]()) }
        for record in records where calendar.component(.year, from: record.date) == year {
            guard let kind = record.kind else { continue }
            let month = calendar.component(.month, from: record.date)
            guard month <= result.count else { continue }
            result[month - 1].byKind[kind, default: 0] += record.cost
        }
        return result
    }

    /// km per calendar year, newest first, for the years with readings.
    func kilometresPerYear(limit: Int = 3) -> [(year: Int, km: Int)] {
        let years = Set(records.map { calendar.component(.year, from: $0.date) }).sorted(by: >)
        return years.prefix(limit).map { (year: $0, km: distance(.year($0))) }
    }

    // MARK: Observations

    /// Two or three plain-language observations.
    func insights(_ period: StatsPeriod, currency: String = "CHF") -> [String] {
        var lines: [String] = []
        let fuel = inPeriod(period).filter { $0.kind == .fuel && ($0.price ?? 0) > 0 }
        if let dearest = fuel.max(by: { ($0.price ?? 0) < ($1.price ?? 0) }), fuel.count >= 3 {
            let avg = fuel.compactMap(\.price).reduce(0, +) / Double(fuel.count)
            let above = Int((((dearest.price ?? 0) / avg) - 1) * 100)
            if above >= 3 {
                lines.append("Teuerste Tankung: \(Self.day(dearest.date)), \(currency) \(String(format: "%.2f", dearest.price ?? 0))/L – \(above) % über deinem Schnitt.")
            }
        }
        if let prev = previous(period), total(prev) > total(period) * 1.5, total(prev) > 0 {
            let big = inPeriod(prev).filter { $0.kind == .repair && $0.cost >= 50 }
                .sorted { $0.cost > $1.cost }.prefix(2)
            if !big.isEmpty {
                let items = big.map { "\($0.title) (\(currency) \(Int($0.cost)))" }.joined(separator: ", ")
                lines.append("\(prev.label) war teurer: \(items) fallen nur alle paar Jahre an.")
            }
        }
        if let biggest = inPeriod(period).filter({ $0.kind != .fuel }).max(by: { $0.cost < $1.cost }), biggest.cost > 0 {
            lines.append("Grösster Posten: \(biggest.title), \(currency) \(Int(biggest.cost.rounded())).")
        }
        return Array(lines.prefix(3))
    }

    private static func day(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "de_CH")))
    }
}
