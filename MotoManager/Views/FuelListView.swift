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

                listSection
                    .padding(.horizontal, sideMargin)
            }
            // Clears the docked add button so the last row is never hidden.
            .padding(.bottom, 96)
        }
        .ignoresSafeArea(edges: .top)
        .background(Color.clear)
        .bottomActionBar(detailVM: viewModel, addLabel: "Neue Tankung erfassen") {
            showingAddFuel = true
        }
        .refreshable {
            await viewModel.reconnect()
        }
        .sheet(isPresented: $showingAddFuel) {
            AddFuelView(viewModel: viewModel)
                .presentationDetents([.large])
                .presentationCornerRadius(Theme.Glass.sheetRadius)
                .presentationBackground(.regularMaterial)
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedFuelRecord) { record in
            FuelDetailView(record: record, viewModel: viewModel)
                .presentationDetents([.large])
                .presentationCornerRadius(Theme.Glass.sheetRadius)
                .presentationBackground(.regularMaterial)
                .presentationDragIndicator(.hidden)
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
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.55))
                Spacer()
                Text("\(fuelRecords.count) \(fuelRecords.count == 1 ? "Eintrag" : "Einträge")")
                    .font(.system(size: 11, weight: .semibold))
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
                    .font(.system(size: 28))
                    .foregroundColor(.white.opacity(0.45))
                Text("Noch keine Tankungen erfasst.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.65))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22))
        } else {
            // Lazy so a long fuel history renders rows on demand instead of all up front.
            LazyVStack(spacing: 0) {
                ForEach(Array(fuelRecords.enumerated()), id: \.element.clientId) { index, record in
                    Button {
                        selectedFuelRecord = record
                    } label: {
                        FuelRow(record: record, averageConsumption: averageConsumption, currency: currency)
                    }
                    .buttonStyle(.plain)

                    if index < fuelRecords.count - 1 {
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

// MARK: - Fuel row

struct FuelRow: View {
    let record: SDMaintenanceRecord
    let averageConsumption: Double
    var currency: String = "EUR"

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
                            .foregroundColor(.white.opacity(0.6))
                            .monospacedDigit()
                    }
                }
                HStack(spacing: 6) {
                    Text(Formatters.mediumDate(record.date))
                    Text("·")
                    Text("\(record.odo) km").monospacedDigit()
                }
                .scaledFont(11, weight: .medium)
                .foregroundColor(.white.opacity(0.55))
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 2) {
                if let cost = record.cost {
                    Text(Formatters.currency(cost, code: currency))
                        .scaledFont(14, weight: .bold)
                        .monospacedDigit()
                        .foregroundColor(.white)
                }
                if let consumption = record.fuelConsumption {
                    Text(String(format: "%.1f L/100km", consumption))
                        .scaledFont(10, weight: .semibold)
                        .monospacedDigit()
                        .foregroundColor(consumptionColor(consumption))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts: [String] = ["Tankung am \(Formatters.mediumDate(record.date))"]
        if let amount = record.fuelAmount {
            parts.append("\(String(format: "%.1f", amount)) Liter")
        }
        parts.append("Kilometerstand \(record.odo)")
        if let cost = record.cost {
            parts.append(Formatters.currency(cost, code: currency))
        }
        if let consumption = record.fuelConsumption {
            parts.append("Verbrauch \(String(format: "%.1f", consumption)) Liter pro 100 Kilometer")
        }
        return parts.joined(separator: ", ")
    }

    private var iconBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.Colors.primary.opacity(0.22))
            Image(systemName: "fuelpump.fill")
                .font(.system(size: 15, weight: .semibold))
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

struct FuelListView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            LiquidBackgroundView().ignoresSafeArea()
            FuelListView(viewModel: .mock)
        }
    }
}
