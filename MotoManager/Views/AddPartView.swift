import SwiftUI

/// Create/edit a catalog part (offline-first). Fitment is picked from the
/// cached series lookup; custom series can be created inline (online only).
struct AddPartView: View {
    @ObservedObject var viewModel: PartsViewModel
    let existingPart: SDPart?

    @State private var partNumber: String
    @State private var name: String
    @State private var manufacturer: String
    @State private var oemPartNumber: String
    @State private var notes: String
    @State private var isPublic: Bool
    @State private var selectedSeriesIds: Set<Int>
    @State private var showingSeriesPicker = false
    @State private var errorMessage: String?

    // BMWBike enrichment: fills only what is still missing.
    @State private var isEnriching = false
    @State private var enrichMessage: String?
    @State private var enrichFailed = false
    /// Remote image to import once saved (only when the part has none).
    @State private var importImageUrl: String?

    // Initial stock (create mode only): a new part always starts with at
    // least one recorded instance so the inventory never has empty parts.
    @State private var stockQuantity = 1
    @State private var stockPrice = ""
    @State private var stockCurrency = "CHF"
    @State private var stockPurchaseDate = Date()
    @State private var stockLocation: SDStorageLocation?
    @State private var newLocationName = ""

    init(viewModel: PartsViewModel, existingPart: SDPart? = nil) {
        self.viewModel = viewModel
        self.existingPart = existingPart
        if let p = existingPart {
            _partNumber = State(initialValue: p.partNumber)
            _name = State(initialValue: p.name)
            _manufacturer = State(initialValue: p.manufacturer)
            _oemPartNumber = State(initialValue: p.oemPartNumber ?? "")
            _notes = State(initialValue: p.partDescription ?? "")
            _isPublic = State(initialValue: p.isPublic)
            _selectedSeriesIds = State(initialValue: Set(p.seriesIds))
        } else {
            _partNumber = State(initialValue: "")
            _name = State(initialValue: "")
            _manufacturer = State(initialValue: "BMW")
            _oemPartNumber = State(initialValue: "")
            _notes = State(initialValue: "")
            _isPublic = State(initialValue: false)
            _selectedSeriesIds = State(initialValue: [])
        }
    }

