import SwiftUI

struct FuelListView: View {
    @ObservedObject var viewModel: MotorcycleDetailViewModel
    @State private var showingAddFuel = false
    @State private var selectedFuelRecord: SDMaintenanceRecord?

    /// Tightened horizontal page margin for the stat strip + list (was 12).
    private let sideMargin: CGFloat = 6

    /// Backed by SwiftData (offline-first); already filtered to fuel + non-deleted.
    private var fuelRecords: [SDMaintenanceRecord] {
        viewModel.fuelRecords
    }

    private var averageConsumption: Double {
        FuelStats.averageConsumption(fuelRecords)
    }

    private var lastEntry: SDMaintenanceRecord? { fuelRecords.first }

    private var yearLiters: Double {
        FuelStats.litersInYear(fuelRecords, year: Calendar.current.component(.year, from: Date()))
    }

    private var currency: String {
        lastEntry?.currency ?? viewModel.motorcycle.currencyCode ?? "EUR"
    }

    private var currentYearShort: String {
        String(Calendar.current.component(.year, from: Date()))
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
        ScrollView {
            VStack(spacing: Theme.Spacing.m) {
                // The header photo extends below its content so the stat strip
                // overlaps it (glass pills on the image) instead of sitting on a
                // hard black cut-off.
                ZStack(alignment: .bottom) {
                    MotorcycleSummaryHeader(
                        motorcycle: viewModel.motorcycle, type: .fuel, viewModel: viewModel,
                        bottomExtension: 96
                    )
                    .ignoresSafeArea(edges: .top)

                    statStrip
                        .padding(.horizontal, sideMargin)
                        .padding(.bottom, 12)
                }

                if trendValues.count >= 3 {
                    ConsumptionTrendCard(values: trendValues, average: averageConsumption)
                        .padding(.horizontal, sideMargin)
                }

                listSection
                    .padding(.horizontal, sideMargin)
            }
            // Clears the docked add button so the last row is never hidden.
            .padding(.bottom, 96)
        }
        .ignoresSafeArea(edges: .top)
        .background(Color.clear)
        // `addAction:` must stay a labeled argument: a trailing closure
        // backward-matches to `secondaryAction` and the button vanishes.
        .bottomActionBar(
            detailVM: viewModel,
            addLabel: "Neue Tankung erfassen",
            addAction: { showingAddFuel = true }
        )
        .refreshable {
            await viewModel.reconnect()
        }
        .sheet(isPresented: $showingAddFuel) {
            AddFuelView(viewModel: viewModel)
                .glassSheet()
        }
        .navigationDestination(item: $selectedFuelRecord) { record in
            FuelDetailView(record: record, viewModel: viewModel)
        }
    }

    // MARK: - Stat strip

    private var statStrip: some View {
        StatStrip([
            StatTile(
                eyebrow: "Ø Verbrauch",
                value: averageConsumption > 0 ? String(format: "%.1f", averageConsumption) : "—",
                unit: "L / 100 km",
                accent: Theme.Colors.primary
            ),
            StatTile(
                eyebrow: "Letzte Tankung",
                value: lastEntry.map { Formatters.dayMonth($0.date) } ?? "—",
                unit: lastEntry?.cost.map { Formatters.currency($0, code: currency, fractionDigits: 0) }
            ),
            StatTile(
                eyebrow: "Liter \(currentYearShort)",
                value: String(format: "%.0f", yearLiters),
                unit: "L"
            )
        ])
    }

    // MARK: - List section

