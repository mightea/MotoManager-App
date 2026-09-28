import SwiftUI

/// Pushed detail page for a catalog part: fitment + description, the stock
/// entries ("Bestand") and the consumption history ("Verbrauch"), with
/// add-affordances for both. All writes are offline-first via PartsViewModel.
struct PartDetailView: View {
    let part: SDPart
    @ObservedObject var viewModel: PartsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showingEdit = false
    @State private var showingAddStock = false
    @State private var editingStock: SDPartStock?
    @State private var showingAddConsumption = false
    @State private var showingPrintLabel = false
    @State private var printingLocation: SDStorageLocation?
    @State private var didAutoDismiss = false
    /// Row deletes (swipe/context menu) wait here for confirmation.
    @State private var pendingStockDelete: SDPartStock?
    @State private var pendingConsumptionDelete: SDPartConsumption?
    /// Captured at init so the auto-pop guard never reads a deleted model.
    private let partClientId: UUID

    init(part: SDPart, viewModel: PartsViewModel) {
        self.part = part
        self.viewModel = viewModel
        self.partClientId = part.clientId
    }

    private var onHand: Int { viewModel.onHand(for: part) }
    private var stocks: [SDPartStock] { viewModel.stocks(for: part) }
    private var consumptions: [SDPartConsumption] { viewModel.consumptions(for: part) }

    /// Purchase value across all stock entries (normalized to CHF where the
    /// server provided it). Entries keep their price after consumption, so
    /// this is what was spent on the part — "Einkaufswert", not a live value.
    private var totalStockValue: Double {
        stocks.reduce(0) { $0 + ($1.normalizedPrice ?? $1.price ?? 0) }
    }

