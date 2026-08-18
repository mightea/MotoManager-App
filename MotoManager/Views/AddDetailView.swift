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
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    field("TITEL") {
                        TextField("", text: $title, prompt: Text("z. B. Zündkerze").foregroundStyle(.tertiary))
                            .foregroundStyle(.primary)
                    }
                    field("WERT") {
                        TextField("", text: $value, prompt: Text("z. B. NGK DPR8EA-9").foregroundStyle(.tertiary), axis: .vertical)
                            .lineLimit(1...5).foregroundStyle(.primary)
                    }

                    if existingDetail != nil { deleteButton }
                }
                .padding(Theme.Spacing.l)
            }
            .navigationTitle(existingDetail == nil ? "Detail hinzufügen" : "Detail bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") { save() }
                        .disabled(!canSave)
                }
            }
            .alert("Detail löschen?", isPresented: $confirmingDelete) {
                Button("Abbrechen", role: .cancel) { }
                Button("Löschen", role: .destructive) {
                    guard let detail = existingDetail,
                          viewModel.deleteDetail(detail) else { return }
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

    private var deleteButton: some View {
        Button(role: .destructive) { confirmingDelete = true } label: {
            Text("Löschen").frame(maxWidth: .infinity)
        }
        .glassActionButton(.danger, in: .roundedRectangle(radius: Theme.Radius.control))
        .padding(.top, Theme.Spacing.s)
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
