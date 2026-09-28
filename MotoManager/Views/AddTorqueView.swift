import SwiftUI

/// Create/edit a torque spec. Writes optimistically to SwiftData via the view
/// model (offline-first, queued for sync).
struct AddTorqueView: View {
    @ObservedObject var viewModel: MotorcycleDetailViewModel
    let existingSpec: SDTorqueSpec?

    @State private var category: String
    @State private var name: String
    @State private var torque: String
    @State private var torqueEnd: String
    @State private var variation: String
    @State private var toolSize: String
    @State private var notes: String
    @State private var unverified: Bool

    init(viewModel: MotorcycleDetailViewModel, existingSpec: SDTorqueSpec? = nil) {
        self.viewModel = viewModel
        self.existingSpec = existingSpec
        if let s = existingSpec {
            _category = State(initialValue: s.category)
            _name = State(initialValue: s.name)
            _torque = State(initialValue: Self.num(s.torque))
            _torqueEnd = State(initialValue: s.torqueEnd.map(Self.num) ?? "")
            _variation = State(initialValue: s.variation.map(Self.num) ?? "")
            _toolSize = State(initialValue: s.toolSize ?? "")
            _notes = State(initialValue: s.recordDescription ?? "")
            _unverified = State(initialValue: s.unverified)
        } else {
            _category = State(initialValue: "")
            _name = State(initialValue: "")
            _torque = State(initialValue: "")
            _torqueEnd = State(initialValue: "")
            _variation = State(initialValue: "")
            _toolSize = State(initialValue: "")
            _notes = State(initialValue: "")
            _unverified = State(initialValue: false)
        }
    }

    var body: some View {
        FormSheet(
            title: existingSpec == nil ? "Drehmoment hinzufügen" : "Drehmoment bearbeiten",
            canSave: canSave,
            tracked: [category, name, torque, torqueEnd, variation, toolSize, notes, unverified],
            delete: existingSpec.map { spec in
                FormSheetDelete(title: "Drehmoment löschen?") { viewModel.deleteTorque(spec) }
            },
            onSave: save
        ) {
            FormField("Kategorie") {
                TextField("", text: $category, prompt: formPrompt("z. B. Motor"))
            }
            FormField("Bauteil") {
                TextField("", text: $name, prompt: formPrompt("z. B. Ölablassschraube"))
            }
            HStack(alignment: .top, spacing: Theme.Spacing.m) {
                FormField("Drehmoment", unit: "Nm") {
                    TextField("", text: $torque, prompt: formPrompt("42"))
                        .keyboardType(.decimalPad)
                }
                FormField("Bis", unit: "Nm") {
                    TextField("", text: $torqueEnd, prompt: formPrompt("optional"))
                        .keyboardType(.decimalPad)
                }
            }
            FormField("Toleranz", unit: "± Nm", hint: "Optional, statt eines Bereichs") {
                TextField("", text: $variation, prompt: formPrompt("z. B. 2"))
                    .keyboardType(.decimalPad)
            }
            FormField("Werkzeug") {
                TextField("", text: $toolSize, prompt: formPrompt("z. B. 17 mm"))
            }
            FormField("Notizen") {
                TextField("", text: $notes, prompt: formPrompt("Optionale Details"), axis: .vertical)
                    .lineLimit(2...5)
            }
            // Marks the spec as coming from an uncertain source; surfaced with
            // a warning color in the workshop list (orange = warning).
            FormToggleRow(
                title: "Unverifiziert",
                subtitle: "Wert aus unsicherer Quelle",
                isOn: $unverified,
                tint: .orange
            )
        }
    }

    private var canSave: Bool {
        !category.trimmingCharacters(in: .whitespaces).isEmpty
            && !name.trimmingCharacters(in: .whitespaces).isEmpty
            && Self.parse(torque) != nil
    }

    private func save() async -> Bool {
        guard canSave, let torqueValue = Self.parse(torque) else { return false }
        let cat = category.trimmingCharacters(in: .whitespaces)
        let nm = name.trimmingCharacters(in: .whitespaces)
        if let s = existingSpec {
            return viewModel.updateTorque(s, category: cat, name: nm, torque: torqueValue,
                                          torqueEnd: Self.parse(torqueEnd), variation: Self.parse(variation),
                                          toolSize: toolSize, description: notes, unverified: unverified)
        }
        return viewModel.createTorque(category: cat, name: nm, torque: torqueValue,
                                      torqueEnd: Self.parse(torqueEnd), variation: Self.parse(variation),
                                      toolSize: toolSize, description: notes, unverified: unverified)
    }

    nonisolated private static func parse(_ s: String) -> Double? {
        Double(s.replacingOccurrences(of: ",", with: "."))
    }
    nonisolated private static func num(_ d: Double) -> String {
        d == d.rounded() ? String(Int(d)) : String(d)
    }
}
