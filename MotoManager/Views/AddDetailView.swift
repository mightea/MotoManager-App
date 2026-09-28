import SwiftUI

/// Create/edit a motorcycle detail (free-form Title/Value pair, e.g. spark
/// plug brand/model). Writes optimistically to SwiftData via the view model
/// (offline-first, queued for sync).
struct AddDetailView: View {
    @ObservedObject var viewModel: MotorcycleDetailViewModel
    let existingDetail: SDMotorcycleDetail?

    @State private var title: String
    @State private var value: String
    @State private var errorMessage: String?

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
        FormSheet(
            title: existingDetail == nil ? "Detail hinzufügen" : "Detail bearbeiten",
            canSave: canSave,
            tracked: [title, value],
            error: errorMessage,
            delete: existingDetail.map { detail in
                FormSheetDelete(title: "Detail löschen?") {
                    let ok = viewModel.deleteDetail(detail)
                    if !ok { errorMessage = "Löschen fehlgeschlagen." }
                    return ok
                }
            },
            onSave: save
        ) {
            FormField("Titel") {
                TextField("", text: $title, prompt: formPrompt("z. B. Zündkerze"))
            }
            FormField("Wert") {
                TextField("", text: $value, prompt: formPrompt("z. B. NGK DPR8EA-9"), axis: .vertical)
                    .lineLimit(1...5)
            }
        }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() async -> Bool {
        errorMessage = nil
        guard canSave else { return false }
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let saved: Bool
        if let d = existingDetail {
            saved = viewModel.updateDetail(d, title: t, value: v)
        } else {
            saved = viewModel.createDetail(title: t, value: v)
        }
        if !saved { errorMessage = "Speichern fehlgeschlagen." }
        return saved
    }
}
