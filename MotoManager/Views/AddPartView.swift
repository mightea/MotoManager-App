import SwiftUI

/// Create/edit a catalog part (offline-first). Fitment is picked from the
/// cached series lookup; custom series can be created inline (online only).
struct AddPartView: View {
    @ObservedObject var viewModel: PartsViewModel
    let existingPart: SDPart?
    @Environment(\.dismiss) private var dismiss

    @State private var partNumber: String
    @State private var name: String
    @State private var manufacturer: String
    @State private var notes: String
    @State private var isPublic: Bool
    @State private var selectedSeriesIds: Set<Int>
    @State private var showingSeriesPicker = false
    @State private var confirmingDelete = false
    @State private var savedAnim = false
    @State private var validationError: String?

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
            _notes = State(initialValue: p.partDescription ?? "")
            _isPublic = State(initialValue: p.isPublic)
            _selectedSeriesIds = State(initialValue: Set(p.seriesIds))
        } else {
            _partNumber = State(initialValue: "")
            _name = State(initialValue: "")
            _manufacturer = State(initialValue: "BMW")
            _notes = State(initialValue: "")
            _isPublic = State(initialValue: false)
            _selectedSeriesIds = State(initialValue: [])
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                header

                field("TEILENUMMER") {
                    TextField("", text: $partNumber,
                              prompt: Text("z. B. 11 42 7 673 541").foregroundColor(.white.opacity(0.3)))
                        .foregroundColor(.white)
                        .autocorrectionDisabled()
                }
                field("NAME") {
                    TextField("", text: $name,
                              prompt: Text("z. B. Ölfilter").foregroundColor(.white.opacity(0.3)))
                        .foregroundColor(.white)
                }
                field("HERSTELLER") {
                    TextField("", text: $manufacturer).foregroundColor(.white)
                }
                field("BAUREIHEN") {
                    Button { showingSeriesPicker = true } label: {
                        HStack {
                            Text(seriesSummary)
                                .foregroundColor(selectedSeriesIds.isEmpty ? .white.opacity(0.35) : .white)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .scaledFont(11, weight: .semibold)
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }
                    .buttonStyle(.plain)
                }
                field("BESCHREIBUNG") {
                    TextField("", text: $notes,
                              prompt: Text("z. B. passt auch für Ölkühler-Variante").foregroundColor(.white.opacity(0.3)),
                              axis: .vertical)
                        .lineLimit(2...5).foregroundColor(.white)
                }

                Toggle(isOn: $isPublic) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Öffentlich teilen")
                            .scaledFont(14, weight: .bold)
                            .foregroundColor(.white)
                        Text("Andere Nutzer sehen Teiledaten und Verfügbarkeit — nie Preise oder Lagerorte.")
                            .scaledFont(11)
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
                .tint(Theme.Colors.primary)
                .padding(.horizontal, 4)

                if existingPart == nil {
                    initialStockSection
                }

                if let validationError {
                    Text(validationError)
                        .scaledFont(12, weight: .semibold)
                        .foregroundColor(Theme.Colors.accent)
                }

                saveButton
                if existingPart != nil { deleteButton }
            }
            .padding(Theme.Spacing.l)
        }
        .background(Color.clear)
        .sheet(isPresented: $showingSeriesPicker) {
            SeriesPickerView(viewModel: viewModel, selection: $selectedSeriesIds)
                .glassSheet()
        }
        .alert("Teil löschen?", isPresented: $confirmingDelete) {
            Button("Abbrechen", role: .cancel) { }
            Button("Löschen", role: .destructive) {
                guard let part = existingPart,
                      viewModel.deletePart(part) else { return }
                dismiss()
            }
        } message: {
            Text("Bestand und Verbrauch dieses Teils werden ebenfalls entfernt.")
        }
    }

    // MARK: - Initial stock (create mode)

    private var initialStockSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            Text("ERSTER BESTAND")
                .scaledFont(11, weight: .heavy).tracking(2)
                .foregroundColor(.white.opacity(0.55))

            field("MENGE") {
                Stepper(value: $stockQuantity, in: 1...999) {
                    Text("\(stockQuantity) Stück")
                        .scaledFont(15, weight: .bold)
                        .foregroundColor(.white)
                }
                .colorScheme(.dark)
            }
            HStack(spacing: Theme.Spacing.m) {
                field("PREIS (GESAMT)") {
                    TextField("", text: $stockPrice, prompt: Text("0").foregroundColor(.white.opacity(0.3)))
                        .keyboardType(.decimalPad).foregroundColor(.white)
                }
                field("WÄHRUNG") {
                    TextField("", text: $stockCurrency).foregroundColor(.white)
                        .textInputAutocapitalization(.characters)
                }
            }
            field("KAUFDATUM") {
                DatePicker("", selection: $stockPurchaseDate, displayedComponents: .date)
                    .labelsHidden().colorScheme(.dark).tint(Theme.Colors.primary)
            }
            field("LAGERORT") {
                Menu {
                    Button("Kein Lagerort") { stockLocation = nil }
                    ForEach(viewModel.storageLocations, id: \.clientId) { location in
                        Button(viewModel.locationPath(location) ?? location.name) {
                            stockLocation = location
                        }
                    }
                } label: {
                    HStack {
                        Text(stockLocation.flatMap { viewModel.locationPath($0) } ?? "Kein Lagerort")
                            .foregroundColor(stockLocation == nil ? .white.opacity(0.35) : .white)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .scaledFont(11, weight: .semibold)
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
            }
            field("NEUER LAGERORT (OPTIONAL)") {
                TextField("", text: $newLocationName,
                          prompt: Text("z. B. Regal A · Kiste 3").foregroundColor(.white.opacity(0.3)))
                    .foregroundColor(.white)
            }
        }
    }

    private var seriesSummary: String {
        if selectedSeriesIds.isEmpty { return "Baureihen wählen …" }
        let names = selectedSeriesIds.sorted().prefix(4).map { viewModel.seriesName($0) }
        let more = selectedSeriesIds.count - names.count
        return names.joined(separator: ", ") + (more > 0 ? " +\(more)" : "")
    }

    private var header: some View {
        HStack {
            Text(existingPart == nil ? "Teil hinzufügen" : "Teil bearbeiten")
                .scaledFont(22, weight: .heavy)
                .foregroundColor(.white)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .scaledFont(14, weight: .bold)
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.white.opacity(0.12)))
            }
            .accessibilityLabel("Schließen")
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .scaledFont(10, weight: .heavy).tracking(1.4)
                .foregroundColor(Theme.Glass.mutedText)
            content()
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: Theme.Glass.fieldRadius).fill(Color.white.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: Theme.Glass.fieldRadius).stroke(Theme.Glass.border, lineWidth: 0.5))
        }
    }

    private var saveButton: some View {
        Button(action: save) {
            Text(savedAnim ? "Gespeichert ✓" : "Speichern").frame(maxWidth: .infinity)
        }
        .buttonStyle(ModernButtonStyle())
        .padding(.top, Theme.Spacing.s)
    }

    private var deleteButton: some View {
        Button(role: .destructive) { confirmingDelete = true } label: {
            Text("Löschen").frame(maxWidth: .infinity).foregroundColor(Theme.Colors.accent).padding(.vertical, 12)
        }
    }

    private func save() {
        let trimmedNumber = partNumber.trimmingCharacters(in: .whitespaces)
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedNumber.isEmpty, !trimmedName.isEmpty else {
            validationError = "Teilenummer und Name sind erforderlich."
            return
        }
        // Same identity rule as the server (partNumber + name, live parts only)
        // so the pending create can't come back as a 400.
        let duplicate = viewModel.parts.contains {
            $0.clientId != existingPart?.clientId
                && $0.partNumber == trimmedNumber && $0.name == trimmedName
        }
        guard !duplicate else {
            validationError = "Ein Teil mit dieser Teilenummer und diesem Namen existiert bereits."
            return
        }

        let ids = Array(selectedSeriesIds).sorted()
        if let p = existingPart {
            guard viewModel.updatePart(
                p, partNumber: trimmedNumber, name: trimmedName,
                manufacturer: manufacturer.trimmingCharacters(in: .whitespaces),
                description: notes, isPublic: isPublic, seriesIds: ids) else { return }
        } else {
            let priceValue = Double(stockPrice.replacingOccurrences(of: ",", with: "."))
            guard viewModel.createPartWithInitialStock(
                partNumber: trimmedNumber, name: trimmedName,
                manufacturer: manufacturer.trimmingCharacters(in: .whitespaces),
                description: notes, isPublic: isPublic, seriesIds: ids,
                quantity: stockQuantity, price: priceValue,
                currency: stockCurrency.trimmingCharacters(in: .whitespaces),
                purchaseDate: stockPurchaseDate, storageLocation: stockLocation,
                newLocationName: newLocationName) != nil else { return }
        }
        withAnimation { savedAnim = true }
        Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            dismiss()
        }
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
        VStack(spacing: 0) {
            HStack {
                Text("Baureihen")
                    .scaledFont(22, weight: .heavy)
                    .foregroundColor(.white)
                Spacer()
                Button("Fertig") { dismiss() }
                    .scaledFont(15, weight: .bold)
                    .foregroundColor(Theme.Colors.primary)
            }
            .padding(Theme.Spacing.l)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .scaledFont(13, weight: .semibold)
                    .foregroundColor(.white.opacity(0.5))
                TextField("", text: $searchText,
                          prompt: Text("Suchen …").foregroundColor(.white.opacity(0.35)))
                    .foregroundColor(.white)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: Theme.Glass.fieldRadius).fill(Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: Theme.Glass.fieldRadius).stroke(Theme.Glass.border, lineWidth: 0.5))
            .padding(.horizontal, Theme.Spacing.l)

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(filtered, id: \.node.id) { entry in
                        seriesRow(entry.node, depth: isSearching ? 0 : entry.depth)
                    }
                    createSection
                }
                .padding(Theme.Spacing.l)
            }
        }
        .background(Color.clear)
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
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(ModelSeriesCatalog.levelLabel(
                            forDepth: ModelSeriesCatalog.depth(of: series, in: viewModel.series))
                         + (series.userId != nil ? " · Eigene" : ""))
                        .scaledFont(10, weight: .semibold)
                        .foregroundColor(.white.opacity(0.4))
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .scaledFont(18)
                    .foregroundColor(isSelected ? Theme.Colors.primary : .white.opacity(0.25))
            }
            .padding(.vertical, 10)
            .padding(.trailing, 14)
            .padding(.leading, 14 + CGFloat(depth) * 18)
            .background(
                RoundedRectangle(cornerRadius: Theme.Glass.fieldRadius)
                    .fill(isSelected ? Theme.Colors.primary.opacity(0.12) : Color.white.opacity(0.04))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var createSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("EIGENE BAUREIHE")
                .scaledFont(10, weight: .heavy).tracking(1.4)
                .foregroundColor(Theme.Glass.mutedText)
                .padding(.top, Theme.Spacing.m)

            if !connectivity.isOnline {
                Text("Nur online möglich — Baureihen werden zentral verwaltet.")
                    .scaledFont(12)
                    .foregroundColor(.white.opacity(0.5))
            } else {
                HStack(spacing: 8) {
                    TextField("", text: $newManufacturer,
                              prompt: Text("Hersteller").foregroundColor(.white.opacity(0.35)))
                        .foregroundColor(.white)
                        .frame(maxWidth: 110)
                    TextField("", text: $newName,
                              prompt: Text("z. B. R 90 S").foregroundColor(.white.opacity(0.35)))
                        .foregroundColor(.white)
                    Button {
                        Task { await createSeries() }
                    } label: {
                        if creating {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "plus.circle.fill")
                                .scaledFont(22)
                                .foregroundColor(Theme.Colors.primary)
                        }
                    }
                    .disabled(creating || newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: Theme.Glass.fieldRadius).fill(Color.white.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: Theme.Glass.fieldRadius).stroke(Theme.Glass.border, lineWidth: 0.5))

                if let createError {
                    Text(createError)
                        .scaledFont(12, weight: .semibold)
                        .foregroundColor(Theme.Colors.accent)
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
