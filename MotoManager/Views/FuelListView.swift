import SwiftUI
import Charts

struct FuelListView: View {
    @ObservedObject var viewModel: MotorcycleDetailViewModel
    // Read the workspace width before NavigationSplitView narrows its columns.
    @Environment(\.horizontalSizeClass) private var sizeClass
    @ObservedObject private var quickActions = QuickActionRouter.shared
    @State private var showingAddFuel = false
    @State private var showingStatistics = false
    @EnvironmentObject private var fleetVM: MotorcycleViewModel
    @State private var selectedFuelRecord: SDMaintenanceRecord?
    @State private var pendingFuelDelete: SDMaintenanceRecord?

    /// Backed by SwiftData (offline-first); already filtered to fuel + non-deleted.
    private var fuelRecords: [SDMaintenanceRecord] {
        viewModel.fuelRecords
    }

    /// Trailing-10-fills average, matching the trend sparkline's window so the
    /// headline number and the chart agree (a lifetime mean diverges as soon
    /// as one old outlier is in the data).
    private var averageConsumption: Double {
        FuelStats.trailingAverageConsumption(fuelRecords, count: 10)
    }

    private var lastEntry: SDMaintenanceRecord? { fuelRecords.first }

    /// Rolling 12 months instead of the calendar year — a calendar-year sum
    /// reads "0 L" for most of the year on a seasonal vehicle.
    private var trailingYearLiters: Double {
        FuelStats.litersInTrailingYear(fuelRecords)
    }

    private var currency: String {
        lastEntry?.currency ?? viewModel.motorcycle.currencyCode ?? "EUR"
    }

    /// Records bucketed by year for the section headers; input is already
    /// date-descending, so years come out newest-first.
    private var recordsByYear: [(year: String, records: [SDMaintenanceRecord])] {
        var sections: [(year: String, records: [SDMaintenanceRecord])] = []
        for record in fuelRecords {
            let year = String(record.date.prefix(4))
            if sections.last?.year == year {
                sections[sections.count - 1].records.append(record)
            } else {
                sections.append((year, [record]))
            }
        }
        return sections
    }

    /// km ridden since the previous fill, keyed by clientId. Non-positive
    /// deltas (odometer corrections) are dropped rather than shown as garbage.
    private var tripDistances: [UUID: Int] {
        var trips: [UUID: Int] = [:]
        for (index, record) in fuelRecords.enumerated() where index + 1 < fuelRecords.count {
            let delta = record.odo - fuelRecords[index + 1].odo
            if delta > 0 { trips[record.clientId] = delta }
        }
        return trips
    }

    /// Rolling average over the most recent fills — a fleet-lifetime mean would
    /// let years-old price levels tint every current fill green.
    private var averagePricePerLiter: Double {
        let prices = Array(fuelRecords.compactMap { $0.pricePerUnit }.filter { $0 > 0 }.prefix(10))
        guard !prices.isEmpty else { return 0 }
        return prices.reduce(0, +) / Double(prices.count)
    }

    var body: some View {
        MotorcycleWorkspace(motorcycle: viewModel.motorcycle, type: .fuel) {
            WorkspaceAction("Tankung erfassen", systemImage: "plus", prominent: true) { showingAddFuel = true }
                .keyboardShortcut("n", modifiers: .command)
        } content: {
            RecordBrowser(selection: $selectedFuelRecord, title: "Tankverlauf",
                          emptyTitle: "Tankung auswählen", systemImage: "fuelpump",
                          overview: AnyView(fuelOverview)) {
                fuelList
            } detail: { record in
                FuelDetailView(record: record, viewModel: viewModel)
            }
        }
        // Consume the "Tankung erfassen" App Shortcut. `initial: true` covers
        // a cold launch where the intent fired before this view existed.
        .onChange(of: quickActions.pending, initial: true) { _, action in
            guard action == .addFuel else { return }
            quickActions.pending = nil
            showingAddFuel = true
        }
        // Reopen an entry lost to a background process kill: a surviving
        // new-entry draft means the add-fuel sheet was open when the app died
        // (normal closes clear it — see FuelEntryDraft).
        .onAppear {
            if FuelEntryDraft.load(motorcycleId: viewModel.motorcycle.id, editingClientId: nil) != nil {
                showingAddFuel = true
            }
        }
        .alert("Tankung löschen?", isPresented: Binding(
            get: { pendingFuelDelete != nil },
            set: { if !$0 { pendingFuelDelete = nil } }
        ), presenting: pendingFuelDelete) { record in
            Button("Abbrechen", role: .cancel) {}
            Button("Löschen", role: .destructive) { _ = viewModel.deleteFuelRecord(record) }
        }
        .sheet(isPresented: $showingAddFuel) {
            AddFuelView(viewModel: viewModel)
                .glassSheet()
        }
        .onReceive(viewModel.$fuelRecords) { records in
            if let selectedFuelRecord, !records.contains(where: { $0.clientId == selectedFuelRecord.clientId }) {
                self.selectedFuelRecord = nil
            }
        }
    }

