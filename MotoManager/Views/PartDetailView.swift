import SwiftUI
import SwiftData

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
    /// "Beim Mangel verbuchen": the defect the consumption is booked for.
    @State private var bookingIssue: SDIssue?
    @State private var showingPrintLabel = false
    @State private var printingLocation: SDStorageLocation?
    @State private var didAutoDismiss = false
    /// Row deletes (swipe/context menu) wait here for confirmation.
    @State private var pendingStockDelete: SDPartStock?
    @State private var pendingConsumptionDelete: SDPartConsumption?
    /// Why the selected bike will need this part soon, if it will.
    let neededFor: String?
    /// Open issues of the selected bike, to link this part to by hand.
    let openIssues: [(id: UUID, title: String)]
    @ObservedObject private var planning = PartsPlanningStore.shared
    @ObservedObject private var issueLinks = IssuePartLinkStore.shared
    /// Captured at init so the auto-pop guard never reads a deleted model.
    private let partClientId: UUID

    init(part: SDPart, viewModel: PartsViewModel, neededFor: String? = nil,
         openIssues: [(id: UUID, title: String)] = []) {
        self.part = part
        self.viewModel = viewModel
        self.neededFor = neededFor
        self.openIssues = openIssues
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
        List {
            heroSection
            linkedIssuesSection
            stockCardSection
            if let neededFor {
                Section {
                    Label {
                        Text("Gebraucht für ").foregroundStyle(.secondary) + Text(neededFor).fontWeight(.semibold)
                    } icon: {
                        Image(systemName: "calendar.badge.clock").foregroundStyle(Theme.Colors.primary)
                    }
                    .font(.subheadline)
                }
            }
            placesSection
            if viewModel.priceHistory(for: part).count >= 2 {
                Section("Preis pro Stück") {
                    PartPriceChart(points: viewModel.priceHistory(for: part))
                        .padding(.vertical, Theme.Spacing.xs)
                }
            }
            if let description = part.partDescription, !description.isEmpty {
                Section("Beschreibung") {
                    Text(NoteBrandPalette.display(description: description, markup: part.descriptionMarkup))
                        .scaledFont(13)
                        .foregroundStyle(.secondary)
                }
            }
            historySection
        }
        .workspaceListStyle()
        .scrollContentBackground(.hidden)
        .frame(maxWidth: 800)
        .frame(maxWidth: .infinity)
        .background(Theme.Colors.background.ignoresSafeArea())
        .toolbar(.visible, for: .navigationBar)
        .navigationTitle(part.name)
        .navigationBarTitleDisplayMode(.inline)
        // The header below already shows the name; the bar keeps it only
        // for the back button's history menu.
        .toolbar {
            ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1).accessibilityHidden(true) }
        }
        .accessibilityIdentifier("part.detail")
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
                Menu {
                    Button(planning.manual.contains(part.clientId) ? "Auf der Einkaufsliste" : "Auf die Einkaufsliste",
                           systemImage: "cart.badge.plus") { planning.addToList(part.clientId) }
                        .disabled(planning.manual.contains(part.clientId))
                    if !openIssues.isEmpty {
                        Menu("Für Mangel vormerken") {
                            ForEach(openIssues, id: \.id) { issue in
                                Toggle(issue.title, isOn: Binding(
                                    get: { issueLinks.isLinked(issue: issue.id, part: part.clientId) },
                                    set: { issueLinks.setLinked($0, issue: issue.id, part: part.clientId) }))
                            }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("Mehr")
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
                .glassSheet()
        }
        .sheet(item: $bookingIssue) { issue in
            AddPartConsumptionView(viewModel: viewModel, part: part, initialNotes: "Mangel: \(issue.title)")
                .glassSheet()
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

    // MARK: - Linked defects

    /// Open defects this part is linked to, on any bike (newest first).
    private var linkedOpenIssues: [SDIssue] {
        let ids = issueLinks.issues(forPart: part.clientId)
        guard !ids.isEmpty else { return [] }
        let context = PersistenceController.shared.mainContext
        return ((try? context.fetch(FetchDescriptor<SDIssue>())) ?? [])
            .filter { ids.contains($0.clientId) && $0.syncState != .pendingDelete && $0.status.lowercased() != "done" }
            .sorted { $0.date > $1.date }
    }

    /// "Passt zu offenem Mangel" — mirrors the webapp's part-issue callout:
    /// bike · title, priority and since when, a shortcut to book one piece
    /// against the defect, and × (or swipe) to unlink.
    @ViewBuilder
    private var linkedIssuesSection: some View {
        let issues = linkedOpenIssues
        if !issues.isEmpty {
            Section {
                ForEach(issues, id: \.clientId) { issue in
                    linkedIssueRow(issue)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button("Verknüpfung lösen", systemImage: "link.badge.minus", role: .destructive) {
                                issueLinks.setLinked(false, issue: issue.clientId, part: part.clientId)
                            }
                        }
                }
            } header: {
                Label(issues.count == 1 ? "Passt zu offenem Mangel" : "Passt zu offenen Mängeln",
                      systemImage: "link")
                    .foregroundStyle(.orange)
            }
        }
    }

    private func linkedIssueRow(_ issue: SDIssue) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m - 4) {
            VStack(alignment: .leading, spacing: 6) {
                Text([bikeLabel(issue.motorcycleId), issue.title].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(Self.priorityLine(priority: issue.priority, date: issue.date).uppercased())
                    .scaledFont(11, weight: .semibold)
                    .monospaced()
                    .foregroundStyle(.secondary)
                Button {
                    bookingIssue = issue
                } label: {
                    Label("Beim Mangel verbuchen", systemImage: "minus.circle")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(Theme.Colors.primary)
                .disabled(onHand <= 0)
                .accessibilityIdentifier("part.issue.book.\(issue.clientId)")
            }
            Spacer(minLength: 0)
            Button {
                issueLinks.setLinked(false, issue: issue.clientId, part: part.clientId)
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Verknüpfung mit \(issue.title) lösen")
        }
        .padding(.vertical, 2)
    }

    private func bikeLabel(_ motorcycleId: Int) -> String? {
        cachedMotorcycle(id: motorcycleId).map { "\($0.make) \($0.model)" }
    }

    /// "Hoch · seit 01.10.2026", like the webapp.
    static func priorityLine(priority: String, date: String) -> String {
        let label = switch priority.lowercased() {
        case "high": "Hoch"
        case "low": "Niedrig"
        default: "Mittel"
        }
        let day = date.prefix(10).split(separator: "-")
        guard day.count == 3 else { return label }
        return "\(label) · seit \(day[2]).\(day[1]).\(day[0])"
    }

    // MARK: - Hero

    private var heroSection: some View {
        Section {
            HStack(alignment: .center, spacing: Theme.Spacing.m - 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.Radius.field)
                        .fill(Theme.Colors.primary.opacity(0.10))
                    if let imageURL = part.image {
                        RemoteImageView(url: imageURL, maxPixelWidth: 400)
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "shippingbox")
                            .scaledFont(28, weight: .semibold)
                            .foregroundStyle(Theme.Colors.primary)
                    }
                }
                .frame(width: 76, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.field))
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(part.name)
                        .font(.title2.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 0) {
                        if !part.manufacturer.isEmpty { Text("\(part.manufacturer) · ") }
                        Text(part.partNumber).monospaced().textSelection(.enabled)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    if let oem = part.oemPartNumber, !oem.isEmpty {
                        HStack(spacing: 0) {
                            Text("BMW-Nr. ")
                            Text(oem).monospaced().textSelection(.enabled)
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                    if part.syncState.isPending {
                        Label("Noch nicht synchronisiert", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }
            }
            if !part.seriesIds.isEmpty || part.isPublic {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(part.seriesIds, id: \.self) { id in
                            Text(viewModel.seriesName(id))
                                .scaledFont(11.5, weight: .bold)
                                .foregroundStyle(Theme.Colors.primary)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Capsule().fill(Theme.Colors.primary.opacity(0.14)))
                        }
                        if part.isPublic {
                            Label("Öffentlich", systemImage: "globe")
                                .scaledFont(11.5, weight: .semibold)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Capsule().fill(Color.primary.opacity(0.08)))
                        }
                    }
                }
                .scrollClipDisabled()
            }
        }
        .listRowInsets(EdgeInsets(top: Theme.Spacing.s, leading: Theme.Spacing.xs,
                                  bottom: Theme.Spacing.xs, trailing: Theme.Spacing.xs))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    // MARK: - Stock card

    /// Orange at one piece, red at none.
    private var stockTint: Color {
        onHand <= 0 ? Theme.Colors.accent : onHand == 1 ? .orange : Theme.Colors.primary
    }

    private var stockCardSection: some View {
        Section {
            HStack(spacing: Theme.Spacing.m - 4) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(onHand <= 1 ? "Knapp · \(onHand) auf Lager" : "Auf Lager")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(onHand <= 1 ? AnyShapeStyle(stockTint) : AnyShapeStyle(.secondary))
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("\(onHand)")
                            .font(.system(size: 30, weight: .heavy))
                            .monospacedDigit()
                            .foregroundStyle(stockTint)
                        Text(totalStockValue > 0
                             ? "Stk. · Einkauf \(Formatters.currency(totalStockValue, code: "CHF", fractionDigits: 0))"
                             : "Stk.")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
                Button { showingAddConsumption = true } label: {
                    Image(systemName: "minus")
                        .font(.title3.weight(.bold))
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.primary.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .disabled(onHand < 1)
                .accessibilityLabel("Verbrauch erfassen")
                .accessibilityIdentifier("part.consume")
                Button { showingAddStock = true } label: {
                    Image(systemName: "plus")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Theme.Colors.primary))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Bestand hinzufügen")
                .accessibilityIdentifier("part.addStock")
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Places

    /// Stocked pieces summed per storage location (consumptions aren't tied
    /// to a place, so this is what was put there).
    private var places: [(location: SDStorageLocation?, quantity: Int)] {
        var order: [UUID?] = []
        var totals: [UUID?: Int] = [:]
        for stock in stocks {
            let id = viewModel.storageLocation(clientId: stock.storageLocationClientId)?.clientId
            if totals[id] == nil { order.append(id) }
            totals[id, default: 0] += stock.quantity
        }
        return order.map { id in
            (location: id.flatMap { viewModel.storageLocation(clientId: $0) }, quantity: totals[id] ?? 0)
        }
    }

    @ViewBuilder
    private var placesSection: some View {
        if !stocks.isEmpty {
            Section {
                ForEach(Array(places.enumerated()), id: \.offset) { _, place in
                    HStack(spacing: 12) {
                        Text("\(place.quantity)×")
                            .scaledFont(15, weight: .heavy)
                            .monospacedDigit()
                            .foregroundStyle(Theme.Colors.primary)
                            .frame(width: 34, alignment: .leading)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(place.location?.name ?? "Ohne Lagerort")
                                .scaledFont(14.5, weight: .semibold)
                            if let location = place.location, let parent = viewModel.locationParentPath(location) {
                                Text(parent)
                                    .scaledFont(12)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                    .contextMenu {
                        if let location = place.location, location.serverId != nil {
                            Button {
                                printingLocation = location
                            } label: {
                                Label("Lagerort-Etikett drucken", systemImage: "printer")
                            }
                        }
                    }
                }
            } header: {
                Text("Lagerorte")
            }
        }
    }

    // MARK: - History

    private enum HistoryEntry {
        case stock(SDPartStock)
        case consumption(SDPartConsumption)

        var date: String {
            switch self {
            case .stock(let stock): stock.purchaseDate ?? ""
            case .consumption(let consumption): consumption.date
            }
        }

        var id: UUID {
            switch self {
            case .stock(let stock): stock.clientId
            case .consumption(let consumption): consumption.clientId
            }
        }
    }

    /// Purchases and uses in one list, newest first.
    private var history: [HistoryEntry] {
        (stocks.map(HistoryEntry.stock) + consumptions.map(HistoryEntry.consumption))
            .sorted { $0.date > $1.date }
    }

    private var historySection: some View {
        Section {
            if history.isEmpty {
                Text("Noch nichts gekauft oder verbraucht. Teile lassen sich auch direkt beim Erfassen einer Wartung verbuchen.")
                    .scaledFont(13)
                    .foregroundStyle(.secondary)
            }
            ForEach(history, id: \.id) { entry in
                switch entry {
                case .stock(let stock):
                    Button { editingStock = stock } label: { stockRow(stock) }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            // No destructive role: that animates the row away
                            // before the confirmation is answered.
                            Button { pendingStockDelete = stock } label: {
                                Label("Löschen", systemImage: "trash")
                            }
                            .tint(.red)
                        }
                        .contextMenu {
                            Button(role: .destructive) { pendingStockDelete = stock } label: {
                                Label("Löschen", systemImage: "trash")
                            }
                        }
                case .consumption(let consumption):
                    consumptionRowLinked(consumption)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button { pendingConsumptionDelete = consumption } label: {
                                Label("Zurückbuchen", systemImage: "arrow.uturn.backward")
                            }
                            .tint(.red)
                        }
                        .contextMenu {
                            Button(role: .destructive) { pendingConsumptionDelete = consumption } label: {
                                Label("Löschen (Bestand zurückbuchen)", systemImage: "arrow.uturn.backward")
                            }
                        }
                }
            }
        } header: {
            sectionHeader("Verlauf", count: history.count)
        }
    }

    /// A purchase: "+N", price per piece, date and place.
    private func stockRow(_ stock: SDPartStock) -> some View {
        HStack(spacing: 12) {
            quantityBadge("+\(stock.quantity)", tint: .green)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if let price = stock.price {
                        let unit = price / Double(max(1, stock.quantity))
                        Text("Gekauft · \(Formatters.currency(unit, code: stock.currency ?? "CHF"))/Stk.")
                    } else {
                        Text("Eingelagert")
                    }
                    if stock.isUsed {
                        Text("GEBRAUCHT")
                            .scaledFont(8, weight: .heavy).tracking(1.0)
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color.orange.opacity(0.16)))
                    }
                }
                .scaledFont(14, weight: .semibold)
                Text([stock.purchaseDate.map(Formatters.mediumDate),
                      viewModel.storageLocation(clientId: stock.storageLocationClientId)?.name]
                    .compactMap { $0 }.joined(separator: " · "))
                    .scaledFont(12)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let notes = stock.notes, !notes.isEmpty {
                    Text(NoteBrandPalette.display(description: notes, markup: stock.notesMarkup))
                        .scaledFont(11)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private func quantityBadge(_ text: String, tint: Color) -> some View {
        Text(text)
            .scaledFont(13, weight: .heavy)
            .monospacedDigit()
            .foregroundStyle(tint)
            .frame(width: 34, height: 32)
            .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: Theme.Radius.badge))
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
            quantityBadge("−\(consumption.quantity)", tint: .orange)
            VStack(alignment: .leading, spacing: 2) {
                Group {
                    if let repair {
                        Text(NoteBrandPalette.display(
                            description: repair.recordDescription ?? repair.summary ?? repair.recordType,
                            markup: repair.descriptionMarkup))
                    } else if consumption.maintenanceClientId != nil || consumption.maintenanceServerId != nil {
                        Text("Verknüpfte Wartung")
                    } else {
                        Text("Verbraucht")
                    }
                }
                .scaledFont(14, weight: .semibold)
                .lineLimit(1)
                // Which bike the part went into — the one thing the repair's
                // own description never says.
                Text((["Verbraucht", Formatters.mediumDate(consumption.date)] + [motorcycleLabel(consumption)].compactMap { $0 })
                    .joined(separator: " · "))
                    .scaledFont(12)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let notes = consumption.notes, !notes.isEmpty {
                    Text(notes)
                        .scaledFont(11)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
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
    /// Rich note; converted to plain text + markup on save (see `NoteMarkup`).
    @State private var notes: AttributedString
    @State private var notesSelection: AttributedTextSelection
    @State private var isUsed: Bool
    @State private var errorMessage: String?

    /// `initialQuantity` prefills a new entry (shopping list, quick booking).
    init(viewModel: PartsViewModel, part: SDPart, existingStock: SDPartStock? = nil, initialQuantity: Int = 1) {
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
            _notes = State(initialValue: NoteMarkup.attributedString(
                NoteMarkup.resolve(description: s.notes, markup: s.notesMarkup)))
            _notesSelection = State(initialValue: AttributedTextSelection())
            _isUsed = State(initialValue: s.isUsed)
        } else {
            _quantity = State(initialValue: max(1, initialQuantity))
            _price = State(initialValue: "")
            _currency = State(initialValue: "CHF")
            _purchaseDate = State(initialValue: Date())
            _selectedLocation = State(initialValue: nil)
            _notes = State(initialValue: AttributedString())
            _notesSelection = State(initialValue: AttributedTextSelection())
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
            FormField("Notizen", hint: "Fett, kursiv und Markenfarben; die Formatierung wird mit dem Web geteilt.") {
                NoteEditor(text: $notes, selection: $notesSelection,
                           prompt: "z. B. Kauf bei Motorradteile Meyer")
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
        let (noteText, noteMarkup) = NoteMarkup.storageForm(notes)
        let saved: Bool
        if let s = existingStock {
            saved = viewModel.updateStock(
                s, quantity: quantity, price: priceValue, currency: trimmedCurrency,
                purchaseDate: purchaseDate, storageLocation: location, notes: noteText,
                notesMarkup: noteMarkup, isUsed: isUsed)
        } else {
            saved = viewModel.addStock(
                part: part, quantity: quantity, price: priceValue, currency: trimmedCurrency,
                purchaseDate: purchaseDate, storageLocation: location, notes: noteText,
                notesMarkup: noteMarkup, isUsed: isUsed) != nil
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
    // No declaration default: set once in init (iOS 27 drops the init value
    // when both are present).
    @State private var notes: String
    @State private var errorMessage: String?

    /// `initialNotes` prefills the note, e.g. "Mangel: …" when booking a
    /// piece against a linked defect.
    init(viewModel: PartsViewModel, part: SDPart, initialNotes: String = "") {
        self.viewModel = viewModel
        self.part = part
        _notes = State(initialValue: initialNotes)
    }

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
