import SwiftUI

/// Create/edit a motorcycle detail (free-form Title/Value pair, e.g. spark
/// plug brand/model). Writes optimistically to SwiftData via the view model
/// (offline-first, queued for sync).
struct AddDetailView: View {
    @ObservedObject var viewModel: MotorcycleDetailViewModel
    let existingDetail: SDMotorcycleDetail?
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var value: String
    @State private var confirmingDelete = false
    @State private var savedAnim = false

    init(viewModel: MotorcycleDetailViewModel, existingDetail: SDMotorcycleDetail? = nil) {
        self.viewModel = viewModel
        self.existingDetail = existingDetail
        if let d = existingDetail {
            _title = State(initialValue: d.title)
            _value = State(initialValue: d.value)
        } else {
            _title = State(initialValue: "")
            _value = State(initialValue: "")
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                header

                field("TITEL") {
                    TextField("", text: $title, prompt: Text("z. B. Zündkerze").foregroundColor(.white.opacity(0.3)))
                        .foregroundColor(.white)
                }
                field("WERT") {
                    TextField("", text: $value, prompt: Text("z. B. NGK DPR8EA-9").foregroundColor(.white.opacity(0.3)), axis: .vertical)
                        .lineLimit(1...5).foregroundColor(.white)
                }

                saveButton
                if existingDetail != nil { deleteButton }
            }
            .padding(Theme.Spacing.l)
        }
        .background(Color.clear)
        .alert("Detail löschen?", isPresented: $confirmingDelete) {
            Button("Abbrechen", role: .cancel) { }
            Button("Löschen", role: .destructive) {
                guard let detail = existingDetail,
                      viewModel.deleteDetail(detail) else { return }
                dismiss()
            }
        }
    }

    private var header: some View {
        HStack {
            Text(existingDetail == nil ? "Detail hinzufügen" : "Detail bearbeiten")
                .scaledFont(22, weight: .heavy)
                .foregroundColor(.white)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .scaledFont(14, weight: .bold)
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
                .scaledFont(10, weight: .heavy).tracking(1.4)
                .foregroundColor(Theme.Glass.mutedText)
            content()
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: Theme.Glass.fieldRadius).fill(Color.white.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: Theme.Glass.fieldRadius).stroke(Theme.Glass.border, lineWidth: 0.5))
        }
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
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        guard canSave else { return }
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let saved: Bool
        if let d = existingDetail {
            saved = viewModel.updateDetail(d, title: t, value: v)
        } else {
            saved = viewModel.createDetail(title: t, value: v)
        }
        guard saved else { return }
        withAnimation { savedAnim = true }
        Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            dismiss()
        }
    }
}