    private var fuelList: some View {
        List {
            WorkspaceListHeader()
            // Expanded layouts keep the overview in the detail column, even
            // when selecting a record temporarily replaces that overview.
            if sizeClass != .regular, !fuelRecords.isEmpty {
                Section {
                    FuelSummaryCard(insights: insights, average: averageConsumption,
                                    liters: trailingYearLiters, currency: currency)
                        .listRowInsets(EdgeInsets())
                    if !StatisticsPlacement.usesTab {
                        Button { showingStatistics = true } label: { StatisticsLinkRow(detailVM: viewModel) }
                            .buttonStyle(.plain)
                    }
                }
            }
            content
            WorkspaceListFooter()
        }
        .accessibilityIdentifier("fuel.history")
        .navigationDestination(isPresented: $showingStatistics) {
            StatisticsView(fleetVM: fleetVM, detailVM: viewModel, pushed: true)
        }
        .alignsWorkspaceColumn(.list)
        .tracksWorkspaceHeader()
        .workspaceListStyle()
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.Colors.background)
        .refreshable { await viewModel.reconnect() }
    }

    private var insights: FuelInsights { FuelInsights(records: fuelRecords) }

    private var overviewTiles: [StatTile] {
        let year = Calendar.current.component(.year, from: Date())
        let fills = insights.fillCount(inYear: year)
        return [
            StatTile(eyebrow: "Ø Verbrauch",
                     value: averageConsumption > 0 ? String(format: "%.1f", averageConsumption) : "—",
                     unit: "L/100 km · letzte 10", accent: Theme.Colors.primary),
            StatTile(eyebrow: "Kosten \(String(year))",
                     value: Formatters.currency(insights.cost(inYear: year), code: currency, fractionDigits: 0),
                     unit: fills == 1 ? "1 Tankung" : "\(fills) Tankungen"),
            StatTile(eyebrow: "Liter", value: String(format: "%.0f", trailingYearLiters),
                     unit: "letzte 12 Monate"),
            StatTile(eyebrow: "Strecke",
                     value: insights.trailingYearDistance().map { Formatters.kilometers($0) } ?? "—",
                     unit: "letzte 12 Monate")
        ]
    }

    /// Wide layouts: the dashboard beside the history, until a fill-up is
    /// selected.
    private var fuelOverview: some View {
        List {
            OverviewTitle("Verbrauch & Kosten")
            Section { StatTileGrid(overviewTiles).cardRow() }
            if fuelRecords.isEmpty {
                Section {
                    Label("Sobald Tankungen erfasst sind, zeigt diese Seite Verbrauch, Kosten und Preise.",
                          systemImage: "chart.xyaxis.line")
                        .foregroundStyle(.secondary)
                    Button("Tankung erfassen", systemImage: "plus") { showingAddFuel = true }
                }
            } else {
                Section { FuelConsumptionCard(insights: insights, average: averageConsumption).cardRow() }
                Section {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: Theme.Spacing.listSection) {
                            FuelMonthlyCostCard(insights: insights, currency: currency)
                            FuelPriceCard(insights: insights, currency: currency)
                        }
                        .frame(minWidth: 560)
                        VStack(spacing: Theme.Spacing.listSection) {
                            FuelMonthlyCostCard(insights: insights, currency: currency)
                            FuelPriceCard(insights: insights, currency: currency)
                        }
                    }
                    .cardRow()
                }
            }
        }
        .accessibilityIdentifier("fuel.overview")
        .alignsWorkspaceColumn(.overview)
        .workspaceListStyle()
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.background)
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - History

    @ViewBuilder
    private var content: some View {
        if viewModel.showsLoadingPlaceholders && fuelRecords.isEmpty {
            Section {
                ForEach(0..<4, id: \.self) { _ in
                    FuelRow.placeholder
                        .redacted(reason: .placeholder)
                }
            }
        } else if fuelRecords.isEmpty {
            Section {
                ListEmptyState {
                    Label("Keine Tankungen erfasst", systemImage: "fuelpump.slash")
                } description: {
                    Text("Erfasse deine erste Tankung – Verbrauch und Kosten werden automatisch berechnet.")
                } actions: {
                    Button { showingAddFuel = true } label: {
                        // The list row tints label icons, which hides the
                        // plus on the prominent capsule; force white.
                        Label("Tankung erfassen", systemImage: "plus")
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.Colors.primary)
                }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } else {
            ForEach(recordsByYear, id: \.year) { section in
                Section(section.year) {
                    ForEach(section.records, id: \.clientId) { record in
                        Button {
                            selectedFuelRecord = record
                        } label: {
                            FuelRow(
                                record: record,
                                averageConsumption: averageConsumption,
                                currency: currency,
                                trip: tripDistances[record.clientId],
                                averagePrice: averagePricePerLiter,
                                isOldest: record.clientId == fuelRecords.last?.clientId
                            )
                        }
                        .buttonStyle(.plain)
                        .selectedRecord(selectedFuelRecord?.clientId == record.clientId)
                        .accessibilityIdentifier("fuel.record.\(record.clientId)")
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                pendingFuelDelete = record
                            } label: {
                                Label("Löschen", systemImage: "trash")
                            }
                            .tint(.red)
                        }
                    }
                }
            }
        }
    }

}

