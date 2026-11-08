import Charts
import SwiftUI

extension View {
    /// Elevated rounded card used by the overview panes.
    func insightCard() -> some View {
        padding(Theme.Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Colors.backgroundElevated, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
    }
}

/// Short German month name ("Jan.", "März") for chart labels.
enum MonthName {
    private static let symbols: [String] = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Formatters.displayLocale
        return calendar.shortStandaloneMonthSymbols
    }()

    static func short(_ month: Int) -> String {
        symbols.indices.contains(month - 1) ? symbols[month - 1] : "\(month)"
    }
}

// MARK: - Consumption chart

/// Consumption over time: one line, the average dashed, the y-range fitted
/// to the data so small differences stay visible. With `showsAxes` the
/// x-axis carries months and the y-axis values; without, it is a sparkline.
struct FuelConsumptionChart: View {
    let series: [(date: Date, value: Double)]
    let average: Double
    var showsAxes = true
    var showsArea = false

    var body: some View {
        Chart {
            if average > 0 {
                RuleMark(y: .value("Durchschnitt", average))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(series.enumerated()), id: \.offset) { _, point in
                if showsArea {
                    AreaMark(x: .value("Datum", point.date),
                             yStart: .value("Basis", yDomain.lowerBound),
                             yEnd: .value("L/100 km", point.value))
                        .foregroundStyle(Theme.Colors.primary.opacity(0.14))
                        .interpolationMethod(.monotone)
                }
                LineMark(x: .value("Datum", point.date), y: .value("L/100 km", point.value))
                    // Smooth, but monotone: never overshoots past a real value.
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: showsAxes ? 3 : 2.5, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(Theme.Colors.primary)
            }
            if let last = series.last {
                PointMark(x: .value("Datum", last.date), y: .value("L/100 km", last.value))
                    .symbolSize(showsAxes ? 60 : 40)
                    .foregroundStyle(Theme.Colors.primary)
            }
        }
        .chartYScale(domain: yDomain)
        // Room at both ends so the first and last month labels aren't clipped.
        .chartXScale(range: .plotDimension(startPadding: showsAxes ? 10 : 4, endPadding: showsAxes ? 18 : 6))
        .chartXAxis {
            if showsAxes {
                AxisMarks(values: .automatic(desiredCount: 6)) {
                    AxisGridLine().foregroundStyle(.quaternary)
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                }
            }
        }
        .chartYAxis {
            if showsAxes {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) {
                    AxisGridLine().foregroundStyle(.quaternary)
                    AxisValueLabel()
                }
            }
        }
        .chartLegend(.hidden)
        .environment(\.locale, Formatters.displayLocale)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var yDomain: ClosedRange<Double> {
        let values = series.map(\.value) + (average > 0 ? [average] : [])
        let lo = values.min() ?? 0
        let hi = values.max() ?? 1
        let pad = max((hi - lo) * 0.18, 0.1)
        return (lo - pad)...(hi + pad)
    }

    private var accessibilityText: String {
        guard let lo = series.map(\.value).min(), let hi = series.map(\.value).max() else {
            return "Verbrauch, keine Daten"
        }
        return String(format: "Verbrauch der letzten %d Tankungen zwischen %.1f und %.1f Liter pro 100 Kilometer, Durchschnitt %.1f",
                      series.count, lo, hi, average)
    }
}

// MARK: - Phone summary

/// One card instead of stat strip plus sparkline: the average, two
/// secondary figures and the trend. Tall phones get a real chart with
/// months on the axis; short ones a sparkline.
struct FuelSummaryCard: View {
    let insights: FuelInsights
    let average: Double
    let liters: Double
    let currency: String
    /// Short windows (one-row header) get a sparkline instead of a chart.
    @Environment(\.workspaceIsCondensed) private var compact
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var year: Int { Calendar.current.component(.year, from: Date()) }
    private var series: [(date: Date, value: Double)] { insights.consumptionSeries(.recent) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.s))
                : AnyLayout(HStackLayout(alignment: .top, spacing: Theme.Spacing.m))
            layout {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Ø Verbrauch · letzte 10")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(average > 0 ? String(format: "%.1f", average) : "—")
                            .font(.title2.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.Colors.primary)
                        Text("L/100 km")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                HStack(alignment: .top, spacing: Theme.Spacing.m) {
                    figure("Kosten \(String(year))",
                           Formatters.currency(insights.cost(inYear: year), code: currency, fractionDigits: 0))
                    figure("Liter", String(format: "%.0f", liters), hint: "letzte 12 Monate")
                }
            }
            if series.count >= 3 {
                FuelConsumptionChart(series: series, average: average, showsAxes: !compact)
                    .frame(height: compact ? 40 : 118)
            }
        }
        .padding(.horizontal, Theme.Spacing.m - 2)
        .padding(.vertical, Theme.Spacing.m - 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fuel.summary")
    }

    private func figure(_ title: String, _ value: String, hint: String? = nil) -> some View {
        VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 1) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(hint ?? "")
    }
}

