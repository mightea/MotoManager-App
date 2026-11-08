import Charts
import Combine
import SwiftData
import SwiftUI

/// Where statistics live: a fifth tab where the tab bar has room (iPad, and
/// the foldable iPhone Duo with its tab rail), a page pushed from Tanken and
/// Wartung on regular iPhones. Decided by the screen's shape, so the folded
/// Duo (≈ 1.45 : 1) counts as roomy while every other iPhone (≥ 1.78 : 1)
/// keeps four tabs.
enum StatisticsPlacement {
    @MainActor static var usesTab: Bool {
        if UIDevice.current.userInterfaceIdiom == .pad { return true }
        let bounds = UIScreen.main.bounds
        let long = max(bounds.width, bounds.height), short = min(bounds.width, bounds.height)
        return short > 0 && long / short < 1.6
    }
}

/// Loads maintenance and fuel records for one motorcycle or the whole
/// garage from the local store.
@MainActor
final class StatisticsModel: ObservableObject {
    @Published private(set) var stats = BikeStatistics(records: [])
    @Published private(set) var perBike: [Int: BikeStatistics] = [:]
    @Published private(set) var isSyncingFleet = false
    private let context = PersistenceController.shared.mainContext

    func load(motorcycleIds: [Int]) {
        let ids = Set(motorcycleIds)
        let all = (try? context.fetch(FetchDescriptor<SDMaintenanceRecord>())) ?? []
        let records = all
            .filter { ids.contains($0.motorcycleId) && $0.syncState != .pendingDelete }
            .compactMap { r -> BikeStatistics.Record? in
                guard let date = Formatters.parseDay(r.date) else { return nil }
                let kind = CostKind.of(recordType: r.recordType)
                return .init(motorcycleId: r.motorcycleId, date: date, odo: r.odo, kind: kind,
                             cost: r.cost ?? 0, liters: kind == .fuel ? r.fuelAmount : nil,
                             consumption: r.fuelConsumption, price: r.pricePerUnit,
                             title: r.recordDescription?.split(separator: "\n").first.map(String.init)
                                ?? r.category.label)
            }
        stats = BikeStatistics(records: records)
        perBike = Dictionary(grouping: records, by: \.motorcycleId).mapValues { BikeStatistics(records: $0) }
    }

    /// The garage view needs every bike's records on the device; only the
    /// selected bike syncs by default.
    func syncFleet(_ ids: [Int]) async {
        isSyncingFleet = true
        await SyncEngine.shared.sync(motorcycleIds: ids)
        isSyncingFleet = false
        load(motorcycleIds: ids)
    }
}

/// Statistik: what a motorcycle (or the garage) cost, per km, per month and
/// for what, plus a few plain observations.
struct StatisticsView: View {
    @ObservedObject var fleetVM: MotorcycleViewModel
    @ObservedObject var detailVM: MotorcycleDetailViewModel
    /// Pushed on iPhone (own bar); the tab variant sits in the workspace.
    var pushed = false

