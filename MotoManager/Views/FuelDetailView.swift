import MapKit
import SwiftUI

/// Fuel-entry detail. Leads with the consumption compared with the average,
/// places the fill-up in the trend, compares price, distance and cost per km,
/// shows the station with its history, then the plain details. ‹ › (and a
/// sideways swipe on iPhone, the arrow keys on iPad) step to the neighbouring
/// fill-ups. Backed by SwiftData, so local edits show immediately.
struct FuelDetailView: View {
    let record: SDMaintenanceRecord
    @ObservedObject var viewModel: MotorcycleDetailViewModel
    /// Shows another fill-up in place (‹ ›).
    var onSelect: ((SDMaintenanceRecord) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showingEdit = false
    @State private var didAutoDismiss = false
    @State private var width: CGFloat = 0
    /// Captured at init so the auto-pop guard never reads a deleted model.
    private let recordClientId: UUID

    init(record: SDMaintenanceRecord, viewModel: MotorcycleDetailViewModel,
         onSelect: ((SDMaintenanceRecord) -> Void)? = nil) {
        self.record = record
        self.viewModel = viewModel
        self.onSelect = onSelect
        self.recordClientId = record.clientId
    }

    private var currency: String { record.currency ?? viewModel.motorcycle.currencyCode ?? "CHF" }
    private var wide: Bool { width >= 640 }

    private func stationName(_ r: SDMaintenanceRecord) -> String? {
        r.locationName ?? viewModel.location(id: r.locationId)?.name
    }

    private var comparison: FuelFillComparison? {
        FuelFillComparison(fills: viewModel.fuelRecords.map {
            .init(id: $0.clientId, date: $0.date, odo: $0.odo, liters: $0.fuelAmount, cost: $0.cost,
                  price: $0.pricePerUnit, consumption: $0.fuelConsumption, station: stationName($0))
        }, id: record.clientId)
    }

    private func record(_ fill: FuelFillComparison.Fill?) -> SDMaintenanceRecord? {
        fill.flatMap { f in viewModel.fuelRecords.first { $0.clientId == f.id } }
    }

    var body: some View {
        let comparison = comparison
        List {
            Section {
                if wide {
                    HStack(alignment: .top, spacing: Theme.Spacing.listSection) {
                        heroCard(comparison).frame(maxWidth: .infinity)
                        tiles(comparison, vertical: true).frame(width: min(300, width * 0.36))
                    }
                } else {
                    heroCard(comparison)
                    tiles(comparison, vertical: false)
                }
            }
            .cardRow()

            if wide {
                Section {
                    HStack(alignment: .top, spacing: Theme.Spacing.listSection) {
                        stationCard(comparison).frame(maxWidth: .infinity)
                        detailsCard.frame(width: min(320, width * 0.4))
                    }
                }
                .cardRow()
            } else {
                Section { stationCard(comparison) }.cardRow()
                Section { detailsCard }.cardRow()
            }

            if let notes = record.recordDescription, !notes.isEmpty {
                Section("Notiz") {
                    Text(NoteBrandPalette.display(description: notes, markup: record.descriptionMarkup))
                        .font(.subheadline)
                }
            }
        }
        .workspaceListStyle()
        .scrollContentBackground(.hidden)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .frame(maxWidth: 1000)
        .frame(maxWidth: .infinity)
        .background(Theme.Colors.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            if sizeClass != .regular, let comparison, onSelect != nil { stepper(comparison) }
        }
        .gesture(swipe(comparison), including: sizeClass == .regular ? .none : .all)
        .toolbar(.visible, for: .navigationBar)
        .navigationTitle(Formatters.mediumDate(record.date))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(longDate).font(.subheadline.weight(.bold))
                    Text(Formatters.kilometers(record.odo) + (record.syncState.isPending ? " · nicht synchron" : ""))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                if sizeClass == .regular, let comparison, onSelect != nil {
                    Button("Ältere Tankung", systemImage: "chevron.left") { go(comparison.previous) }
                        .disabled(comparison.previous == nil)
                        .keyboardShortcut(.leftArrow, modifiers: [])
                    Button("Neuere Tankung", systemImage: "chevron.right") { go(comparison.next) }
                        .disabled(comparison.next == nil)
                        .keyboardShortcut(.rightArrow, modifiers: [])
                }
                Button("Bearbeiten") { showingEdit = true }
                    .accessibilityIdentifier("fuel.detail.edit")
            }
        }
        .sheet(isPresented: $showingEdit) {
            // Delete lives in the edit sheet, away from a stray tap.
            AddFuelView(viewModel: viewModel, existingRecord: record)
                .glassSheet()
        }
        // Pop back if the record disappears underneath us (remote delete via
        // sync, or delete from within the edit sheet).
        .onReceive(viewModel.$fuelRecords) { records in
            guard !didAutoDismiss,
                  !records.contains(where: { $0.clientId == recordClientId }) else { return }
            didAutoDismiss = true
            dismiss()
        }
    }

    private var longDate: String {
        guard let date = Formatters.parseDay(record.date) else { return Formatters.mediumDate(record.date) }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.wide).year().locale(Formatters.displayLocale))
    }

    private func go(_ fill: FuelFillComparison.Fill?) {
        guard let target = record(fill) else { return }
        withAnimation(.easeOut(duration: 0.2)) { onSelect?(target) }
    }

    private func swipe(_ comparison: FuelFillComparison?) -> some Gesture {
        DragGesture(minimumDistance: 40).onEnded { value in
            guard let comparison, abs(value.translation.width) > abs(value.translation.height) * 2 else { return }
            go(value.translation.width < 0 ? comparison.next : comparison.previous)
        }
    }

    // MARK: - Hero

    private func heroCard(_ comparison: FuelFillComparison?) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m - 4) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Verbrauch").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    if let consumption = record.fuelConsumption {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(String(format: "%.1f", consumption))
                                .font(.system(size: 40, weight: .heavy)).monospacedDigit()
                            Text("L/100 km").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        }
                        if let delta = comparison?.consumptionDelta {
                            Text(deltaText(delta))
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(abs(delta) < 0.25 ? Color.secondary : delta > 0 ? Color.orange : Color.green)
                        }
                    } else {
                        Text("—").font(.system(size: 40, weight: .heavy)).foregroundStyle(.secondary)
                        Text(!record.fullTank
                             ? "Teilfüllung – Verbrauch folgt mit der nächsten Volltankung"
                             : comparison?.isOldest == true
                                ? "Erste Tankung – Verbrauch ab der nächsten"
                                : "Kein Verbrauch – keine Volltankung davor")
                            .font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: Theme.Spacing.s)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.2f L", record.fuelAmount ?? 0))
                        .font(.title3.weight(.heavy)).monospacedDigit()
                    if let cost = record.cost {
                        Text(Formatters.currency(cost, code: currency)).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            if let comparison {
                let window = comparison.trendWindow
                let series = window.values.compactMap { v in Formatters.parseDay(v.date).map { (date: $0, value: v.value) } }
                if series.count >= 3 {
                    FuelConsumptionChart(series: series, average: comparison.averageConsumption ?? 0,
                                         highlight: window.highlight)
                        .frame(height: wide ? 150 : 110)
                }
            }
        }
        .insightCard()
    }

    private func deltaText(_ delta: Double) -> String {
        if abs(delta) < 0.05 { return "genau dein Schnitt" }
        return String(format: "%.1f %@ deinem Schnitt", abs(delta), delta > 0 ? "über" : "unter")
    }

    // MARK: - Tiles

    private func tiles(_ comparison: FuelFillComparison?, vertical: Bool) -> some View {
        let items = tileItems(comparison)
        let layout = vertical || dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: Theme.Spacing.s))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Theme.Spacing.s))
        return layout {
            ForEach(items, id: \.title) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(item.value).font(.headline.weight(.heavy)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                    Text(item.note).font(.caption2.weight(.semibold)).foregroundStyle(item.tint).lineLimit(2)
                }
                .frame(maxWidth: .infinity, minHeight: vertical ? 0 : 72, alignment: .topLeading)
                .padding(Theme.Spacing.m - 6)
                .background(Theme.Colors.backgroundElevated, in: RoundedRectangle(cornerRadius: Theme.Radius.field))
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func tileItems(_ c: FuelFillComparison?) -> [(title: String, value: String, note: String, tint: Color)] {
        var items: [(String, String, String, Color)] = []
        let price = record.pricePerUnit.map { Formatters.currency($0, code: currency) } ?? "—"
        if let delta = c?.priceDelta, abs(delta) >= 0.03 {
            items.append(("Preis / L", price, String(format: "%@%d %% zu Ø", delta > 0 ? "+" : "−", Int(abs(delta * 100).rounded())),
                          delta > 0 ? .orange : .green))
        } else {
            items.append(("Preis / L", price, c?.priceDelta == nil ? " " : "≈ Schnitt", .secondary))
        }
        if let km = c?.distance {
            let since = c?.previous.map { "seit " + Formatters.dayMonthName($0.date) } ?? " "
            items.append(("Strecke", "\(km) km", since, .secondary))
        } else {
            items.append(("Strecke", "—", "erste Tankung", .secondary))
        }
        if let perKm = c?.costPerKilometer {
            var note = " "
            var tint = Color.secondary
            if let avg = c?.averageCostPerKilometer {
                let rp = (perKm - avg) * 100
                note = abs(rp) < 0.5 ? "≈ Schnitt" : String(format: "%@%.0f Rp. zu Ø", rp > 0 ? "+" : "−", abs(rp))
                tint = abs(rp) < 0.5 ? .secondary : rp > 0 ? .orange : .green
            }
            items.append(("Kosten / km", Formatters.costPerKilometer(perKm, currency: currency), note, tint))
        } else {
            items.append(("Kosten / km", "—", " ", .secondary))
        }
        return items.map { (title: $0.0, value: $0.1, note: $0.2, tint: $0.3) }
    }

    // MARK: - Station

    private var stationCoordinates: (lat: Double, lon: Double)? {
        if let lat = record.latitude, let lon = record.longitude { return (lat, lon) }
        if let location = viewModel.location(id: record.locationId), let lat = location.latitude, let lon = location.longitude {
            return (lat, lon)
        }
        return nil
    }

    @ViewBuilder
    private func stationCard(_ comparison: FuelFillComparison?) -> some View {
        let name = stationName(record)
        if name != nil || stationCoordinates != nil {
            VStack(alignment: .leading, spacing: 0) {
                if let coords = stationCoordinates {
                    let point = CLLocationCoordinate2D(latitude: coords.lat, longitude: coords.lon)
                    Map(initialPosition: .region(MKCoordinateRegion(center: point, latitudinalMeters: 700, longitudinalMeters: 700))) {
                        Marker(name ?? "Tankstelle", systemImage: "fuelpump.fill", coordinate: point)
                            .tint(Theme.Colors.primary)
                    }
                    .mapControlVisibility(.hidden)
                    .allowsHitTesting(false)
                    .frame(height: wide ? 180 : 130)
                }
                HStack(alignment: .center, spacing: Theme.Spacing.s) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name ?? "Tankstelle").font(.subheadline.weight(.bold))
                        if let history = comparison?.stationHistory {
                            Text(historyText(history)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    if let coords = stationCoordinates {
                        Button("Route") { openInMaps(lat: coords.lat, lon: coords.lon, name: name) }
                            .font(.footnote.weight(.semibold))
                            .buttonStyle(.bordered)
                            .tint(Theme.Colors.primary)
                    }
                }
                .padding(Theme.Spacing.m - 2)
            }
            .background(Theme.Colors.backgroundElevated)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        }
    }

    private func historyText(_ h: (visits: Int, averagePrice: Double?, lastBefore: String?)) -> String {
        var parts = [h.visits == 1 ? "Erste Tankung hier" : "\(h.visits). Tankung hier"]
        if h.visits > 1, let avg = h.averagePrice { parts.append("Ø " + Formatters.currency(avg, code: currency) + "/L") }
        if let last = h.lastBefore { parts.append("zuletzt " + Formatters.dayMonthName(last)) }
        return parts.joined(separator: " · ")
    }

    private func openInMaps(lat: Double, lon: Double, name: String?) {
        let item = MKMapItem(location: CLLocation(latitude: lat, longitude: lon), address: nil)
        item.name = name ?? "Tankstelle"
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }

    // MARK: - Details

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            detailRow("Kilometerstand", Formatters.kilometers(record.odo))
            Divider()
            detailRow("Tankmenge", String(format: "%.2f L", record.fuelAmount ?? 0))
            if let type = record.fuelType, !type.isEmpty {
                Divider()
                detailRow("Kraftstoff", type)
            }
            Divider()
            HStack(spacing: 6) {
                flag("Voll getankt", on: record.fullTank)
                flag("Additiv", on: record.fuelAdditiveAdded)
                flag("Bleiersatz", on: record.leadSubstituteAdded)
            }
            .padding(.vertical, Theme.Spacing.m - 4)
        }
        .padding(.horizontal, Theme.Spacing.m - 2)
        .background(Theme.Colors.backgroundElevated, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.semibold).monospacedDigit()
        }
        .font(.subheadline)
        .padding(.vertical, Theme.Spacing.m - 4)
        .accessibilityElement(children: .combine)
    }

    private func flag(_ title: String, on: Bool) -> some View {
        Label(title, systemImage: on ? "checkmark" : "minus")
            .labelStyle(.titleAndIcon)
            .font(.caption.weight(.bold))
            .foregroundStyle(on ? Theme.Colors.primary : .secondary)
            .padding(.horizontal, 9)
            .frame(minHeight: 26)
            .background(Capsule().fill(on ? Theme.Colors.primary.opacity(0.14) : Color.primary.opacity(0.06)))
            .accessibilityLabel("\(title): \(on ? "ja" : "nein")")
    }

    // MARK: - Stepper

    private func stepper(_ c: FuelFillComparison) -> some View {
        HStack {
            Button { go(c.previous) } label: {
                Label(c.previous.map { Formatters.dayMonthName($0.date) } ?? "älteste", systemImage: "chevron.left")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, Theme.Spacing.m - 2)
                    .frame(minHeight: 44)
            }
            .disabled(c.previous == nil)
            .accessibilityLabel("Ältere Tankung")
            .accessibilityIdentifier("fuel.detail.previous")
            Spacer()
            Text("\(c.position.index) von \(c.position.count)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
            Spacer()
            Button { go(c.next) } label: {
                HStack(spacing: 6) {
                    Text(c.next.map { Formatters.dayMonthName($0.date) } ?? "neueste")
                    Image(systemName: "chevron.right")
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, Theme.Spacing.m - 2)
                .frame(minHeight: 44)
            }
            .disabled(c.next == nil)
            .accessibilityLabel("Neuere Tankung")
            .accessibilityIdentifier("fuel.detail.next")
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.Colors.primary)
        .padding(.horizontal, 4)
        .frame(minHeight: 52)
        .glassEffect(.regular, in: Capsule())
        .padding(.horizontal, Theme.Spacing.pageH)
        .padding(.bottom, Theme.Spacing.s)
    }
}