// MARK: - Overview cards

/// Consumption card with a range switch, for the wide overview.
struct FuelConsumptionCard: View {
    let insights: FuelInsights
    let average: Double
    @State private var range: FuelChartRange = .recent

    var body: some View {
        let series = insights.consumptionSeries(range)
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center) { titles; Spacer(minLength: Theme.Spacing.m); picker.fixedSize() }
                VStack(alignment: .leading, spacing: Theme.Spacing.s) { titles; picker }
            }
            if series.count >= 2 {
                FuelConsumptionChart(series: series, average: average, showsArea: true)
                    .frame(height: 210)
            } else {
                Text("Für diesen Zeitraum gibt es zu wenige Tankungen mit Verbrauch.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .insightCard()
    }

    private var titles: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Verbrauch").font(.headline)
            Text(average > 0 ? String(format: "L/100 km · Ø %.1f gestrichelt", average) : "L/100 km")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var picker: some View {
        Picker("Zeitraum", selection: $range) {
            ForEach(FuelChartRange.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("fuel.chartRange")
    }
}

/// Spend per month of the current year, the latest month highlighted.
struct FuelMonthlyCostCard: View {
    let insights: FuelInsights
    let currency: String
    private var year: Int { Calendar.current.component(.year, from: Date()) }

    var body: some View {
        let months = insights.monthlyCosts(year: year)
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(alignment: .firstTextBaseline) {
                Text("Kosten pro Monat").font(.headline)
                Spacer()
                Text("\(String(year)) · \(Formatters.currency(insights.cost(inYear: year), code: currency, fractionDigits: 0))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Chart {
                ForEach(months, id: \.month) { entry in
                    BarMark(x: .value("Monat", MonthName.short(entry.month)),
                            y: .value("Kosten", entry.cost))
                        .foregroundStyle(entry.month == months.last?.month
                                         ? Theme.Colors.primary : Theme.Colors.primary.opacity(0.35))
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6))
                }
            }
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks { AxisValueLabel() }
            }
            .frame(height: 130)
            .accessibilityLabel("Kosten pro Monat \(String(year))")
        }
        .insightCard()
    }
}

/// Latest, cheapest and dearest price per liter, plus fuel cost per km.
struct FuelPriceCard: View {
    let insights: FuelInsights
    let currency: String
    var fuelType: String? = nil
    private var year: Int { Calendar.current.component(.year, from: Date()) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text("Preis pro Liter").font(.headline)
                Spacer()
                if let fuelType, !fuelType.isEmpty {
                    Text(fuelType).font(.footnote).foregroundStyle(.secondary)
                }
            }
            if let latest = insights.latestPrice {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                    Text(String(format: "%.2f", latest))
                        .font(.title.weight(.bold))
                        .monospacedDigit()
                    Text("\(currency) zuletzt")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            if let extremes = insights.priceExtremes() {
                line("Günstigste", "\(String(format: "%.2f", extremes.low.price)) · \(dates(extremes.low.dates))")
                line("Teuerste", "\(String(format: "%.2f", extremes.high.price)) · \(dates(extremes.high.dates))")
            }
            if let perKm = insights.costPerKilometer(inYear: year) {
                line("Kosten pro km (\(String(year)))", "≈ " + Formatters.costPerKilometer(perKm, currency: currency))
            }
            if insights.latestPrice == nil {
                Text("Noch keine Preise erfasst.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .insightCard()
    }

    private func dates(_ dates: [Date]) -> String {
        dates.map { $0.formatted(.dateTime.day().month(.abbreviated).locale(Formatters.displayLocale)) }
            .joined(separator: ", ")
    }

    private func line(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: Theme.Spacing.s)
            Text(value).fontWeight(.semibold).monospacedDigit().multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }
}

/// Overview heading that matches `WorkspaceListHeader`, so the list and
/// overview columns share one baseline and inset.
struct OverviewTitle: View {
    let title: String
    @Environment(\.workspaceColumns) private var columns

    init(_ title: String) { self.title = title }

    var body: some View {
        Section {
            Group {
                if let columns {
                    AlignedTitle(title: title, columns: columns)
                } else {
                    Text(title).padding(.top, Theme.Spacing.s)
                }
            }
                .font(.headline)
                .padding(.horizontal, Theme.Spacing.s)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("workspace.overviewTitle")
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listSectionMargins(.top, Theme.Spacing.s)
        .listSectionMargins(.bottom, Theme.Spacing.s)
    }
}

private struct AlignedTitle: View {
    let title: String
    @ObservedObject var columns: ColumnAlignment

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Sits above the variable padding, so the offset never moves it.
            ColumnTitleMarker(column: .overview, lead: Theme.Spacing.s)
            Text(title).padding(.top, Theme.Spacing.s + columns.overviewOffset)
        }
    }
}

extension View {
    /// A list row that hosts its own card: no row inset, no row chrome.
    func cardRow() -> some View {
        listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}