    @StateObject private var model = StatisticsModel()
    @State private var garage = false
    @State private var period: StatsPeriod = .year(Calendar.current.component(.year, from: Date()))
    @State private var width: CGFloat = 0
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var currentYear: Int { Calendar.current.component(.year, from: Date()) }
    private var wide: Bool { width >= 700 }
    private var ids: [Int] { garage ? fleetVM.motorcycles.map(\.id) : [detailVM.motorcycle.id] }
    private var stats: BikeStatistics { model.stats }
    private var bikeName: String { "\(detailVM.motorcycle.make) \(detailVM.motorcycle.model)" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.listSection) {
                controls
                if stats.records.isEmpty {
                    ContentUnavailableView("Noch keine Daten", systemImage: "chart.bar",
                        description: Text("Erfasse Tankungen und Wartungen – hier siehst du dann, was das Motorrad kostet."))
                        .padding(.top, Theme.Spacing.xl)
                } else {
                    hero
                    if garage { fleetTable }
                    pair { monthlyCard } second: { breakdownCard }
                    if garage { consumptionCard }
                    pair { kilometresCard } second: { insightsCard }
                }
            }
            .padding(.horizontal, Theme.Spacing.pageH)
            .padding(.top, pushed ? Theme.Spacing.s : Theme.Spacing.m)
            .padding(.bottom, Theme.Spacing.xl)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .background(Theme.Colors.background)
        .tracksWorkspaceHeader()
        .refreshable { await model.syncFleet(ids) }
        .task(id: ids) {
            model.load(motorcycleIds: ids)
            if garage { await model.syncFleet(ids) }
        }
        .navigationTitle("Statistik")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(pushed ? .visible : .hidden, for: .navigationBar)
        .toolbar {
            if pushed {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: reportText) { Label("Teilen", systemImage: "square.and.arrow.up") }
                }
            }
        }
        .accessibilityIdentifier("statistics")
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Picker("Umfang", selection: $garage) {
                Text(detailVM.motorcycle.model).tag(false)
                Text("Ganze Garage").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: wide ? 320 : .infinity)
            .accessibilityIdentifier("statistics.scope")
            HStack(spacing: 6) {
                ForEach([StatsPeriod.year(currentYear), .trailingYear, .all]) { option in
                    Button { period = option } label: {
                        Text(option.label)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(period == option ? Color.white : Color.primary)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 34)
                            .background(Capsule().fill(period == option ? Theme.Colors.primary : Theme.Colors.backgroundElevated))
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(period == option ? .isSelected : [])
                }
                if model.isSyncingFleet { ProgressView().padding(.leading, Theme.Spacing.s) }
            }
        }
    }

    // MARK: - Hero

    private var periodTitle: String {
        switch period {
        case .year(let y): "Gesamtkosten \(y)"
        case .trailingYear: "Gesamtkosten, 12 Monate"
        case .all: "Gesamtkosten, alle Jahre"
        }
    }

    private func chf(_ value: Double, _ digits: Int = 0) -> String {
        Formatters.currency(value, code: "CHF", fractionDigits: digits)
    }

    private var hero: some View {
        let km = stats.distance(period)
        let tiles: [StatTile] = [
            StatTile(eyebrow: "Kosten / km",
                     value: stats.costPerKilometer(period).map { Formatters.costPerKilometer($0, currency: "CHF") } ?? "—",
                     unit: km > 0 ? Formatters.kilometers(km) : "keine km", accent: Theme.Colors.primary),
            StatTile(eyebrow: CostKind.fuel.label, value: chf(stats.total(period, kind: .fuel)),
                     unit: String(format: "%.0f Liter", stats.liters(period))),
            StatTile(eyebrow: "Unterhalt",
                     value: chf(stats.total(period, kind: .maintenance) + stats.total(period, kind: .repair)),
                     unit: "\(stats.count(period, kind: .maintenance) + stats.count(period, kind: .repair)) Einträge")
        ]
        return VStack(alignment: .leading, spacing: Theme.Spacing.m - 4) {
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(garage ? "\(periodTitle) · \(fleetVM.motorcycles.count) Motorräder" : periodTitle)
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(chf(stats.total(period))).font(.largeTitle.weight(.bold)).monospacedDigit()
                }
                Spacer()
                if let change = stats.change(period), let prev = stats.previous(period) {
                    Text("\(change < 0 ? "−" : "+")\(Int(abs(change * 100).rounded())) % zu \(prev.label)")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(change < 0 ? Color.green : Color.orange)
                }
            }
            StatTileGrid(tiles)
        }
        .insightCard()
        .accessibilityIdentifier("statistics.hero")
    }

    // MARK: - Cards

    @ViewBuilder
    private func pair<A: View, B: View>(@ViewBuilder _ first: () -> A, @ViewBuilder second: () -> B) -> some View {
        if wide {
            HStack(alignment: .top, spacing: Theme.Spacing.listSection) { first(); second() }
        } else {
            first(); second()
        }
    }

    private static let colors: [CostKind: Color] = [.fuel: Theme.Colors.primary, .maintenance: Color(hex: 0x2B115A), .repair: .orange]

    private var chartYear: Int {
        if case .year(let y) = period { return y }
        return currentYear
    }

    private var monthlyCard: some View {
        let months = stats.monthly(year: chartYear)
        return VStack(alignment: .leading, spacing: Theme.Spacing.m - 4) {
            HStack {
                Text("Kosten pro Monat").font(.headline)
                Spacer()
                Text(String(chartYear)).font(.footnote).foregroundStyle(.secondary)
            }
            Chart {
                ForEach(months, id: \.month) { entry in
                    ForEach(CostKind.allCases) { kind in
                        BarMark(x: .value("Monat", MonthName.short(entry.month)),
                                y: .value("CHF", entry.byKind[kind] ?? 0))
                            .foregroundStyle(by: .value("Art", kind.label))
                    }
                }
            }
            .chartForegroundStyleScale(domain: CostKind.allCases.map(\.label),
                                       range: CostKind.allCases.map { Self.colors[$0] ?? .gray })
            .chartLegend(position: .bottom, alignment: .leading)
            .frame(height: wide ? 220 : 170)
        }
        .insightCard()
    }

    private var breakdownCard: some View {
        let total = max(1, stats.total(period))
        return VStack(alignment: .leading, spacing: Theme.Spacing.m - 4) {
            Text("Wofür").font(.headline)
            ForEach(CostKind.allCases) { kind in
                let value = stats.total(period, kind: kind)
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(kind.label).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(chf(value)).font(.subheadline.weight(.bold)).monospacedDigit()
                    }
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.08))
                            Capsule().fill(Self.colors[kind] ?? .gray)
                                .frame(width: proxy.size.width * CGFloat(value / total))
                        }
                    }
                    .frame(height: 6)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .insightCard()
    }

    private var kilometresCard: some View {
        let years = stats.kilometresPerYear()
        let maxKm = max(1, years.map(\.km).max() ?? 1)
        return VStack(alignment: .leading, spacing: Theme.Spacing.m - 4) {
            Text("Gefahrene Kilometer").font(.headline)
            ForEach(years, id: \.year) { entry in
                HStack(spacing: Theme.Spacing.s) {
                    Text(String(entry.year)).font(.subheadline.weight(.bold)).frame(width: 46, alignment: .leading)
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.08))
                            RoundedRectangle(cornerRadius: 4).fill(Theme.Colors.primary)
                                .frame(width: proxy.size.width * CGFloat(entry.km) / CGFloat(maxKm))
                        }
                    }
                    .frame(height: 14)
                    Text(Formatters.kilometers(entry.km)).font(.subheadline).monospacedDigit()
                        .frame(width: 90, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .insightCard()
    }

    @ViewBuilder
    private var insightsCard: some View {
        let lines = stats.insights(period)
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("Aufgefallen").font(.headline)
                ForEach(lines, id: \.self) { line in
                    Label(line, systemImage: "lightbulb").font(.subheadline)
                }
            }
            .insightCard()
        }
    }

    // MARK: - Garage

    private var bikesById: [Int: Motorcycle] { Dictionary(fleetVM.motorcycles.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) }

    private var fleetRows: [(bike: Motorcycle, km: Int, cost: Double, perKm: Double?)] {
        model.perBike.compactMap { id, s in
            bikesById[id].map { (bike: $0, km: s.distance(period), cost: s.total(period), perKm: s.costPerKilometer(period)) }
        }
        .sorted { $0.cost > $1.cost }
    }

    private var fleetTable: some View {
        let rows = fleetRows
        let cheapest = rows.compactMap(\.perKm).min()
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Motorrad").frame(maxWidth: .infinity, alignment: .leading)
                Text("km").frame(width: 70, alignment: .trailing)
                Text("Kosten").frame(width: 80, alignment: .trailing)
                Text("pro km").frame(width: 70, alignment: .trailing)
            }
            .font(.caption.weight(.bold)).foregroundStyle(.secondary)
            .padding(.bottom, Theme.Spacing.s)
            ForEach(rows, id: \.bike.id) { row in
                Divider()
                Button {
                    fleetVM.selectMotorcycle(row.bike)
                    garage = false
                } label: {
                    HStack {
                        Text(row.bike.model).font(.subheadline.weight(.bold)).lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(row.km > 0 ? Formatters.kilometers(row.km).replacingOccurrences(of: " km", with: "") : "—")
                            .frame(width: 70, alignment: .trailing)
                        Text(chf(row.cost)).frame(width: 80, alignment: .trailing)
                        Text(row.perKm.map { String(format: "%.2f", $0) } ?? "—")
                            .fontWeight(.bold)
                            .foregroundStyle(row.perKm != nil && row.perKm == cheapest ? Color.green : Color.primary)
                            .frame(width: 70, alignment: .trailing)
                    }
                    .font(.subheadline).monospacedDigit()
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .insightCard()
        .accessibilityIdentifier("statistics.fleet")
    }

    @ViewBuilder
    private var consumptionCard: some View {
        let rows = model.perBike.compactMap { id, s in
            bikesById[id].flatMap { bike in s.averageConsumption(period).map { (bike: bike, value: $0) } }
        }.sorted { $0.value < $1.value }
        if rows.count > 1 {
            let maxValue = rows.map(\.value).max() ?? 1
            VStack(alignment: .leading, spacing: Theme.Spacing.m - 4) {
                Text("Ø Verbrauch im Vergleich").font(.headline)
                ForEach(rows, id: \.bike.id) { row in
                    HStack(spacing: Theme.Spacing.s) {
                        Text(row.bike.model).font(.subheadline.weight(.semibold)).lineLimit(1).frame(width: 110, alignment: .leading)
                        GeometryReader { proxy in
                            RoundedRectangle(cornerRadius: 4).fill(Theme.Colors.primary)
                                .frame(width: proxy.size.width * CGFloat(row.value / maxValue))
                        }
                        .frame(height: 12)
                        Text(String(format: "%.1f L", row.value)).font(.subheadline).monospacedDigit()
                            .frame(width: 60, alignment: .trailing)
                    }
                }
            }
            .insightCard()
        }
    }

    // MARK: - Report

    var reportText: String {
        Self.report(stats: stats, title: garage ? "Ganze Garage" : bikeName, period: period)
    }

    /// The period as plain text for sharing.
    static func report(stats: BikeStatistics, title: String, period: StatsPeriod) -> String {
        func chf(_ value: Double) -> String { Formatters.currency(value, code: "CHF", fractionDigits: 0) }
        var lines = ["MotoManager · Statistik", title, period.label, "",
                     "Gesamtkosten: \(chf(stats.total(period)))"]
        for kind in CostKind.allCases { lines.append("\(kind.label): \(chf(stats.total(period, kind: kind)))") }
        let km = stats.distance(period)
        if km > 0 { lines.append("Gefahren: \(Formatters.kilometers(km))") }
        if let perKm = stats.costPerKilometer(period) {
            lines.append("Kosten pro km: \(Formatters.costPerKilometer(perKm, currency: "CHF"))")
        }
        return lines.joined(separator: "\n")
    }
}

