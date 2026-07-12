import SwiftUI

/// Create/edit the recommended tire pressures. One riding configuration
/// (Solo / Sozius / Offroad) is edited at a time via a segmented control;
/// values entered for the others are kept and everything saves together.
/// Every configuration is optional but at least one complete front/rear
/// pair is required; deleting removes only the selected configuration —
/// deleting the last one removes the record. Online-only (no offline queue):
/// failures surface as an alert and the sheet stays open.
struct AddTirePressureView: View {
    @ObservedObject var viewModel: MotorcycleDetailViewModel
    @Environment(\.dismiss) private var dismiss

    private struct ConfigInput {
        var front = ""
        var rear = ""
        var sidecar = ""

        var isEmpty: Bool {
            front.trimmingCharacters(in: .whitespaces).isEmpty
                && rear.trimmingCharacters(in: .whitespaces).isEmpty
                && sidecar.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private enum ConfigState { case empty, complete, incomplete }

    private let hasSidecar: Bool
    private let isEditing: Bool

    @State private var unit: String
    @State private var config: PressureConfig = .solo
    @State private var inputs: [PressureConfig: ConfigInput]
    @State private var confirmingDelete = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var savedAnim = false

    init(viewModel: MotorcycleDetailViewModel) {
        self.viewModel = viewModel
        self.hasSidecar = viewModel.motorcycle.hasSidecar ?? false
        let existing = viewModel.tirePressure
        self.isEditing = existing != nil
        _unit = State(initialValue: existing?.preferredUnit ?? "bar")

        var initial: [PressureConfig: ConfigInput] = [:]
        for cfg in PressureConfig.allCases {
            var input = ConfigInput()
            if let existing {
                let values = existing.values(for: cfg)
                let unit = existing.preferredUnit
                input.front = values.front.map { PressureUnitFormat.fieldText(bar: $0, unit: unit) } ?? ""
                input.rear = values.rear.map { PressureUnitFormat.fieldText(bar: $0, unit: unit) } ?? ""
                // Without a sidecar the field never renders and stored values
                // are not loaded, so the next save clears them.
                if viewModel.motorcycle.hasSidecar ?? false {
                    input.sidecar = values.sidecar.map { PressureUnitFormat.fieldText(bar: $0, unit: unit) } ?? ""
                }
            }
            initial[cfg] = input
        }
        _inputs = State(initialValue: initial)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                header

                unitPicker
                configPicker

                pressureField("VORDERREIFEN", text: binding(\.front))
                pressureField("HINTERREIFEN", text: binding(\.rear))
                if hasSidecar {
                    pressureField("BEIWAGENREIFEN", text: binding(\.sidecar))
                }

                if state(of: config) == .incomplete {
                    Text("Vorder- und Hinterreifen zusammen erfassen.")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Theme.Colors.accent)
                }

                saveButton
                if isEditing && state(of: config) != .empty { deleteButton }
            }
            .padding(Theme.Spacing.l)
        }
        .background(Color.clear)
        .alert("Fehler", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "")
        }
        .alert(deleteRemovesRecord ? "Reifendruck-Eintrag löschen?" : "\(config.label) löschen?", isPresented: $confirmingDelete) {
            Button("Abbrechen", role: .cancel) { }
            Button("Löschen", role: .destructive) { deleteSelectedConfig() }
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Text(isEditing ? "Reifendruck bearbeiten" : "Reifendruck erfassen")
                .font(.system(size: 22, weight: .heavy))
                .foregroundColor(.white)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.white.opacity(0.12)))
            }
            .accessibilityLabel("Schließen")
        }
    }

    private var unitPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("EINHEIT")
                .font(.system(size: 10, weight: .heavy)).tracking(1.4)
                .foregroundColor(Theme.Glass.mutedText)
            GlassSegmentedControl(
                segments: [
                    .init(value: "bar", label: "bar"),
                    .init(value: "psi", label: "psi")
                ],
                selection: .init(
                    get: { unit },
                    set: { switchUnit(to: $0) }
                )
            )
        }
    }

    private var configPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("KONFIGURATION")
                .font(.system(size: 10, weight: .heavy)).tracking(1.4)
                .foregroundColor(Theme.Glass.mutedText)
            GlassSegmentedControl(
                segments: PressureConfig.allCases.map { cfg in
                    .init(value: cfg, label: state(of: cfg) == .complete ? "\(cfg.label) ✓" : cfg.label)
                },
                selection: $config
            )
            Text("Mindestens eine Konfiguration erfassen — Felder leer lassen, um eine zu entfernen.")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.45))
        }
    }

    private func pressureField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .heavy)).tracking(1.4)
                .foregroundColor(Theme.Glass.mutedText)
            HStack {
                TextField("", text: text, prompt: Text(unit == "psi" ? "z. B. 32" : "z. B. 2.2").foregroundColor(.white.opacity(0.3)))
                    .keyboardType(.decimalPad)
                    .foregroundColor(.white)
                Text(unit)
                    .font(.system(size: 11, weight: .heavy)).tracking(1)
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: Theme.Glass.fieldRadius).fill(Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: Theme.Glass.fieldRadius).stroke(Theme.Glass.border, lineWidth: 0.5))

            if let bar = PressureUnitFormat.parseToBar(text.wrappedValue, unit: unit) {
                Text(PressureUnitFormat.secondary(bar: bar, unit: unit))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.45))
            }
        }
    }

    private var saveButton: some View {
        Button(action: save) {
            Text(savedAnim ? "Gespeichert ✓" : "Speichern").frame(maxWidth: .infinity)
        }
        .buttonStyle(ModernButtonStyle())
        .disabled(!canSave || isSaving)
        .opacity(canSave && !isSaving ? 1 : 0.5)
        .padding(.top, Theme.Spacing.s)
    }

    private var deleteButton: some View {
        Button(role: .destructive) { confirmingDelete = true } label: {
            Text(deleteRemovesRecord ? "Eintrag löschen" : "\(config.label) löschen")
                .frame(maxWidth: .infinity)
                .foregroundColor(Theme.Colors.accent)
                .padding(.vertical, 12)
        }
        .disabled(isSaving)
    }

    // MARK: - State

    private func binding(_ keyPath: WritableKeyPath<ConfigInput, String>) -> Binding<String> {
        .init(
            get: { inputs[config, default: ConfigInput()][keyPath: keyPath] },
            set: { inputs[config, default: ConfigInput()][keyPath: keyPath] = $0 }
        )
    }

    /// Mirrors the webapp's rules: a configuration is complete when front and
    /// rear parse and the sidecar field is empty or parses; a half-filled or
    /// unparseable set blocks saving.
    private func state(of cfg: PressureConfig) -> ConfigState {
        let input = inputs[cfg, default: ConfigInput()]
        if input.isEmpty { return .empty }
        let front = PressureUnitFormat.parseToBar(input.front, unit: unit)
        let rear = PressureUnitFormat.parseToBar(input.rear, unit: unit)
        let sidecarText = input.sidecar.trimmingCharacters(in: .whitespaces)
        let sidecarOk = sidecarText.isEmpty || PressureUnitFormat.parseToBar(sidecarText, unit: unit) != nil
        return front != nil && rear != nil && sidecarOk ? .complete : .incomplete
    }

    private var canSave: Bool {
        let states = PressureConfig.allCases.map { state(of: $0) }
        return !states.contains(.incomplete) && states.contains(.complete)
    }

    /// Deleting the selected configuration removes the record when no other
    /// configuration holds values.
    private var deleteRemovesRecord: Bool {
        PressureConfig.allCases.allSatisfy { $0 == config || state(of: $0) != .complete }
    }

    // MARK: - Actions

    /// Serialize every complete configuration; `omitting` drops one, which is
    /// how a single set gets deleted (the server clears absent columns).
    private func buildPayload(omitting omitted: PressureConfig? = nil) -> [String: Any] {
        var payload: [String: Any] = ["preferredUnit": unit]
        let keys: [PressureConfig: (front: String, rear: String, sidecar: String)] = [
            .solo: ("frontBar", "rearBar", "sidecarBar"),
            .passenger: ("frontPassengerBar", "rearPassengerBar", "sidecarPassengerBar"),
            .offroad: ("frontOffroadBar", "rearOffroadBar", "sidecarOffroadBar"),
        ]
        for cfg in PressureConfig.allCases where cfg != omitted && state(of: cfg) == .complete {
            let input = inputs[cfg, default: ConfigInput()]
            let names = keys[cfg]!
            payload[names.front] = PressureUnitFormat.parseToBar(input.front, unit: unit)
            payload[names.rear] = PressureUnitFormat.parseToBar(input.rear, unit: unit)
            if let sidecar = PressureUnitFormat.parseToBar(input.sidecar, unit: unit) {
                payload[names.sidecar] = sidecar
            }
        }
        return payload
    }

    private func save() {
        guard canSave, !isSaving else { return }
        isSaving = true
        Task {
            do {
                try await viewModel.saveTirePressure(payload: buildPayload())
                withAnimation { savedAnim = true }
                try? await Task.sleep(nanoseconds: 400_000_000)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }

    private func deleteSelectedConfig() {
        guard !isSaving else { return }
        isSaving = true
        Task {
            do {
                if deleteRemovesRecord {
                    try await viewModel.deleteTirePressure()
                } else {
                    inputs[config] = ConfigInput()
                    try await viewModel.saveTirePressure(payload: buildPayload(omitting: config))
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }

    private func switchUnit(to next: String) {
        guard next != unit else { return }
        for cfg in PressureConfig.allCases {
            var input = inputs[cfg, default: ConfigInput()]
            input.front = convert(input.front, to: next)
            input.rear = convert(input.rear, to: next)
            input.sidecar = convert(input.sidecar, to: next)
            inputs[cfg] = input
        }
        unit = next
    }

    /// Convert a field string from the current unit to `next`, keeping the
    /// canonical bar value; unparseable text is left as typed.
    private func convert(_ text: String, to next: String) -> String {
        guard let bar = PressureUnitFormat.parseToBar(text, unit: unit) else { return text }
        return PressureUnitFormat.fieldText(bar: bar, unit: next)
    }
}
