import SwiftUI

/// Create/edit a torque spec. Writes optimistically to SwiftData via the view
/// model (offline-first, queued for sync).
struct AddTorqueView: View {
    @ObservedObject var viewModel: MotorcycleDetailViewModel
    let existingSpec: SDTorqueSpec?
    @Environment(\.dismiss) private var dismiss

    @State private var category: String
    @State private var name: String
    @State private var torque: String
    @State private var torqueEnd: String
    @State private var variation: String
    @State private var toolSize: String
    @State private var notes: String
    @State private var unverified: Bool
    @State private var confirmingDelete = false
    @State private var savedAnim = false

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
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    field("KATEGORIE") {
                        TextField("", text: $category, prompt: Text("z. B. Motor").foregroundStyle(.tertiary))
                            .foregroundStyle(.primary)
                    }
                    field("BAUTEIL") {
                        TextField("", text: $name, prompt: Text("z. B. Ölablassschraube").foregroundStyle(.tertiary))
                            .foregroundStyle(.primary)
                    }
                    HStack(spacing: Theme.Spacing.m) {
                        field("NM") {
                            TextField("", text: $torque, prompt: Text("42").foregroundStyle(.tertiary))
                                .keyboardType(.decimalPad).foregroundStyle(.primary)
                        }
                        field("NM (BIS)") {
                            TextField("", text: $torqueEnd, prompt: Text("optional").foregroundStyle(.tertiary))
                                .keyboardType(.decimalPad).foregroundStyle(.primary)
                        }
                    }
                    field("WERKZEUG") {
                        TextField("", text: $toolSize, prompt: Text("z. B. 17 mm").foregroundStyle(.tertiary))
                            .foregroundStyle(.primary)
                    }
                    field("NOTIZEN") {
                        TextField("", text: $notes, prompt: Text("Optionale Details").foregroundStyle(.tertiary), axis: .vertical)
                            .lineLimit(2...5).foregroundStyle(.primary)
                    }

                    unverifiedToggle

                    if existingSpec != nil { deleteButton }
                }
                .padding(Theme.Spacing.l)
            }
            .navigationTitle(existingSpec == nil ? "Drehmoment hinzufügen" : "Drehmoment bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            // Success tick when the save lands (HIG: haptic feedback for
            // user-initiated confirmations).
            .sensoryFeedback(.success, trigger: savedAnim) { _, new in new }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") { save() }
                        .disabled(!canSave)
                }
            }
            .alert("Drehmoment löschen?", isPresented: $confirmingDelete) {
                Button("Abbrechen", role: .cancel) { }
                Button("Löschen", role: .destructive) {
                    guard let spec = existingSpec,
                          viewModel.deleteTorque(spec) else { return }
                    dismiss()
                }
            }
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .scaledFont(10, weight: .heavy).tracking(1.4)
                .foregroundStyle(.secondary)
            content()
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.field).fill(Color.primary.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.field).stroke(Theme.Glass.border, lineWidth: 0.5))
        }
    }

    /// Marks the spec as coming from an uncertain source; surfaced with a warning
    /// color in the workshop list. Orange follows the app's warning convention.
    private var unverifiedToggle: some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) {
                unverified.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(unverified ? Color.orange : Color.clear)
                        .frame(width: 18, height: 18)
                    if unverified {
                        Image(systemName: "checkmark")
                            .scaledFont(10, weight: .heavy)
                            .foregroundStyle(Color.white)
                    } else {
                        Circle()
                            .stroke(Color.primary.opacity(0.35), lineWidth: 1.5)
                            .frame(width: 18, height: 18)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Unverifiziert")
                        .scaledFont(13, weight: .semibold)
                        .foregroundStyle(unverified ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.primary))
                    Text("Wert aus unsicherer Quelle")
                        .scaledFont(11, weight: .regular)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.field)
                    .fill(unverified ? Color.orange.opacity(0.16) : Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.field)
                    .stroke(unverified ? Color.orange.opacity(0.35) : Theme.Glass.border, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Unverifiziert")
        .accessibilityValue(unverified ? "aktiviert" : "deaktiviert")
    }

    private var deleteButton: some View {
        Button(role: .destructive) { confirmingDelete = true } label: {
            Text("Löschen").frame(maxWidth: .infinity)
        }
        .glassActionButton(.danger, in: .roundedRectangle(radius: Theme.Radius.control))
        .padding(.top, Theme.Spacing.s)
    }

    private var canSave: Bool {
        !category.trimmingCharacters(in: .whitespaces).isEmpty
            && !name.trimmingCharacters(in: .whitespaces).isEmpty
            && Self.parse(torque) != nil
    }

    private func save() {
        guard canSave, let torqueValue = Self.parse(torque) else { return }
        let cat = category.trimmingCharacters(in: .whitespaces)
        let nm = name.trimmingCharacters(in: .whitespaces)
        let saved: Bool
        if let s = existingSpec {
            saved = viewModel.updateTorque(s, category: cat, name: nm, torque: torqueValue,
                                   torqueEnd: Self.parse(torqueEnd), variation: Self.parse(variation),
                                   toolSize: toolSize, description: notes, unverified: unverified)
        } else {
            saved = viewModel.createTorque(category: cat, name: nm, torque: torqueValue,
                                   torqueEnd: Self.parse(torqueEnd), variation: Self.parse(variation),
                                   toolSize: toolSize, description: notes, unverified: unverified)
        }
        guard saved else { return }
        withAnimation { savedAnim = true }
        Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            dismiss()
        }
    }

    nonisolated private static func parse(_ s: String) -> Double? {
        Double(s.replacingOccurrences(of: ",", with: "."))
    }
    nonisolated private static func num(_ d: Double) -> String {
        d == d.rounded() ? String(Int(d)) : String(d)
    }
}