    var body: some View {
        DetailPage(
            accent: Theme.Colors.primary,
            eyebrow: part.syncState.isPending ? "TEIL · NICHT SYNCHRON" : "TEIL",
            title: part.name,
            subtitle: part.partNumber,
            body: {
                catalogSection
                stockSection
                consumptionSection
            }
        )
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { showingPrintLabel = true } label: {
                    Image(systemName: "printer.fill")
                }
                .accessibilityLabel("Etikett drucken")
                .disabled(part.serverId == nil)
                Button { showingEdit = true } label: {
                    Image(systemName: "pencil")
                }
                .accessibilityLabel("Bearbeiten")
            }
        }
        .sheet(isPresented: $showingEdit) {
            AddPartView(viewModel: viewModel, existingPart: part)
                .glassSheet()
        }
        .sheet(isPresented: $showingAddStock) {
            AddPartStockView(viewModel: viewModel, part: part)
                .glassSheet()
        }
        .sheet(item: $editingStock) { stock in
            AddPartStockView(viewModel: viewModel, part: part, existingStock: stock)
                .glassSheet()
        }
        .sheet(isPresented: $showingAddConsumption) {
            AddPartConsumptionView(viewModel: viewModel, part: part)
                .glassSheet(detents: [.medium, .large])
        }
        .sheet(isPresented: $showingPrintLabel) {
            if let content = partLabelContent {
                PrintLabelView(content: content)
                    .glassSheet()
            }
        }
        .sheet(item: $printingLocation) { location in
            if let content = locationLabelContent(location) {
                PrintLabelView(content: content)
                    .glassSheet()
            }
        }
        .alert(
            "Bestand löschen?",
            isPresented: Binding(
                get: { pendingStockDelete != nil },
                set: { if !$0 { pendingStockDelete = nil } }
            ),
            presenting: pendingStockDelete
        ) { stock in
            Button("Abbrechen", role: .cancel) { }
            Button("Löschen", role: .destructive) { viewModel.deleteStock(stock) }
        }
        .alert(
            "Verbrauch löschen?",
            isPresented: Binding(
                get: { pendingConsumptionDelete != nil },
                set: { if !$0 { pendingConsumptionDelete = nil } }
            ),
            presenting: pendingConsumptionDelete
        ) { consumption in
            Button("Abbrechen", role: .cancel) { }
            Button("Löschen", role: .destructive) { viewModel.deleteConsumption(consumption) }
        } message: { _ in
            Text("Die Menge wird dem Bestand wieder gutgeschrieben.")
        }
        // Pop back if the part disappears underneath us (remote delete via
        // sync, or delete from within the edit sheet).
        .onReceive(viewModel.$parts) { parts in
            guard !didAutoDismiss,
                  !parts.contains(where: { $0.clientId == partClientId }) else { return }
            didAutoDismiss = true
            dismiss()
        }
    }

    // MARK: - Label content

    /// Label for the part itself — mirrors the webapp's `part-label.tsx`.
    /// Requires a server id (the QR links to the part's web page), so it's
    /// unavailable while the part is still waiting to sync.
    private var partLabelContent: LabelContent? {
        guard let serverId = part.serverId else { return nil }
        var subtitle = part.manufacturer
        let fitment = part.seriesIds.map { viewModel.seriesName($0) }
        if !fitment.isEmpty {
            let shown = fitment.prefix(3).joined(separator: ", ")
            let extra = fitment.count > 3 ? " +\(fitment.count - 3) weitere" : ""
            subtitle += " · \(shown)\(extra)"
        }
        return LabelContent(
            url: LabelWebLinks.partURL(serverId: serverId),
            code: part.partNumber,
            title: part.name,
            subtitle: subtitle,
            footer: "MotoManager · Teil #\(serverId)"
        )
    }

    /// Label for a stock entry's storage location — mirrors the webapp's
    /// `storage-location-label.tsx` (name + path, for shelves and bins).
    private func locationLabelContent(_ location: SDStorageLocation) -> LabelContent? {
        guard let serverId = location.serverId else { return nil }
        return LabelContent(
            url: LabelWebLinks.storageLocationURL(serverId: serverId),
            code: nil,
            title: location.name,
            // Ancestors only — the name is already the label title.
            subtitle: viewModel.locationParentPath(location),
            footer: "MotoManager · Lagerort #\(serverId)"
        )
    }

    // MARK: - Catalog

    private var catalogSection: some View {
        Section {
            if let imageURL = part.image {
                RemoteImageView(url: imageURL, maxPixelWidth: 800)
                    .frame(maxWidth: .infinity)
                    .frame(height: 160)
                    .listRowInsets(EdgeInsets())
            }
            HStack(spacing: 8) {
                infoPill(part.manufacturer, icon: "building.2.fill")
                if part.isPublic {
                    infoPill("Öffentlich", icon: "globe")
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(onHand)")
                        .scaledFont(26, weight: .heavy)
                        .monospacedDigit()
                        .foregroundStyle(onHand > 0 ? AnyShapeStyle(Theme.Colors.primary) : AnyShapeStyle(.tertiary))
                    Text("AUF LAGER")
                        .scaledFont(8, weight: .heavy).tracking(1.2)
                        .foregroundStyle(.tertiary)
                    if totalStockValue > 0 {
                        Text(Formatters.currency(totalStockValue, code: "CHF"))
                            .scaledFont(12, weight: .bold)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .padding(.top, 6)
                        Text("EINKAUFSWERT")
                            .scaledFont(8, weight: .heavy).tracking(1.2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.vertical, 2)

            if let oem = part.oemPartNumber, !oem.isEmpty {
                HStack(spacing: 8) {
                    Text("BMW-NR.")
                        .scaledFont(10, weight: .heavy).tracking(1.4)
                        .foregroundStyle(.tertiary)
                    Text(oem)
                        .scaledFont(13, weight: .semibold)
                        .monospaced()
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                }
                .accessibilityElement(children: .combine)
            }

            if !part.seriesIds.isEmpty {
                seriesChips
            }

            if let description = part.partDescription, !description.isEmpty {
                Text(description)
                    .scaledFont(13)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var seriesChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(part.seriesIds, id: \.self) { id in
                    Text(viewModel.seriesName(id))
                        .scaledFont(11, weight: .semibold)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Capsule().fill(Color.primary.opacity(0.10)))
                }
            }
        }
    }

    private func infoPill(_ text: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).scaledFont(9, weight: .bold)
            Text(text).scaledFont(11, weight: .semibold)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(Capsule().fill(Color.primary.opacity(0.10)))
    }

    // MARK: - Stock

    private var stockSection: some View {
        Section {
            if stocks.isEmpty {
                Text("Noch kein Bestand erfasst.")
                    .scaledFont(13)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(stocks, id: \.clientId) { stock in
                    Button { editingStock = stock } label: {
                        stockRow(stock)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        // No destructive role: that animates the row away
                        // before the confirmation is answered.
                        Button {
                            pendingStockDelete = stock
                        } label: {
                            Label("Löschen", systemImage: "trash")
                        }
                        .tint(.red)
                    }
                    .contextMenu {
                        if let location = viewModel.storageLocation(clientId: stock.storageLocationClientId),
                           location.serverId != nil {
                            Button {
                                printingLocation = location
                            } label: {
                                Label("Lagerort-Etikett drucken", systemImage: "printer")
                            }
                        }
                        Button(role: .destructive) {
                            pendingStockDelete = stock
                        } label: {
                            Label("Löschen", systemImage: "trash")
                        }
                    }
                }
            }

            Button { showingAddStock = true } label: {
                Label("Bestand hinzufügen", systemImage: "plus")
                    .scaledFont(13, weight: .semibold)
            }
            .tint(Theme.Colors.primary)
        } header: {
            sectionHeader("Bestand", count: stocks.count)
        }
    }

    private func stockRow(_ stock: SDPartStock) -> some View {
        HStack(spacing: 12) {
            Text("\(stock.quantity)×")
                .scaledFont(16, weight: .heavy)
                .monospacedDigit()
                .foregroundStyle(Theme.Colors.primary)
                .frame(width: 44, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if let price = stock.price {
                        let unit = price / Double(max(1, stock.quantity))
                        Text("\(Formatters.currency(unit, code: stock.currency ?? "CHF")) / Stk.")
                            .scaledFont(13, weight: .bold)
                            .foregroundStyle(.primary)
                        if stock.quantity > 1 {
                            Text("· \(Formatters.currency(price, code: stock.currency ?? "CHF")) gesamt")
                                .scaledFont(12)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Ohne Preis")
                            .scaledFont(13, weight: .semibold)
                            .foregroundStyle(.tertiary)
                    }
                    if let date = stock.purchaseDate {
                        Text("· \(Formatters.mediumDate(date))")
                            .scaledFont(12)
                            .foregroundStyle(.secondary)
                    }
                    if stock.isUsed {
                        Text("GEBRAUCHT")
                            .scaledFont(8, weight: .heavy).tracking(1.0)
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color.orange.opacity(0.16)))
                    }
                }
                if let path = viewModel.locationPath(viewModel.storageLocation(clientId: stock.storageLocationClientId)) {
                    HStack(spacing: 4) {
                        Image(systemName: "archivebox.fill")
                            .scaledFont(9)
                        Text(path)
                            .lineLimit(1)
                    }
                    .scaledFont(11, weight: .semibold)
                    .foregroundStyle(.tertiary)
                }
                if let notes = stock.notes, !notes.isEmpty {
                    Text(notes)
                        .scaledFont(11)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .scaledFont(11, weight: .semibold)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    // MARK: - Consumption

    private var consumptionSection: some View {
        Section {
            if consumptions.isEmpty {
                Text("Noch kein Verbrauch erfasst. Teile lassen sich auch direkt beim Erfassen einer Wartung verbuchen.")
                    .scaledFont(13)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(consumptions, id: \.clientId) { consumption in
                    consumptionRowLinked(consumption)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                pendingConsumptionDelete = consumption
                            } label: {
                                Label("Zurückbuchen", systemImage: "arrow.uturn.backward")
                            }
                            .tint(.red)
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                pendingConsumptionDelete = consumption
                            } label: {
                                Label("Löschen (Bestand zurückbuchen)", systemImage: "arrow.uturn.backward")
                            }
                        }
                }
            }

            Button { showingAddConsumption = true } label: {
                Label("Verbrauch erfassen", systemImage: "minus")
                    .scaledFont(13, weight: .semibold)
            }
            .tint(Theme.Colors.primary)
            .disabled(onHand < 1)
        } header: {
            sectionHeader("Verbrauch", count: consumptions.count)
        }
    }

    /// The bike a consumption was booked on, preferring the context the server
    /// joined onto the row (available offline, and survives the motorcycle not
    /// being in the JSON cache) and falling back to the cache by id.
    private func motorcycleLabel(_ consumption: SDPartConsumption) -> String? {
        let joined = [consumption.motorcycleMake, consumption.motorcycleModel]
            .compactMap { $0 }
            .joined(separator: " ")
        if !joined.isEmpty { return joined }
        guard let id = consumption.motorcycleServerId,
              let moto = cachedMotorcycle(id: id) else { return nil }
        return "\(moto.make) \(moto.model)"
    }

    private func cachedMotorcycle(id: Int) -> Motorcycle? {
        let cached: [Motorcycle] = CacheStore.shared.load([Motorcycle].self, key: CacheKey.motorcycles) ?? []
        return cached.first { $0.id == id }
    }

    /// Row wrapped in a link to the repair when the bike can be resolved —
    /// MaintenanceDetailView needs a real Motorcycle to build its view model,
    /// so an unresolvable one degrades to the plain, non-tappable row.
    @ViewBuilder
    private func consumptionRowLinked(_ consumption: SDPartConsumption) -> some View {
        if let repair = viewModel.maintenanceRecord(for: consumption),
           let moto = cachedMotorcycle(id: repair.motorcycleId) {
            NavigationLink {
                LinkedRepairView(motorcycle: moto, record: repair, partsVM: viewModel)
            } label: {
                consumptionRow(consumption)
            }
            .buttonStyle(.plain)
        } else {
            consumptionRow(consumption)
        }
    }

    private func consumptionRow(_ consumption: SDPartConsumption) -> some View {
        let repair = viewModel.maintenanceRecord(for: consumption)
        return HStack(spacing: 12) {
            Text("−\(consumption.quantity)")
                .scaledFont(16, weight: .heavy)
                .monospacedDigit()
                .foregroundStyle(Theme.Colors.accent)
                .frame(width: 44, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(Formatters.mediumDate(consumption.date))
                    .scaledFont(13, weight: .bold)
                    .foregroundStyle(.primary)
                if let repair {
                    HStack(spacing: 4) {
                        Image(systemName: "wrench.and.screwdriver.fill")
                            .scaledFont(9)
                        Text(repair.recordDescription ?? repair.summary ?? repair.recordType)
                            .lineLimit(1)
                        if cachedMotorcycle(id: repair.motorcycleId) != nil {
                            Image(systemName: "chevron.right")
                                .scaledFont(8)
                        }
                    }
                    .scaledFont(11, weight: .semibold)
                    .foregroundStyle(.tertiary)
                } else if consumption.maintenanceClientId != nil || consumption.maintenanceServerId != nil {
                    Text("Verknüpfte Wartung")
                        .scaledFont(11, weight: .semibold)
                        .foregroundStyle(.tertiary)
                }
                // Which bike the part went into — the whole point of the link,
                // and the one thing the repair's own description never says.
                if let motorcycle = motorcycleLabel(consumption) {
                    HStack(spacing: 4) {
                        Image(systemName: "bicycle")
                            .scaledFont(9)
                        Text(motorcycle).lineLimit(1)
                    }
                    .scaledFont(11, weight: .semibold)
                    .foregroundStyle(Theme.Colors.primary.opacity(0.8))
                }
                if let notes = consumption.notes, !notes.isEmpty {
                    Text(notes)
                        .scaledFont(11)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    // MARK: - Shared bits

    private func sectionHeader(_ label: String, count: Int) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(count) \(count == 1 ? "Eintrag" : "Einträge")")
        }
    }
}

// MARK: - Add/edit stock sheet

/// Create/edit a stock entry: quantity, price + currency, purchase date,
/// storage location (with inline create), notes.
struct AddPartStockView: View {
    @ObservedObject var viewModel: PartsViewModel
    let part: SDPart
    let existingStock: SDPartStock?

    @State private var quantity: Int
    @State private var price: String
    @State private var currency: String
    @State private var purchaseDate: Date
    @State private var selectedLocation: SDStorageLocation?
    @State private var newLocationName: String
    @State private var notes: String
    @State private var isUsed: Bool
    @State private var errorMessage: String?

    init(viewModel: PartsViewModel, part: SDPart, existingStock: SDPartStock? = nil) {
        self.viewModel = viewModel
        self.part = part
        self.existingStock = existingStock
        _newLocationName = State(initialValue: "")
        if let s = existingStock {
            _quantity = State(initialValue: s.quantity)
            _price = State(initialValue: s.price.map { String($0) } ?? "")
            _currency = State(initialValue: s.currency ?? "CHF")
            let f = ISO8601DateFormatter(); f.formatOptions = [.withFullDate]
            _purchaseDate = State(initialValue: s.purchaseDate.flatMap { f.date(from: $0) } ?? Date())
            // Resolved here (not onAppear) so the unsaved-changes snapshot
            // starts from the stored location.
            _selectedLocation = State(initialValue: viewModel.storageLocation(clientId: s.storageLocationClientId))
            _notes = State(initialValue: s.notes ?? "")
            _isUsed = State(initialValue: s.isUsed)
        } else {
            _quantity = State(initialValue: 1)
            _price = State(initialValue: "")
            _currency = State(initialValue: "CHF")
            _purchaseDate = State(initialValue: Date())
            _selectedLocation = State(initialValue: nil)
            _notes = State(initialValue: "")
            _isUsed = State(initialValue: false)
        }
    }

    var body: some View {
        FormSheet(
            title: existingStock == nil ? "Bestand hinzufügen" : "Bestand bearbeiten",
            canSave: canSave,
            tracked: [quantity, price, currency, purchaseDate,
                      selectedLocation?.clientId.uuidString ?? "", newLocationName, notes, isUsed],
            error: errorMessage,
            delete: existingStock.map { stock in
                FormSheetDelete(title: "Bestand löschen?") { viewModel.deleteStock(stock) }
            },
            onSave: save
        ) {
            PartQuantityField(quantity: $quantity)
            CurrencyField(price: $price, currency: $currency)
            FormField("Kaufdatum") {
                DatePicker("", selection: $purchaseDate, displayedComponents: .date)
                    .labelsHidden().tint(Theme.Colors.primary)
            }
            StorageLocationPicker(
                viewModel: viewModel,
                selection: $selectedLocation,
                newLocationName: $newLocationName
            )
            FormField("Notizen") {
                TextField("", text: $notes,
                          prompt: formPrompt("z. B. Kauf bei Motorradteile Meyer"),
                          axis: .vertical)
                    .lineLimit(2...4)
            }
            FormToggleRow(
                title: "Gebrauchtteil",
                subtitle: "z. B. aus einem Motorrad ausgeschlachtet",
                isOn: $isUsed
            )
        }
    }

    /// Quantity is stepper-bound (≥ 1); the price is optional but must be a
    /// number when given.
    private var canSave: Bool {
        quantity > 0 && CurrencyField.isValid(price)
    }

    private func save() async -> Bool {
        errorMessage = nil
        guard canSave else { return false }
        // Inline location creation wins over the picker when both are set.
        var location = selectedLocation
        let newName = newLocationName.trimmingCharacters(in: .whitespaces)
        if !newName.isEmpty {
            guard let created = viewModel.createStorageLocation(name: newName, parent: selectedLocation) else {
                errorMessage = "Lagerort konnte nicht angelegt werden."
                return false
            }
            location = created
        }
        let priceValue = CurrencyField.parse(price)
        let trimmedCurrency = currency.trimmingCharacters(in: .whitespaces)
        let saved: Bool
        if let s = existingStock {
            saved = viewModel.updateStock(
                s, quantity: quantity, price: priceValue, currency: trimmedCurrency,
                purchaseDate: purchaseDate, storageLocation: location, notes: notes,
                isUsed: isUsed)
        } else {
            saved = viewModel.addStock(
                part: part, quantity: quantity, price: priceValue, currency: trimmedCurrency,
                purchaseDate: purchaseDate, storageLocation: location, notes: notes,
                isUsed: isUsed) != nil
        }
        if !saved { errorMessage = "Speichern fehlgeschlagen." }
        return saved
    }
}

// MARK: - Manual consumption sheet

/// "Verbrauch erfassen" — a manual correction not tied to a repair. The
/// quantity is capped at the local on-hand, mirroring the server rule.
struct AddPartConsumptionView: View {
    @ObservedObject var viewModel: PartsViewModel
    let part: SDPart

    @State private var quantity = 1
    @State private var date = Date()
    @State private var notes = ""
    @State private var errorMessage: String?

    private var onHand: Int { viewModel.onHand(for: part) }

    var body: some View {
        FormSheet(
            title: "Verbrauch erfassen",
            canSave: canSave,
            tracked: [quantity, date, notes],
            error: errorMessage,
            onSave: save
        ) {
            Text("\(part.name) · \(onHand) auf Lager")
                .scaledFont(12, weight: .semibold)
                .foregroundStyle(.secondary)

            PartQuantityField(quantity: $quantity, range: 1...max(1, onHand))
            FormField("Datum") {
                DatePicker("", selection: $date, displayedComponents: .date)
                    .labelsHidden().tint(Theme.Colors.primary)
            }
            FormField("Notiz") {
                TextField("", text: $notes, prompt: formPrompt("z. B. defekt / verloren"))
            }
        }
    }

    /// Can't book more than is on hand (the server enforces the same).
    private var canSave: Bool {
        quantity >= 1 && quantity <= onHand
    }

    private func save() async -> Bool {
        errorMessage = nil
        guard canSave else { return false }
        guard viewModel.addConsumption(part: part, quantity: quantity, date: date, notes: notes) else {
            errorMessage = "Nicht genug Bestand oder Speichern fehlgeschlagen."
            return false
        }
        return true
    }
}

/// Hosts `MaintenanceDetailView` when navigating in from a part's consumption
/// history.
///
/// That view is built around a `MotorcycleDetailViewModel` (it reads the bike,
/// its locations and the sibling records that make up a bundled entry), which
/// normally comes from the garage flow. Reached from the Teile tab there is no
/// such view model in scope, so one is created here for the bike the repair
/// belongs to and primed from the local store — otherwise the page would render
/// with no location names and no bundled children until the next sync.
private struct LinkedRepairView: View {
    let motorcycle: Motorcycle
    let record: SDMaintenanceRecord
    @ObservedObject var partsVM: PartsViewModel
    @StateObject private var detailVM: MotorcycleDetailViewModel

    init(motorcycle: Motorcycle, record: SDMaintenanceRecord, partsVM: PartsViewModel) {
        self.motorcycle = motorcycle
        self.record = record
        self.partsVM = partsVM
        _detailVM = StateObject(wrappedValue: MotorcycleDetailViewModel(motorcycle: motorcycle))
    }

    var body: some View {
        MaintenanceDetailView(record: record, viewModel: detailVM, partsVM: partsVM)
            .onAppear { detailVM.reloadLocal() }
    }
}
