import SwiftUI

/// Detail sheet for a catalog part: fitment + description, the stock entries
/// ("Bestand") and the consumption history ("Verbrauch"), with add-affordances
/// for both. All writes are offline-first via PartsViewModel.
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
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                header
                catalogCard
                stockSection
                consumptionSection
            }
            .padding(Theme.Spacing.l)
            .padding(.bottom, 40)
        }
        .background(Color.clear)
        .sheet(isPresented: $showingEdit) {
            AddPartView(viewModel: viewModel, existingPart: part)
                .presentationDetents([.large])
                .presentationCornerRadius(Theme.Glass.sheetRadius)
                .presentationBackground(.regularMaterial)
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingAddStock) {
            AddPartStockView(viewModel: viewModel, part: part)
                .presentationDetents([.large])
                .presentationCornerRadius(Theme.Glass.sheetRadius)
                .presentationBackground(.regularMaterial)
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $editingStock) { stock in
            AddPartStockView(viewModel: viewModel, part: part, existingStock: stock)
                .presentationDetents([.large])
                .presentationCornerRadius(Theme.Glass.sheetRadius)
                .presentationBackground(.regularMaterial)
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingAddConsumption) {
            AddPartConsumptionView(viewModel: viewModel, part: part)
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(Theme.Glass.sheetRadius)
                .presentationBackground(.regularMaterial)
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingPrintLabel) {
            if let content = partLabelContent {
                PrintLabelView(content: content)
                    .presentationDetents([.large])
                    .presentationCornerRadius(Theme.Glass.sheetRadius)
                    .presentationBackground(.regularMaterial)
                    .presentationDragIndicator(.visible)
            }
        }
        .sheet(item: $printingLocation) { location in
            if let content = locationLabelContent(location) {
                PrintLabelView(content: content)
                    .presentationDetents([.large])
                    .presentationCornerRadius(Theme.Glass.sheetRadius)
                    .presentationBackground(.regularMaterial)
                    .presentationDragIndicator(.visible)
            }
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
        let path = viewModel.locationPath(location)
        return LabelContent(
            url: LabelWebLinks.storageLocationURL(serverId: serverId),
            code: nil,
            title: location.name,
            subtitle: path == location.name ? nil : path,
            footer: "MotoManager · Lagerort #\(serverId)"
        )
    }

    // MARK: - Header & catalog

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(part.name)
                    .font(.system(size: 24, weight: .heavy))
                    .foregroundColor(.white)
                Text(part.partNumber)
                    .font(.system(size: 13, weight: .semibold))
                    .monospaced()
                    .foregroundColor(.white.opacity(0.6))
            }
            Spacer()
            Button { showingPrintLabel = true } label: {
                Image(systemName: "printer.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.white.opacity(0.12)))
            }
            .accessibilityLabel("Etikett drucken")
            .disabled(part.serverId == nil)
            .opacity(part.serverId == nil ? 0.4 : 1)
            Button { showingEdit = true } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.white.opacity(0.12)))
            }
            .accessibilityLabel("Bearbeiten")
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.white.opacity(0.12)))
            }
            .accessibilityLabel("Schließen")
        }
    }

    private var catalogCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let imageURL = part.image {
                RemoteImageView(url: imageURL, maxPixelWidth: 800)
                    .frame(maxWidth: .infinity)
                    .frame(height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Glass.fieldRadius))
            }
            HStack(spacing: 8) {
                infoPill(part.manufacturer, icon: "building.2.fill")
                if part.isPublic {
                    infoPill("Öffentlich", icon: "globe")
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(onHand)")
                        .font(.system(size: 26, weight: .heavy))
                        .monospacedDigit()
                        .foregroundColor(onHand > 0 ? Theme.Colors.primary : .white.opacity(0.35))
                    Text("AUF LAGER")
                        .font(.system(size: 8, weight: .heavy)).tracking(1.2)
                        .foregroundColor(.white.opacity(0.4))
                    if totalStockValue > 0 {
                        Text(Formatters.currency(totalStockValue, code: "CHF"))
                            .font(.system(size: 12, weight: .bold))
                            .monospacedDigit()
                            .foregroundColor(.white.opacity(0.7))
                            .padding(.top, 6)
                        Text("EINKAUFSWERT")
                            .font(.system(size: 8, weight: .heavy)).tracking(1.2)
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
            }

            if !part.seriesIds.isEmpty {
                seriesChips
            }

            if let description = part.partDescription, !description.isEmpty {
                Text(description)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.l).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.l).stroke(Theme.Glass.border, lineWidth: 0.5))
    }

    private var seriesChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(part.seriesIds, id: \.self) { id in
                    Text(viewModel.seriesName(id))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Capsule().fill(Color.white.opacity(0.10)))
                }
            }
        }
    }

    private func infoPill(_ text: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9, weight: .bold))
            Text(text).font(.system(size: 11, weight: .semibold))
        }
        .foregroundColor(.white.opacity(0.75))
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(Capsule().fill(Color.white.opacity(0.10)))
    }

    // MARK: - Stock

    private var stockSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Bestand", count: stocks.count)

            Button { showingAddStock = true } label: {
                ctaLabel("Bestand hinzufügen", icon: "plus")
            }
            .buttonStyle(.plain)

            if stocks.isEmpty {
                Text("Noch kein Bestand erfasst.")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.5))
            } else {
                VStack(spacing: 8) {
                    ForEach(stocks, id: \.clientId) { stock in
                        Button { editingStock = stock } label: {
                            stockRow(stock)
                        }
                        .buttonStyle(.plain)
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
                                viewModel.deleteStock(stock)
                            } label: {
                                Label("Löschen", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
    }

    private func stockRow(_ stock: SDPartStock) -> some View {
        HStack(spacing: 12) {
            Text("\(stock.quantity)×")
                .font(.system(size: 16, weight: .heavy))
                .monospacedDigit()
                .foregroundColor(Theme.Colors.primary)
                .frame(width: 44, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if let price = stock.price {
                        let unit = price / Double(max(1, stock.quantity))
                        Text("\(Formatters.currency(unit, code: stock.currency ?? "CHF")) / Stk.")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                        if stock.quantity > 1 {
                            Text("· \(Formatters.currency(price, code: stock.currency ?? "CHF")) gesamt")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.55))
                        }
                    } else {
                        Text("Ohne Preis")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    if let date = stock.purchaseDate {
                        Text("· \(Formatters.mediumDate(date))")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.55))
                    }
                    if stock.isUsed {
                        Text("GEBRAUCHT")
                            .font(.system(size: 8, weight: .heavy)).tracking(1.0)
                            .foregroundColor(.orange)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color.orange.opacity(0.16)))
                    }
                }
                if let path = viewModel.locationPath(viewModel.storageLocation(clientId: stock.storageLocationClientId)) {
                    HStack(spacing: 4) {
                        Image(systemName: "archivebox.fill")
                            .font(.system(size: 9))
                        Text(path)
                            .lineLimit(1)
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.45))
                }
                if let notes = stock.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.3))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Theme.Glass.fieldRadius).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: Theme.Glass.fieldRadius).stroke(Theme.Glass.border, lineWidth: 0.5))
    }

    // MARK: - Consumption

    private var consumptionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Verbrauch", count: consumptions.count)

            Button { showingAddConsumption = true } label: {
                ctaLabel("Verbrauch erfassen", icon: "minus")
            }
            .buttonStyle(.plain)
            .disabled(onHand < 1)
            .opacity(onHand < 1 ? 0.5 : 1)

            if consumptions.isEmpty {
                Text("Noch kein Verbrauch erfasst. Teile lassen sich auch direkt beim Erfassen einer Wartung verbuchen.")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.5))
            } else {
                VStack(spacing: 8) {
                    ForEach(consumptions, id: \.clientId) { consumption in
                        consumptionRow(consumption)
                            .contextMenu {
                                Button(role: .destructive) {
                                    viewModel.deleteConsumption(consumption)
                                } label: {
                                    Label("Löschen (Bestand zurückbuchen)", systemImage: "arrow.uturn.backward")
                                }
                            }
                    }
                }
            }
        }
    }

    private func consumptionRow(_ consumption: SDPartConsumption) -> some View {
        let repair = viewModel.maintenanceRecord(for: consumption)
        return HStack(spacing: 12) {
            Text("−\(consumption.quantity)")
                .font(.system(size: 16, weight: .heavy))
                .monospacedDigit()
                .foregroundColor(Theme.Colors.accent)
                .frame(width: 44, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(Formatters.mediumDate(consumption.date))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                if let repair {
                    HStack(spacing: 4) {
                        Image(systemName: "wrench.and.screwdriver.fill")
                            .font(.system(size: 9))
                        Text(repair.recordDescription ?? repair.summary ?? repair.recordType)
                            .lineLimit(1)
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
                } else if consumption.maintenanceClientId != nil || consumption.maintenanceServerId != nil {
                    Text("Verknüpfte Wartung")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.5))
                }
                if let notes = consumption.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Theme.Glass.fieldRadius).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: Theme.Glass.fieldRadius).stroke(Theme.Glass.border, lineWidth: 0.5))
    }

    // MARK: - Shared bits

    private func sectionHeader(_ label: String, count: Int) -> some View {
        HStack {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .heavy)).tracking(2)
                .foregroundColor(.white.opacity(0.55))
            Spacer()
            Text("\(count) \(count == 1 ? "Eintrag" : "Einträge")")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
        }
    }

    private func ctaLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
            Text(title)
                .font(.system(size: 13, weight: .bold))
            Spacer(minLength: 0)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: Theme.Glass.fieldRadius).fill(Color.white.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: Theme.Glass.fieldRadius).stroke(Theme.Glass.border, lineWidth: 0.5))
    }
}

