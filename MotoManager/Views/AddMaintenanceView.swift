import SwiftUI
import SwiftData

/// Create/edit a non-fuel maintenance record. Uses the webapp's canonical
/// type system (fluid + fluid subtype, brakepad/brakerotor via a UI-only
/// "brake" type, …) with conditional type-specific fields. Writes
/// optimistically to SwiftData via the view model (offline-first).
///
/// Legacy records (older iOS builds wrote `oil`, `tires`, `brakes`, …) open
/// with the mapped picker selection, but their stored type is only rewritten
/// when the user actually changes a type-determining control — never silently.
struct AddMaintenanceView: View {
    @ObservedObject var viewModel: MotorcycleDetailViewModel
    let existingRecord: SDMaintenanceRecord?
    @Environment(\.dismiss) private var dismiss

    /// Parts consumed by this repair (partClientId → quantity). Create-only:
    /// consumptions of an existing record are managed in the Teile tab.
    @State private var usedParts: [UUID: Int] = [:]
    @State private var availableParts: [SDPart] = []

    /// Picker values (webapp canonical set minus fuel/location, plus the
    /// UI-only "brake" which submits brakepad/brakerotor).
    static let formTypes: [(value: String, label: String)] = [
        ("service", "Service"),
        ("repair", "Reparatur"),
        ("tire", "Reifenwechsel"),
        ("fluid", "Flüssigkeit"),
        ("brake", "Bremse"),
        ("battery", "Batterie"),
        ("chain", "Kette"),
        ("inspection", "MFK"),
        ("general", "Allgemein"),
    ]

    /// Fluid subtypes in display order (webapp `fluidTypeLabels`).
    static let fluidTypes = [
        "engineoil", "gearboxoil", "finaldriveoil", "finaldrivegearboxoil",
        "forkoil", "brakefluid", "coolant",
    ]

    @State private var formType: String
    @State private var brakeComponent: String   // brakepad | brakerotor
    @State private var brand: String
    @State private var model: String
    @State private var tirePosition: String
    @State private var tireSize: String
    @State private var dotCode: String
    @State private var batteryType: String
    @State private var fluidType: String
    @State private var viscosity: String
    @State private var oilType: String          // "" = none

    @State private var odo: String
    @State private var cost: String
    @State private var currency: String
    @State private var notes: String
    @State private var date: Date
    @State private var confirmingDelete = false
    @State private var savedAnim = false
    @State private var showingOdoScanner = false

    /// Set when editing a record whose stored type isn't canonical; submitted
    /// unchanged unless the user touches a type-determining control.
    private let legacyOriginalType: String?
    @State private var typeDirty = false

