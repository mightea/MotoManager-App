import SwiftUI

/// Compact online-only fleet creation flow. Motorcycles are not syncable
/// SwiftData entities yet, so the form keeps that limitation explicit.
struct AddMotorcycleView: View {
    @ObservedObject var viewModel: MotorcycleViewModel
    let onCreated: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var make = ""
    @State private var model = ""
    @State private var fabricationDate = ""
    @State private var odometer = "0"
    @State private var currency = "CHF"
    @State private var isVeteran = false
    @State private var isSaving = false

    private var canSave: Bool {
        !make.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && Int(odometer) != nil
            && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Motorrad") {
                    TextField("Marke", text: $make)
                        .textContentType(.organizationName)
                    TextField("Modell", text: $model)
                    TextField("Baujahr", text: $fabricationDate)
                        .keyboardType(.numberPad)
                    TextField("Kilometerstand", text: $odometer)
                        .keyboardType(.numberPad)
                    Picker("Währung", selection: $currency) {
                        ForEach(["CHF", "EUR", "USD"], id: \.self) { Text($0) }
                    }
                    Toggle("Veteranenfahrzeug", isOn: $isVeteran)
                }

                Section {
                    Label("Zum Anlegen ist eine Serververbindung erforderlich.", systemImage: "wifi")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let error = viewModel.errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.Colors.accent)
                    }
                }
            }
            .navigationTitle("Motorrad hinzufügen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Anlegen", action: save)
                        .disabled(!canSave)
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    private func save() {
        guard let odo = Int(odometer), canSave else { return }
        isSaving = true
        Task {
            let created = await viewModel.createMotorcycle(
                make: make.trimmingCharacters(in: .whitespacesAndNewlines),
                model: model.trimmingCharacters(in: .whitespacesAndNewlines),
                fabricationDate: fabricationDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? nil : fabricationDate.trimmingCharacters(in: .whitespacesAndNewlines),
                initialOdo: max(0, odo),
                currencyCode: currency,
                isVeteran: isVeteran
            )
            isSaving = false
            if created { onCreated() }
        }
    }
}
