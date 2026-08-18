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

    /// Parts consumed by this repair (partClientId → quantity). Seeded from the
    /// record's existing consumptions when editing, so parts can be added,
    /// re-quantified and removed here rather than only in the Teile tab.
    @State private var usedParts: [UUID: Int] = [:]
    @State private var availableParts: [SDPart] = []
    /// What the record already holds per part, captured on appear. Needed both
    /// to seed `usedParts` and to raise the stepper ceiling: a part this record
    /// consumed is no longer in on-hand, so without adding it back an entry
    /// that took the last piece could never be re-saved.
    @State private var bookedParts: [UUID: Int] = [:]

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
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    field("ART") {
                        Picker("Art", selection: $formType) {
                            ForEach(Self.formTypes, id: \.value) { Text($0.label).tag($0.value) }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    typeSpecificFields

                    field("KILOMETERSTAND") {
                        HStack(spacing: 8) {
                            TextField("", text: $odo).keyboardType(.numberPad).foregroundStyle(.primary)
                            Button {
                                showingOdoScanner = true
                            } label: {
                                Image(systemName: "camera.viewfinder")
                                    .scaledFont(26, weight: .semibold)
                                    .foregroundStyle(Theme.Colors.primary)
                                    .frame(width: 52, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Kilometerstand scannen")
                        }
                    }
                    HStack(spacing: Theme.Spacing.m) {
                        field("KOSTEN") {
                            TextField("", text: $cost, prompt: Text("0").foregroundStyle(.tertiary))
                                .keyboardType(.decimalPad).foregroundStyle(.primary)
                        }
                        field("WÄHRUNG") {
                            TextField("", text: $currency).foregroundStyle(.primary)
                                .textInputAutocapitalization(.characters)
                        }
                    }
                    field("DATUM") {
                        DatePicker("", selection: $date, displayedComponents: .date)
                            .labelsHidden().tint(Theme.Colors.primary)
                    }
                    field("BESCHREIBUNG") {
                        TextField("", text: $notes, prompt: Text("z. B. Ölwechsel + Filter").foregroundStyle(.tertiary), axis: .vertical)
                            .lineLimit(2...5).foregroundStyle(.primary)
                    }

                    usedPartsSection

                    if existingRecord != nil { deleteButton }
                }
                .padding(Theme.Spacing.l)
            }
            .navigationTitle(existingRecord == nil ? "Wartung erfassen" : "Wartung bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern", action: save)
                }
            }
            .onChange(of: formType) { typeDirty = true }
            .onChange(of: brakeComponent) { typeDirty = true }
            .onChange(of: fluidType) { typeDirty = true }
            .sheet(isPresented: $showingOdoScanner) {
                OdometerScanSheet(onResult: { value in odo = "\(value)" })
                    .glassSheet()
            }
            .onAppear {
                let context = PersistenceController.shared.mainContext
                var parts = PartsInventory.availableParts(in: context)

                // Seed from what the record already holds. Those parts may have
                // zero on-hand (this entry used them up), so they are missing from
                // `availableParts` and have to be merged back in — otherwise the
                // entry's own parts would be invisible in its own form.
                if let record = existingRecord {
                    let existing = PartsInventory.consumptions(forMaintenance: record, in: context)
                    var booked: [UUID: Int] = [:]
                    for consumption in existing {
                        booked[consumption.partClientId, default: 0] += consumption.quantity
                    }
                    bookedParts = booked
                    usedParts = booked

                    let known = Set(parts.map(\.clientId))
                    let missing = ((try? context.fetch(FetchDescriptor<SDPart>())) ?? [])
                        .filter { booked[$0.clientId] != nil && !known.contains($0.clientId) }
                    parts = (parts + missing).sorted { $0.name < $1.name }
                }
                availableParts = parts
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
    }

    // MARK: - Type-specific fields

    @ViewBuilder
    private var typeSpecificFields: some View {
        switch formType {
        case "tire":
            labeledControl("POSITION") { tirePositionPicker }
            HStack(spacing: Theme.Spacing.m) {
                field("GRÖSSE") {
                    TextField("", text: $tireSize, prompt: prompt("180/55 ZR17")).foregroundStyle(.primary)
                }
                field("DOT-CODE") {
                    TextField("", text: $dotCode, prompt: prompt("2423")).foregroundStyle(.primary)
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
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if fluidType.hasSuffix("oil") {
                HStack(spacing: Theme.Spacing.m) {
                    field("VISKOSITÄT") {
                        TextField("", text: $viscosity, prompt: prompt("10W-40")).foregroundStyle(.primary)
                    }
                    field("ÖL-TYP") {
                        Picker("Öl-Typ", selection: $oilType) {
                            Text("—").tag("")
                            ForEach(["synthetic", "semi-synthetic", "mineral"], id: \.self) {
                                Text(MaintenanceCategory.oilTypeLabels[$0] ?? $0).tag($0)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            field("MARKE") {
                TextField("", text: $brand, prompt: prompt("z. B. Motul")).foregroundStyle(.primary)
            }
        case "brake":
            labeledControl("KOMPONENTE") {
                GlassSegmentedControl(
                    segments: [
                        .init(value: "brakepad", label: "Bremsbeläge"),
                        .init(value: "brakerotor", label: "Bremsscheibe"),
                    ],
                    selection: $brakeComponent
                )
            }
            labeledControl("POSITION") { tirePositionPicker }
            brandModelFields
        case "battery":
            field("BATTERIETYP") {
                Picker("Batterietyp", selection: $batteryType) {
                    ForEach(["lead-acid", "gel", "agm", "lithium-ion", "other"], id: \.self) {
                        Text(MaintenanceCategory.batteryTypeLabels[$0] ?? $0).tag($0)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            brandModelFields
        default:
            EmptyView()
        }
    }

    private var tirePositionPicker: some View {
        GlassSegmentedControl(
            segments: [
                .init(value: "front", label: "Vorne"),
                .init(value: "rear", label: "Hinten"),
                .init(value: "sidecar", label: "Beiwagen"),
            ],
            selection: $tirePosition
        )
    }

    private var brandModelFields: some View {
        HStack(spacing: Theme.Spacing.m) {
            field("MARKE") {
                TextField("", text: $brand, prompt: prompt("z. B. Michelin")).foregroundStyle(.primary)
            }
            field("MODELL") {
                TextField("", text: $model, prompt: prompt("z. B. Road 6")).foregroundStyle(.primary)
            }
        }
    }

    private func prompt(_ text: String) -> Text {
        Text(text).foregroundStyle(.tertiary)
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

    /// Field label without the boxed background — for controls that bring
    /// their own chrome (the glass segmented control).
    private func labeledControl<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .scaledFont(10, weight: .heavy).tracking(1.4)
                .foregroundStyle(.secondary)
            content()
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

    /// On-hand plus whatever this record already booked of the part — the
    /// latter is not in on-hand any more, but is still available *to this
    /// entry*.
    private func maxQuantity(for part: SDPart) -> Int {
        let context = PersistenceController.shared.mainContext
        return PartsInventory.onHand(for: part.clientId, in: context)
            + (bookedParts[part.clientId] ?? 0)
    }

    private func usedPartRow(_ part: SDPart) -> some View {
        let maxQuantity = maxQuantity(for: part)
        let quantity = usedParts[part.clientId] ?? 1
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(part.name)
                    .scaledFont(13, weight: .bold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("\(part.partNumber) · max. \(maxQuantity)")
                    .scaledFont(10, weight: .semibold)
                    .foregroundStyle(.tertiary)
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
                    .foregroundStyle(Theme.Colors.primary)
            }
            .fixedSize()
            Button {
                usedParts.removeValue(forKey: part.clientId)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
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
                .foregroundStyle(Theme.Colors.primary)
            }
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive) { confirmingDelete = true } label: {
            Text("Löschen").frame(maxWidth: .infinity)
        }
        .glassActionButton(.danger, in: .roundedRectangle(radius: Theme.Radius.control))
        .padding(.top, Theme.Spacing.s)
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
            syncUsedParts(for: r)
        } else {
            guard let record = viewModel.createMaintenance(draft) else { return }
            recordUsedParts(for: record)
        }
        dismiss()
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

    /// Reconcile an existing record's consumptions with what the form now
    /// shows: add the newly picked, re-quantify the changed, remove the
    /// dropped.
    ///
    /// A consumption whose quantity is unchanged is left completely alone —
    /// touching it would mark it pendingUpdate and push a no-op that only
    /// causes the server to recompute partsCost and bump the record's
    /// updatedAt, waking every other client for nothing.
    ///
    /// Quantity changes are done as delete + create rather than an in-place
    /// edit: the local on-hand guard in `recordConsumption` is what keeps an
    /// offline write from being rejected at push time, and freeing the old
    /// quantity first is what makes an increase fit.
    private func syncUsedParts(for record: SDMaintenanceRecord) {
        let context = PersistenceController.shared.mainContext
        let existing = PartsInventory.consumptions(forMaintenance: record, in: context)
        var partsById: [UUID: SDPart] = [:]
        for part in availableParts { partsById[part.clientId] = part }

        var changed = false
        for consumption in existing {
            let desired = usedParts[consumption.partClientId]
            if desired == consumption.quantity { continue }
            PartsInventory.removeConsumption(consumption, in: context)
            changed = true
        }

        for (partClientId, quantity) in usedParts {
            // Untouched entries were skipped above and must not be re-created.
            let unchanged = existing.contains {
                $0.partClientId == partClientId && $0.quantity == quantity
            }
            if unchanged { continue }
            guard let part = partsById[partClientId] else { continue }
            PartsInventory.recordConsumption(
                part: part,
                quantity: quantity,
                date: record.date,
                maintenanceClientId: record.clientId,
                maintenanceServerId: record.serverId,
                in: context
            )
            changed = true
        }

        if changed {
            _ = PersistenceMonitor.shared.save(context, operation: "Verwendete Teile aktualisieren")
        }
    }
}
