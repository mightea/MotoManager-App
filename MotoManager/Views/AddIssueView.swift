import SwiftUI

/// Create/edit an issue ("Mangel"). Writes optimistically to SwiftData via the
/// view model, so it works offline and queues for sync.
struct AddIssueView: View {
    @ObservedObject var viewModel: MotorcycleDetailViewModel
    let existingIssue: SDIssue?
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var notes: String
    @State private var odo: String
    @State private var priority: String
    @State private var status: String
    @State private var date: Date
    @State private var savedAnim = false

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
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    field("TITEL") {
                        TextField("", text: $title, prompt: Text("z. B. Bremsbeläge abgenutzt").foregroundStyle(.tertiary))
                            .textInputAutocapitalization(.sentences)
                            .foregroundStyle(.primary)
                    }

                    field("KILOMETERSTAND") {
                        TextField("", text: $odo)
                            .keyboardType(.numberPad)
                            .foregroundStyle(.primary)
                    }

                    labeledSegment("PRIORITÄT", selection: $priority, options: priorities, label: priorityLabel)
                    labeledSegment("STATUS", selection: $status, options: statuses, label: statusLabel)

                    field("DATUM") {
                        DatePicker("", selection: $date, displayedComponents: .date)
                            .labelsHidden()
                            .tint(Theme.Colors.primary)
                    }

                    field("NOTIZEN") {
                        TextField("", text: $notes, prompt: Text("Optionale Details").foregroundStyle(.tertiary), axis: .vertical)
                            .lineLimit(3...6)
                            .foregroundStyle(.primary)
                    }
                }
                .padding(Theme.Spacing.l)
            }
            .navigationTitle(existingIssue == nil ? "Mangel erfassen" : "Mangel bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
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

    private func labeledSegment(_ label: String, selection: Binding<String>, options: [String], label labeler: @escaping (String) -> String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .scaledFont(10, weight: .heavy).tracking(1.4)
                .foregroundStyle(.secondary)
            GlassSegmentedControl(
                segments: options.map { .init(value: $0, label: labeler($0)) },
                selection: selection
            )
        }
    }

    private func priorityLabel(_ p: String) -> String {
        switch p { case "low": return "Niedrig"; case "high": return "Hoch"; default: return "Mittel" }
    }
    private func statusLabel(_ s: String) -> String {
        switch s { case "in_progress": return "In Arbeit"; case "done": return "Erledigt"; default: return "Neu" }
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let odoValue = Int(odo) ?? (viewModel.motorcycle.latestOdo ?? viewModel.motorcycle.initialOdo)
        let saved: Bool
        if let issue = existingIssue {
            saved = viewModel.updateIssue(issue, odo: odoValue, title: trimmed, description: notes, priority: priority, status: status, date: date)
        } else {
            saved = viewModel.createIssue(odo: odoValue, title: trimmed, description: notes, priority: priority, status: status, date: date)
        }
        guard saved else { return }
        withAnimation { savedAnim = true }
        Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            dismiss()
        }
    }
}
