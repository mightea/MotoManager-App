import SwiftUI

/// Editor for the user's service-interval rules (years per item, optional
/// km limit), pushed from Settings. Mirrors the webapp's "Service-Intervalle"
/// form and writes to `PUT /api/settings`, so both clients judge the same
/// bike the same way. Online-only: settings aren't part of the offline sync.
struct ServiceIntervalsSettingsView: View {
    @ObservedObject private var store = UserSettingsStore.shared
    @EnvironmentObject private var connectivity: ConnectivityMonitor
    @Environment(\.dismiss) private var dismiss
    @State private var draft: UserSettings
    @State private var isSaving = false
    @State private var errorMessage: String?

    init() {
        _draft = State(initialValue: UserSettingsStore.shared.settings)
    }

    private var isDirty: Bool { draft != store.settings }

    var body: some View {
        List {
            Section {
                Text("Nach diesen Regeln bewertet die App, wann Reifen, Batterie, Flüssigkeiten und Kette fällig sind. Jahre zählen ab dem letzten Eintrag, Kilometer ab dessen Stand — ohne km-Wert gilt nur die Zeit.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .listRowBackground(Color.clear)

            Section("Reifen") {
                intervalRow("Reifen", years: $draft.tireInterval, kms: $draft.tireKmInterval)
            }
            Section("Batterie") {
                intervalRow("Blei / AGM / Gel", years: $draft.batteryDefaultInterval, kms: nil)
                intervalRow("Lithium-Ionen", years: $draft.batteryLithiumInterval, kms: nil)
            }
            Section("Flüssigkeiten") {
                intervalRow("Motoröl", years: $draft.engineOilInterval, kms: $draft.engineOilKmInterval)
                intervalRow("Getriebeöl", years: $draft.gearboxOilInterval, kms: $draft.gearboxOilKmInterval)
                intervalRow("Endantriebsöl", years: $draft.finalDriveOilInterval, kms: $draft.finalDriveOilKmInterval)
                intervalRow("Endantrieb-Getriebeöl", years: $draft.finalDriveGearboxOilInterval,
                            kms: $draft.finalDriveGearboxOilKmInterval)
                intervalRow("Gabelöl", years: $draft.forkOilInterval, kms: $draft.forkOilKmInterval)
                intervalRow("Bremsflüssigkeit", years: $draft.brakeFluidInterval, kms: $draft.brakeFluidKmInterval)
                intervalRow("Kühlmittel", years: $draft.coolantInterval, kms: $draft.coolantKmInterval)
            }
            Section("Wartung") {
                intervalRow("Kette reinigen/fetten", years: $draft.chainInterval, kms: $draft.chainKmInterval)
            }

            if !connectivity.isOnline {
                Section {
                    Label("Offline – Änderungen können erst online gespeichert werden.", systemImage: "wifi.slash")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Service-Intervalle")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                        .accessibilityLabel("Wird gespeichert")
                } else {
                    Button("Speichern") { Task { await save() } }
                        .disabled(!isDirty || !connectivity.isOnline)
                }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Fertig") { hideKeyboard() }
            }
        }
        .alert("Speichern fehlgeschlagen", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .task {
            // A fresh server copy may differ from the cached one; only adopt
            // it while nothing has been edited yet.
            let before = store.settings
            await store.refresh()
            if draft == before { draft = store.settings }
        }
    }

    /// One tracked item: years stepper plus an optional km limit field.
    private func intervalRow(_ label: String, years: Binding<Int>, kms: Binding<Int?>?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Stepper(value: years, in: 1...20) {
                HStack {
                    Text(label)
                    Spacer()
                    Text(years.wrappedValue == 1 ? "jedes Jahr" : "alle \(years.wrappedValue) Jahre")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            if let kms {
                HStack {
                    Text("km-Limit")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    TextField("keins", value: kms, format: .number.grouping(.never))
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 120)
                        .accessibilityLabel("\(label) km-Limit")
                    Text("km")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await store.update(draft)
            draft = store.settings
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
