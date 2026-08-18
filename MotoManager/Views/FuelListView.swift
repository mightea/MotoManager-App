import SwiftUI
import Charts

struct FuelListView: View {
    @ObservedObject var viewModel: MotorcycleDetailViewModel
    @Environment(\.chromeActions) private var chrome
    @State private var showingAddFuel = false
    @State private var selectedFuelRecord: SDMaintenanceRecord?

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

    /// Consumption of the last 10 fills, oldest→newest, for the trend sparkline.
    private var trendValues: [Double] {
        Array(fuelRecords.compactMap { $0.fuelConsumption }.prefix(10)).reversed()
    }

    var body: some View {
        List {
            // The header photo extends below its content so the stat strip
            // overlaps it (glass pills on the image) instead of sitting on a
            // hard black cut-off.
            Section {
                ZStack(alignment: .bottom) {
                    MotorcycleSummaryHeader(
                        motorcycle: viewModel.motorcycle, type: .fuel, viewModel: viewModel,
                        bottomExtension: 96
                    )

                    StatStrip([
                        StatTile(
                            eyebrow: "Ø Verbrauch",
                            value: averageConsumption > 0 ? String(format: "%.1f", averageConsumption) : "—",
                            unit: "L/100 km · letzte 10",
                            accent: Theme.Colors.primary
                        ),
                        StatTile(
                            eyebrow: "Letzte Tankung",
                            value: lastEntry.map { Formatters.dayMonth($0.date) } ?? "—",
                            unit: lastEntry?.cost.map { Formatters.currency($0, code: currency, fractionDigits: 0) }
                        ),
                        StatTile(
                            eyebrow: "Liter",
                            value: String(format: "%.0f", trailingYearLiters),
                            unit: "letzte 12 Monate"
                        )
                    ])
                    .padding(.horizontal, Theme.Spacing.pageH)
                    .padding(.bottom, 12)
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listSectionMargins(.all, 0)

            if trendValues.count >= 3 {
                Section {
                    ConsumptionTrendRow(values: trendValues, average: averageConsumption)
                }
            }

            content
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .ignoresSafeArea(edges: .top)
        .refreshable {
            await viewModel.reconnect()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Neue Tankung erfassen", systemImage: "plus") {
                    showingAddFuel = true
                }
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) {
                Button("Einstellungen", systemImage: "gearshape") {
                    chrome.openSettings()
                }
            }
        }
        .sheet(isPresented: $showingAddFuel) {
            AddFuelView(viewModel: viewModel)
                .glassSheet()
        }
        .navigationDestination(item: $selectedFuelRecord) { record in
            FuelDetailView(record: record, viewModel: viewModel)
        }
    }

    // MARK: - History

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && fuelRecords.isEmpty {
            Section {
                ForEach(0..<4, id: \.self) { _ in
                    FuelRow.placeholder
                        .redacted(reason: .placeholder)
                }
            }
        } else if fuelRecords.isEmpty {
            Section {
                ContentUnavailableView {
                    Label("Keine Tankungen erfasst", systemImage: "fuelpump.slash")
                } description: {
                    Text("Erfasse deine erste Tankung – Verbrauch und Kosten werden automatisch berechnet.")
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
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                _ = viewModel.deleteFuelRecord(record)
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

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            iconBadge

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(String(format: "%.1f", record.fuelAmount ?? 0))
                            .scaledFont(14, weight: .semibold)
                            .monospacedDigit()
                        Text("L")
                            .scaledFont(11, weight: .medium)
                            .foregroundStyle(.secondary)
                    }
                    if let pricePerUnit = record.pricePerUnit, pricePerUnit > 0 {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text("\(Formatters.currency(pricePerUnit, code: currency))/L")
                            .scaledFont(12, weight: .medium)
                            .foregroundStyle(priceStyle(pricePerUnit))
                            .monospacedDigit()
                    }
                }
                // Year lives in the section header; the trip beats the raw
                // odometer for at-a-glance value (odometer is on the detail).
                HStack(spacing: 6) {
                    Text(Formatters.dayMonthName(record.date))
                    Text("·")
                    if let trip {
                        Text("\(trip) km").monospacedDigit()
                    } else {
                        Text("\(record.odo) km").monospacedDigit()
                    }
                    if let station = record.locationName, !station.isEmpty {
                        Text("·")
                        Text(station)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .scaledFont(11, weight: .medium)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 0)

            // Consumption leads on the trailing side — it's the number riders
            // compare between fills; the cost is secondary context. A missing
            // consumption on a non-oldest record means a partial fill.
            VStack(alignment: .trailing, spacing: 3) {
                if let consumption = record.fuelConsumption {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(String(format: "%.1f", consumption))
                            .scaledFont(15, weight: .bold)
                            .monospacedDigit()
                            .foregroundStyle(consumptionStyle(consumption))
                        Text("L/100km")
                            .scaledFont(9, weight: .semibold)
                            .foregroundStyle(.secondary)
                    }
                } else if !isOldest {
                    Text("TEILTANKUNG")
                        .scaledFont(8, weight: .heavy)
                        .tracking(0.5)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.primary.opacity(0.10)))
                        .foregroundStyle(.secondary)
                }
                if let cost = record.cost {
                    Text(Formatters.currency(cost, code: currency))
                        .scaledFont(11, weight: .medium)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
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

    /// Tint the per-liter price against the fleet average so expensive and
    /// cheap fills stand out (same idea as `consumptionStyle`).
    private func priceStyle(_ price: Double) -> AnyShapeStyle {
        guard averagePrice > 0 else { return AnyShapeStyle(.secondary) }
        if price > averagePrice * 1.05 { return AnyShapeStyle(Color.orange) }
        if price < averagePrice * 0.95 { return AnyShapeStyle(Color.green) }
        return AnyShapeStyle(.secondary)
    }

    private var iconBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Radius.controlInner)
                .fill(Theme.Colors.primary.opacity(0.22))
            Image(systemName: "fuelpump.fill")
                .scaledFont(15, weight: .semibold)
                .foregroundStyle(Theme.Colors.primary)
        }
        .frame(width: 36, height: 36)
        .overlay(alignment: .topTrailing) {
            if record.syncState.isPending {
                PendingBadge().offset(x: 5, y: -5)
            }
        }
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

// MARK: - Consumption trend

/// Compact list row with a Swift Charts sparkline of the last fills'
/// consumption. One series, one hue; the bike's average is a muted dashed
/// reference line. No axes or grid — the trend direction is the message.
struct ConsumptionTrendRow: View {
    /// Consumption values, oldest→newest.
    let values: [Double]
    let average: Double

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Verbrauchstrend".uppercased())
                    .scaledFont(9, weight: .heavy)
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                Text("Letzte \(values.count) Tankungen")
                    .scaledFont(11, weight: .medium)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: Theme.Spacing.m)

