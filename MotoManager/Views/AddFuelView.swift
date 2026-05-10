import SwiftUI

struct AddFuelView: View {
    @ObservedObject var viewModel: MotorcycleDetailViewModel
    @Environment(\.dismiss) var dismiss

    enum PriceMode: String, CaseIterable {
        case total = "Total"
        case perLiter = "Per Liter"
    }

    @State private var odo: String = ""
    @State private var amount: String = ""
    @State private var priceInput: String = ""
    @State private var priceMode: PriceMode = .total
    @State private var fuelType: String = "98"
    @State private var currency: String
    @State private var currencies: [Currency]
    @State private var locationName: String = ""
    @State private var notes: String = ""
    @State private var date = Date()

    private let fuelTypes = ["95", "98", "E10", "Diesel"]

    init(viewModel: MotorcycleDetailViewModel) {
        self.viewModel = viewModel
        _currency = State(initialValue: Self.defaultCurrency(for: viewModel))
        _currencies = State(initialValue: CacheStore.shared.load([Currency].self, key: CacheKey.currencies) ?? [])
    }

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

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidBackgroundView().ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Theme.Spacing.l) {
                        essentialsSection
                        priceSection
                        dateField
                        detailsSection
                        saveButton
                    }
                    .padding()
                }
            }
            .navigationTitle("Add Fuel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                await refreshCurrencies()
            }
        }
    }

    private func refreshCurrencies() async {
        if let fresh = try? await NetworkManager.shared.fetchCurrencies() {
            currencies = fresh
        }
    }

    // MARK: - Sections

    private var essentialsSection: some View {
        VStack(spacing: Theme.Spacing.m) {
            QuickInputField(label: "Odometer (km)", text: $odo, icon: "gauge.with.dots", keyboardType: .numberPad)

            QuickInputField(label: "Amount (Liters)", text: $amount, icon: "fuelpump.fill", keyboardType: .decimalPad)

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
                    TextField(priceMode == .total ? "Total cost" : "Cost per liter", text: $priceInput)
                        .keyboardType(.decimalPad)
                }
                .padding()
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
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, Theme.Spacing.s)
            }
        }
    }

    private var detailsSection: some View {
        VStack(spacing: Theme.Spacing.m) {
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
                    .font(.system(size: 14, weight: .bold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundColor(Theme.Colors.primary)
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, 14)
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
            .padding()
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
                    .padding(.top, 6)
                TextField("Anything worth remembering?", text: $notes, axis: .vertical)
                    .lineLimit(2...4)
            }
            .padding()
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
                Text("Save Fuel Record")
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

            let succeeded = await viewModel.addFuelRecord(
                odo: odoInt,
                amount: amountValue,
                cost: totalCost,
                pricePerUnit: pricePerLiter,
                currency: currency,
                date: date,
                fuelType: fuelType,
                locationName: locationName.isEmpty ? nil : locationName,
                notes: notes.isEmpty ? nil : notes
            )

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

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(label)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.secondary)

            HStack {
                Image(systemName: icon)
                    .foregroundColor(Theme.Colors.primary)
                TextField("", text: $text)
                    .keyboardType(keyboardType)
            }
            .padding()
            .background(.ultraThinMaterial)
            .cornerRadius(Theme.Radius.m)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.m)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
        }
    }
}

struct AddFuelView_Previews: PreviewProvider {
    static var previews: some View {
        AddFuelView(viewModel: .mock)
    }
}