    init(viewModel: MotorcycleDetailViewModel, existingRecord: SDMaintenanceRecord? = nil) {
        self.viewModel = viewModel
        self.existingRecord = existingRecord
        if let r = existingRecord {
            let raw = r.recordType.lowercased()
            let normalized = MaintenanceCategory.normalize(type: raw, fluidType: r.fluidType)
            let isCanonical = MaintenanceCategory(rawValue: raw) != nil
            self.legacyOriginalType = isCanonical ? nil : r.recordType

            let initialFormType: String
            switch normalized.category {
            case .brakepad, .brakerotor: initialFormType = "brake"
            case .tire: initialFormType = "tire"
            case .fluid: initialFormType = "fluid"
            case .battery: initialFormType = "battery"
            case .chain: initialFormType = "chain"
            case .inspection: initialFormType = "inspection"
            case .repair: initialFormType = "repair"
            case .service: initialFormType = "service"
            default: initialFormType = "general"
            }
            _formType = State(initialValue: initialFormType)
            _brakeComponent = State(initialValue: normalized.category == .brakerotor ? "brakerotor" : "brakepad")
            _brand = State(initialValue: r.brand ?? "")
            _model = State(initialValue: r.model ?? "")
            _tirePosition = State(initialValue: r.tirePosition ?? "rear")
            _tireSize = State(initialValue: r.tireSize ?? "")
            _dotCode = State(initialValue: r.dotCode ?? "")
            _batteryType = State(initialValue: r.batteryType ?? "lead-acid")
            _fluidType = State(initialValue: normalized.fluidType ?? "engineoil")
            _viscosity = State(initialValue: r.viscosity ?? "")
            _oilType = State(initialValue: r.oilType ?? "")
            _odo = State(initialValue: "\(r.odo)")
            _cost = State(initialValue: r.cost.map { String($0) } ?? "")
            _currency = State(initialValue: r.currency ?? viewModel.motorcycle.currencyCode ?? "CHF")
            _notes = State(initialValue: r.recordDescription ?? r.summary ?? "")
            let f = ISO8601DateFormatter(); f.formatOptions = [.withFullDate]
            _date = State(initialValue: f.date(from: r.date) ?? Date())
        } else {
            self.legacyOriginalType = nil
            _formType = State(initialValue: "service")
            _brakeComponent = State(initialValue: "brakepad")
            _brand = State(initialValue: "")
            _model = State(initialValue: "")
            _tirePosition = State(initialValue: "rear")
            _tireSize = State(initialValue: "")
            _dotCode = State(initialValue: "")
            _batteryType = State(initialValue: "lead-acid")
            _fluidType = State(initialValue: "engineoil")
            _viscosity = State(initialValue: "")
            _oilType = State(initialValue: "")
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
                    Picker("Art", selection: $formType) {
                        ForEach(Self.formTypes, id: \.value) { Text($0.label).tag($0.value) }
                    }
                    .pickerStyle(.menu)
                    .tint(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                typeSpecificFields

                field("KILOMETERSTAND") {
                    HStack(spacing: 8) {
                        TextField("", text: $odo).keyboardType(.numberPad).foregroundColor(.white)
                        Button {
                            showingOdoScanner = true
                        } label: {
                            Image(systemName: "camera.viewfinder")
                                .scaledFont(26, weight: .semibold)
                                .foregroundColor(Theme.Colors.primary)
                                .frame(width: 52, height: 44)
                                .contentShape(Rectangle())
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
        .onChange(of: formType) { typeDirty = true }
        .onChange(of: brakeComponent) { typeDirty = true }
        .onChange(of: fluidType) { typeDirty = true }
        .sheet(isPresented: $showingOdoScanner) {
            OdometerScanSheet(onResult: { value in odo = "\(value)" })
                .glassSheet()
        }
        .onAppear {
            availableParts = PartsInventory.availableParts(
                in: PersistenceController.shared.mainContext)
        }
        .alert("Eintrag löschen?", isPresented: $confirmingDelete) {
            Button("Abbrechen", role: .cancel) { }
            Button("Löschen", role: .destructive) {
                guard let record = existingRecord,
                      viewModel.deleteMaintenance(record) else { return }
                dismiss()
            }
        }
    }

    // MARK: - Type-specific fields

    @ViewBuilder
    private var typeSpecificFields: some View {
        switch formType {
        case "tire":
            field("POSITION") { tirePositionPicker }
            HStack(spacing: Theme.Spacing.m) {
                field("GRÖSSE") {
                    TextField("", text: $tireSize, prompt: prompt("180/55 ZR17")).foregroundColor(.white)
                }
                field("DOT-CODE") {
                    TextField("", text: $dotCode, prompt: prompt("2423")).foregroundColor(.white)
                }
            }
            brandModelFields
        case "fluid":
            field("FLUID-ART") {
                Picker("Fluid-Art", selection: $fluidType) {
                    ForEach(Self.fluidTypes, id: \.self) {
                        Text(SDMaintenanceRecord.fluidTypeLabels[$0] ?? $0).tag($0)
                    }
                }
                .pickerStyle(.menu).tint(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if fluidType.hasSuffix("oil") {
                HStack(spacing: Theme.Spacing.m) {
                    field("VISKOSITÄT") {
                        TextField("", text: $viscosity, prompt: prompt("10W-40")).foregroundColor(.white)
                    }
                    field("ÖL-TYP") {
                        Picker("Öl-Typ", selection: $oilType) {
                            Text("—").tag("")
                            ForEach(["synthetic", "semi-synthetic", "mineral"], id: \.self) {
                                Text(MaintenanceCategory.oilTypeLabels[$0] ?? $0).tag($0)
                            }
                        }
                        .pickerStyle(.menu).tint(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            field("MARKE") {
                TextField("", text: $brand, prompt: prompt("z. B. Motul")).foregroundColor(.white)
            }
        case "brake":
            field("KOMPONENTE") {
                Picker("Komponente", selection: $brakeComponent) {
                    Text("Bremsbeläge").tag("brakepad")
                    Text("Bremsscheibe").tag("brakerotor")
                }
                .pickerStyle(.segmented).colorScheme(.dark)
            }
            field("POSITION") { tirePositionPicker }
            brandModelFields
        case "battery":
            field("BATTERIETYP") {
                Picker("Batterietyp", selection: $batteryType) {
                    ForEach(["lead-acid", "gel", "agm", "lithium-ion", "other"], id: \.self) {
                        Text(MaintenanceCategory.batteryTypeLabels[$0] ?? $0).tag($0)
                    }
                }
                .pickerStyle(.menu).tint(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            brandModelFields
        default:
            EmptyView()
        }
    }

    private var tirePositionPicker: some View {
        Picker("Position", selection: $tirePosition) {
            Text("Vorne").tag("front")
            Text("Hinten").tag("rear")
            Text("Beiwagen").tag("sidecar")
        }
        .pickerStyle(.segmented).colorScheme(.dark)
    }

    private var brandModelFields: some View {
        HStack(spacing: Theme.Spacing.m) {
            field("MARKE") {
                TextField("", text: $brand, prompt: prompt("z. B. Michelin")).foregroundColor(.white)
            }
            field("MODELL") {
                TextField("", text: $model, prompt: prompt("z. B. Road 6")).foregroundColor(.white)
            }
        }
    }

    private func prompt(_ text: String) -> Text {
        Text(text).foregroundColor(.white.opacity(0.3))
    }

    private var header: some View {
        HStack {
            Text(existingRecord == nil ? "Wartung erfassen" : "Wartung bearbeiten")
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
                    .scaledFont(13, weight: .bold)
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text("\(part.partNumber) · \(maxQuantity) auf Lager")
                    .scaledFont(10, weight: .semibold)
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
                    .scaledFont(13, weight: .heavy)
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
                        .scaledFont(14)
                    Text("Teil hinzufügen")
                        .scaledFont(13, weight: .bold)
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

    // MARK: - Save

    /// The `type` string written to the record: legacy stays untouched unless
    /// a type-determining control changed; "brake" resolves to its component.
    private var submittedType: String {
        if let legacy = legacyOriginalType, !typeDirty { return legacy }
        return formType == "brake" ? brakeComponent : formType
    }

    private func save() {
        let odoValue = Int(odo) ?? (viewModel.motorcycle.latestOdo ?? viewModel.motorcycle.initialOdo)
        let costValue = Double(cost.replacingOccurrences(of: ",", with: ".")) ?? 0
        let type = submittedType
        let category = MaintenanceCategory.normalize(type: type, fluidType: nil).category

        var draft = MotorcycleDetailViewModel.MaintenanceDraft(
            type: type, odo: odoValue, date: date,
            cost: costValue, currency: currency, description: notes
        )
        switch category {
        case .tire:
            draft.brand = brand; draft.model = model
            draft.tirePosition = tirePosition
            draft.tireSize = tireSize; draft.dotCode = dotCode
        case .brakepad, .brakerotor:
            draft.brand = brand; draft.model = model
            draft.tirePosition = tirePosition
        case .battery:
            draft.brand = brand; draft.model = model
            draft.batteryType = batteryType
        case .fluid:
            draft.brand = brand
            // Legacy fluid type untouched → keep the stored (possibly nil)
            // fluidType instead of writing the inferred one behind the
            // user's back.
            if legacyOriginalType != nil && !typeDirty {
                draft.fluidType = existingRecord?.fluidType
            } else {
                draft.fluidType = fluidType
            }
            if fluidType.hasSuffix("oil") {
                draft.viscosity = viscosity
                draft.oilType = oilType.isEmpty ? nil : oilType
            }
        default:
            break
        }

        if let r = existingRecord {
            guard viewModel.updateMaintenance(r, draft: draft) else { return }
        } else {
            guard let record = viewModel.createMaintenance(draft) else { return }
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
        _ = PersistenceMonitor.shared.save(context, operation: "Verwendete Teile speichern")
    }
}
