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
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                header

                field("KATEGORIE") {
                    TextField("", text: $category, prompt: Text("z. B. Motor").foregroundColor(.white.opacity(0.3)))
                        .foregroundColor(.white)
                }
                field("BAUTEIL") {
                    TextField("", text: $name, prompt: Text("z. B. Ölablassschraube").foregroundColor(.white.opacity(0.3)))
                        .foregroundColor(.white)
                }
                HStack(spacing: Theme.Spacing.m) {
                    field("NM") {
                        TextField("", text: $torque, prompt: Text("42").foregroundColor(.white.opacity(0.3)))
                            .keyboardType(.decimalPad).foregroundColor(.white)
                    }
                    field("NM (BIS)") {
                        TextField("", text: $torqueEnd, prompt: Text("optional").foregroundColor(.white.opacity(0.3)))
                            .keyboardType(.decimalPad).foregroundColor(.white)
                    }
                }
                field("WERKZEUG") {
                    TextField("", text: $toolSize, prompt: Text("z. B. 17 mm").foregroundColor(.white.opacity(0.3)))
                        .foregroundColor(.white)
                }
                field("NOTIZEN") {
                    TextField("", text: $notes, prompt: Text("Optionale Details").foregroundColor(.white.opacity(0.3)), axis: .vertical)
                        .lineLimit(2...5).foregroundColor(.white)
                }

                unverifiedToggle

                saveButton
                if existingSpec != nil { deleteButton }
            }
            .padding(Theme.Spacing.l)
        }
        .background(Color.clear)
        .alert("Drehmoment löschen?", isPresented: $confirmingDelete) {
            Button("Abbrechen", role: .cancel) { }
            Button("Löschen", role: .destructive) {
                if let s = existingSpec { viewModel.deleteTorque(s) }
                dismiss()
            }
        }
    }

    private var header: some View {
        HStack {
            Text(existingSpec == nil ? "Drehmoment hinzufügen" : "Drehmoment bearbeiten")
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

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .heavy)).tracking(1.4)
                .foregroundColor(Theme.Glass.mutedText)
            content()
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: Theme.Glass.fieldRadius).fill(Color.white.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: Theme.Glass.fieldRadius).stroke(Theme.Glass.border, lineWidth: 0.5))
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
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundColor(.white)
                    } else {
                        Circle()
                            .stroke(Color.white.opacity(0.35), lineWidth: 1.5)
                            .frame(width: 18, height: 18)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Unverifiziert")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(unverified ? Color.orange : .white)
                    Text("Wert aus unsicherer Quelle")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.white.opacity(0.5))
                }
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: Theme.Glass.fieldRadius)
                    .fill(unverified ? Color.orange.opacity(0.16) : Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Glass.fieldRadius)
                    .stroke(unverified ? Color.orange.opacity(0.35) : Theme.Glass.border, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Unverifiziert")
        .accessibilityValue(unverified ? "aktiviert" : "deaktiviert")
    }

    private var saveButton: some View {
        Button(action: save) {
            Text(savedAnim ? "Gespeichert ✓" : "Speichern").frame(maxWidth: .infinity)
        }
        .buttonStyle(ModernButtonStyle())
        .disabled(!canSave)
        .opacity(canSave ? 1 : 0.5)
        .padding(.top, Theme.Spacing.s)
    }

    private var deleteButton: some View {
        Button(role: .destructive) { confirmingDelete = true } label: {
            Text("Löschen").frame(maxWidth: .infinity).foregroundColor(Theme.Colors.accent)
                .padding(.vertical, 12)
        }
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
        if let s = existingSpec {
            viewModel.updateTorque(s, category: cat, name: nm, torque: torqueValue,
                                   torqueEnd: Self.parse(torqueEnd), variation: Self.parse(variation),
                                   toolSize: toolSize, description: notes, unverified: unverified)
        } else {
            viewModel.createTorque(category: cat, name: nm, torque: torqueValue,
                                   torqueEnd: Self.parse(torqueEnd), variation: Self.parse(variation),
                                   toolSize: toolSize, description: notes, unverified: unverified)
        }
        withAnimation { savedAnim = true }
        Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            dismiss()
        }
    }

    private static func parse(_ s: String) -> Double? {
        Double(s.replacingOccurrences(of: ",", with: "."))
    }
    private static func num(_ d: Double) -> String {
        d == d.rounded() ? String(Int(d)) : String(d)
    }
}
