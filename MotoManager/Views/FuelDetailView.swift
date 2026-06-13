import SwiftUI
import MapKit

/// Fuel-entry detail page matching the prototype's
/// `motomanager-app/project/assets/details/FuelDetail.jsx`.
///
/// Uses the shared `DetailPage` chrome. Hero shows the liters, a TANKUNG
/// eyebrow + bike/date subline, and three stat tiles (total cost, price/L,
/// L/100 km). Body sections cover Details, Kosten, Verbrauch and (when
/// coordinates are present) Tankstelle with an inline map. The sticky
/// bottom action bar offers Bearbeiten + Löschen.
struct FuelDetailView: View {
    let recordId: Int
    @ObservedObject var viewModel: MotorcycleDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingEdit = false
    @State private var confirmingDelete = false

    init(record: MaintenanceRecord, viewModel: MotorcycleDetailViewModel) {
        self.recordId = record.id
        self.viewModel = viewModel
    }

    /// Look up the latest record so the detail view refreshes after an edit
    /// without prop drilling. Falls back to the unavailable state if removed.
    private var record: MaintenanceRecord? {
        viewModel.maintenanceRecords.first { $0.id == recordId }
    }

    var body: some View {
        Group {
            if let record {
                DetailPage(
                    backLabel: "Tanken",
                    accent: Theme.Colors.primary,
                    eyebrow: "TANKUNG",
                    title: titleString(for: record),
                    subtitle: subtitle(for: record),
                    heroContent: { heroStats(for: record) },
                    body: { sections(for: record) },
                    actions: { actionBar },
                    onClose: { dismiss() }
                )
            } else {
                unavailable
            }
        }
        .sheet(isPresented: $showingEdit) {
            if let record {
                AddFuelView(viewModel: viewModel, existingRecord: record)
                    .presentationDetents([.large])
                    .presentationCornerRadius(Theme.Glass.sheetRadius)
                    .presentationBackground(.regularMaterial)
                    .presentationDragIndicator(.visible)
            }
        }
        .alert("Tankung löschen?", isPresented: $confirmingDelete) {
            Button("Abbrechen", role: .cancel) { }
            Button("Löschen", role: .destructive) {
                // Backend delete is not wired yet — keep the affordance but
                // bail out without mutating state. Replace with a real
                // viewModel.deleteFuelRecord call once the API lands.
            }
        } message: {
            Text("Diese Tankung kann nicht wiederhergestellt werden.")
        }
    }

    // MARK: - Hero

    private func titleString(for record: MaintenanceRecord) -> String {
        let liters = record.fuelAmount ?? 0
        return String(format: "%.1f L", liters)
    }

    private func subtitle(for record: MaintenanceRecord) -> String {
        let date = formatDateFull(record.date)
        return "\(date) · \(viewModel.motorcycle.make) \(viewModel.motorcycle.model)"
    }

    @ViewBuilder
    private func heroStats(for record: MaintenanceRecord) -> some View {
        HStack(spacing: 8) {
            HeroStatTile(
                eyebrow: "Gesamtpreis",
                value: formatCurrency(record.cost ?? 0, currency: currency(for: record)),
                accent: Theme.Colors.primary
            )
            HeroStatTile(
                eyebrow: "Preis / L",
                value: formatCurrency(record.pricePerUnit ?? 0, currency: currency(for: record))
            )
            if let consumption = record.fuelConsumption {
                HeroStatTile(
                    eyebrow: "Verbrauch",
                    value: String(format: "%.1f", consumption),
                    unit: "L / 100 km",
                    accent: consumption > 6 ? .orange : .green
                )
            }
        }
        .padding(.top, 12)
    }

    // MARK: - Sections