    private var listSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack {
                Text("Letzte Tankungen".uppercased())
                    .scaledFont(11, weight: .heavy)
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.55))
                Spacer()
                Text("\(fuelRecords.count) \(fuelRecords.count == 1 ? "Eintrag" : "Einträge")")
                    .scaledFont(11, weight: .semibold)
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.horizontal, 6)

            content
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && fuelRecords.isEmpty {
            VStack(spacing: 0) {
                ForEach(0..<4, id: \.self) { _ in
                    GlassShimmerRow()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 22))
        } else if fuelRecords.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "fuelpump.slash")
                    .scaledFont(28)
                    .foregroundColor(.white.opacity(0.45))
                Text("Noch keine Tankungen erfasst.")
                    .scaledFont(13, weight: .medium)
                    .foregroundColor(.white.opacity(0.65))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22))
        } else {
            // Lazy so a long fuel history renders rows on demand instead of all
            // up front; one glass card per year section.
            LazyVStack(spacing: Theme.Spacing.s) {
                ForEach(recordsByYear, id: \.year) { section in
                    YearHeader(section.year)
                    VStack(spacing: 0) {
                        ForEach(Array(section.records.enumerated()), id: \.element.clientId) { index, record in
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

                            if index < section.records.count - 1 {
                                Divider()
                                    .background(Color.white.opacity(0.08))
                                    .padding(.leading, 60)
                            }
                        }
                    }
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22))
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
                            .foregroundColor(.white.opacity(0.55))
                    }
                    if let pricePerUnit = record.pricePerUnit, pricePerUnit > 0 {
                        Text("·")
                            .foregroundColor(.white.opacity(0.4))
                        Text("\(Formatters.currency(pricePerUnit, code: currency))/L")
                            .scaledFont(12, weight: .medium)
                            .foregroundColor(priceColor(pricePerUnit))
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
                .foregroundColor(.white.opacity(0.55))
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
                            .foregroundColor(consumptionColor(consumption))
                        Text("L/100km")
                            .scaledFont(9, weight: .semibold)
                            .foregroundColor(.white.opacity(0.5))
                    }
                } else if !isOldest {
                    Text("TEILTANKUNG")
                        .scaledFont(8, weight: .heavy)
                        .tracking(0.5)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.10)))
                        .foregroundColor(.white.opacity(0.6))
                }
                if let cost = record.cost {
                    Text(Formatters.currency(cost, code: currency))
                        .scaledFont(11, weight: .medium)
                        .monospacedDigit()
                        .foregroundColor(.white.opacity(0.6))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
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
    /// cheap fills stand out (same idea as `consumptionColor`).
    private func priceColor(_ price: Double) -> Color {
        guard averagePrice > 0 else { return .white.opacity(0.6) }
        if price > averagePrice * 1.05 { return .orange.opacity(0.9) }
        if price < averagePrice * 0.95 { return .green.opacity(0.9) }
        return .white.opacity(0.6)
    }

    private var iconBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.Colors.primary.opacity(0.22))
            Image(systemName: "fuelpump.fill")
                .scaledFont(15, weight: .semibold)
                .foregroundColor(Theme.Colors.primary)
        }
        .frame(width: 36, height: 36)
        .overlay(alignment: .topTrailing) {
            if record.syncState.isPending {
                PendingBadge().offset(x: 5, y: -5)
            }
        }
    }

    private func consumptionColor(_ value: Double) -> Color {
        if averageConsumption <= 0 {
            return .white.opacity(0.6)
        }
        if value > averageConsumption + 0.4 { return .orange }
        if value < averageConsumption - 0.4 { return .green }
        return .white.opacity(0.7)
    }
}

// MARK: - Consumption trend

/// Compact glass card with a sparkline of the last fills' consumption.
/// One series, one hue; the bike's average is a muted dashed reference line.
struct ConsumptionTrendCard: View {
    /// Consumption values, oldest→newest.
    let values: [Double]
    let average: Double

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Verbrauchstrend".uppercased())
                    .scaledFont(9, weight: .heavy)
                    .tracking(1.2)
                    .foregroundColor(.white.opacity(0.55))
                Text("Letzte \(values.count) Tankungen")
                    .scaledFont(11, weight: .medium)
                    .foregroundColor(.white.opacity(0.6))
            }

            Spacer(minLength: Theme.Spacing.m)

            Sparkline(values: values, reference: average > 0 ? average : nil)
                .frame(width: 150, height: 34)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        guard let last = values.last else { return "Verbrauchstrend" }
        return "Verbrauchstrend der letzten \(values.count) Tankungen, "
            + "zuletzt \(String(format: "%.1f", last)) Liter pro 100 Kilometer, "
            + "Durchschnitt \(String(format: "%.1f", average))"
    }
}

/// Minimal line sparkline: 2pt rounded line, endpoint dot, optional dashed
/// reference line. No axes or grid — the trend direction is the message.
private struct Sparkline: View {
    let values: [Double]
    var reference: Double? = nil

    var body: some View {
        GeometryReader { geo in
            let lo = min(values.min() ?? 0, reference ?? .greatestFiniteMagnitude)
            let hi = max(values.max() ?? 1, reference ?? -.greatestFiniteMagnitude)
            let span = max(hi - lo, 0.1)
            // 4pt vertical inset keeps the endpoint dot inside the frame.
            let plot = geo.size.height - 8
            let point: (Int, Double) -> CGPoint = { index, value in
                CGPoint(
                    x: geo.size.width * CGFloat(index) / CGFloat(max(values.count - 1, 1)),
                    y: 4 + plot * (1 - CGFloat((value - lo) / span))
                )
            }

            ZStack {
                if let reference {
                    let y = 4 + plot * (1 - CGFloat((reference - lo) / span))
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: geo.size.width, y: y))
                    }
                    .stroke(Color.white.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }

                Path { p in
                    for (index, value) in values.enumerated() {
                        let pt = point(index, value)
                        if index == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                    }
                }
                .stroke(
                    Theme.Colors.primary,
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                )

                if let lastValue = values.last {
                    Circle()
                        .fill(Theme.Colors.primary)
                        .frame(width: 6, height: 6)
                        .position(point(values.count - 1, lastValue))
                }
            }
        }
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
