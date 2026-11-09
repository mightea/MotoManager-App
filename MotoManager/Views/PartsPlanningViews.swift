import Charts
import SwiftUI

// MARK: - Planner

/// Combines the inventory with the selected bike's open issues and service
/// intervals: what the bike will need soon, and the shopping list.
@MainActor
struct PartsPlanner {
    let parts: PartsViewModel
    let bike: MotorcycleDetailViewModel
    let store: PartsPlanningStore
    let links: IssuePartLinkStore

    func fits(_ part: SDPart) -> Bool {
        guard let seriesId = bike.motorcycle.seriesId else { return true }
        return ModelSeriesCatalog.matches(partSeriesIds: part.seriesIds, bikeSeriesId: seriesId, in: parts.series)
    }

    private var openIssues: [SDIssue] {
        bike.issues.filter { $0.status.lowercased() != "done" }
    }

    private var intervals: [PartNeeds.Interval] {
        let records = bike.serviceRecords
        let odo = bike.motorcycle.latestOdo ?? records.map(\.odo).max() ?? bike.motorcycle.initialOdo
        return MaintenanceIntervalsEngine.insights(records: records, currentOdo: odo,
                                                   settings: UserSettingsStore.shared.settings)
            .map { .init(key: $0.key, label: $0.label, due: $0.nextDate, isDue: $0.status != .ok) }
    }

    var needs: [PartNeed] {
        PartNeeds.needs(
            parts: parts.parts.map { .init(id: $0.clientId, name: $0.name, fitsBike: fits($0)) },
            issues: openIssues.map { .init(id: $0.clientId, title: $0.title, text: $0.recordDescription ?? "") },
            intervals: intervals, links: links.partsByIssue)
    }

    var items: [ShoppingItem] {
        let issueNeeds = Set(needs.filter { if case .issue = $0.reason { true } else { false } }.map(\.partId))
        return ShoppingList.items(
            parts: parts.parts.map { .init(id: $0.clientId, name: $0.name, onHand: parts.onHand(for: $0),
                                           unitPrice: parts.lastUnitPrice(for: $0)) },
            neededForIssue: issueNeeds, manual: store.manual, dismissed: store.dismissed,
            quantities: store.quantities)
    }

    func part(_ id: UUID) -> SDPart? { parts.part(clientId: id) }

    /// "Mangel „Vergaser tropft“" / "Motoröl fällig Mai 2027".
    static func reasonText(_ reason: PartNeedReason) -> String {
        switch reason {
        case .issue(let title): "Mangel „\(title)“"
        case .interval(let label, let due):
            "\(label) fällig " + due.formatted(.dateTime.month(.abbreviated).year().locale(Formatters.displayLocale))
        }
    }

    func reasonText(for part: SDPart) -> String? {
        needs.first { $0.partId == part.clientId }.map { Self.reasonText($0.reason) }
    }

    var openIssueList: [(id: UUID, title: String)] { openIssues.map { ($0.clientId, $0.title) } }

    var bikeName: String { "\(bike.motorcycle.make) \(bike.motorcycle.model)" }
}

/// Orange at one piece, red at none, blue otherwise.
func stockTint(_ onHand: Int) -> Color {
    onHand <= 0 ? Theme.Colors.accent : onHand == 1 ? .orange : Theme.Colors.primary
}

struct StockPill: View {
    let onHand: Int
    var body: some View {
        Text("\(onHand)")
            .scaledFont(14, weight: .heavy)
            .monospacedDigit()
            .foregroundStyle(stockTint(onHand))
            .padding(.horizontal, 7)
            .frame(minWidth: 36, minHeight: 30)
            .background(stockTint(onHand).opacity(0.15), in: RoundedRectangle(cornerRadius: Theme.Radius.badge))
            .accessibilityLabel("Bestand \(onHand)")
    }
}

// MARK: - Bald gebraucht

