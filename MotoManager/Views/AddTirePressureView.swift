import SwiftUI

/// Create/edit the recommended tire pressures. One riding configuration
/// (Solo / Sozius / Offroad) is edited at a time via a segmented control;
/// values entered for the others are kept and everything saves together.
/// Every configuration is optional but at least one complete front/rear
/// pair is required; deleting removes only the selected configuration —
/// deleting the last one removes the record. Online-only (no offline queue):
/// failures surface as an inline error and the sheet stays open.
struct AddTirePressureView: View {
    @ObservedObject var viewModel: MotorcycleDetailViewModel

    private struct ConfigInput: Hashable {
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
    @State private var errorMessage: String?

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
        FormSheet(
            title: isEditing ? "Reifendruck bearbeiten" : "Reifendruck erfassen",
            canSave: canSave,
            tracked: [unit, inputs],
            error: errorMessage,
            delete: isEditing && state(of: config) != .empty ? deleteAction : nil,
            onSave: save
        ) {
            unitPicker
            configPicker

            pressureField("Vorderreifen", text: binding(\.front))
            pressureField("Hinterreifen", text: binding(\.rear))
            if hasSidecar {
                pressureField("Beiwagenreifen", text: binding(\.sidecar))
            }

            if state(of: config) == .incomplete {
                Text("Vorder- und Hinterreifen zusammen erfassen.")
                    .scaledFont(11, weight: .semibold)
                    .foregroundStyle(Theme.Colors.accent)
            }
        }
    }

    // MARK: - Sections

    private var unitPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            FormLabel("Einheit")
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
            FormLabel("Konfiguration")
            GlassSegmentedControl(
                segments: PressureConfig.allCases.map { cfg in
                    .init(value: cfg, label: state(of: cfg) == .complete ? "\(cfg.label) ✓" : cfg.label)
                },
                selection: $config
            )
            Text("Mindestens eine Konfiguration erfassen — Felder leer lassen, um eine zu entfernen.")
                .scaledFont(11, weight: .medium)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Pressure input with the unit as suffix; the hint shows the value
    /// converted to the other unit once it parses.
    private func pressureField(_ label: String, text: Binding<String>) -> some View {
        FormField(
            label,
            unit: unit,
            hint: PressureUnitFormat.parseToBar(text.wrappedValue, unit: unit)
                .map { PressureUnitFormat.secondary(bar: $0, unit: unit) }
        ) {
            TextField("", text: text, prompt: formPrompt(unit == "psi" ? "z. B. 32" : "z. B. 2.2"))
                .keyboardType(.decimalPad)
        }
    }

    /// Deletes only the selected configuration, or the whole record when no
    /// other configuration holds values.
    private var deleteAction: FormSheetDelete {
        FormSheetDelete(
            title: deleteRemovesRecord ? "Reifendruck-Eintrag löschen?" : "\(config.label) löschen?",
            message: deleteRemovesRecord
                ? "Der gesamte Reifendruck-Eintrag wird entfernt."
                : "Nur die Konfiguration \(config.label) wird entfernt, die übrigen bleiben erhalten."
        ) {
            await deleteSelectedConfig()
        }
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

    /// Present a save/delete failure inline. A connectivity failure reads as
    /// "Offline"; anything else shows the error's description.
    private func present(_ error: Error) {
        if case APIError.offline = error {
            errorMessage = APIError.offline.errorDescription ?? "Offline"
        } else {
            errorMessage = error.localizedDescription
        }
    }

    private func save() async -> Bool {
        errorMessage = nil
        guard canSave else { return false }
        do {
            try await viewModel.saveTirePressure(payload: buildPayload())
            return true
        } catch {
            present(error)
            return false
        }
    }

    private func deleteSelectedConfig() async -> Bool {
        errorMessage = nil
        do {
            if deleteRemovesRecord {
                try await viewModel.deleteTirePressure()
            } else {
                try await viewModel.saveTirePressure(payload: buildPayload(omitting: config))
                inputs[config] = ConfigInput()
            }
            return true
        } catch {
            present(error)
            return false
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
