import CoreLocation
import MapKit
import SwiftUI

/// Glass bottom-sheet fuel-entry flow.
///
/// Native fields preserve complete values on focus. Price/L and total are
/// auto-coupled — typing into one derives the other from the entered liters.
/// Currency is picked above the fields; keyboard controls move
/// between the odometer, liters, per-liter price and total.
///
/// Location, notes, and fuelType are intentionally not shown in this sheet
/// (per design); when editing an existing record they are preserved from the
/// original record and round-tripped untouched. The date is editable via a
/// compact row so missed fill-ups can be backdated.
struct AddFuelView: View {
    @ObservedObject var viewModel: MotorcycleDetailViewModel
    let existingRecord: SDMaintenanceRecord?
    @Environment(\.dismiss) var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var sizeClass

    private enum Field: Hashable { case odo, liters, price, total }
    private enum PriceCouple: String { case perLiter, total }
    /// Fuel-station GPS detection lifecycle (new entries only).
    private enum StationState: Equatable { case idle, detecting, matched, suggestCreate, denied, failed }
    // Fields also seeded from `existingRecord` in init must not carry a
    // declaration default: iOS 27's @State macro discards the init value
    // when both are set.
    @State private var odo: String
    @State private var liters: String
    @State private var price: String
    @State private var total: String
    @State private var coupleSource: PriceCouple
    @State private var fullTank: Bool
    @State private var fuelAdditiveAdded: Bool
    @State private var leadSubstituteAdded: Bool
    @State private var savedAnim: Bool = false
    @State private var showingOdoScanner = false
    @State private var currency: String
    @State private var currencies: [Currency]
    @State private var currencyPopoverOpen: Bool = false
    /// Hidden — preserved across edits but not user-editable in this sheet.
    @State private var fuelType: String
    @State private var locationName: String
    @State private var notes: String
    @State private var date: Date

    // Fuel-station detection (new entries): GPS → match an existing backend
    // location or propose creating one. `locationId` links the record server-side;
    // `stationCoord` is kept for the local detail map.
    @State private var locationId: Int?
    @State private var stationName: String = ""
    @State private var stationCoord: CLLocationCoordinate2D?
    @State private var stationState: StationState = .idle

    @FocusState private var focused: Field?

    init(viewModel: MotorcycleDetailViewModel, existingRecord: SDMaintenanceRecord? = nil) {
        self.viewModel = viewModel
        self.existingRecord = existingRecord

        _currencies = State(initialValue: CacheStore.shared.load([Currency].self, key: CacheKey.currencies) ?? [])

        _liters = State(initialValue: "")
        _price = State(initialValue: "")
        _total = State(initialValue: "")
        _coupleSource = State(initialValue: .perLiter)
        _fullTank = State(initialValue: true)
        _fuelAdditiveAdded = State(initialValue: false)
        _leadSubstituteAdded = State(initialValue: false)
        _fuelType = State(initialValue: "98")
        _locationName = State(initialValue: "")
        _notes = State(initialValue: "")
        _date = State(initialValue: Date())

        if let record = existingRecord {
            _odo = State(initialValue: "\(record.odo)")
            _liters = State(initialValue: record.fuelAmount.map { Self.numberString($0) } ?? "")
            _fuelType = State(initialValue: record.fuelType ?? "98")
            _locationName = State(initialValue: record.locationName ?? "")
            _notes = State(initialValue: record.recordDescription ?? "")
            _currency = State(initialValue: record.currency ?? Self.defaultCurrency(for: viewModel))
            _fuelAdditiveAdded = State(initialValue: record.fuelAdditiveAdded)
            _leadSubstituteAdded = State(initialValue: record.leadSubstituteAdded)

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]
            _date = State(initialValue: formatter.date(from: record.date) ?? Date())

            // Prefer per-liter when both are present — that's the "source of truth"
            // the user typed.
            if let perUnit = record.pricePerUnit, perUnit > 0 {
                _price = State(initialValue: Self.numberString(perUnit))
                _coupleSource = State(initialValue: .perLiter)
                if let cost = record.cost, cost > 0 {
                    _total = State(initialValue: Self.numberString(cost))
                }
            } else if let cost = record.cost, cost > 0 {
                _total = State(initialValue: Self.numberString(cost))
                _coupleSource = State(initialValue: .total)
            }
        } else {
            let currentOdo = viewModel.motorcycle.latestOdo ?? viewModel.motorcycle.initialOdo
            _odo = State(initialValue: "\(currentOdo)")
            _currency = State(initialValue: Self.defaultCurrency(for: viewModel))

            // Seed price from the previous fuel entry's per-liter cost so the
            // first tap on liters auto-derives the total.
            if let lastPerL = viewModel.lastFuelPerLiter, lastPerL > 0 {
                _price = State(initialValue: Self.numberString(lastPerL))
            }
        }