    var body: some View {
        FormSheet(
            title: existingPart == nil ? "Teil hinzufügen" : "Teil bearbeiten",
            canSave: canSave,
            tracked: tracked,
            error: errorMessage,
            delete: existingPart.map { part in
                FormSheetDelete(
                    title: "Teil löschen?",
                    message: "Bestand und Verbrauch dieses Teils werden ebenfalls entfernt."
                ) { viewModel.deletePart(part) }
            },
            onSave: save
        ) {
            FormField("Teilenummer") {
                TextField("", text: $partNumber, prompt: formPrompt("z. B. 11 42 7 673 541"))
                    .autocorrectionDisabled()
            }
            FormField("Name") {
                TextField("", text: $name, prompt: formPrompt("z. B. Ölfilter"))
            }
            FormField("Hersteller") {
                TextField("", text: $manufacturer, prompt: formPrompt("BMW"))
            }
            oemSection
            FormField("Baureihen") {
                Button { showingSeriesPicker = true } label: {
                    HStack {
                        Text(seriesSummary)
                            .foregroundStyle(selectedSeriesIds.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .scaledFont(11, weight: .semibold)
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            FormField("Beschreibung") {
                TextField("", text: $notes,
                          prompt: formPrompt("z. B. passt auch für Ölkühler-Variante"),
                          axis: .vertical)
                    .lineLimit(2...5)
            }
            FormToggleRow(
                title: "Öffentlich teilen",
                subtitle: "Andere Nutzer sehen Teiledaten und Verfügbarkeit — nie Preise oder Lagerorte.",
                isOn: $isPublic
            )

            if existingPart == nil {
                initialStockSection
            }
        }
        .sheet(isPresented: $showingSeriesPicker) {
            SeriesPickerView(viewModel: viewModel, selection: $selectedSeriesIds)
                .glassSheet()
        }
    }

    /// Every editable value, for the unsaved-changes guard.
    private var tracked: [AnyHashable] {
        [partNumber, name, manufacturer, oemPartNumber, notes, isPublic,
         selectedSeriesIds, importImageUrl ?? "",
         stockQuantity, stockPrice, stockCurrency, stockPurchaseDate,
         stockLocation?.clientId.uuidString ?? "", newLocationName]
    }

    /// Part number and name are required (they are the part's identity);
    /// the initial stock price is optional but must be a number when given.
    private var canSave: Bool {
        !partNumber.trimmingCharacters(in: .whitespaces).isEmpty
            && !name.trimmingCharacters(in: .whitespaces).isEmpty
            && (existingPart != nil || CurrencyField.isValid(stockPrice))
    }

    // MARK: - BMW part number + BMWBike enrichment

    /// Number to look up: the OEM field for aftermarket parts, else the
    /// part's own number when it is a BMW part.
    private var lookupNumber: String? {
        let oem = oemPartNumber.trimmingCharacters(in: .whitespaces)
        if !oem.isEmpty { return oem }
        let own = partNumber.trimmingCharacters(in: .whitespaces)
        let isBmw = manufacturer.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare("BMW") == .orderedSame
        return isBmw && !own.isEmpty ? own : nil
    }

    private var oemSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            FormField(
                "BMW-Teilenummer (Original)",
                hint: "Für Nachbau- oder Fremdteile: die BMW-Nummer, die das Teil ersetzt."
            ) {
                TextField("", text: $oemPartNumber, prompt: formPrompt("z. B. 12 32 1 244 409"))
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled()
            }

            if let number = lookupNumber {
                Button {
                    Task { await enrich(from: number) }
                } label: {
                    HStack(spacing: Theme.Spacing.s) {
                        if isEnriching {
                            ProgressView()
                        } else {
                            Image(systemName: "sparkle.magnifyingglass")
                        }
                        Text("Von BMWBike ergänzen")
                    }
                    .frame(maxWidth: .infinity)
                }
                .glassActionButton(.secondary, in: .roundedRectangle(radius: Theme.Radius.control))
                .disabled(isEnriching)
            }
            if let enrichMessage {
                Text(enrichMessage)
                    .scaledFont(12, weight: .semibold)
                    .foregroundStyle(enrichFailed ? AnyShapeStyle(Theme.Colors.accent) : AnyShapeStyle(.secondary))
                    .padding(.horizontal, Theme.Spacing.xs)
            }
        }
    }

    private func enrich(from number: String) async {
        isEnriching = true
        defer { isEnriching = false }
        enrichFailed = false
        let result: BmwbikeLookup?
        do {
            result = try await viewModel.lookupBmwbike(partNumber: number)
        } catch APIError.offline {
            enrichFailed = true
            enrichMessage = "Nur online möglich."
            return
        } catch {
            enrichFailed = true
            enrichMessage = "BMWBike-Abfrage fehlgeschlagen."
            return
        }
        guard let result else {
            enrichFailed = true
            enrichMessage = "BMWBike kennt die Nummer \(number) nicht."
            return
        }

        var added: [String] = []
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            name = result.name
            added.append("Name")
        }
        if notes.trimmingCharacters(in: .whitespaces).isEmpty,
           let description = result.description, !description.isEmpty {
            notes = description
            added.append("Beschreibung")
        }
        let newSeries = Set(result.seriesIds).subtracting(selectedSeriesIds)
        if !newSeries.isEmpty {
            selectedSeriesIds.formUnion(newSeries)
            added.append(newSeries.count == 1 ? "1 Baureihe" : "\(newSeries.count) Baureihen")
        }
        let hasImage = existingPart?.image != nil || existingPart?.pendingImageUrl != nil
        if !hasImage, importImageUrl == nil, let imageUrl = result.imageUrl {
            importImageUrl = imageUrl
            added.append("Bild")
        }
        enrichMessage = added.isEmpty
            ? "Nichts zu ergänzen — die Daten sind bereits vollständig."
            : "Ergänzt: " + added.joined(separator: ", ") + " (wird beim Speichern übernommen)"
    }

    // MARK: - Initial stock (create mode)

    private var initialStockSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            FormLabel("Erster Bestand")
                .padding(.top, Theme.Spacing.s)
            PartQuantityField(quantity: $stockQuantity)
            CurrencyField(price: $stockPrice, currency: $stockCurrency)
            FormField("Kaufdatum") {
                DatePicker("", selection: $stockPurchaseDate, displayedComponents: .date)
                    .labelsHidden().tint(Theme.Colors.primary)
            }
            StorageLocationPicker(
                viewModel: viewModel,
                selection: $stockLocation,
                newLocationName: $newLocationName
            )
        }
    }

    private var seriesSummary: String {
        if selectedSeriesIds.isEmpty { return "Baureihen wählen …" }
        let names = selectedSeriesIds.sorted().prefix(4).map { viewModel.seriesName($0) }
        let more = selectedSeriesIds.count - names.count
        return names.joined(separator: ", ") + (more > 0 ? " +\(more)" : "")
    }

    private func save() async -> Bool {
        errorMessage = nil
        let trimmedNumber = partNumber.trimmingCharacters(in: .whitespaces)
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard canSave else { return false }
        // Same identity rule as the server (partNumber + name, live parts only)
        // so the pending create can't come back as a 400.
        let duplicate = viewModel.parts.contains {
            $0.clientId != existingPart?.clientId
                && $0.partNumber == trimmedNumber && $0.name == trimmedName
        }
        guard !duplicate else {
            errorMessage = "Ein Teil mit dieser Teilenummer und diesem Namen existiert bereits."
            return false
        }

        let ids = Array(selectedSeriesIds).sorted()
        let saved: Bool
        if let p = existingPart {
            saved = viewModel.updatePart(
                p, partNumber: trimmedNumber, name: trimmedName,
                manufacturer: manufacturer.trimmingCharacters(in: .whitespaces),
                description: notes, isPublic: isPublic, seriesIds: ids,
                oemPartNumber: oemPartNumber, importImageUrl: importImageUrl)
        } else {
            saved = viewModel.createPartWithInitialStock(
                partNumber: trimmedNumber, name: trimmedName,
                manufacturer: manufacturer.trimmingCharacters(in: .whitespaces),
                description: notes, isPublic: isPublic, seriesIds: ids,
                oemPartNumber: oemPartNumber, importImageUrl: importImageUrl,
                quantity: stockQuantity, price: CurrencyField.parse(stockPrice),
                currency: stockCurrency.trimmingCharacters(in: .whitespaces),
                purchaseDate: stockPurchaseDate, storageLocation: stockLocation,
                newLocationName: newLocationName) != nil
        }
        if !saved { errorMessage = "Speichern fehlgeschlagen." }
        return saved
    }
}

