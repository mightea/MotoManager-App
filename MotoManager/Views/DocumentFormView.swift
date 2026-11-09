import SwiftUI

/// A picked file (or scan) waiting for its title and type before upload. The
/// bytes are read only when the upload starts.
struct PendingDocumentUpload: Identifiable {
    let id = UUID()
    let title: String
    let fileName: String
    let mimeType: String
    let data: @Sendable () throws -> Data
}

/// Title and type of a document: before an upload, or to edit one the user
/// owns. Online-only, like every document write.
struct DocumentFormView: View {
    enum Mode {
        case upload(PendingDocumentUpload)
        case edit(Document)
    }

    let mode: Mode
    /// Upload: hand the details back (the caller runs the upload and shows its
    /// progress). Edit: save here and report the updated document.
    let onUpload: (PendingDocumentUpload, String, DocumentType?) -> Void
    let onSaved: (Document) -> Void
    @ObservedObject var viewModel: MotorcycleDetailViewModel

    @State private var title: String
    @State private var docType: DocumentType?
    @State private var errorMessage: String?

    init(mode: Mode, viewModel: MotorcycleDetailViewModel,
         onUpload: @escaping (PendingDocumentUpload, String, DocumentType?) -> Void = { _, _, _ in },
         onSaved: @escaping (Document) -> Void = { _ in }) {
        self.mode = mode
        self.viewModel = viewModel
        self.onUpload = onUpload
        self.onSaved = onSaved
        switch mode {
        case .upload(let pending):
            _title = State(initialValue: pending.title)
            _docType = State(initialValue: nil)
        case .edit(let document):
            _title = State(initialValue: document.title)
            _docType = State(initialValue: document.documentType)
        }
        _errorMessage = State(initialValue: nil)
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var sheetTitle: String {
        if case .upload = mode { return "Dokument hochladen" }
        return "Dokument bearbeiten"
    }

    var body: some View {
        FormSheet(
            title: sheetTitle,
            canSave: !trimmedTitle.isEmpty,
            tracked: [title, docType?.key ?? ""],
            error: errorMessage,
            onSave: save
        ) {
            if case .upload(let pending) = mode {
                Label(pending.fileName, systemImage: "doc")
                    .scaledFont(13, weight: .semibold)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            FormField("Titel") {
                TextField("", text: $title, prompt: formPrompt("z. B. Werkstatthandbuch 2019"))
                    .accessibilityIdentifier("documentForm.title")
            }
            FormField("Typ") {
                Picker("Typ", selection: $docType) {
                    Text("Kein Typ").tag(DocumentType?.none)
                    ForEach(DocumentType.allCases) { type in
                        Label(type.label, systemImage: type.systemImage).tag(DocumentType?.some(type))
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .accessibilityIdentifier("documentForm.type")
            }
        }
    }

    private func save() async -> Bool {
        errorMessage = nil
        guard !trimmedTitle.isEmpty else { return false }
        switch mode {
        case .upload(let pending):
            onUpload(pending, trimmedTitle, docType)
            return true
        case .edit(let document):
            do {
                let updated = try await viewModel.updateDocument(document, title: trimmedTitle, docType: docType)
                onSaved(updated)
                return true
            } catch {
                errorMessage = error.localizedDescription
                return false
            }
        }
    }
}