/// Rows for the parts the bike will need soon, with why and where.
struct NeededPartsRows: View {
    let planner: PartsPlanner
    let needs: [PartNeed]
    let onSelect: (SDPart) -> Void

    var body: some View {
        ForEach(needs, id: \.partId) { need in
            if let part = planner.part(need.partId) {
                let onHand = planner.parts.onHand(for: part)
                Button { onSelect(part) } label: {
                    HStack(spacing: Theme.Spacing.m - 4) {
                        Image(systemName: icon(need.reason))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(tint(need.reason))
                            .frame(width: 34, height: 34)
                            .background(tint(need.reason).opacity(0.15), in: RoundedRectangle(cornerRadius: Theme.Radius.controlInner))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(part.name).font(.subheadline.weight(.bold)).lineLimit(1)
                            Text(detail(need, part: part, onHand: onHand))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Spacer(minLength: 0)
                        StockPill(onHand: onHand)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("parts.needed.\(part.clientId)")
            }
        }
    }

    private func icon(_ reason: PartNeedReason) -> String {
        if case .issue = reason { return "exclamationmark" }
        return "calendar"
    }

    private func tint(_ reason: PartNeedReason) -> Color {
        if case .issue = reason { return .orange }
        return Theme.Colors.primary
    }

    private func detail(_ need: PartNeed, part: SDPart, onHand: Int) -> String {
        let place = onHand <= 0 ? "nicht an Lager" : (planner.parts.placePath(for: part) ?? "ohne Lagerort")
        return PartsPlanner.reasonText(need.reason) + " · " + place
    }
}

// MARK: - Einkaufsliste

/// The shopping list: fills itself from low stock and from parts open issues
/// need, plus the user's own entries. Ticking an item books it in.
struct ShoppingListView: View {
    @ObservedObject var parts: PartsViewModel
    @ObservedObject var bike: MotorcycleDetailViewModel
    @ObservedObject private var store = PartsPlanningStore.shared
    @ObservedObject private var links = IssuePartLinkStore.shared
    @State private var booking: SDPart?
    @State private var bookingQuantity = 1
    @State private var onHandBeforeBooking = 0
    @State private var showingPicker = false

    private var planner: PartsPlanner { PartsPlanner(parts: parts, bike: bike, store: store, links: links) }

    var body: some View {
        let items = planner.items
        let total = items.compactMap(\.estimate).reduce(0, +)
        List {
            Section {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Geschätzt, nach letztem Preis").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline) {
                        Text(total > 0 ? "ca. " + Formatters.currency(total, code: "CHF", fractionDigits: 0) : "—")
                            .font(.title2.weight(.bold))
                        Spacer()
                        Text(items.count == 1 ? "1 Teil" : "\(items.count) Teile")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
            if items.isEmpty {
                Section {
                    Text("Nichts zu kaufen: kein Teil ist knapp, und offene Mängel sind gedeckt.")
                        .foregroundStyle(.secondary)
                }
            }
            ForEach([ShoppingItem.Group.issue, .low, .manual], id: \.self) { group in
                let rows = items.filter { $0.group == group }
                if !rows.isEmpty {
                    Section {
                        ForEach(rows) { item in row(item) }
                    } header: {
                        HStack {
                            Text(group.title)
                            Spacer()
                            let sum = rows.compactMap(\.estimate).reduce(0, +)
                            if sum > 0 { Text(Formatters.currency(sum, code: "CHF", fractionDigits: 0)) }
                        }
                    }
                }
            }
            Section {
                Text("Abhaken = gekauft: fragt nach Preis und Lagerort und bucht den Bestand. Die Liste bleibt auf diesem Gerät.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .listRowBackground(Color.clear)
        }
        .workspaceListStyle()
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.background)
        .navigationTitle("Einkaufsliste")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Teil vormerken", systemImage: "plus") { showingPicker = true }
                    .accessibilityIdentifier("shopping.add")
                if !items.isEmpty {
                    ShareLink(item: ShoppingList.text(items)) { Label("Teilen", systemImage: "square.and.arrow.up") }
                }
            }
        }
        .sheet(item: $booking, onDismiss: finishBooking) { part in
            AddPartStockView(viewModel: parts, part: part, initialQuantity: bookingQuantity)
                .glassSheet()
        }
        .sheet(isPresented: $showingPicker) {
            PartPickerSheet(parts: parts.parts) { store.addToList($0.clientId) }
        }
        .accessibilityIdentifier("shopping.list")
    }

    private func row(_ item: ShoppingItem) -> some View {
        HStack(spacing: Theme.Spacing.m - 4) {
            Button {
                guard let part = planner.part(item.partId) else { return }
                bookingQuantity = item.quantity
                onHandBeforeBooking = item.onHand
                booking = part
            } label: {
                Image(systemName: "circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(item.name) gekauft, Bestand verbuchen")
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.subheadline.weight(.bold)).lineLimit(2)
                Text(subtitle(item)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Stepper(value: Binding(get: { item.quantity }, set: { store.setQuantity($0, for: item.partId) }), in: 1...99) {
                Text("\(item.quantity)").font(.subheadline.weight(.heavy)).monospacedDigit()
            }
            .fixedSize()
            .accessibilityLabel("Menge \(item.quantity)")
        }
        .swipeActions {
            Button("Entfernen", role: .destructive) { store.clear(item.partId, onHand: item.onHand) }
        }
    }

    private func subtitle(_ item: ShoppingItem) -> String {
        var parts = [item.onHand <= 0 ? "nicht an Lager" : "\(item.onHand) an Lager"]
        if let price = item.unitPrice { parts.append("zuletzt " + Formatters.currency(price, code: "CHF")) }
        return parts.joined(separator: " · ")
    }

    /// A manual entry leaves the list once the purchase is booked.
    private func finishBooking() {
        for id in store.manual {
            if let part = planner.part(id), parts.onHand(for: part) > onHandBeforeBooking {
                store.clear(id, onHand: parts.onHand(for: part))
            }
        }
    }
}

/// Search and pick a part (shopping list, issue links).
struct PartPickerSheet: View {
    let parts: [SDPart]
    var title = "Teil vormerken"
    let onPick: (SDPart) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [SDPart] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let sorted = parts.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        guard !q.isEmpty else { return sorted }
        return sorted.filter { $0.name.lowercased().contains(q) || $0.partNumber.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            List(filtered, id: \.clientId) { part in
                Button {
                    onPick(part)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(part.name).font(.subheadline.weight(.semibold))
                        Text(part.partNumber).font(.caption).monospaced().foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .searchable(text: $query, prompt: "Name oder Teilenummer")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
    }
}

// MARK: - Quick booking after a scan

/// Opened by scanning a part's label: book pieces out (or in) in two taps.
struct QuickBookSheet: View {
    let part: SDPart
    @ObservedObject var viewModel: PartsViewModel
    let bikeName: String
    let onDetails: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var delta = -1
    @State private var failed = false

    private var onHand: Int { viewModel.onHand(for: part) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack(spacing: Theme.Spacing.m - 4) {
                    Image(systemName: "shippingbox")
                        .font(.title2)
                        .foregroundStyle(Theme.Colors.primary)
                        .frame(width: 54, height: 54)
                        .background(Theme.Colors.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.chip))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(part.name).font(.title3.weight(.bold))
                        Text([part.manufacturer, part.partNumber, viewModel.placePath(for: part)]
                            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                VStack(spacing: Theme.Spacing.m) {
                    HStack {
                        Text("Auf Lager").foregroundStyle(.secondary)
                        Spacer()
                        Text("\(onHand) → ").foregroundStyle(.secondary) + Text("\(max(0, onHand + delta))").bold()
                    }
                    .font(.subheadline)
                    HStack(spacing: Theme.Spacing.l) {
                        stepButton("minus", label: "Weniger") { delta = max(-onHand, delta - 1) }
                            .disabled(onHand + delta <= 0)
                        Text(delta > 0 ? "+\(delta)" : "\(delta)")
                            .font(.system(size: 40, weight: .heavy))
                            .monospacedDigit()
                            .foregroundStyle(delta < 0 ? Color.orange : delta > 0 ? Color.green : Color.secondary)
                            .frame(minWidth: 90)
                        stepButton("plus", label: "Mehr") { delta += 1 }
                    }
                    .frame(maxWidth: .infinity)
                    if delta < 0 {
                        HStack {
                            Text("Für")
                            Spacer()
                            Text(bikeName).fontWeight(.semibold).foregroundStyle(Theme.Colors.primary)
                        }
                        .font(.subheadline)
                    }
                }
                .padding(Theme.Spacing.m)
                .background(Theme.Colors.backgroundElevated, in: RoundedRectangle(cornerRadius: Theme.Radius.field))
                if failed {
                    Text("Verbuchen fehlgeschlagen.").font(.footnote).foregroundStyle(Theme.Colors.accent)
                }
                Spacer(minLength: 0)
                HStack(spacing: Theme.Spacing.s) {
                    Button("Details") { dismiss(); onDetails() }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    Button(action: book) {
                        Text(delta < 0 ? "\(-delta) Stück verbuchen" : "\(delta) Stück einlagern")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(Theme.Colors.primary)
                    .disabled(delta == 0)
                    .accessibilityIdentifier("quickbook.confirm")
                }
            }
            .padding(Theme.Spacing.m)
            .navigationTitle("Etikett gescannt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(role: .close) { dismiss() } }
            }
            .onAppear { if onHand == 0 { delta = 1 } }
        }
        .presentationDetents([.medium, .large])
    }

    private func stepButton(_ image: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: image)
                .font(.title2.weight(.bold))
                .frame(width: 56, height: 56)
                .background(Circle().fill(Color.primary.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func book() {
        let ok: Bool
        if delta < 0 {
            ok = viewModel.addConsumption(part: part, quantity: -delta, date: Date(), notes: "Für \(bikeName)")
        } else {
            let place = viewModel.stocks(for: part).last.flatMap { viewModel.storageLocation(clientId: $0.storageLocationClientId) }
            ok = viewModel.addStock(part: part, quantity: delta, price: viewModel.lastUnitPrice(for: part).map { $0 * Double(delta) },
                                    currency: "CHF", purchaseDate: Date(), storageLocation: place, notes: nil) != nil
        }
        if ok { dismiss() } else { failed = true }
    }
}

// MARK: - Price history

struct PartPriceChart: View {
    let points: [(date: String, unitPrice: Double)]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Chart {
                ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                    if let date = Formatters.parseDay(point.date) {
                        LineMark(x: .value("Datum", date), y: .value("CHF", point.unitPrice))
                            .foregroundStyle(Theme.Colors.primary)
                            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        PointMark(x: .value("Datum", date), y: .value("CHF", point.unitPrice))
                            .foregroundStyle(Theme.Colors.primary)
                    }
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) }
            .frame(height: 80)
            if let first = points.first, let last = points.last {
                HStack {
                    Text("\(Formatters.mediumDate(first.date)) · \(Formatters.currency(first.unitPrice, code: "CHF"))")
                    Spacer()
                    Text("\(Formatters.mediumDate(last.date)) · \(Formatters.currency(last.unitPrice, code: "CHF"))")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        guard let first = points.first, let last = points.last else { return "Preisverlauf" }
        return "Preis pro Stück von \(Formatters.currency(first.unitPrice, code: "CHF")) auf \(Formatters.currency(last.unitPrice, code: "CHF"))"
    }
}