            chart
                .frame(width: 150, height: 34)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var chart: some View {
        Chart {
            if average > 0 {
                RuleMark(y: .value("Durchschnitt", average))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(.tertiary)
            }
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                LineMark(
                    x: .value("Tankung", index),
                    y: .value("Verbrauch", value)
                )
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .foregroundStyle(Theme.Colors.primary)
            }
            if let last = values.last {
                PointMark(
                    x: .value("Tankung", values.count - 1),
                    y: .value("Verbrauch", last)
                )
                .symbolSize(36)
                .foregroundStyle(Theme.Colors.primary)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: yDomain)
        .chartLegend(.hidden)
    }

    /// Pad the value range so the line never kisses the frame edges, and keep
    /// the reference line inside the plot.
    private var yDomain: ClosedRange<Double> {
        let lo = min(values.min() ?? 0, average > 0 ? average : .greatestFiniteMagnitude)
        let hi = max(values.max() ?? 1, average > 0 ? average : -.greatestFiniteMagnitude)
        let pad = max((hi - lo) * 0.15, 0.1)
        return (lo - pad)...(hi + pad)
    }

    private var accessibilityText: String {
        guard let last = values.last else { return "Verbrauchstrend" }
        return "Verbrauchstrend der letzten \(values.count) Tankungen, "
            + "zuletzt \(String(format: "%.1f", last)) Liter pro 100 Kilometer, "
            + "Durchschnitt \(String(format: "%.1f", average))"
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
