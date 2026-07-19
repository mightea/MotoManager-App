import SwiftUI
import MapKit

/// Maintenance-record detail page, backed by a SwiftData `SDMaintenanceRecord`
/// (offline-first). Pushed onto the tab's NavigationStack; mirrors the
/// webapp's expanded row: type-specific metadata, consumed parts, bundled
/// child works, and a map hero for located records.
struct MaintenanceDetailView: View {
    let record: SDMaintenanceRecord
    @ObservedObject var viewModel: MotorcycleDetailViewModel
    @ObservedObject var partsVM: PartsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingEdit = false
    @State private var confirmingDelete = false
    @State private var didAutoDismiss = false
    @State private var selectedPart: SDPart?
    @State private var selectedChild: SDMaintenanceRecord?
    /// Captured at init so the auto-pop guard never reads a deleted model.
    private let recordClientId: UUID

    init(record: SDMaintenanceRecord, viewModel: MotorcycleDetailViewModel, partsVM: PartsViewModel) {
        self.record = record
        self.viewModel = viewModel
        self.partsVM = partsVM
        self.recordClientId = record.clientId
    }

    var body: some View {
        let category = record.category
        DetailPage(
            accent: category.tint,
            eyebrow: record.syncState.isPending ? "WARTUNGSEINTRAG · NICHT SYNCHRON" : "WARTUNGSEINTRAG",
            title: MaintenanceSummarizer.summarize(record, locations: viewModel.userLocations),
            barTitle: Formatters.mediumDate(record.date),
            subtitle: "\(viewModel.motorcycle.make) \(viewModel.motorcycle.model)",
            heroBackground: { heroMap },
            heroContent: { categoryPill(category) },
            body: { sections(category) }
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
            AddMaintenanceView(viewModel: viewModel, existingRecord: record)
                .glassSheet()
        }
        .navigationDestination(item: $selectedPart) { part in
            PartDetailView(part: part, viewModel: partsVM)
        }
        .navigationDestination(item: $selectedChild) { child in
            MaintenanceDetailView(record: child, viewModel: viewModel, partsVM: partsVM)
        }
        .alert("Wartung löschen?", isPresented: $confirmingDelete) {
            Button("Abbrechen", role: .cancel) { }
            Button("Löschen", role: .destructive) {
                didAutoDismiss = true
                viewModel.deleteMaintenance(record)
                dismiss()
            }
        } message: {
            Text("Dieser Eintrag kann nicht wiederhergestellt werden.")
        }
        // Pop back if the record disappears underneath us (remote delete via
        // sync, or delete from within the edit sheet).
        .onReceive(viewModel.$serviceRecords) { records in
            guard !didAutoDismiss,
                  !records.contains(where: { $0.clientId == recordClientId }) else { return }
            didAutoDismiss = true
            dismiss()
        }
    }

    // MARK: - Hero

