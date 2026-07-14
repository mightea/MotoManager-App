import SwiftUI
import SwiftData

/// Create/edit a non-fuel maintenance record (oil, tire, inspection, …).
/// Writes optimistically to SwiftData via the view model (offline-first).
struct AddMaintenanceView: View {
    @ObservedObject var viewModel: MotorcycleDetailViewModel
    let existingRecord: SDMaintenanceRecord?
    @Environment(\.dismiss) private var dismiss

    /// Parts consumed by this repair (partClientId → quantity). Create-only:
    /// consumptions of an existing record are managed in the Teile tab.
    @State private var usedParts: [UUID: Int] = [:]
    @State private var availableParts: [SDPart] = []

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
    @State private var showingOdoScanner = false

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
                    HStack(spacing: 8) {
                        TextField("", text: $odo).keyboardType(.numberPad).foregroundColor(.white)
                        Button {
                            showingOdoScanner = true
                        } label: {
                            Image(systemName: "camera.viewfinder")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(Theme.Colors.primary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Kilometerstand scannen")
                    }
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

                if existingRecord == nil {
                    usedPartsSection
                }

                saveButton
                if existingRecord != nil { deleteButton }
            }
            .padding(Theme.Spacing.l)
        }
        .background(Color.clear)
        .sheet(isPresented: $showingOdoScanner) {
            OdometerScanSheet(onResult: { value in odo = "\(value)" })
            .presentationDetents([.large])
            .presentationCornerRadius(Theme.Glass.sheetRadius)
            .presentationBackground(.regularMaterial)
            .presentationDragIndicator(.visible)
        }
        .onAppear {
            availableParts = PartsInventory.availableParts(
                in: PersistenceController.shared.mainContext)
        }
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

    // MARK: - Verwendete Teile (consumption from the parts inventory)

    @ViewBuilder
    private var usedPartsSection: some View {
        if !availableParts.isEmpty {
            field("VERWENDETE TEILE") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(selectedParts, id: \.clientId) { part in
                        usedPartRow(part)
                    }
                    addPartMenu
                }
            }
        }
    }

    private var selectedParts: [SDPart] {
        availableParts.filter { usedParts[$0.clientId] != nil }
    }

    private var unselectedParts: [SDPart] {
        availableParts.filter { usedParts[$0.clientId] == nil }
    }

    private func usedPartRow(_ part: SDPart) -> some View {
        let context = PersistenceController.shared.mainContext
        let maxQuantity = PartsInventory.onHand(for: part.clientId, in: context)
        let quantity = usedParts[part.clientId] ?? 1
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(part.name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text("\(part.partNumber) · \(maxQuantity) auf Lager")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
            }
            Spacer(minLength: 0)
            Stepper(
                value: Binding(
                    get: { usedParts[part.clientId] ?? 1 },
                    set: { usedParts[part.clientId] = $0 }
                ),
                in: 1...max(1, maxQuantity)
            ) {
                Text("\(quantity)×")
                    .font(.system(size: 13, weight: .heavy))
                    .monospacedDigit()
                    .foregroundColor(Theme.Colors.primary)
            }
            .colorScheme(.dark)
            .fixedSize()
            Button {
                usedParts.removeValue(forKey: part.clientId)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.white.opacity(0.35))
            }
        }
    }

    @ViewBuilder
    private var addPartMenu: some View {
        if !unselectedParts.isEmpty {
            Menu {
                ForEach(unselectedParts, id: \.clientId) { part in
                    Button("\(part.name) (\(part.partNumber))") {
                        usedParts[part.clientId] = 1
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14))
                    Text("Teil hinzufügen")
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundColor(Theme.Colors.primary)
            }
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
            let record = viewModel.createMaintenance(type: type, odo: odoValue, date: date, cost: costValue, currency: currency, description: notes)
            recordUsedParts(for: record)
        }
        withAnimation { savedAnim = true }
        Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            dismiss()
        }
    }

    /// Book the selected parts against the freshly created repair. Linked via
    /// the record's clientId so the SyncEngine can resolve the server id at
    /// push time (maintenance pushes before consumptions).
    private func recordUsedParts(for record: SDMaintenanceRecord) {
        guard !usedParts.isEmpty else { return }
        let context = PersistenceController.shared.mainContext
        for part in selectedParts {
            guard let quantity = usedParts[part.clientId] else { continue }
            PartsInventory.recordConsumption(
                part: part,
                quantity: quantity,
                date: record.date,
                maintenanceClientId: record.clientId,
                maintenanceServerId: record.serverId,
                in: context
            )
        }
        try? context.save()
    }
}
