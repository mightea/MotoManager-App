import SwiftUI

/// Create/edit an issue ("Mangel"). Writes optimistically to SwiftData via the
/// view model, so it works offline and queues for sync.
struct AddIssueView: View {
    @ObservedObject var viewModel: MotorcycleDetailViewModel
    let existingIssue: SDIssue?

    @State private var title: String
    @State private var notes: String
    @State private var odo: String
    @State private var priority: String
    @State private var status: String
    @State private var date: Date
    @State private var errorMessage: String?

    private let priorities = ["low", "medium", "high"]
    private let statuses = ["new", "in_progress", "done"]

    init(viewModel: MotorcycleDetailViewModel, existingIssue: SDIssue? = nil) {
        self.viewModel = viewModel
        self.existingIssue = existingIssue
        if let issue = existingIssue {
            _title = State(initialValue: issue.title)
            _notes = State(initialValue: issue.recordDescription ?? "")
            _odo = State(initialValue: "\(issue.odo)")
            _priority = State(initialValue: issue.priority)
            _status = State(initialValue: issue.status)
            let f = ISO8601DateFormatter(); f.formatOptions = [.withFullDate]
            _date = State(initialValue: f.date(from: issue.date) ?? Date())
        } else {
            _title = State(initialValue: "")
            _notes = State(initialValue: "")
            _odo = State(initialValue: "\(viewModel.motorcycle.latestOdo ?? viewModel.motorcycle.initialOdo)")
            _priority = State(initialValue: "medium")
            _status = State(initialValue: "new")
            _date = State(initialValue: Date())
        }
    }

    var body: some View {
        FormSheet(
            title: existingIssue == nil ? "Mangel erfassen" : "Mangel bearbeiten",
            canSave: canSave,
            tracked: [title, notes, odo, priority, status, date],
            error: errorMessage,
            delete: existingIssue.map { issue in
                FormSheetDelete(title: "Mangel löschen?") {
                    let ok = viewModel.deleteIssue(issue)
                    if !ok { errorMessage = "Löschen fehlgeschlagen." }
                    return ok
                }
            },
            onSave: save
        ) {
            FormField("Titel") {
                TextField("", text: $title, prompt: formPrompt("z. B. Bremsbeläge abgenutzt"))
                    .textInputAutocapitalization(.sentences)
            }

            FormField("Kilometerstand", unit: "km") {
                TextField("", text: $odo)
                    .keyboardType(.numberPad)
            }

            VStack(alignment: .leading, spacing: 6) {
                FormLabel("Priorität")
                GlassSegmentedControl(
                    segments: priorities.map { .init(value: $0, label: priorityLabel($0)) },
                    selection: $priority
                )
            }
            VStack(alignment: .leading, spacing: 6) {
                FormLabel("Status")
                GlassSegmentedControl(
                    segments: statuses.map { .init(value: $0, label: statusLabel($0)) },
                    selection: $status
                )
            }

            FormField("Datum") {
                DatePicker("", selection: $date, displayedComponents: .date)
                    .labelsHidden()
                    .tint(Theme.Colors.primary)
            }

            FormField("Notizen") {
                TextField("", text: $notes, prompt: formPrompt("Optionale Details"), axis: .vertical)
                    .lineLimit(3...6)
            }
        }
    }

    private func priorityLabel(_ p: String) -> String {
        switch p { case "low": return "Niedrig"; case "high": return "Hoch"; default: return "Mittel" }
    }
    private func statusLabel(_ s: String) -> String {
        switch s { case "in_progress": return "In Arbeit"; case "done": return "Erledigt"; default: return "Neu" }
    }

    private var parsedOdo: Int? {
        Int(odo.trimmingCharacters(in: .whitespaces))
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && parsedOdo != nil
    }

    private func save() async -> Bool {
        errorMessage = nil
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let odoValue = parsedOdo else { return false }
        let saved: Bool
        if let issue = existingIssue {
            saved = viewModel.updateIssue(issue, odo: odoValue, title: trimmed, description: notes, priority: priority, status: status, date: date)
        } else {
            saved = viewModel.createIssue(odo: odoValue, title: trimmed, description: notes, priority: priority, status: status, date: date)
        }
        if !saved { errorMessage = "Speichern fehlgeschlagen." }
        return saved
    }
}