    private func categoryPill(_ category: MaintenanceCategory) -> some View {
        HStack(spacing: 6) {
            Image(systemName: category.icon)
                .font(.system(size: 12, weight: .semibold))
            Text(record.fluidTypeLabel ?? category.label)
                .font(.system(size: 12, weight: .heavy))
        }
        .foregroundColor(category.tint)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Capsule().fill(category.tint.opacity(0.20)))
        .overlay(Capsule().stroke(category.tint.opacity(0.35), lineWidth: 0.5))
    }

    /// Coordinates from the record itself (locally-created) or the resolved
    /// user location (synced records only carry `locationId`).
    private var heroCoordinates: (lat: Double, lon: Double, name: String?)? {
        if let lat = record.latitude, let lon = record.longitude {
            return (lat, lon, record.locationName)
        }
        if let location = viewModel.location(id: record.locationId),
           let lat = location.latitude, let lon = location.longitude {
            return (lat, lon, location.name)
        }
        return nil
    }

    /// Dimmed, non-interactive map behind the hero when the record has a
    /// resolvable place — same pattern as the fuel detail.
    @ViewBuilder
    private var heroMap: some View {
        if let coords = heroCoordinates {
            Map(initialPosition: .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: coords.lat, longitude: coords.lon),
                latitudinalMeters: 900, longitudinalMeters: 900
            ))) {
                Marker(coords.name ?? record.category.label,
                       coordinate: CLLocationCoordinate2D(latitude: coords.lat, longitude: coords.lon))
                    .tint(record.category.tint)
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

    // MARK: - Sections

    @ViewBuilder
    private func sections(_ category: MaintenanceCategory) -> some View {
        HStack(spacing: 8) {
            statCard(eyebrow: "KOSTEN",
                     value: record.cost.map { Formatters.currency($0, code: currency, fractionDigits: 0) } ?? "—",
                     accent: category.tint)
            statCard(eyebrow: "BEI", value: "\(record.odo) km")
        }

        DetailSection("ÜBERSICHT") {
            DetailRow(label: "Datum", value: Formatters.mediumDate(record.date), mono: false)
            divider
            DetailRow(label: "Kilometerstand", value: "\(record.odo) km")
            divider
            DetailRow(label: "Kategorie", value: record.fluidTypeLabel ?? category.label, mono: false)
            divider
            DetailRow(label: "Motorrad",
                      value: "\(viewModel.motorcycle.make) \(viewModel.motorcycle.model)",
                      mono: false)
        }

        detailsSection(category)
        costSection(category)
        usedPartsSection
        childRecordsSection
        siblingRecordsSection

        if let notes = record.recordDescription ?? record.summary, !notes.isEmpty {
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

    /// Type-specific metadata (webapp `metadataItems`): only rows with values,
    /// section omitted entirely when empty.
    @ViewBuilder
    private func detailsSection(_ category: MaintenanceCategory) -> some View {
        let rows = detailRows(category)
        if !rows.isEmpty {
            DetailSection("DETAILS") {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 { divider }
                    DetailRow(label: row.0, value: row.1, mono: false)
                }
            }
        }
    }

    private func detailRows(_ category: MaintenanceCategory) -> [(String, String)] {
        var rows: [(String, String)] = []
        let technical: Set<MaintenanceCategory> = [.tire, .battery, .fluid, .chain, .brakepad, .brakerotor]

        if technical.contains(category) {
            if let brand = record.brand, !brand.isEmpty { rows.append(("Marke", brand)) }
            if let model = record.model, !model.isEmpty { rows.append(("Modell", model)) }
        }
        switch category {
        case .tire:
            if let position = record.tirePosition {
                rows.append(("Position", MaintenanceCategory.tirePositionLabels[position] ?? position))
            }
            if let size = record.tireSize, !size.isEmpty { rows.append(("Grösse", size)) }
            if let dot = record.dotCode, !dot.isEmpty {
                var value = MaintenanceSummarizer.formattedDot(dot)
                if let age = MaintenanceSummarizer.dotAgeYears(dot) {
                    value += String(format: " (%.1f Jahre)", age)
                }
                rows.append(("DOT / Alter", value))
            }
        case .brakepad, .brakerotor:
            if let position = record.tirePosition {
                rows.append(("Position", MaintenanceCategory.tirePositionLabels[position] ?? position))
            }
        case .fluid:
            if let label = record.fluidTypeLabel { rows.append(("Art", label)) }
            if let viscosity = record.viscosity, !viscosity.isEmpty { rows.append(("Viskosität", viscosity)) }
            if let oilType = record.oilType, let label = MaintenanceCategory.oilTypeLabels[oilType] {
                rows.append(("Öl-Typ", label))
            }
        case .battery:
            if let type = record.batteryType {
                rows.append(("Batterietyp", MaintenanceCategory.batteryTypeLabels[type] ?? type))
            }
        case .inspection:
            if let place = viewModel.location(id: record.locationId)?.name
                ?? record.inspectionLocation ?? record.locationName {
                rows.append(("Prüfstelle", place))
            }
        case .location:
            if let place = viewModel.location(id: record.locationId)?.name ?? record.locationName {
                rows.append(("Standort", place))
            }
        case .service:
            if let place = viewModel.location(id: record.locationId)?.name {
                rows.append(("Betrieb", place))
            }
        default:
            break
        }
        return rows
    }

    /// KOSTEN with the normalized value in the user's base currency when the
    /// record was paid in a different one (webapp behavior).
    @ViewBuilder
    private func costSection(_ category: MaintenanceCategory) -> some View {
        if let cost = record.cost {
            DetailSection("KOSTEN") {
                DetailRow(label: "Betrag",
                          value: Formatters.currency(cost, code: currency),
                          accent: category.tint)
                if let normalized = record.normalizedCost,
                   let baseCurrency = viewModel.motorcycle.currencyCode,
                   currency != baseCurrency {
                    divider
                    DetailRow(label: "Umgerechnet",
                              value: "≈ \(Formatters.currency(normalized, code: baseCurrency))")
                }
            }
        }
    }

    // MARK: - Verwendete Teile

    @ViewBuilder
    private var usedPartsSection: some View {
        let consumptions = partsVM.consumptions(forMaintenance: record)
        if !consumptions.isEmpty {
            DetailSection("VERWENDETE TEILE") {
                ForEach(Array(consumptions.enumerated()), id: \.element.clientId) { index, consumption in
                    if index > 0 { divider }
                    usedPartRow(consumption)
                }
            }
        }
    }

    @ViewBuilder
    private func usedPartRow(_ consumption: SDPartConsumption) -> some View {
        let part = partsVM.part(clientId: consumption.partClientId, serverId: consumption.partServerId)
        Button {
            if let part { selectedPart = part }
        } label: {
            HStack(spacing: 10) {
                Text("\(consumption.quantity)×")
                    .font(.system(size: 14, weight: .heavy))
                    .monospacedDigit()
                    .foregroundColor(Theme.Colors.primary)
                    .frame(width: 36, alignment: .leading)
                VStack(alignment: .leading, spacing: 1) {
                    Text(part?.name ?? "Unbekanntes Teil")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    if let number = part?.partNumber {
                        Text(number)
                            .font(.system(size: 11, weight: .semibold))
                            .monospaced()
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
                Spacer(minLength: 0)
                if part != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.3))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(part == nil)
    }

    // MARK: - Eingeschlossene Arbeiten / Weitere Einträge

    /// Bundled sub-works: children link via `parentId` → this record's server
    /// id (server-assigned; iOS never creates children itself).
    private var childRecords: [SDMaintenanceRecord] {
        guard let serverId = record.serverId else { return [] }
        return viewModel.serviceRecords.filter { $0.parentId == serverId }
    }

    @ViewBuilder
    private var childRecordsSection: some View {
        if !childRecords.isEmpty {
            DetailSection("EINGESCHLOSSENE ARBEITEN") {
                ForEach(Array(childRecords.enumerated()), id: \.element.clientId) { index, child in
                    if index > 0 { divider }
                    recordLinkRow(child)
                }
            }
        }
    }

    /// Same-day/-odo/-category sibling parents: the list collapses them onto
    /// one primary row, so the detail keeps the rest reachable.
    private var siblingRecords: [SDMaintenanceRecord] {
        viewModel.serviceRecords.filter { other in
            other.clientId != record.clientId
                && other.parentId == nil
                && other.date == record.date
                && other.odo == record.odo
                && other.category == record.category
        }
    }

    @ViewBuilder
    private var siblingRecordsSection: some View {
        if !siblingRecords.isEmpty {
            DetailSection("WEITERE EINTRÄGE") {
                ForEach(Array(siblingRecords.enumerated()), id: \.element.clientId) { index, sibling in
                    if index > 0 { divider }
                    recordLinkRow(sibling)
                }
            }
        }
    }

    private func recordLinkRow(_ other: SDMaintenanceRecord) -> some View {
        let category = other.category
        return Button {
            selectedChild = other
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(category.tint.opacity(0.15))
                    Image(systemName: category.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(category.tint)
                }
                .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(MaintenanceSummarizer.summarize(other, locations: viewModel.userLocations))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(category.label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.5))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.3))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func statCard(eyebrow: String, value: String, accent: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(eyebrow)
                .font(.system(size: 10, weight: .heavy))
                .tracking(1.2)
                .foregroundColor(Theme.Glass.mutedText)
            Text(value)
                .font(.system(size: 22, weight: .heavy))
                .monospacedDigit()
                .foregroundColor(accent ?? .white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.Glass.hairline, lineWidth: 0.5))
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.Glass.hairline)
            .frame(height: 0.5)
            .padding(.leading, 14)
    }

    private var currency: String {
        record.currency ?? viewModel.motorcycle.currencyCode ?? "EUR"
    }
}
