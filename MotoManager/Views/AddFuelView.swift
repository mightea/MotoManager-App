import SwiftUI

/// Glass bottom-sheet fuel-entry flow.
///
/// Recreates the prototype in `motomanager-app/project/assets/screens/FuelEntrySheet.jsx`:
/// four fields (km, liters, price/L, total) where price/L and total are
/// auto-coupled — typing into one derives the other from the entered liters.
/// Currency is picked via a small pill in the header; the system .decimalPad
/// drives all four fields.
///
/// Location, notes, fuelType, and date are intentionally not shown in this
/// sheet (per design); when editing an existing record they are preserved
/// from the original record and round-tripped untouched.
struct AddFuelView: View {
    @ObservedObject var viewModel: MotorcycleDetailViewModel
    let existingRecord: MaintenanceRecord?
    @Environment(\.dismiss) var dismiss

    private enum Field: Hashable { case odo, liters, price, total }
    private enum PriceCouple { case perLiter, total }

    @State private var odo: String
    @State private var liters: String = ""
    @State private var price: String = ""
    @State private var total: String = ""
    @State private var coupleSource: PriceCouple = .perLiter
    @State private var fullTank: Bool = true
    @State private var savedAnim: Bool = false
    @State private var currency: String
    @State private var currencies: [Currency]
    @State private var currencyPopoverOpen: Bool = false
    /// Hidden — preserved across edits but not user-editable in this sheet.
    @State private var fuelType: String = "98"
    @State private var locationName: String = ""
    @State private var notes: String = ""
    @State private var date = Date()

    @FocusState private var focused: Field?

