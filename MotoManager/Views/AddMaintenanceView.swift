import SwiftUI

/// Create/edit a non-fuel maintenance record (oil, tire, inspection, …).
/// Writes optimistically to SwiftData via the view model (offline-first).
struct AddMaintenanceView: View {
    @ObservedObject var viewModel: MotorcycleDetailViewModel
    let existingRecord: SDMaintenanceRecord?
    @Environment(\.dismiss) private var dismiss

    /// (value sent to the API, German label).
    static let types: [(value: String, label: String)] = [
        ("service", "Service"),
        ("oil", "Öl"),
        ("tire", "Reifen"),
        ("inspection", "Inspektion"),
        ("chain", "Antrieb"),
        ("brakes", "Bremsen"),
        ("battery", "Elektrik"),
        ("coolant", "Kühler"),
    ]

    @State private var type: String
    @State private var odo: String
    @State private var cost: String
    @State private var currency: String
    @State private var notes: String
    @State private var date: Date
    @State private var confirmingDelete = false
    @State private var savedAnim = false

    init(viewModel: MotorcycleDetailViewModel, existingRecord: SDMaintenanceRecord? = nil) {
        self.viewModel = viewModel
        self.existingRecord = existingRecord
        if let r = existingRecord {
            _type = State(initialValue: r.recordType)
            _odo = State(initialValue: "\(r.odo)")
            _cost = State(initialValue: r.cost.map { String($0) } ?? "")
            _currency = State(initialValue: r.currency ?? viewModel.motorcycle.currencyCode ?? "CHF")
            _notes = State(initialValue: r.recordDescription ?? r.summary ?? "")
            let f = ISO8601DateFormatter(); f.formatOptions = [.withFullDate]
            _date = State(initialValue: f.date(from: r.date) ?? Date())
        } else {
            _type = State(initialValue: "service")
            _odo = State(initialValue: "\(viewModel.motorcycle.latestOdo ?? viewModel.motorcycle.initialOdo)")
            _cost = State(initialValue: "")
            _currency = State(initialValue: viewModel.motorcycle.currencyCode ?? "CHF")
            _notes = State(initialValue: "")
            _date = State(initialValue: Date())
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                header

                field("ART") {
                    Picker("Art", selection: $type) {
                        ForEach(Self.types, id: \.value) { Text($0.label).tag($0.value) }
                    }
                    .pickerStyle(.menu)
                    .tint(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                field("KILOMETERSTAND") {
                    TextField("", text: $odo).keyboardType(.numberPad).foregroundColor(.white)
                }
                HStack(spacing: Theme.Spacing.m) {
                    field("KOSTEN") {
                        TextField("", text: $cost, prompt: Text("0").foregroundColor(.white.opacity(0.3)))
                            .keyboardType(.decimalPad).foregroundColor(.white)
                    }
                    field("WÄHRUNG") {
                        TextField("", text: $currency).foregroundColor(.white)
                            .textInputAutocapitalization(.characters)
                    }
                }
                field("DATUM") {
                    DatePicker("", selection: $date, displayedComponents: .date)
                        .labelsHidden().colorScheme(.dark).tint(Theme.Colors.primary)
                }
                field("BESCHREIBUNG") {
                    TextField("", text: $notes, prompt: Text("z. B. Ölwechsel + Filter").foregroundColor(.white.opacity(0.3)), axis: .vertical)
                        .lineLimit(2...5).foregroundColor(.white)
                }

                saveButton
                if existingRecord != nil { deleteButton }
            }
            .padding(Theme.Spacing.l)
        }
        .background(Color.clear)
        .alert("Eintrag löschen?", isPresented: $confirmingDelete) {
            Button("Abbrechen", role: .cancel) { }
            Button("Löschen", role: .destructive) {
                if let r = existingRecord { viewModel.deleteMaintenance(r) }
                dismiss()
            }
        }
    }

    private var header: some View {
        HStack {
            Text(existingRecord == nil ? "Wartung erfassen" : "Wartung bearbeiten")
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

    private var saveButton: some View {
        Button(action: save) {
            Text(savedAnim ? "Gespeichert ✓" : "Speichern").frame(maxWidth: .infinity)
        }
        .buttonStyle(ModernButtonStyle())
        .padding(.top, Theme.Spacing.s)
    }

    private var deleteButton: some View {
        Button(role: .destructive) { confirmingDelete = true } label: {
            Text("Löschen").frame(maxWidth: .infinity).foregroundColor(Theme.Colors.accent).padding(.vertical, 12)
        }
    }

    private func save() {
        let odoValue = Int(odo) ?? (viewModel.motorcycle.latestOdo ?? viewModel.motorcycle.initialOdo)
        let costValue = Double(cost.replacingOccurrences(of: ",", with: ".")) ?? 0
        if let r = existingRecord {
            viewModel.updateMaintenance(r, type: type, odo: odoValue, date: date, cost: costValue, currency: currency, description: notes)
        } else {
            viewModel.createMaintenance(type: type, odo: odoValue, date: date, cost: costValue, currency: currency, description: notes)
        }
        withAnimation { savedAnim = true }
        Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            dismiss()
        }
    }
}
