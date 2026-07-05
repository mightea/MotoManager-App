import SwiftUI

/// Create/edit a catalog part (offline-first). Fitment is picked from the
/// cached series lookup; custom series can be created inline (online only).
struct AddPartView: View {
    @ObservedObject var viewModel: PartsViewModel
    let existingPart: SDPart?
    @Environment(\.dismiss) private var dismiss

    @State private var partNumber: String
    @State private var name: String
    @State private var manufacturer: String
    @State private var notes: String
    @State private var isPublic: Bool
    @State private var selectedSeriesIds: Set<Int>
    @State private var showingSeriesPicker = false
    @State private var confirmingDelete = false
    @State private var savedAnim = false
    @State private var validationError: String?

    init(viewModel: PartsViewModel, existingPart: SDPart? = nil) {
        self.viewModel = viewModel
        self.existingPart = existingPart
        if let p = existingPart {
            _partNumber = State(initialValue: p.partNumber)
            _name = State(initialValue: p.name)
            _manufacturer = State(initialValue: p.manufacturer)
            _notes = State(initialValue: p.partDescription ?? "")
            _isPublic = State(initialValue: p.isPublic)
            _selectedSeriesIds = State(initialValue: Set(p.seriesIds))
        } else {
            _partNumber = State(initialValue: "")
            _name = State(initialValue: "")
            _manufacturer = State(initialValue: "BMW")
            _notes = State(initialValue: "")
            _isPublic = State(initialValue: false)
            _selectedSeriesIds = State(initialValue: [])
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                header

                field("TEILENUMMER") {
                    TextField("", text: $partNumber,
                              prompt: Text("z. B. 11 42 7 673 541").foregroundColor(.white.opacity(0.3)))
                        .foregroundColor(.white)
                        .autocorrectionDisabled()
                }
                field("NAME") {
                    TextField("", text: $name,
                              prompt: Text("z. B. Ölfilter").foregroundColor(.white.opacity(0.3)))
                        .foregroundColor(.white)
                }
                field("HERSTELLER") {
                    TextField("", text: $manufacturer).foregroundColor(.white)
                }
                field("BAUREIHEN") {
                    Button { showingSeriesPicker = true } label: {
                        HStack {
                            Text(seriesSummary)
                                .foregroundColor(selectedSeriesIds.isEmpty ? .white.opacity(0.35) : .white)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }
                    .buttonStyle(.plain)
                }
                field("BESCHREIBUNG") {
                    TextField("", text: $notes,
                              prompt: Text("z. B. passt auch für Ölkühler-Variante").foregroundColor(.white.opacity(0.3)),
                              axis: .vertical)
                        .lineLimit(2...5).foregroundColor(.white)
                }

                Toggle(isOn: $isPublic) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Öffentlich teilen")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                        Text("Andere Nutzer sehen Teiledaten und Verfügbarkeit — nie Preise oder Lagerorte.")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
                .tint(Theme.Colors.primary)
                .padding(.horizontal, 4)

                if let validationError {
                    Text(validationError)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.Colors.accent)
                }

                saveButton
                if existingPart != nil { deleteButton }
            }
            .padding(Theme.Spacing.l)
        }
        .background(Color.clear)
        .sheet(isPresented: $showingSeriesPicker) {
            SeriesPickerView(viewModel: viewModel, selection: $selectedSeriesIds)
                .presentationDetents([.large])
                .presentationCornerRadius(Theme.Glass.sheetRadius)
                .presentationBackground(.regularMaterial)
                .presentationDragIndicator(.visible)
        }
        .alert("Teil löschen?", isPresented: $confirmingDelete) {
            Button("Abbrechen", role: .cancel) { }
            Button("Löschen", role: .destructive) {
                if let p = existingPart { viewModel.deletePart(p) }
                dismiss()
            }
        } message: {
            Text("Bestand und Verbrauch dieses Teils werden ebenfalls entfernt.")
        }
    }

    private var seriesSummary: String {
        if selectedSeriesIds.isEmpty { return "Baureihen wählen …" }
        let names = selectedSeriesIds.sorted().prefix(4).map { viewModel.seriesName($0) }
        let more = selectedSeriesIds.count - names.count
        return names.joined(separator: ", ") + (more > 0 ? " +\(more)" : "")
    }

    private var header: some View {
        HStack {
            Text(existingPart == nil ? "Teil hinzufügen" : "Teil bearbeiten")
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
        let trimmedNumber = partNumber.trimmingCharacters(in: .whitespaces)
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedNumber.isEmpty, !trimmedName.isEmpty else {
            validationError = "Teilenummer und Name sind erforderlich."
            return
        }
        // Same identity rule as the server (partNumber + name, live parts only)
        // so the pending create can't come back as a 400.
        let duplicate = viewModel.parts.contains {
            $0.clientId != existingPart?.clientId
                && $0.partNumber == trimmedNumber && $0.name == trimmedName
        }
        guard !duplicate else {
            validationError = "Ein Teil mit dieser Teilenummer und diesem Namen existiert bereits."
            return
        }

        let ids = Array(selectedSeriesIds).sorted()
        if let p = existingPart {
            viewModel.updatePart(
                p, partNumber: trimmedNumber, name: trimmedName,
                manufacturer: manufacturer.trimmingCharacters(in: .whitespaces),
                description: notes, isPublic: isPublic, seriesIds: ids)
        } else {
            viewModel.createPart(
                partNumber: trimmedNumber, name: trimmedName,
                manufacturer: manufacturer.trimmingCharacters(in: .whitespaces),
                description: notes, isPublic: isPublic, seriesIds: ids)
        }
        withAnimation { savedAnim = true }
        Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            dismiss()
        }
    }
}

