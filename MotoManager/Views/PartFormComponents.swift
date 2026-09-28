import SwiftUI

// Inputs shared by the part sheets (AddPartView's initial stock and
// AddPartStockView), so both record stock the same way.

/// Quantity stepper for a stock entry ("12 Stück").
struct PartQuantityField: View {
    var label = "Menge"
    @Binding var quantity: Int
    var range: ClosedRange<Int> = 1...999

    var body: some View {
        FormField(label) {
            Stepper(value: $quantity, in: range) {
                Text("\(quantity) Stück")
                    .scaledFont(15, weight: .bold)
            }
        }
    }
}

/// Total price plus its ISO currency code, side by side.
struct CurrencyField: View {
    @Binding var price: String
    @Binding var currency: String

    /// Empty is allowed (no price); anything else must be a number.
    static func isValid(_ price: String) -> Bool {
        let trimmed = price.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || parse(trimmed) != nil
    }

    static func parse(_ price: String) -> Double? {
        let trimmed = price.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed.replacingOccurrences(of: ",", with: "."))
    }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            FormField("Preis (gesamt)") {
                TextField("", text: $price, prompt: formPrompt("0"))
                    .keyboardType(.decimalPad)
            }
            FormField("Währung") {
                TextField("", text: $currency, prompt: formPrompt("CHF"))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
            }
            .frame(maxWidth: 120)
        }
    }
}

/// Storage-location menu over the cached locations, plus the optional
/// inline "new location" name (created under the selected one on save).
struct StorageLocationPicker: View {
    @ObservedObject var viewModel: PartsViewModel
    @Binding var selection: SDStorageLocation?
    @Binding var newLocationName: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            locationMenu
            newLocationField
        }
    }

    private var locationMenu: some View {
        FormField("Lagerort") {
            Menu {
                Button("Kein Lagerort") { selection = nil }
                ForEach(viewModel.storageLocations, id: \.clientId) { location in
                    Button(viewModel.locationPath(location) ?? location.name) {
                        selection = location
                    }
                }
            } label: {
                HStack {
                    Text(selection.flatMap { viewModel.locationPath($0) } ?? "Kein Lagerort")
                        .foregroundStyle(selection == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .scaledFont(11, weight: .semibold)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
        }
    }

    private var newLocationField: some View {
        FormField(
            "Neuer Lagerort",
            hint: selection == nil ? nil : "Wird unter dem gewählten Lagerort angelegt."
        ) {
            TextField("", text: $newLocationName, prompt: formPrompt("optional, z. B. Regal A · Kiste 3"))
        }
    }
}