    @ViewBuilder
    private func sections(for record: MaintenanceRecord) -> some View {
        DetailSection("DETAILS") {
            DetailRow(label: "Datum", value: formatDateFull(record.date), mono: false)
            divider
            DetailRow(label: "Kilometerstand", value: "\(record.odo) km")
            divider
            DetailRow(label: "Tankmenge", value: String(format: "%.2f L", record.fuelAmount ?? 0))
            if let type = record.fuelType, !type.isEmpty {
                divider
                DetailRow(label: "Kraftstoff", value: type, mono: false)
            }
        }

        DetailSection("KOSTEN") {
            DetailRow(
                label: "Preis pro Liter",
                value: formatCurrency(record.pricePerUnit ?? 0, currency: currency(for: record))
            )
            divider
            DetailRow(
                label: "Gesamtpreis",
                value: formatCurrency(record.cost ?? 0, currency: currency(for: record)),
                accent: Theme.Colors.primary
            )
            if let costPerKm = costPerKm(for: record) {
                divider
                DetailRow(label: "Kosten pro km", value: Formatters.costPerKilometer(costPerKm, currency: currency(for: record)))
            }
        }

        if let consumption = record.fuelConsumption, let trip = record.tripDistance, trip > 0 {
            DetailSection("VERBRAUCH") {
                DetailRow(
                    label: "Verbrauch",
                    value: String(format: "%.1f L / 100 km", consumption),
                    accent: consumption > 6 ? .orange : .green
                )
                divider
                DetailRow(label: "Strecke seit letzter Tankung", value: "\(Int(trip)) km")
            }
        }

        if let lat = record.latitude, let lon = record.longitude {
            stationSection(for: record, lat: lat, lon: lon)
        } else if let location = record.locationName, !location.isEmpty {
            DetailSection("TANKSTELLE") {
                DetailRow(label: "Standort", value: location, mono: false)
            }
        }

        if let notes = record.description, !notes.isEmpty {
            DetailSection("NOTIZEN") {
                Text(notes)
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.92))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            }
        }
    }

    private func stationSection(for record: MaintenanceRecord, lat: Double, lon: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("TANKSTELLE\(record.locationName.map { " · \($0.uppercased())" } ?? "")")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1.4)
                    .foregroundColor(Theme.Glass.mutedText)
                Spacer()
                Button {
                    openInMaps(lat: lat, lon: lon, name: record.locationName)
                } label: {
                    Text("In Karten öffnen")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Theme.Colors.primary)
                }
            }
            .padding(.leading, 6)

            Map(initialPosition: .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                latitudinalMeters: 600, longitudinalMeters: 600
            ))) {
                Marker(record.locationName ?? "Tankstelle", coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
                    .tint(Theme.Colors.primary)
            }
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Glass.fieldRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Glass.fieldRadius)
                    .stroke(Theme.Glass.hairline, lineWidth: 0.5)
            )

            DetailSection {
                if let name = record.locationName, !name.isEmpty {
                    DetailRow(label: "Name", value: name, mono: false)
                    divider
                }
                DetailRow(label: "Koordinaten", value: String(format: "%.4f, %.4f", lat, lon))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func openInMaps(lat: Double, lon: Double, name: String?) {
        let placemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
        let item = MKMapItem(placemark: placemark)
        item.name = name ?? "Tankstelle"
        item.openInMaps()
    }

    // MARK: - Action bar

    private var actionBar: some View {
        Group {
            DetailActionButton("Bearbeiten", systemImage: "pencil", variant: .secondary) {
                showingEdit = true
            }
            DetailActionButton("Löschen", systemImage: "trash", variant: .danger) {
                confirmingDelete = true
            }
        }
    }

    // MARK: - Unavailable

    private var unavailable: some View {
        ZStack {
            Theme.Colors.navy950.ignoresSafeArea()
            ContentUnavailableView(
                "Tankung nicht gefunden",
                systemImage: "fuelpump.slash.fill",
                description: Text("Dieser Eintrag wurde möglicherweise entfernt.")
            )
            .foregroundColor(.white)
            VStack {
                HStack {
                    backPill
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                Spacer()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
    }

    private var backPill: some View {
        Button { dismiss() } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left").font(.system(size: 14, weight: .heavy))
                Text("Tanken").font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.white.opacity(0.10)))
            .overlay(Capsule().stroke(Theme.Glass.strongBorder, lineWidth: 0.5))
        }
    }

    // MARK: - Helpers

    private var divider: some View {
        Rectangle()
            .fill(Theme.Glass.hairline)
            .frame(height: 0.5)
            .padding(.leading, 14)
    }

    private func currency(for record: MaintenanceRecord) -> String {
        record.currency ?? viewModel.motorcycle.currencyCode ?? "EUR"
    }

    private func formatCurrency(_ value: Double, currency: String) -> String {
        Formatters.currency(value, code: currency)
    }

    private func costPerKm(for record: MaintenanceRecord) -> Double? {
        guard let trip = record.tripDistance, trip > 0, let cost = record.cost else { return nil }
        return cost / trip
    }

    private func formatDateFull(_ iso: String) -> String {
        Formatters.mediumDate(iso)
    }
}

struct FuelDetailView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            FuelDetailView(
                record: MotorcycleDetailViewModel.mock.maintenanceRecords[0],
                viewModel: .mock
            )
        }
    }
}
