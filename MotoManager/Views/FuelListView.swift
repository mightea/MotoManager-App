import SwiftUI

struct FuelListView: View {
    @ObservedObject var viewModel: MotorcycleDetailViewModel
    @State private var showingAddFuel = false
    @State private var selectedFuelRecord: SDMaintenanceRecord?

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
                MotorcycleSummaryHeader(motorcycle: viewModel.motorcycle, type: .fuel, viewModel: viewModel)
                    .ignoresSafeArea(edges: .top)

                statStrip
                    .padding(.horizontal, Theme.Spacing.m)

                ctaCard
                    .padding(.horizontal, Theme.Spacing.m)

                listSection
                    .padding(.horizontal, Theme.Spacing.m)
            }
            .padding(.bottom, 110)
        }
        .ignoresSafeArea(edges: .top)
        .background(Color.clear)
        .refreshable {
            await viewModel.loadAllData()
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

    // MARK: - CTA card

    private var ctaCard: some View {
        Button {
            showingAddFuel = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 44, height: 44)
                    Image(systemName: "fuelpump.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Neue Tankung erfassen")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Schnell-Eingabe mit Tastatur")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                }

                Spacer(minLength: 0)

                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white.opacity(0.95))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(
                ZStack {
                    Theme.Colors.primary
                    LinearGradient(
                        colors: [Color.white.opacity(0.15), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            )
            .cornerRadius(22)
            .shadow(color: Theme.Colors.primary.opacity(0.5), radius: 14, x: 0, y: 8)
        }
        .buttonStyle(.plain)
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
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            )
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
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            )
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
