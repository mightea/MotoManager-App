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

    var body: some View {
        DetailPage(
            backLabel: "Tanken",
            accent: Theme.Colors.primary,
            eyebrow: record.syncState.isPending ? "TANKUNG · NICHT SYNCHRON" : "TANKUNG",
            title: titleString,
            subtitle: subtitle,
            heroContent: { heroStats },
            body: { sections },
            actions: { actionBar },
            onClose: { dismiss() }
        )
        .sheet(isPresented: $showingEdit) {
            AddFuelView(viewModel: viewModel, existingRecord: record)
                .presentationDetents([.large])
                .presentationCornerRadius(Theme.Glass.sheetRadius)
                .presentationBackground(.regularMaterial)
                .presentationDragIndicator(.visible)
        }
        .alert("Tankung löschen?", isPresented: $confirmingDelete) {
            Button("Abbrechen", role: .cancel) { }
            Button("Löschen", role: .destructive) {
                viewModel.deleteFuelRecord(record)
                dismiss()
            }
        } message: {
            Text("Diese Tankung kann nicht wiederhergestellt werden.")
        }
    }

    // MARK: - Hero

    private var titleString: String {
        String(format: "%.1f L", record.fuelAmount ?? 0)
    }

    private var subtitle: String {
        "\(Formatters.mediumDate(record.date)) · \(viewModel.motorcycle.make) \(viewModel.motorcycle.model)"
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
                    .font(.system(size: 14))
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