/// The Statistik tab on iPad and the Duo: same photo header as the others.
struct StatisticsTab: View {
    @ObservedObject var fleetVM: MotorcycleViewModel
    @ObservedObject var detailVM: MotorcycleDetailViewModel

    /// This bike's current year, for the header's share button.
    private var report: String {
        let model = StatisticsModel()
        model.load(motorcycleIds: [detailVM.motorcycle.id])
        let year = Calendar.current.component(.year, from: Date())
        return StatisticsView.report(stats: model.stats,
                                     title: "\(detailVM.motorcycle.make) \(detailVM.motorcycle.model)",
                                     period: .year(year))
    }

    var body: some View {
        MotorcycleWorkspace(motorcycle: detailVM.motorcycle, type: .statistics) {
            ShareLink(item: report) {
                WorkspaceActionLabel(title: "Bericht teilen", systemImage: "square.and.arrow.up", prominent: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Bericht teilen")
        } content: {
            StatisticsView(fleetVM: fleetVM, detailVM: detailVM)
        }
    }
}

/// "Statistik ›" with the headline numbers, for Tanken and Wartung on iPhone.
struct StatisticsLinkRow: View {
    @ObservedObject var detailVM: MotorcycleDetailViewModel

    private var summary: String {
        let year = Calendar.current.component(.year, from: Date())
        let records = (detailVM.fuelRecords + detailVM.serviceRecords).filter {
            $0.date.hasPrefix(String(year)) && CostKind.of(recordType: $0.recordType) != nil
        }
        let total = records.compactMap(\.cost).reduce(0, +)
        return "Gesamtkosten \(year) " + Formatters.currency(total, code: "CHF", fractionDigits: 0) + " · Garage-Vergleich"
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.m - 4) {
            Image(systemName: "chart.bar.xaxis")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Theme.Colors.primary, in: RoundedRectangle(cornerRadius: Theme.Radius.badge))
            VStack(alignment: .leading, spacing: 1) {
                Text("Statistik").font(.subheadline.weight(.bold)).foregroundStyle(Theme.Colors.primary)
                Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("statistics.link")
    }
}