    init(viewModel: MotorcycleDetailViewModel, existingRecord: MaintenanceRecord? = nil) {
        self.viewModel = viewModel
        self.existingRecord = existingRecord

        _currencies = State(initialValue: CacheStore.shared.load([Currency].self, key: CacheKey.currencies) ?? [])

        if let record = existingRecord {
            _odo = State(initialValue: "\(record.odo)")
            _liters = State(initialValue: record.fuelAmount.map { Self.numberString($0) } ?? "")
            _fuelType = State(initialValue: record.fuelType ?? "98")
            _locationName = State(initialValue: record.locationName ?? "")
            _notes = State(initialValue: record.description ?? "")
            _currency = State(initialValue: record.currency ?? Self.defaultCurrency(for: viewModel))

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
            if let lastPerL = viewModel.maintenanceRecords
                .first(where: { $0.recordType.lowercased() == "fuel" })?
                .pricePerUnit, lastPerL > 0
            {
                _price = State(initialValue: Self.numberString(lastPerL))
            }
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear

            VStack(spacing: 0) {
                header
                fieldStack
                metaRow
                saveButton
                Spacer(minLength: 0)
            }
            hiddenTextFields
        }
        .background(sheetBackground)
        .onAppear {
            if focused == nil {
                // Mirrors FuelEntrySheet.jsx setActiveField("liters") on open.
                focused = .liters
            }
        }
        .task {
            await refreshCurrencies()
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

    private var sheetBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Theme.Colors.navy900.opacity(0.6),
                    Theme.Colors.navy950.opacity(0.8)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(isEditing ? "Tankung bearbeiten" : "Neue Tankung")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.Glass.mutedText)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            currencyPill
            closeButton
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var subtitle: String {
        let plate = viewModel.motorcycle.numberPlate?.isEmpty == false
            ? " · \(viewModel.motorcycle.numberPlate!)"
            : ""
        return "\(viewModel.motorcycle.make) \(viewModel.motorcycle.model)\(plate)"
    }

    private var fieldStack: some View {
        VStack(spacing: 8) {
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
                onTap: { focused = .odo }
            )
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
                    onTap: { focused = .price }
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

    private var saveButton: some View {
        Button(action: save) {
            HStack(spacing: 8) {
                if savedAnim {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                    Text("Gespeichert")
                } else if viewModel.isLoading {
                    ProgressView().tint(.white)
                } else {
                    Text(isEditing ? "Änderungen speichern" : "Tankung speichern")
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .foregroundColor(saveTextColor)
            .font(.system(size: 15, weight: .heavy))
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(saveButtonColor)
            )
            .shadow(
                color: canSave && !savedAnim
                    ? Theme.Colors.primary.opacity(0.45)
                    : .clear,
                radius: 12, x: 0, y: 6
            )
        }
        .buttonStyle(.plain)
        .disabled(!canSave || savedAnim)
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .animation(.easeOut(duration: 0.18), value: canSave)
        .animation(.easeOut(duration: 0.18), value: savedAnim)
    }

    private var saveButtonColor: Color {
        if savedAnim { return Color.green }
        return canSave ? Theme.Colors.primary : Color.white.opacity(0.10)
    }

    private var saveTextColor: Color {
        canSave || savedAnim ? .white : Theme.Glass.mutedText
    }

    // MARK: - Header subcomponents

    private var currencyPill: some View {
        Menu {
            Picker("Currency", selection: $currency) {
                ForEach(currencyOptions, id: \.self) { code in
                    Text(currencyMenuLabel(code)).tag(code)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "dollarsign.circle")
                    .font(.system(size: 11, weight: .semibold))
                Text(currency)
                    .font(.system(size: 12, weight: .heavy))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .heavy))
                    .opacity(0.6)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(Color.white.opacity(0.10))
            )
            .overlay(
                Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.5)
            )
        }
        .accessibilityLabel("Währung")
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.white.opacity(0.12)))
        }
        .accessibilityLabel("Schliessen")
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
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundColor(.white)
                    } else {
                        Circle()
                            .stroke(Color.white.opacity(0.35), lineWidth: 1.5)
                            .frame(width: 16, height: 16)
                    }
                }
                Text("Voll getankt")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(fullTank ? Color.green : .white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(
                    fullTank
                        ? Color.green.opacity(0.18)
                        : Color.white.opacity(0.08)
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

    private func consumptionChip(_ value: Double) -> some View {
        let isHigh = value > 6
        let color: Color = isHigh ? .orange : .green
        return HStack(spacing: 5) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 10, weight: .heavy))
            Text(String(format: "%.1f L/100 km", value))
                .font(.system(size: 11, weight: .heavy))
                .monospacedDigit()
        }
        .foregroundColor(color)
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

    private var previousFuelEntry: MaintenanceRecord? {
        viewModel.maintenanceRecords.first(where: { $0.recordType.lowercased() == "fuel" })
    }

    private var odoHint: String? {
        if let prev = previousFuelEntry {
            return "letzter Stand: \(prev.odo) km"
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

    private var averageConsumption: Double? {
        let values = viewModel.maintenanceRecords.compactMap { $0.fuelConsumption }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
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
        if let recent = viewModel.maintenanceRecords
            .first(where: { $0.recordType.lowercased() == "fuel" && ($0.currency?.isEmpty == false) })?
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
        Task {
            let pricePerLiter = priceValue
            let totalCost = totalValue

            let succeeded: Bool
            if let record = existingRecord {
                succeeded = await viewModel.updateFuelRecord(
                    recordId: record.id,
                    odo: odoValue,
                    amount: litersValue,
                    cost: totalCost,
                    pricePerUnit: pricePerLiter,
                    currency: currency,
                    date: date,
                    fuelType: fuelType,
                    locationName: locationName.isEmpty ? nil : locationName,
                    notes: notes.isEmpty ? nil : notes
                )
            } else {
                succeeded = await viewModel.addFuelRecord(
                    odo: odoValue,
                    amount: litersValue,
                    cost: totalCost,
                    pricePerUnit: pricePerLiter,
                    currency: currency,
                    date: date,
                    fuelType: fuelType,
                    locationName: locationName.isEmpty ? nil : locationName,
                    notes: notes.isEmpty ? nil : notes
                )
            }

            if succeeded {
                withAnimation { savedAnim = true }
                try? await Task.sleep(nanoseconds: 900_000_000)
                dismiss()
            }
        }
    }
}

struct AddFuelView_Previews: PreviewProvider {
    static var previews: some View {
        Color.clear
            .sheet(isPresented: .constant(true)) {
                AddFuelView(viewModel: .mock)
                    .presentationDetents([.large])
                    .presentationCornerRadius(Theme.Glass.sheetRadius)
                    .presentationBackground(.regularMaterial)
            }
    }
}