// MARK: - Add/edit stock sheet

/// Create/edit a stock entry: quantity, price + currency, purchase date,
/// storage location (with inline create), notes.
struct AddPartStockView: View {
    @ObservedObject var viewModel: PartsViewModel
    let part: SDPart
    let existingStock: SDPartStock?
    @Environment(\.dismiss) private var dismiss

    @State private var quantity: Int
    @State private var price: String
    @State private var currency: String
    @State private var purchaseDate: Date
    @State private var selectedLocation: SDStorageLocation?
    @State private var newLocationName = ""
    @State private var notes: String
    @State private var isUsed: Bool
    @State private var savedAnim = false

    init(viewModel: PartsViewModel, part: SDPart, existingStock: SDPartStock? = nil) {
        self.viewModel = viewModel
        self.part = part
        self.existingStock = existingStock
        if let s = existingStock {
            _quantity = State(initialValue: s.quantity)
            _price = State(initialValue: s.price.map { String($0) } ?? "")
            _currency = State(initialValue: s.currency ?? "CHF")
            let f = ISO8601DateFormatter(); f.formatOptions = [.withFullDate]
            _purchaseDate = State(initialValue: s.purchaseDate.flatMap { f.date(from: $0) } ?? Date())
            _selectedLocation = State(initialValue: nil)
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
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                header

                field("MENGE") {
                    Stepper(value: $quantity, in: 1...999) {
                        Text("\(quantity) Stück")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .colorScheme(.dark)
                }
                HStack(spacing: Theme.Spacing.m) {
                    field("PREIS (GESAMT)") {
                        TextField("", text: $price, prompt: Text("0").foregroundColor(.white.opacity(0.3)))
                            .keyboardType(.decimalPad).foregroundColor(.white)
                    }
                    field("WÄHRUNG") {
                        TextField("", text: $currency).foregroundColor(.white)
                            .textInputAutocapitalization(.characters)
                    }
                }
                field("KAUFDATUM") {
                    DatePicker("", selection: $purchaseDate, displayedComponents: .date)
                        .labelsHidden().colorScheme(.dark).tint(Theme.Colors.primary)
                }
                field("LAGERORT") {
                    locationPicker
                }
                field("NEUER LAGERORT (OPTIONAL)") {
                    TextField("", text: $newLocationName,
                              prompt: Text("z. B. Regal A · Kiste 3").foregroundColor(.white.opacity(0.3)))
                        .foregroundColor(.white)
                }
                field("NOTIZEN") {
                    TextField("", text: $notes,
                              prompt: Text("z. B. Kauf bei Motorradteile Meyer").foregroundColor(.white.opacity(0.3)),
                              axis: .vertical)
                        .lineLimit(2...4).foregroundColor(.white)
                }
                field("ZUSTAND") {
                    Toggle(isOn: $isUsed) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Gebrauchtteil")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                            Text("z. B. aus einem Motorrad ausgeschlachtet")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.45))
                        }
                    }
                    .tint(Theme.Colors.primary)
                }

                saveButton
                if let existingStock {
                    Button(role: .destructive) {
                        viewModel.deleteStock(existingStock)
                        dismiss()
                    } label: {
                        Text("Löschen").frame(maxWidth: .infinity)
                            .foregroundColor(Theme.Colors.accent).padding(.vertical, 12)
                    }
                }
            }
            .padding(Theme.Spacing.l)
        }
        .background(Color.clear)
        .onAppear {
            if let s = existingStock {
                selectedLocation = viewModel.storageLocation(clientId: s.storageLocationClientId)
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(existingStock == nil ? "Bestand hinzufügen" : "Bestand bearbeiten")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundColor(.white)
                Text(part.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.55))
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.white.opacity(0.12)))
            }
            .accessibilityLabel("Schließen")
        }
    }

    private var locationPicker: some View {
        Menu {
            Button("Kein Lagerort") { selectedLocation = nil }
            ForEach(viewModel.storageLocations, id: \.clientId) { location in
                Button(viewModel.locationPath(location) ?? location.name) {
                    selectedLocation = location
                }
            }
        } label: {
            HStack {
                Text(selectedLocation.flatMap { viewModel.locationPath($0) } ?? "Kein Lagerort")
                    .foregroundColor(selectedLocation == nil ? .white.opacity(0.35) : .white)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .heavy)).tracking(1.4)
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

    private func save() {
        // Inline location creation wins over the picker when both are set.
        var location = selectedLocation
        let newName = newLocationName.trimmingCharacters(in: .whitespaces)
        if !newName.isEmpty {
            location = viewModel.createStorageLocation(name: newName, parent: selectedLocation)
        }
        let priceValue = Double(price.replacingOccurrences(of: ",", with: "."))
        if let s = existingStock {
            viewModel.updateStock(
                s, quantity: quantity, price: priceValue, currency: currency,
                purchaseDate: purchaseDate, storageLocation: location, notes: notes,
                isUsed: isUsed)
        } else {
            viewModel.addStock(
                part: part, quantity: quantity, price: priceValue, currency: currency,
                purchaseDate: purchaseDate, storageLocation: location, notes: notes,
                isUsed: isUsed)
        }
        withAnimation { savedAnim = true }
        Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            dismiss()
        }
    }
}

