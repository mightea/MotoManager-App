import SwiftUI
import MapKit

/// Fuel-entry detail page. Backed by a SwiftData `SDMaintenanceRecord` (offline-
/// first), so it reflects local edits and pending-sync state immediately.
///
/// Uses the shared `DetailPage` chrome. Hero shows the liters, a TANKUNG
/// eyebrow + bike/date subline, and three stat tiles (total cost, price/L,
/// L/100 km). The sticky bottom action bar offers Bearbeiten + Löschen.
struct FuelDetailView: View {
    let record: SDMaintenanceRecord
    @ObservedObject var viewModel: MotorcycleDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingEdit = false
    @State private var confirmingDelete = false
    @State private var didAutoDismiss = false
    /// Captured at init so the auto-pop guard never reads a deleted model.
    private let recordClientId: UUID

    init(record: SDMaintenanceRecord, viewModel: MotorcycleDetailViewModel) {
        self.record = record
        self.viewModel = viewModel
        self.recordClientId = record.clientId
    }

    var body: some View {
        DetailPage(
            accent: Theme.Colors.primary,
            eyebrow: record.syncState.isPending ? "TANKUNG · NICHT SYNCHRON" : "TANKUNG",
            title: titleString,
            barTitle: Formatters.mediumDate(record.date),
            subtitle: subtitle,
            heroBackground: { heroMap },
            heroContent: { heroStats },
            body: { sections }
        )
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { showingEdit = true } label: {
                    Image(systemName: "pencil")
                }
                .accessibilityLabel("Bearbeiten")
                Button(role: .destructive) { confirmingDelete = true } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Löschen")
            }
        }
        .sheet(isPresented: $showingEdit) {
            AddFuelView(viewModel: viewModel, existingRecord: record)
                .glassSheet()
        }
        .alert("Tankung löschen?", isPresented: $confirmingDelete) {
            Button("Abbrechen", role: .cancel) { }
            Button("Löschen", role: .destructive) {
                guard viewModel.deleteFuelRecord(record) else { return }
                didAutoDismiss = true
                dismiss()
            }
        } message: {
            Text("Diese Tankung kann nicht wiederhergestellt werden.")
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

    // MARK: - Hero

    private var titleString: String {
        String(format: "%.1f L", record.fuelAmount ?? 0)
    }

    /// The bar title already carries the date, so the hero subline only names
    /// the bike.
    private var subtitle: String {
        "\(viewModel.motorcycle.make) \(viewModel.motorcycle.model)"
    }

    /// Dimmed, non-interactive map of the fuel stop behind the hero — only
    /// when the record carries coordinates. The scrim keeps the hero text
    /// legible; the interactive map with "In Karten öffnen" stays in the
    /// TANKSTELLE section below.
    @ViewBuilder
    private var heroMap: some View {
        if let lat = record.latitude, let lon = record.longitude {
            Map(initialPosition: .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                latitudinalMeters: 900, longitudinalMeters: 900
            ))) {
                Marker(record.locationName ?? "Tankstelle",
                       coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
                    .tint(Theme.Colors.primary)
            }
            .mapControlVisibility(.hidden)
            .allowsHitTesting(false)
            .environment(\.colorScheme, .dark)
            .overlay(
                LinearGradient(
                    stops: [
                        .init(color: Theme.Colors.navy950.opacity(0.55), location: 0.0),
                        .init(color: Theme.Colors.navy950.opacity(0.45), location: 0.5),
                        .init(color: Theme.Colors.navy950.opacity(0.9), location: 1.0)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            )
        }
    }

    private var currency: String {
        record.currency ?? viewModel.motorcycle.currencyCode ?? "EUR"
    }

    @ViewBuilder
    private var heroStats: some View {
        HStack(spacing: 8) {
            HeroStatTile(
                eyebrow: "Gesamtpreis",
                value: Formatters.currency(record.cost ?? 0, code: currency),
                accent: Theme.Colors.primary
            )
            HeroStatTile(
                eyebrow: "Preis / L",
                value: Formatters.currency(record.pricePerUnit ?? 0, code: currency)
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
    private var sections: some View {
        DetailSection("DETAILS") {
            DetailRow(label: "Datum", value: Formatters.mediumDate(record.date), mono: false)
            divider
            DetailRow(label: "Kilometerstand", value: "\(record.odo) km")
            divider
            DetailRow(label: "Tankmenge", value: String(format: "%.2f L", record.fuelAmount ?? 0))
            if let type = record.fuelType, !type.isEmpty {
                divider
                DetailRow(label: "Kraftstoff", value: type, mono: false)
            }
            if record.fuelAdditiveAdded {
                divider
                DetailRow(label: "Additiv", value: "Ja", mono: false)
            }
            if record.leadSubstituteAdded {
                divider
                DetailRow(label: "Bleiersatz", value: "Ja", mono: false)
            }
        }

        DetailSection("KOSTEN") {
            DetailRow(label: "Preis pro Liter", value: Formatters.currency(record.pricePerUnit ?? 0, code: currency))
            divider
            DetailRow(label: "Gesamtpreis", value: Formatters.currency(record.cost ?? 0, code: currency), accent: Theme.Colors.primary)
            if let costPerKm {
                divider
                DetailRow(label: "Kosten pro km", value: Formatters.costPerKilometer(costPerKm, currency: currency))
            }
        }

        if let consumption = record.fuelConsumption, let trip = record.tripDistance, trip > 0 {
            DetailSection("VERBRAUCH") {
                DetailRow(label: "Verbrauch", value: String(format: "%.1f L / 100 km", consumption), accent: consumption > 6 ? .orange : .green)
                divider
                DetailRow(label: "Strecke seit letzter Tankung", value: "\(Int(trip)) km")
            }
        }

        if let lat = record.latitude, let lon = record.longitude {
            stationSection(lat: lat, lon: lon)
        } else if let location = record.locationName, !location.isEmpty {
            DetailSection("TANKSTELLE") {
                DetailRow(label: "Standort", value: location, mono: false)
            }
        }

        if let notes = record.recordDescription, !notes.isEmpty {
            DetailSection("NOTIZEN") {
                Text(notes)
                    .scaledFont(14)
                    .foregroundColor(.white.opacity(0.92))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            }
        }
    }

    private func stationSection(lat: Double, lon: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("TANKSTELLE\(record.locationName.map { " · \($0.uppercased())" } ?? "")")
                    .scaledFont(10, weight: .heavy)
                    .tracking(1.4)
                    .foregroundColor(Theme.Glass.mutedText)
                Spacer()
                Button {
                    openInMaps(lat: lat, lon: lon, name: record.locationName)
                } label: {
                    Text("In Karten öffnen")
                        .scaledFont(11, weight: .semibold)
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func openInMaps(lat: Double, lon: Double, name: String?) {
        let location = CLLocation(latitude: lat, longitude: lon)
        let item = MKMapItem(location: location, address: nil)
        item.name = name ?? "Tankstelle"
        item.openInMaps()
    }

    // MARK: - Helpers

    private var divider: some View {
        Rectangle()
            .fill(Theme.Glass.hairline)
            .frame(height: 0.5)
            .padding(.leading, 14)
    }

    private var costPerKm: Double? {
        guard let trip = record.tripDistance, trip > 0, let cost = record.cost else { return nil }
        return cost / trip
    }
}