        // Restore an interrupted entry: a draft that survived until here means
        // the process was killed while this sheet was open (ordinary
        // backgrounding keeps @State alive; a background jettison does not).
        let draft = FuelEntryDraft.load(
            motorcycleId: viewModel.motorcycle.id,
            editingClientId: existingRecord?.clientId
        )
        if let draft {
            _odo = State(initialValue: draft.odo)
            _liters = State(initialValue: draft.liters)
            _price = State(initialValue: draft.price)
            _total = State(initialValue: draft.total)
            _coupleSource = State(initialValue: PriceCouple(rawValue: draft.coupleSource) ?? .perLiter)
            _fullTank = State(initialValue: draft.fullTank)
            _fuelAdditiveAdded = State(initialValue: draft.fuelAdditiveAdded)
            _leadSubstituteAdded = State(initialValue: draft.leadSubstituteAdded)
            _currency = State(initialValue: draft.currency)
            _date = State(initialValue: draft.date)
        }

    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color.clear

                ScrollView {
                    VStack(spacing: 0) {
                        HStack {
                            Text("Währung").font(.subheadline).foregroundStyle(.secondary)
                            Spacer()
                            currencyMenu.frame(minHeight: 44)
                        }
                        .padding(.horizontal, Theme.Spacing.m)
                        fieldStack
                        dateRow
                        if existingRecord == nil {
                            stationRow
                        }
                        metaRow
                        additiveRow
                        saveButton
                    }
                    .padding(.top, 10)
                    .adaptiveFormWidth()
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(isEditing ? "Tankung bearbeiten" : "Neue Tankung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) {
                        if sizeClass == .regular { Text("Speichern") }
                        else { Image(systemName: "checkmark") }
                    }
                        .disabled(!canSave || savedAnim)
                        .keyboardShortcut("s", modifiers: .command)
                        .accessibilityLabel("Speichern")
                        .accessibilityIdentifier("fuel.save")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Button("Vorheriges Feld", systemImage: "chevron.up") { moveFocus(by: -1) }
                        .labelStyle(.iconOnly)
                        .disabled(focused == .odo)
                    Button("Nächstes Feld", systemImage: "chevron.down") { moveFocus(by: 1) }
                        .labelStyle(.iconOnly)
                        .disabled(focused == .total)
                    Spacer()
                    Button("Fertig") { focused = nil }
                }
            }
        }
        .sheet(isPresented: $showingOdoScanner) {
            OdometerScanSheet(onResult: { value in
                odo = "\(value)"
            })
            .glassSheet()
        }
        .task {
            // Mirrors FuelEntrySheet.jsx setActiveField("liters") on open —
            // but only after the presentation transition has settled. Focusing
            // during presentation makes the sheet wait for the keyboard, which
            // visibly delays it on device (worst on the first open).
            try? await Task.sleep(for: .milliseconds(500))
            if focused == nil {
                focused = .liters
            }
        }
        .task {
            await refreshCurrencies()
        }
        .task {
            // Detect the fuel station on open (new entries only).
            if existingRecord == nil { await detectStation() }
        }
        .onChange(of: odo) { _, newValue in
            let sanitized = newValue.filter { $0.isNumber }
            if sanitized != newValue {
                odo = sanitized
                return
            }
        }
        .onChange(of: liters) { _, newValue in
            let sanitized = sanitizeDecimal(newValue)
            if sanitized != newValue {
                liters = sanitized
            } else {
                recomputeFromLiters()
            }
        }
        .onChange(of: price) { _, newValue in
            let sanitized = sanitizeDecimal(newValue)
            if sanitized != newValue {
                price = sanitized
            } else if focused == .price {
                coupleSource = .perLiter
                recomputeTotalFromPrice()
            }
        }
        .onChange(of: total) { _, newValue in
            let sanitized = sanitizeDecimal(newValue)
            if sanitized != newValue {
                total = sanitized
            } else if focused == .total {
                coupleSource = .total
                recomputePriceFromTotal()
            }
        }
        .onChange(of: draftSnapshot) { _, draft in
            // Keep an on-disk draft while the sheet is open so a process kill
            // in the background can't lose a half-typed entry.
            draft.persist()
        }
        .onDisappear {
            // Every normal close path (saved, cancelled, swiped away) retires
            // the draft; only a mid-entry process death leaves it for restore.
            FuelEntryDraft.clear()
        }
    }

    /// Everything the crash-safe draft mirrors (see `FuelEntryDraft`).
    /// `savedAt` stays constant here so `onChange` only fires on real edits.
    private var draftSnapshot: FuelEntryDraft {
        FuelEntryDraft(
            motorcycleId: viewModel.motorcycle.id,
            editingClientId: existingRecord?.clientId,
            odo: odo, liters: liters, price: price, total: total,
            coupleSource: coupleSource.rawValue,
            fullTank: fullTank,
            fuelAdditiveAdded: fuelAdditiveAdded,
            leadSubstituteAdded: leadSubstituteAdded,
            currency: currency, date: date,
            savedAt: .distantPast
        )
    }

    // MARK: - Sections

    private var fieldStack: some View {
        VStack(spacing: Theme.Spacing.s) {
            HStack(alignment: .center, spacing: Theme.Spacing.s) {
                numericField("Kilometerstand", unit: "km", text: $odo, field: .odo, hint: odoHint)
                Button {
                    focused = nil
                    showingOdoScanner = true
                } label: {
                    Image(systemName: "camera.viewfinder")
                        .font(.title2)
                        .frame(width: 52, height: 52)
                }
                .accessibilityLabel("Kilometerstand scannen")
            }
            numericField("Tankmenge", unit: "L", text: $liters, field: .liters, hint: litersHint)
            let priceLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: Theme.Spacing.s))
                : AnyLayout(HStackLayout(spacing: Theme.Spacing.s))
            priceLayout {
                priceField
                totalField
            }
        }
        .padding(.horizontal, Theme.Spacing.m)
    }

    private var priceField: some View {
        numericField("Preis / Liter", unit: currency, text: $price, field: .price,
            hint: coupleSource == .total && !price.isEmpty ? "Berechnet" : nil)
    }

    private var totalField: some View {
        numericField("Gesamtpreis", unit: currency, text: $total, field: .total,
            hint: coupleSource == .perLiter && !total.isEmpty ? "Berechnet" : nil)
    }

    private func numericField(_ title: String, unit: String, text: Binding<String>, field: Field, hint: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline) {
                TextField(title, text: text, prompt: Text("0"))
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                    .keyboardType(field == .odo ? .numberPad : .decimalPad)
                    .focused($focused, equals: field)
                    .submitLabel(field == .total ? .done : .next)
                    .onSubmit { moveFocus(by: 1) }
                    .accessibilityLabel(title)
                    .accessibilityIdentifier("fuel.\(field)")
                Text(unit).font(.footnote).foregroundStyle(.secondary)
            }
            if let hint, !hint.isEmpty {
                Text(hint).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.Spacing.m)
        .background(Theme.Colors.backgroundElevated, in: RoundedRectangle(cornerRadius: Theme.Radius.field))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.field)
                .stroke(focused == field ? Theme.Colors.primary : Theme.Glass.border, lineWidth: 1)
        }
    }

    private func moveFocus(by offset: Int) {
        let fields: [Field] = [.odo, .liters, .price, .total]
        guard let focused, let index = fields.firstIndex(of: focused) else {
            focused = .odo
            return
        }
        let next = index + offset
        self.focused = fields.indices.contains(next) ? fields[next] : nil
    }

    private var metaRow: some View {
        HStack(alignment: .center) {
            fullTankToggle
            Spacer(minLength: 0)
            if let l100 = derivedConsumption {
                consumptionChip(l100)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    private var additiveRow: some View {
        HStack(alignment: .center, spacing: 8) {
            checkPill(label: "Additiv", isOn: $fuelAdditiveAdded)
            checkPill(label: "Bleiersatz", isOn: $leadSubstituteAdded)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.top, 2)
        .padding(.bottom, 4)
    }

    private var saveButton: some View {
        Button(action: save) {
            HStack(spacing: 8) {
                if savedAnim {
                    Image(systemName: "checkmark")
                        .scaledFont(16, weight: .bold)
                    Text("Gespeichert")
                } else if viewModel.isLoading {
                    ProgressView()
                } else {
                    Text(isEditing ? "Änderungen speichern" : "Tankung speichern")
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 34)
            .scaledFont(15, weight: .heavy)
        }
        .glassActionButton(savedAnim ? .success : .primary, in: .roundedRectangle(radius: Theme.Radius.chip))
        .disabled(!canSave || savedAnim)
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .animation(.easeOut(duration: 0.18), value: canSave)
        .animation(.easeOut(duration: 0.18), value: savedAnim)
        // Success tick when the save lands (HIG: haptic feedback for
        // user-initiated confirmations).
        .sensoryFeedback(.success, trigger: savedAnim) { _, new in new }
    }

    // MARK: - Toolbar subcomponents

    private var currencyMenu: some View {
        Menu {
            Picker("Currency", selection: $currency) {
                ForEach(currencyOptions, id: \.self) { code in
                    Text(currencyMenuLabel(code)).tag(code)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "\(Formatters.currencySymbol(for: currency)).circle")
                    .scaledFont(11, weight: .semibold)
                Text(currency)
                    .scaledFont(12, weight: .heavy)
            }
        }
        .accessibilityLabel("Währung")
    }

    // MARK: - Meta-row helpers

    private var fullTankToggle: some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) {
                fullTank.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(fullTank ? Color.green : Color.clear)
                        .frame(width: 16, height: 16)
                    if fullTank {
                        Image(systemName: "checkmark")
                            .scaledFont(9, weight: .heavy)
                            .foregroundStyle(.primary)
                    } else {
                        Circle()
                            .stroke(Color.primary.opacity(0.35), lineWidth: 1.5)
                            .frame(width: 16, height: 16)
                    }
                }
                Text("Voll getankt")
                    .scaledFont(11, weight: .semibold)
                    .foregroundStyle(fullTank ? Color.green : Color.primary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(
                    fullTank
                        ? Color.green.opacity(0.18)
                        : Color.primary.opacity(0.08)
                )
            )
            .overlay(
                Capsule().stroke(
                    fullTank
                        ? Color.green.opacity(0.35)
                        : Color.clear,
                    lineWidth: 0.5
                )
            )
        }
        .buttonStyle(.plain)
    }

    /// Same pill style as `fullTankToggle`, for the additive/lead-substitute flags.
    private func checkPill(label: String, isOn: Binding<Bool>) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) {
                isOn.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(isOn.wrappedValue ? Color.green : Color.clear)
                        .frame(width: 16, height: 16)
                    if isOn.wrappedValue {
                        Image(systemName: "checkmark")
                            .scaledFont(9, weight: .heavy)
                            .foregroundStyle(.primary)
                    } else {
                        Circle()
                            .stroke(Color.primary.opacity(0.35), lineWidth: 1.5)
                            .frame(width: 16, height: 16)
                    }
                }
                Text(label)
                    .scaledFont(11, weight: .semibold)
                    .foregroundStyle(isOn.wrappedValue ? Color.green : Color.primary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(
                    isOn.wrappedValue
                        ? Color.green.opacity(0.18)
                        : Color.primary.opacity(0.08)
                )
            )
            .overlay(
                Capsule().stroke(
                    isOn.wrappedValue
                        ? Color.green.opacity(0.35)
                        : Color.clear,
                    lineWidth: 0.5
                )
            )
        }
        .buttonStyle(.plain)
    }

    private func consumptionChip(_ value: Double) -> some View {
        let isHigh = value > 6
        let color: Color = isHigh ? .orange : .green
        return HStack(spacing: 5) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .scaledFont(10, weight: .heavy)
            Text(String(format: "%.1f L/100 km", value))
                .scaledFont(11, weight: .heavy)
                .monospacedDigit()
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(color.opacity(0.18)))
    }

    // MARK: - Derived values

    private var isEditing: Bool { existingRecord != nil }

    private var litersValue: Double {
        Double(liters.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private var priceValue: Double {
        Double(price.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private var totalValue: Double {
        Double(total.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private var odoValue: Int {
        Int(odo) ?? 0
    }

    private var canSave: Bool {
        odoValue > 0 && litersValue > 0 && totalValue > 0 && !viewModel.isLoading
    }

    private var previousFuelEntry: SDMaintenanceRecord? {
        viewModel.fuelRecords.first
    }

    private var odoHint: String? {
        if let prev = previousFuelEntry {
            return "letzter Stand: \(Formatters.kilometers(prev.odo))"
        }
        return nil
    }

    private var litersHint: String? {
        var parts: [String] = []
        if let tank = viewModel.motorcycle.fuelTankSize {
            parts.append("Tank max \(String(format: "%g", tank)) L")
        }
        if let avg = averageConsumption {
            parts.append("Ø \(String(format: "%.1f", avg)) L/100 km")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Same robust trailing average the fuel list headlines, so the hint and
    /// the stat strip never show two different "Ø" values.
    private var averageConsumption: Double? {
        let avg = FuelStats.trailingAverageConsumption(
            viewModel.fuelRecords, count: 10)
        return avg > 0 ? avg : nil
    }

    private var derivedConsumption: Double? {
        guard let prev = previousFuelEntry,
              litersValue > 0 else { return nil }
        let diff = odoValue - prev.odo
        guard diff > 0 else { return nil }
        return (litersValue / Double(diff)) * 100
    }

    private var currencyOptions: [String] {
        if !currencies.isEmpty {
            return currencies.map { $0.code }
        }
        return ["CHF", "EUR", "USD", "GBP", "AUD"]
    }

    // MARK: - Date

    /// Compact date row so a missed fill-up can be backdated right when it's
    /// entered (defaults to today; future dates make no sense for a fill-up).
    private var dateRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar")
                .scaledFont(14, weight: .semibold)
                .foregroundStyle(Theme.Colors.primary)
                .frame(width: 22)
            Text("DATUM")
                .scaledFont(9, weight: .heavy)
                .tracking(1)
                .foregroundStyle(Theme.Glass.mutedText)
            Spacer(minLength: 0)
            DatePicker("", selection: $date, in: ...Date(), displayedComponents: .date)
                .labelsHidden()
                .environment(\.locale, Formatters.displayLocale)
                .tint(Theme.Colors.primary)
        }
        .frame(minHeight: 30)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.field).fill(Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.field).stroke(Theme.Glass.border, lineWidth: 0.5))
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .accessibilityLabel("Datum der Tankung")
    }

    // MARK: - Fuel station (GPS detection)

    private var stationRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "fuelpump.fill")
                .scaledFont(14, weight: .semibold)
                .foregroundStyle(Theme.Colors.primary)
                .frame(width: 22)
            stationContent
        }
        .frame(minHeight: 30)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.field).fill(Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.field).stroke(Theme.Glass.border, lineWidth: 0.5))
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var stationContent: some View {
        switch stationState {
        case .idle:
            Button { Task { await detectStation() } } label: {
                Text("Tankstelle in der Nähe suchen")
                    .scaledFont(13, weight: .semibold)
                    .foregroundStyle(Theme.Colors.primary)
            }
            Spacer(minLength: 0)
        case .detecting:
            ProgressView().controlSize(.small)
            Text("Tankstelle wird gesucht…")
                .scaledFont(13)
                .foregroundStyle(Theme.Glass.mutedText)
            Spacer(minLength: 0)
        case .matched:
            VStack(alignment: .leading, spacing: 1) {
                Text("TANKSTELLE")
                    .scaledFont(9, weight: .heavy).tracking(1)
                    .foregroundStyle(Theme.Glass.mutedText)
                Text(stationName)
                    .scaledFont(14, weight: .semibold)
                    .foregroundStyle(.primary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Button { clearStation() } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.Glass.mutedText)
            }
        case .suggestCreate:
            VStack(alignment: .leading, spacing: 2) {
                Text("NEUE TANKSTELLE")
                    .scaledFont(9, weight: .heavy).tracking(1)
                    .foregroundStyle(Theme.Glass.mutedText)
                TextField("Name der Tankstelle", text: $stationName)
                    .scaledFont(14, weight: .semibold)
                    .foregroundStyle(.primary)
                    .textFieldStyle(.plain)
            }
            Spacer(minLength: 0)
            Button { Task { await createStation() } } label: {
                Text("Anlegen").scaledFont(13, weight: .heavy)
                    .foregroundStyle(Theme.Colors.primary)
            }
            .disabled(stationName.trimmingCharacters(in: .whitespaces).isEmpty)
        case .denied:
            Text("Standortzugriff verweigert")
                .scaledFont(13).foregroundStyle(Theme.Glass.mutedText)
            Spacer(minLength: 0)
        case .failed:
            Text("Keine Tankstelle gefunden")
                .scaledFont(13).foregroundStyle(Theme.Glass.mutedText)
            Spacer(minLength: 0)
            Button { Task { await detectStation() } } label: {
                Image(systemName: "arrow.clockwise").foregroundStyle(Theme.Colors.primary)
            }
        }
    }

    /// Watchdog against an endless "Tankstelle wird gesucht…" spinner: offline
    /// (or with a slow GPS fix) the row must degrade to the retryable state
    /// instead of spinning forever. Cancel once the lookup resolves.
    private func stationWatchdog(timeout: Duration = .seconds(6)) -> Task<Void, Never> {
        Task {
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled, stationState == .detecting else { return }
            stationState = .failed
        }
    }

    private func detectStation() async {
        guard existingRecord == nil else { return }
        stationState = .detecting
        let watchdog = stationWatchdog()
        defer { watchdog.cancel() }
        do {
            let location = try await LocationManager.shared.requestCurrentLocation()
            let coord = location.coordinate
            // If the watchdog already gave up, a late result must not yank the
            // row back while the user may be doing something else with it.
            guard stationState == .detecting else { return }
            stationCoord = coord
            let nearby = try await NetworkManager.shared.fetchNearbyLocations(
                latitude: coord.latitude, longitude: coord.longitude, radiusMeters: 250)
            guard stationState == .detecting else { return }
            if let match = nearby.first {
                locationId = match.id
                stationName = match.name
                if let la = match.latitude, let lo = match.longitude {
                    stationCoord = CLLocationCoordinate2D(latitude: la, longitude: lo)
                }
                stationState = .matched
            } else {
                stationName = (try? await reverseGeocodedName(coord)) ?? ""
                guard stationState == .detecting else { return }
                stationState = .suggestCreate
            }
        } catch LocationManager.LocationError.denied {
            stationState = .denied
        } catch {
            if stationState == .detecting { stationState = .failed }
        }
    }

    private func createStation() async {
        guard let coord = stationCoord else { return }
        let name = stationName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        stationState = .detecting
        let watchdog = stationWatchdog()
        defer { watchdog.cancel() }
        do {
            let created = try await NetworkManager.shared.createLocation(
                name: name, latitude: coord.latitude, longitude: coord.longitude)
            locationId = created.id
            stationName = created.name
            stationState = .matched
        } catch {
            if stationState == .detecting { stationState = .suggestCreate }
        }
    }

    private func clearStation() {
        locationId = nil
        stationName = ""
        stationState = .idle
    }

    private func reverseGeocodedName(_ coord: CLLocationCoordinate2D) async throws -> String {
        let location = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        guard let request = MKReverseGeocodingRequest(location: location) else { return "" }
        let items = try await request.mapItems
        guard let item = items.first else { return "" }
        if let name = item.name, !name.isEmpty { return name }
        if let address = item.address?.shortAddress, !address.isEmpty { return address }
        return item.addressRepresentations?.cityWithContext ?? ""
    }

    // MARK: - Coupling logic

    private func recomputeFromLiters() {
        guard litersValue > 0 else { return }
        switch coupleSource {
        case .perLiter:
            if priceValue > 0 {
                total = String(format: "%.2f", priceValue * litersValue)
            }
        case .total:
            if totalValue > 0 {
                price = String(format: "%.2f", totalValue / litersValue)
            }
        }
    }

    private func recomputeTotalFromPrice() {
        guard litersValue > 0, priceValue > 0 else { return }
        total = String(format: "%.2f", priceValue * litersValue)
    }

    private func recomputePriceFromTotal() {
        guard litersValue > 0, totalValue > 0 else { return }
        price = String(format: "%.2f", totalValue / litersValue)
    }

    // MARK: - Helpers

    private static func numberString(_ value: Double) -> String {
        String(format: "%g", value)
    }

    private static func defaultCurrency(for viewModel: MotorcycleDetailViewModel) -> String {
        if let recent = viewModel.fuelRecords
            .first(where: { $0.currency?.isEmpty == false })?
            .currency {
            return recent
        }
        return viewModel.motorcycle.currencyCode ?? "EUR"
    }

    private func currencyMenuLabel(_ code: String) -> String {
        if let match = currencies.first(where: { $0.code == code }), let label = match.label, !label.isEmpty {
            return "\(code) · \(label)"
        }
        return code
    }

    private func refreshCurrencies() async {
        if let fresh = try? await NetworkManager.shared.fetchCurrencies() {
            currencies = fresh
        }
    }

    private func sanitizeDecimal(_ input: String) -> String {
        var result = ""
        var sawSeparator = false
        for char in input {
            if char.isNumber {
                result.append(char)
            } else if (char == "." || char == ",") && !sawSeparator {
                result.append(char)
                sawSeparator = true
            }
        }
        return result
    }

    // MARK: - Save

    private func save() {
        guard canSave, !savedAnim else { return }
        let pricePerLiter = priceValue
        let totalCost = totalValue

        // Optimistic, offline-first: writes to the local store and queues sync.
        let saved: Bool
        if let record = existingRecord {
            saved = viewModel.updateFuelRecord(
                record,
                odo: odoValue, amount: litersValue, cost: totalCost, pricePerUnit: pricePerLiter,
                currency: currency, date: date, fuelType: fuelType,
                locationName: locationName.isEmpty ? nil : locationName,
                notes: notes.isEmpty ? nil : notes,
                fuelAdditiveAdded: fuelAdditiveAdded,
                leadSubstituteAdded: leadSubstituteAdded
            )
        } else {
            saved = viewModel.createFuelRecord(
                odo: odoValue, amount: litersValue, cost: totalCost, pricePerUnit: pricePerLiter,
                currency: currency, date: date, fuelType: fuelType,
                locationName: stationName.isEmpty ? (locationName.isEmpty ? nil : locationName) : stationName,
                notes: notes.isEmpty ? nil : notes,
                fuelAdditiveAdded: fuelAdditiveAdded,
                leadSubstituteAdded: leadSubstituteAdded,
                locationId: locationId,
                latitude: stationCoord?.latitude,
                longitude: stationCoord?.longitude
            )
        }
        guard saved else { return }

        withAnimation { savedAnim = true }
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            dismiss()
        }
    }
}

struct AddFuelView_Previews: PreviewProvider {
    static var previews: some View {
        Color.clear
            .sheet(isPresented: .constant(true)) {
                AddFuelView(viewModel: .mock)
                    .presentationDetents([.large])
                    .presentationCornerRadius(Theme.Radius.sheet)
                    .presentationBackground(.regularMaterial)
            }
    }
}