// MARK: - Series picker

/// Multi-select over the cached series lookup with an inline "Eigene Baureihe"
/// creator (disabled offline — the lookup is server-managed).
struct SeriesPickerView: View {
    @ObservedObject var viewModel: PartsViewModel
    @Binding var selection: Set<Int>
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var connectivity = ConnectivityMonitor.shared

    @State private var searchText = ""
    @State private var newName = ""
    @State private var newManufacturer = "BMW"
    @State private var creating = false
    @State private var createError: String?

    /// Tree-ordered entries; the search matches the full Familie › Serie ›
    /// Modell path so "GS" finds nodes on every level.
    private var filtered: [(node: ModelSeries, depth: Int)] {
        let entries = ModelSeriesCatalog.tree(viewModel.series)
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return entries }
        return entries.filter {
            ModelSeriesCatalog.path(of: $0.node, in: viewModel.series)
                .lowercased().contains(query)
        }
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: Theme.Spacing.xs) {
                    ForEach(filtered, id: \.node.id) { entry in
                        seriesRow(entry.node, depth: isSearching ? 0 : entry.depth)
                    }
                    createSection
                }
                .padding(Theme.Spacing.l)
                .adaptiveFormWidth()
            }
            .scrollDismissesKeyboard(.interactively)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Suchen …")
            .autocorrectionDisabled()
            .navigationTitle("Baureihen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) { dismiss() }
                        .accessibilityLabel("Fertig")
                }
            }
        }
        .task { await viewModel.loadSeries() }
    }

    private func seriesRow(_ series: ModelSeries, depth: Int) -> some View {
        let isSelected = selection.contains(series.id)
        return Button {
            if isSelected { selection.remove(series.id) } else { selection.insert(series.id) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(isSearching
                         ? ModelSeriesCatalog.path(of: series, in: viewModel.series)
                         : series.displayName)
                        .scaledFont(14, weight: depth == 0 ? .bold : .semibold)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(ModelSeriesCatalog.levelLabel(
                            forDepth: ModelSeriesCatalog.depth(of: series, in: viewModel.series))
                         + (series.userId != nil ? " · Eigene" : ""))
                        .scaledFont(10, weight: .semibold)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .scaledFont(18)
                    .foregroundStyle(isSelected ? AnyShapeStyle(Theme.Colors.primary) : AnyShapeStyle(.tertiary))
            }
            .padding(.vertical, 10)
            .padding(.trailing, 14)
            .padding(.leading, 14 + CGFloat(depth) * 18)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.field)
                    .fill(isSelected ? Theme.Colors.primary.opacity(0.12) : Color.primary.opacity(0.04))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var createSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            FormLabel("Eigene Baureihe")
                .padding(.top, Theme.Spacing.m)

            if !connectivity.isOnline {
                Text("Nur online möglich — Baureihen werden zentral verwaltet.")
                    .scaledFont(12)
                    .foregroundStyle(.tertiary)
            } else {
                HStack(spacing: Theme.Spacing.s) {
                    TextField("", text: $newManufacturer, prompt: formPrompt("Hersteller"))
                        .frame(maxWidth: 110)
                    TextField("", text: $newName, prompt: formPrompt("z. B. R 90 S"))
                    Button {
                        Task { await createSeries() }
                    } label: {
                        if creating {
                            ProgressView()
                        } else {
                            Image(systemName: "plus.circle.fill")
                                .scaledFont(22)
                                .foregroundStyle(Theme.Colors.primary)
                        }
                    }
                    .disabled(creating || newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityLabel("Baureihe anlegen")
                }
                .formFieldBox()

                if let createError {
                    FormErrorBanner(message: createError)
                }
            }
        }
    }

    private func createSeries() async {
        creating = true
        createError = nil
        let created = await viewModel.createSeries(
            name: newName.trimmingCharacters(in: .whitespaces),
            manufacturer: newManufacturer.trimmingCharacters(in: .whitespaces).isEmpty
                ? "BMW" : newManufacturer.trimmingCharacters(in: .whitespaces))
        if let created {
            selection.insert(created.id)
            newName = ""
        } else {
            createError = "Baureihe konnte nicht angelegt werden."
        }
        creating = false
    }
}