// MARK: - Manual consumption sheet

/// "Verbrauch erfassen" — a manual correction not tied to a repair. The
/// quantity is capped at the local on-hand, mirroring the server rule.
struct AddPartConsumptionView: View {
    @ObservedObject var viewModel: PartsViewModel
    let part: SDPart
    @Environment(\.dismiss) private var dismiss

    @State private var quantity = 1
    @State private var date = Date()
    @State private var notes = ""
    @State private var savedAnim = false
    @State private var errorText: String?

    private var onHand: Int { viewModel.onHand(for: part) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Verbrauch erfassen")
                            .font(.system(size: 22, weight: .heavy))
                            .foregroundColor(.white)
                        Text("\(part.name) · \(onHand) auf Lager")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.55))
                    }
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.white.opacity(0.12)))
                    }
                    .accessibilityLabel("Schließen")
                }

                field("MENGE") {
                    Stepper(value: $quantity, in: 1...max(1, onHand)) {
                        Text("\(quantity) Stück")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .colorScheme(.dark)
                }
                field("DATUM") {
                    DatePicker("", selection: $date, displayedComponents: .date)
                        .labelsHidden().colorScheme(.dark).tint(Theme.Colors.primary)
                }
                field("NOTIZ") {
                    TextField("", text: $notes,
                              prompt: Text("z. B. defekt / verloren").foregroundColor(.white.opacity(0.3)))
                        .foregroundColor(.white)
                }

                if let errorText {
                    Text(errorText)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.Colors.accent)
                }

                Button(action: save) {
                    Text(savedAnim ? "Gespeichert ✓" : "Speichern").frame(maxWidth: .infinity)
                }
                .buttonStyle(ModernButtonStyle())
            }
            .padding(Theme.Spacing.l)
        }
        .background(Color.clear)
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .heavy)).tracking(1.4)
                .foregroundColor(Theme.Glass.mutedText)
            content()
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: Theme.Glass.fieldRadius).fill(Color.white.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: Theme.Glass.fieldRadius).stroke(Theme.Glass.border, lineWidth: 0.5))
        }
    }

    private func save() {
        guard viewModel.addConsumption(part: part, quantity: quantity, date: date, notes: notes) else {
            errorText = "Nicht genug Bestand."
            return
        }
        withAnimation { savedAnim = true }
        Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            dismiss()
        }
    }
}
