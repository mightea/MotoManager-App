import SwiftUI

/// Compact online-only fleet creation flow. Motorcycles are not syncable
/// SwiftData entities yet, so the form keeps that limitation explicit.
struct AddMotorcycleView: View {
    @ObservedObject var viewModel: MotorcycleViewModel
    let onCreated: () -> Void

    @State private var make = ""
    @State private var model = ""
    @State private var fabricationDate = ""
    @State private var odometer = "0"
    @State private var currency = "CHF"
    @State private var isVeteran = false
    @State private var errorMessage: String?
    /// Set once the backend created the motorcycle; `onCreated` runs when the
    /// sheet has gone (after FormSheet's success beat), not mid-animation.
    @State private var didCreate = false

    private var canSave: Bool {
        !make.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && Int(odometer.trimmingCharacters(in: .whitespaces)) != nil
    }

    var body: some View {
        FormSheet(
            title: "Motorrad hinzufügen",
            canSave: canSave,
            tracked: [make, model, fabricationDate, odometer, currency, isVeteran],
            error: errorMessage,
            onSave: save
        ) {
            FormField("Marke") {
                TextField("", text: $make, prompt: formPrompt("z. B. BMW"))
                    .textContentType(.organizationName)
            }
            FormField("Modell") {
                TextField("", text: $model, prompt: formPrompt("z. B. R 1250 GS"))
            }
            HStack(alignment: .top, spacing: Theme.Spacing.m) {
                FormField("Baujahr") {
                    TextField("", text: $fabricationDate, prompt: formPrompt("optional"))
                        .keyboardType(.numberPad)
                }
                FormField("Kilometerstand", unit: "km") {
                    TextField("", text: $odometer, prompt: formPrompt("0"))
                        .keyboardType(.numberPad)
                }
            }
            FormField("Währung") {
                Picker("Währung", selection: $currency) {
                    ForEach(["CHF", "EUR", "USD"], id: \.self) { Text($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
            FormToggleRow(title: "Veteranenfahrzeug", isOn: $isVeteran)

            Label("Zum Anlegen ist eine Serververbindung erforderlich.", systemImage: "wifi")
                .scaledFont(12, weight: .medium)
                .foregroundStyle(.secondary)
        }
        .onDisappear {
            if didCreate { onCreated() }
        }
    }

    private func save() async -> Bool {
        errorMessage = nil
        guard canSave, let odo = Int(odometer.trimmingCharacters(in: .whitespaces)) else { return false }
        let year = fabricationDate.trimmingCharacters(in: .whitespacesAndNewlines)
        let created = await viewModel.createMotorcycle(
            make: make.trimmingCharacters(in: .whitespacesAndNewlines),
            model: model.trimmingCharacters(in: .whitespacesAndNewlines),
            fabricationDate: year.isEmpty ? nil : year,
            initialOdo: max(0, odo),
            currencyCode: currency,
            isVeteran: isVeteran
        )
        guard created else {
            errorMessage = viewModel.errorMessage ?? "Motorrad konnte nicht angelegt werden."
            return false
        }
        didCreate = true
        return true
    }
}
