import CoreLocation
import MapKit
import SwiftUI

/// Glass bottom-sheet fuel-entry flow.
///
/// Recreates the prototype in `motomanager-app/project/assets/screens/FuelEntrySheet.jsx`:
/// four fields (km, liters, price/L, total) where price/L and total are
/// auto-coupled — typing into one derives the other from the entered liters.
/// Currency is picked via a small pill in the header; the system .decimalPad
/// drives all four fields.
///
/// Location, notes, and fuelType are intentionally not shown in this sheet
/// (per design); when editing an existing record they are preserved from the
/// original record and round-tripped untouched. The date is editable via a
/// compact row so missed fill-ups can be backdated.
struct AddFuelView: View {
    @ObservedObject var viewModel: MotorcycleDetailViewModel
    let existingRecord: SDMaintenanceRecord?
    @Environment(\.dismiss) var dismiss

    private enum Field: Hashable { case odo, liters, price, total }
    private enum PriceCouple { case perLiter, total }
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
    @State private var fullTank: Bool = true
    @State private var fuelAdditiveAdded: Bool
    @State private var leadSubstituteAdded: Bool
    @State private var savedAnim: Bool = false
    /// One-shot: on the first tap into the pre-filled odo/price fields we strip
    /// the part that usually changes (odo's last 3 digits, the price decimals)
    /// so the user only types the delta. New entries only.
    @State private var odoPrepared = false
    @State private var pricePrepared = false
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
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color.clear

                ScrollView {
                    VStack(spacing: 0) {
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
                }
                hiddenTextFields
            }
            .navigationTitle(isEditing ? "Tankung bearbeiten" : "Neue Tankung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    currencyMenu
                }
            }
        }
        .sheet(isPresented: $showingOdoScanner) {
            OdometerScanSheet(onResult: { value in
                odo = "\(value)"
                // Keep the full scanned value on the next tap (don't strip digits).
                odoPrepared = true
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
            if sanitized != newValue { odo = sanitized }
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
    }

    // MARK: - Sections

    private var fieldStack: some View {
        VStack(spacing: 8) {
            // Odometer row carries a camera button to scan the reading from the
            // dashboard instead of typing it.
            ZStack(alignment: .topTrailing) {
                GlassFieldRow(
                    eyebrow: "KILOMETERSTAND",
                    unit: "km",
                    value: odo,
                    hint: odoHint,
                    icon: "gauge.with.dots",
                    size: .big,
                    derived: false,
                    accent: false,
                    isActive: focused == .odo,
                    onTap: { prepareOdoIfNeeded(); focused = .odo }
                )
                Button {
                    focused = nil
                    showingOdoScanner = true
                } label: {
                    Image(systemName: "camera.viewfinder")
                        .scaledFont(26, weight: .semibold)
                        .foregroundStyle(Theme.Colors.primary)
                        .frame(width: 60, height: 60)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Kilometerstand scannen")
            }
            GlassFieldRow(
                eyebrow: "TANKMENGE",
                unit: "L",
                value: liters,
                hint: litersHint,
                icon: "drop.fill",
                size: .big,
                derived: false,
                accent: false,
                isActive: focused == .liters,
                onTap: { focused = .liters }
            )
            HStack(spacing: 8) {
                GlassFieldRow(
                    eyebrow: "PREIS / LITER",
                    unit: currency,
                    value: price,
                    hint: nil,
                    icon: "dollarsign.circle",
                    size: .compact,
                    derived: coupleSource == .total && !price.isEmpty && !liters.isEmpty,
                    accent: false,
                    isActive: focused == .price,
                    onTap: { preparePriceIfNeeded(); focused = .price }
                )
                GlassFieldRow(
                    eyebrow: "GESAMTPREIS",
                    unit: currency,
                    value: total,
                    hint: nil,
                    icon: "dollarsign.circle.fill",
                    size: .compact,
                    derived: coupleSource == .perLiter && !total.isEmpty && !liters.isEmpty,
                    accent: true,
                    isActive: focused == .total,
                    onTap: { focused = .total }
                )
            }
        }
        .padding(.horizontal, 14)
    }

    private var hiddenTextFields: some View {
        // Hidden inputs that drive the system .decimalPad keyboard. They share
        // the @FocusState enum so taps on a `GlassFieldRow` route input to the
        // right state binding. Using .numberPad on `odo` because we only want
        // integers there.
        ZStack {
            TextField("", text: $odo)
                .keyboardType(.numberPad)
                .focused($focused, equals: .odo)
            TextField("", text: $liters)
                .keyboardType(.decimalPad)
                .focused($focused, equals: .liters)
            TextField("", text: $price)
                .keyboardType(.decimalPad)
                .focused($focused, equals: .price)
            TextField("", text: $total)
                .keyboardType(.decimalPad)
                .focused($focused, equals: .total)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .allowsHitTesting(false)
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
                Image(systemName: "dollarsign.circle")
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

    // MARK: - Fast-entry prep

    /// First tap into the pre-filled odometer: drop the last three digits so the
    /// user just types the change since the last fill (e.g. 134'373 → 134___).
    private func prepareOdoIfNeeded() {
        guard existingRecord == nil, !odoPrepared else { return }
        odoPrepared = true
        if odo.count > 3 { odo = String(odo.dropLast(3)) }
    }

    /// First tap into the pre-filled price/L: drop the decimals (the part that
    /// usually changes), keeping the integer + separator (e.g. 1.66 → 1.).
    private func preparePriceIfNeeded() {
        guard existingRecord == nil, !pricePrepared, !price.isEmpty else { return }
        pricePrepared = true
        let intPart = price.prefix { $0.isNumber }
        price = intPart + "."
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
