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
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                header

                field("TITEL") {
                    TextField("", text: $title, prompt: Text("z. B. Bremsbeläge abgenutzt").foregroundColor(.white.opacity(0.3)))
                        .textInputAutocapitalization(.sentences)
                        .foregroundColor(.white)
                }

                field("KILOMETERSTAND") {
                    TextField("", text: $odo)
                        .keyboardType(.numberPad)
                        .foregroundColor(.white)
                }

                labeledSegment("PRIORITÄT", selection: $priority, options: priorities, label: priorityLabel)
                labeledSegment("STATUS", selection: $status, options: statuses, label: statusLabel)

                field("DATUM") {
                    DatePicker("", selection: $date, displayedComponents: .date)
                        .labelsHidden()
                        .colorScheme(.dark)
                        .tint(Theme.Colors.primary)
                }

                field("NOTIZEN") {
                    TextField("", text: $notes, prompt: Text("Optionale Details").foregroundColor(.white.opacity(0.3)), axis: .vertical)
                        .lineLimit(3...6)
                        .foregroundColor(.white)
                }

                saveButton
            }
            .padding(Theme.Spacing.l)
        }
        .background(Color.clear)
    }

    private var header: some View {
        HStack {
            Text(existingIssue == nil ? "Mangel erfassen" : "Mangel bearbeiten")
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

    private func labeledSegment(_ label: String, selection: Binding<String>, options: [String], label labeler: @escaping (String) -> String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .scaledFont(10, weight: .heavy).tracking(1.4)
                .foregroundColor(Theme.Glass.mutedText)
            Picker(label, selection: selection) {
                ForEach(options, id: \.self) { Text(labeler($0)).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    private var saveButton: some View {
        Button(action: save) {
            Text(savedAnim ? "Gespeichert ✓" : "Speichern")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(ModernButtonStyle())
        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
        .opacity(title.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
        .padding(.top, Theme.Spacing.s)
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