// MARK: - Series picker

/// Multi-select over the cached series lookup with an inline "Eigene Baureihe"
/// creator (disabled offline — the lookup is server-managed).
struct SeriesPickerView: View {
    @ObservedObject var viewModel: PartsViewModel
    @Binding var selection: Set<Int>
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var connectivity = ConnectivityMonitor.shared

    @State private var searchText = ""
    @State private var newName = ""
    @State private var newManufacturer = "BMW"
    @State private var creating = false
    @State private var createError: String?

    private var filtered: [ModelSeries] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return viewModel.series }
        return viewModel.series.filter { $0.displayName.lowercased().contains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Baureihen")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundColor(.white)
                Spacer()
                Button("Fertig") { dismiss() }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Theme.Colors.primary)
            }
            .padding(Theme.Spacing.l)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
                TextField("", text: $searchText,
                          prompt: Text("Suchen …").foregroundColor(.white.opacity(0.35)))
                    .foregroundColor(.white)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: Theme.Glass.fieldRadius).fill(Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: Theme.Glass.fieldRadius).stroke(Theme.Glass.border, lineWidth: 0.5))
            .padding(.horizontal, Theme.Spacing.l)

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(filtered) { series in
                        seriesRow(series)
                    }
                    createSection
                }
                .padding(Theme.Spacing.l)
            }
        }
        .background(Color.clear)
        .task { await viewModel.loadSeries() }
    }

    private func seriesRow(_ series: ModelSeries) -> some View {
        let isSelected = selection.contains(series.id)
        return Button {
            if isSelected { selection.remove(series.id) } else { selection.insert(series.id) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(series.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    if series.userId != nil {
                        Text("Eigene Baureihe")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundColor(isSelected ? Theme.Colors.primary : .white.opacity(0.25))
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: Theme.Glass.fieldRadius)
                    .fill(isSelected ? Theme.Colors.primary.opacity(0.12) : Color.white.opacity(0.04))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var createSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("EIGENE BAUREIHE")
                .font(.system(size: 10, weight: .heavy)).tracking(1.4)
                .foregroundColor(Theme.Glass.mutedText)
                .padding(.top, Theme.Spacing.m)

            if !connectivity.isOnline {
                Text("Nur online möglich — Baureihen werden zentral verwaltet.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
            } else {
                HStack(spacing: 8) {
                    TextField("", text: $newManufacturer,
                              prompt: Text("Hersteller").foregroundColor(.white.opacity(0.35)))
                        .foregroundColor(.white)
                        .frame(maxWidth: 110)
                    TextField("", text: $newName,
                              prompt: Text("z. B. R 90 S").foregroundColor(.white.opacity(0.35)))
                        .foregroundColor(.white)
                    Button {
                        Task { await createSeries() }
                    } label: {
                        if creating {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 22))
                                .foregroundColor(Theme.Colors.primary)
                        }
                    }
                    .disabled(creating || newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: Theme.Glass.fieldRadius).fill(Color.white.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: Theme.Glass.fieldRadius).stroke(Theme.Glass.border, lineWidth: 0.5))

                if let createError {
                    Text(createError)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.Colors.accent)
                }
            }
        }
    }

    private func createSeries() async {
        creating = true
        createError = nil
        let created = await viewModel.createSeries(
            name: newName.trimmingCharacters(in: .whitespaces),
            manufacturer: newManufacturer.trimmingCharacters(in: .whitespaces).isEmpty
                ? "BMW" : newManufacturer.trimmingCharacters(in: .whitespaces))
        if let created {
            selection.insert(created.id)
            newName = ""
        } else {
            createError = "Baureihe konnte nicht angelegt werden."
        }
        creating = false
    }
}
