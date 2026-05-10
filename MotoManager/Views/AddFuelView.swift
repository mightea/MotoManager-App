import SwiftUI

struct AddFuelView: View {
    @ObservedObject var viewModel: MotorcycleDetailViewModel
    let existingRecord: MaintenanceRecord?
    @Environment(\.dismiss) var dismiss

    enum PriceMode: String, CaseIterable {
        case total = "Total"
        case perLiter = "Per Liter"
    }

    @State private var odo: String
    @State private var amount: String = ""
    @State private var priceInput: String = ""
    @State private var priceMode: PriceMode = .total
    @State private var fuelType: String = "98"
    @State private var currency: String
    @State private var currencies: [Currency]
    @State private var locationName: String = ""
    @State private var notes: String = ""
    @State private var date = Date()

    private let fuelTypes = ["95", "98", "E10"]

    init(viewModel: MotorcycleDetailViewModel, existingRecord: MaintenanceRecord? = nil) {
        self.viewModel = viewModel
        self.existingRecord = existingRecord

        _currencies = State(initialValue: CacheStore.shared.load([Currency].self, key: CacheKey.currencies) ?? [])

        if let record = existingRecord {
            _odo = State(initialValue: "\(record.odo)")
            _amount = State(initialValue: record.fuelAmount.map { Self.numberString($0) } ?? "")
            _fuelType = State(initialValue: record.fuelType ?? "98")
            _locationName = State(initialValue: record.locationName ?? "")
            _notes = State(initialValue: record.description ?? "")
            _currency = State(initialValue: record.currency ?? Self.defaultCurrency(for: viewModel))

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]
            _date = State(initialValue: formatter.date(from: record.date) ?? Date())

            if let perUnit = record.pricePerUnit, perUnit > 0 {
                _priceMode = State(initialValue: .perLiter)
                _priceInput = State(initialValue: Self.numberString(perUnit))
            } else if let cost = record.cost, cost > 0 {
                _priceMode = State(initialValue: .total)
                _priceInput = State(initialValue: Self.numberString(cost))
            }
        } else {
            let currentOdo = viewModel.motorcycle.latestOdo ?? viewModel.motorcycle.initialOdo
            _odo = State(initialValue: "\(currentOdo)")
            _currency = State(initialValue: Self.defaultCurrency(for: viewModel))
        }
    }

    private static func numberString(_ value: Double) -> String {
        String(format: "%g", value)
    }

    private var isEditing: Bool { existingRecord != nil }

    /// Preselect the currency the user most likely wants: latest fuel record's
    /// currency first, falling back to the motorcycle's default, then EUR.
    private static func defaultCurrency(for viewModel: MotorcycleDetailViewModel) -> String {
        if let recent = viewModel.maintenanceRecords
            .first(where: { $0.recordType.lowercased() == "fuel" && ($0.currency?.isEmpty == false) })?
            .currency {
            return recent
        }
        return viewModel.motorcycle.currencyCode ?? "EUR"
    }

    // MARK: - Derived values

    private var amountValue: Double {
        Double(amount.replacingOccurrences(of: ",", with: ".")) ?? 0.0
    }

    private var priceValue: Double {
        Double(priceInput.replacingOccurrences(of: ",", with: ".")) ?? 0.0
    }

    private var totalCost: Double {
        switch priceMode {
        case .total: return priceValue
        case .perLiter: return priceValue * amountValue
        }
    }

    private var pricePerLiter: Double {
        switch priceMode {
        case .total: return amountValue > 0 ? priceValue / amountValue : 0
        case .perLiter: return priceValue
        }
    }

    private var canSave: Bool {
        !odo.isEmpty && amountValue > 0 && !viewModel.isLoading
    }

    private var previousFuelOdo: Int? {
        viewModel.maintenanceRecords
            .first(where: { $0.recordType.lowercased() == "fuel" })?
            .odo
    }

    private var tripDistance: Int? {
        guard let prev = previousFuelOdo,
              let current = Int(odo),
              current > prev else { return nil }
        return current - prev
    }

    private var fuelConsumption: Double? {
        guard let trip = tripDistance, trip > 0, amountValue > 0 else { return nil }
        return (amountValue / Double(trip)) * 100
    }

    /// Always returns a string so the label slot stays reserved and the rest
    /// of the form does not shift as the user types. Em-dash placeholder when
    /// the value is not yet computable.
    private var tripHint: String {
        if let trip = tripDistance, trip > 0 {
            return "Trip: \(trip) km since last fill"
        }
        return "Trip: — km since last fill"
    }

    private var consumptionHint: String {
        if let consumption = fuelConsumption {
            return String(format: "≈ %.1f L/100 km", consumption)
        }
        return "≈ — L/100 km"
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidBackgroundView().ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Theme.Spacing.m) {
                        essentialsSection
                        priceSection
                        dateField
                        detailsSection
                        saveButton
                            .padding(.top, Theme.Spacing.s)
                    }
                    .padding()
                }
            }
            .navigationTitle(isEditing ? "Edit Fuel" : "Add Fuel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                await refreshCurrencies()
            }
            .onChange(of: odo) { _, newValue in
                let sanitized = newValue.filter { $0.isNumber }
                if sanitized != newValue { odo = sanitized }
            }
            .onChange(of: amount) { _, newValue in
                let sanitized = sanitizeDecimal(newValue)
                if sanitized != newValue { amount = sanitized }
            }
            .onChange(of: priceInput) { _, newValue in
                let sanitized = sanitizeDecimal(newValue)
                if sanitized != newValue { priceInput = sanitized }
            }
        }
    }

    private func refreshCurrencies() async {
        if let fresh = try? await NetworkManager.shared.fetchCurrencies() {
            currencies = fresh
        }
    }

    /// Keeps digits and at most one decimal separator (. or ,), dropping
    /// everything else. Guards against hardware-keyboard input or pasted
    /// strings since `.decimalPad` only controls the soft keyboard.
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

    // MARK: - Sections

    private var essentialsSection: some View {
        VStack(spacing: Theme.Spacing.s) {
            QuickInputField(label: "Odometer (km)", text: $odo, icon: "gauge.with.dots", keyboardType: .numberPad, hint: tripHint)

            QuickInputField(label: "Amount (Liters)", text: $amount, icon: "fuelpump.fill", keyboardType: .decimalPad, hint: consumptionHint)

            fuelTypePicker
        }
    }

    private var priceSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack {
                Text("Price")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                Spacer()
                Picker("Mode", selection: $priceMode) {
                    ForEach(PriceMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
            }

            HStack(spacing: Theme.Spacing.s) {
                HStack {
                    Image(systemName: priceMode == .total ? "creditcard.fill" : "scalemass.fill")
                        .foregroundColor(Theme.Colors.primary)
                        .font(.system(size: 14))
                    TextField(priceMode == .total ? "Total cost" : "Cost per liter", text: $priceInput)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 15))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .cornerRadius(Theme.Radius.m)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.m)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )

                currencyMenu
            }

            if let hint = priceHint {
                Text(hint)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.leading, Theme.Spacing.s)
            }
        }
    }

    private var detailsSection: some View {
        VStack(spacing: Theme.Spacing.s) {
            sectionHeader("Optional Details")
            QuickInputField(label: "Location", text: $locationName, icon: "mappin.and.ellipse")
            notesField
        }
    }

    // MARK: - Components

    private var fuelTypePicker: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Fuel Type")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.secondary)

            Picker("Fuel Type", selection: $fuelType) {
                ForEach(fuelTypes, id: \.self) { type in
                    Text(type).tag(type)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var currencyMenu: some View {
        Menu {
            ForEach(currencies) { c in
                Button(currencyMenuLabel(c)) { currency = c.code }
            }
        } label: {
            HStack(spacing: 4) {
                Text(currency)
                    .font(.system(size: 13, weight: .bold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundColor(Theme.Colors.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(.ultraThinMaterial)
            .cornerRadius(Theme.Radius.m)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.m)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
        }
        .disabled(currencies.isEmpty)
    }

    private func currencyMenuLabel(_ currency: Currency) -> String {
        if let label = currency.label, !label.isEmpty {
            return "\(currency.code) · \(label)"
        }
        return currency.code
    }

    private var dateField: some View {
        DatePicker("Date", selection: $date, displayedComponents: .date)
            .font(.system(size: 14))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .cornerRadius(Theme.Radius.m)
    }

    private var notesField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Notes")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.secondary)

            HStack(alignment: .top) {
                Image(systemName: "text.alignleft")
                    .foregroundColor(Theme.Colors.primary)
                    .font(.system(size: 14))
                    .padding(.top, 4)
                TextField("Anything worth remembering?", text: $notes, axis: .vertical)
                    .font(.system(size: 15))
                    .lineLimit(2...4)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .cornerRadius(Theme.Radius.m)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.m)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
        }
    }

    private func sectionHeader(_ label: String) -> some View {
        HStack {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .heavy))
                .tracking(2)
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    private var saveButton: some View {
        Button(action: save) {
            if viewModel.isLoading {
                ProgressView().tint(.white)
            } else {
                Text(isEditing ? "Save Changes" : "Save Fuel Record")
            }
        }
        .buttonStyle(ModernButtonStyle(isLoading: viewModel.isLoading))
        .disabled(!canSave)
    }

    // MARK: - Hint

    private var priceHint: String? {
        guard priceValue > 0, amountValue > 0 else { return nil }
        switch priceMode {
        case .total:
            return "≈ \(formatPerLiter(pricePerLiter)) \(currency)/L"
        case .perLiter:
            return "≈ \(formatTotal(totalCost)) \(currency) total"
        }
    }

    // MARK: - Actions

    private func save() {
        Task {
            let odoInt = Int(odo) ?? 0
            let trimmedLocation = locationName.isEmpty ? nil : locationName
            let trimmedNotes = notes.isEmpty ? nil : notes

            let succeeded: Bool
            if let record = existingRecord {
                succeeded = await viewModel.updateFuelRecord(
                    recordId: record.id,
                    odo: odoInt,
                    amount: amountValue,
                    cost: totalCost,
                    pricePerUnit: pricePerLiter,
                    currency: currency,
                    date: date,
                    fuelType: fuelType,
                    locationName: trimmedLocation,
                    notes: trimmedNotes
                )
            } else {
                succeeded = await viewModel.addFuelRecord(
                    odo: odoInt,
                    amount: amountValue,
                    cost: totalCost,
                    pricePerUnit: pricePerLiter,
                    currency: currency,
                    date: date,
                    fuelType: fuelType,
                    locationName: trimmedLocation,
                    notes: trimmedNotes
                )
            }

            if succeeded {
                dismiss()
            }
        }
    }

    private func formatTotal(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private func formatPerLiter(_ value: Double) -> String {
        String(format: "%.3f", value)
    }
}

struct QuickInputField: View {
    let label: String
    @Binding var text: String
    let icon: String
    var keyboardType: UIKeyboardType = .default
    var hint: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(label)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.secondary)

            HStack {
                Image(systemName: icon)
                    .foregroundColor(Theme.Colors.primary)
                    .font(.system(size: 14))
                TextField("", text: $text)
                    .keyboardType(keyboardType)
                    .font(.system(size: 15))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .cornerRadius(Theme.Radius.m)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.m)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )

            if let hint, !hint.isEmpty {
                Text(hint)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.leading, Theme.Spacing.s)
            }
        }
    }
}

struct AddFuelView_Previews: PreviewProvider {
    static var previews: some View {
        AddFuelView(viewModel: .mock)
    }
}