// MARK: - Fuel row

struct FuelRow: View {
    let record: SDMaintenanceRecord
    let averageConsumption: Double
    var currency: String = "EUR"
    /// km since the previous fill; nil for the oldest record (or odo glitches).
    var trip: Int? = nil
    /// Fleet-average price per liter, for tinting expensive/cheap fills.
    var averagePrice: Double = 0
    /// The oldest record can't have a consumption — don't badge it as partial.
    var isOldest: Bool = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Skeleton stand-in for the loading state (rendered `.redacted`).
    static var placeholder: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: Theme.Radius.controlInner)
                .fill(.quaternary)
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text("12.3 L · 1.89/L")
                Text("15. Aug. · 234 km")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("5.2")
        }
        .padding(.vertical, 4)
    }

    /// "161 km · CHF 1.87/L": the trip (or the odometer for the oldest
    /// record) and the price per liter.
    private var detailLine: String {
        var parts = [trip.map { "\($0) km" } ?? Formatters.kilometers(record.odo)]
        if let price = record.pricePerUnit, price > 0 {
            parts.append("\(Formatters.currency(price, code: currency))/L")
        }
        return parts.joined(separator: " · ")
    }

    /// "günstig" / "teuer" against the recent average price, nil in between.
    private var priceTag: (label: String, tint: Color)? {
        guard averagePrice > 0, let price = record.pricePerUnit, price > 0 else { return nil }
        if price > averagePrice * 1.05 { return ("teuer", .orange) }
        if price < averagePrice * 0.95 { return ("günstig", Theme.Colors.primary) }
        return nil
    }

    var body: some View {
        // At accessibility sizes the trailing consumption block no longer fits
        // beside the fill details — stack the row vertically instead of letting
        // the texts wrap mid-number.
        let rowLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        rowLayout {
            dateTile

            VStack(alignment: .leading, spacing: 2) {
                // Amount and what it cost — the two numbers a fill-up is.
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(String(format: "%.1f L", record.fuelAmount ?? 0))
                        .scaledFont(14.5, weight: .bold)
                    if let cost = record.cost {
                        Text(" · \(Formatters.currency(cost, code: currency))")
                            .scaledFont(14.5, weight: .medium)
                            .foregroundStyle(.secondary)
                    }
                }
                .monospacedDigit()
                .lineLimit(1)
                // Year and month live in the tile; the trip beats the raw
                // odometer for at-a-glance value (odometer is on the detail).
                HStack(spacing: 6) {
                    Text(detailLine)
                    .scaledFont(12, weight: .medium)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    if let priceTag {
                        Text(priceTag.label)
                            .scaledFont(10.5, weight: .bold)
                            .foregroundStyle(priceTag.tint)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(priceTag.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
                .lineLimit(1)
            }

            if !dynamicTypeSize.isAccessibilitySize {
                Spacer(minLength: 0)
            }

            // Consumption leads on the trailing side — it's the number riders
            // compare between fills. A missing consumption on a non-oldest
            // record means a partial fill.
            VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 1) {
                if let consumption = record.fuelConsumption {
                    Text(String(format: "%.1f", consumption))
                        .scaledFont(17, weight: .heavy)
                        .monospacedDigit()
                        .foregroundStyle(consumptionStyle(consumption))
                    Text("L/100 km")
                        .scaledFont(10.5, weight: .medium)
                        .foregroundStyle(.secondary)
                } else if !isOldest {
                    Text("—")
                        .scaledFont(17, weight: .heavy)
                        .foregroundStyle(.secondary)
                    Text("Teilfüllung")
                        .scaledFont(10.5, weight: .medium)
                        .foregroundStyle(.secondary)
                }
            }
            .fixedSize()
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    /// Day and month, so the history scans like a calendar.
    private var dateTile: some View {
        let parts = Self.dayAndMonth(record.date)
        return VStack(spacing: 0) {
            Text(parts.day)
                .scaledFont(16, weight: .heavy)
                .monospacedDigit()
            Text(parts.month)
                .scaledFont(9.5, weight: .bold)
                .foregroundStyle(.secondary)
        }
        .frame(width: 42, height: 44)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.controlInner).fill(Color.primary.opacity(0.06)))
        .overlay(alignment: .topTrailing) {
            if record.syncState.isPending {
                PendingBadge().offset(x: 5, y: -5)
            }
        }
    }

    static func dayAndMonth(_ iso: String) -> (day: String, month: String) {
        guard let date = Formatters.parseDay(iso) else { return (String(iso.suffix(2)), "") }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let day = calendar.component(.day, from: date)
        let month = calendar.component(.month, from: date)
        let name = String(MonthName.short(month).replacingOccurrences(of: ".", with: "").prefix(3)).uppercased()
        return (String(format: "%02d", day), name)
    }

    private var accessibilityText: String {
        var parts: [String] = ["Tankung am \(Formatters.mediumDate(record.date))"]
        if let consumption = record.fuelConsumption {
            parts.append("Verbrauch \(String(format: "%.1f", consumption)) Liter pro 100 Kilometer")
        } else if !isOldest {
            parts.append("Teiltankung")
        }
        if let amount = record.fuelAmount {
            parts.append("\(String(format: "%.1f", amount)) Liter")
        }
        if let trip {
            parts.append("\(trip) Kilometer seit der letzten Tankung")
        } else {
            parts.append("Kilometerstand \(record.odo)")
        }
        if let station = record.locationName, !station.isEmpty {
            parts.append("bei \(station)")
        }
        if let cost = record.cost {
            parts.append(Formatters.currency(cost, code: currency))
        }
        return parts.joined(separator: ", ")
    }

    private func consumptionStyle(_ value: Double) -> AnyShapeStyle {
        if averageConsumption <= 0 {
            return AnyShapeStyle(.secondary)
        }
        if value > averageConsumption + 0.4 { return AnyShapeStyle(Color.orange) }
        if value < averageConsumption - 0.4 { return AnyShapeStyle(Color.green) }
        return AnyShapeStyle(.primary)
    }
}

struct FuelListView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            LiquidBackgroundView().ignoresSafeArea()
            FuelListView(viewModel: .mock)
        }
    }
}
