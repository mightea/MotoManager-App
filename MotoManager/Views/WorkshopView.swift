import SwiftUI
import UniformTypeIdentifiers

/// The "Technik" tab: one overview of the bike's reference data — tire
/// pressure, details, torque specs and documents — instead of a category
/// switcher. Short sections show everything; long ones show a preview and
/// expand in place (works the same in the iPad split view, where a pushed
/// screen would fight the document column). A single search covers every
/// category and lists all matches while it's active. Adding goes through the
/// header "+" menu and the empty states only, so every section header is a
/// plain title with a count.
struct WorkshopView: View {
    @ObservedObject var viewModel: MotorcycleDetailViewModel
    @State private var presentedDocument: Document?
    @State private var searchText = ""
    @ObservedObject private var offlineStore = DocumentOfflineStore.shared
    @State private var selectedTorqueGroup: String = "Alle"
    @State private var torqueExpanded = false
    @State private var detailsExpanded = false
    @State private var showingAddTorque = false
    @State private var editingTorque: SDTorqueSpec?
    @State private var showingAddDetail = false
    @State private var editingDetail: SDMotorcycleDetail?
    @State private var showingTirePressure = false
    @State private var showingDocumentImporter = false
    @State private var isUploadingDocument = false
    @State private var documentUploadError: String?
    @State private var pendingTorqueDelete: SDTorqueSpec?
    @State private var pendingDetailDelete: SDMotorcycleDetail?

    /// Rows a collapsed section shows before "Alle … anzeigen".
    private static let torquePreviewCount = 3
    private static let detailsPreviewCount = 4

    private var query: String { searchText.trimmingCharacters(in: .whitespaces) }
    private var isSearching: Bool { !query.isEmpty }

    private func matchesSearch(_ text: String) -> Bool {
        !isSearching || text.localizedStandardContains(query)
    }

    private var motoLabel: String {
        let make = viewModel.motorcycle.make
        let model = viewModel.motorcycle.model
        let full = "\(make) \(model)"
        return full.count > 14 ? make : full
    }

    private var filteredDetails: [SDMotorcycleDetail] {
        viewModel.details.filter { matchesSearch("\($0.title) \($0.value)") }
    }

    private var torqueGroups: [String] {
        let groups = Set(viewModel.torque.map(\.category))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return ["Alle"] + groups
    }

    private var filteredTorque: [SDTorqueSpec] {
        viewModel.torque.filter {
            (selectedTorqueGroup == "Alle" || $0.category == selectedTorqueGroup)
                && matchesSearch("\($0.name) \($0.category) \($0.recordDescription ?? "")")
        }
    }

    private var bikeDocuments: [Document] { viewModel.documents.filter { matchesSearch($0.title) } }
    private var commonDocuments: [Document] { viewModel.commonDocuments.filter { matchesSearch($0.title) } }

    private var isEmpty: Bool {
        viewModel.torque.isEmpty
            && viewModel.details.isEmpty
            && viewModel.documents.isEmpty
            && viewModel.commonDocuments.isEmpty
            && viewModel.tirePressure == nil
    }

    private var hasSearchResults: Bool {
        !filteredDetails.isEmpty || !filteredTorque.isEmpty || !bikeDocuments.isEmpty || !commonDocuments.isEmpty
    }

    // MARK: - Header stat strip (iPad overview column)

    private var documentCount: Int {
        viewModel.documents.count + viewModel.commonDocuments.count
    }

    private var statTiles: [StatTile] {
        [
            StatTile(eyebrow: "Details", value: "\(viewModel.details.count)",
                     unit: Self.entries(viewModel.details.count)),
            StatTile(eyebrow: "Drehmomente", value: "\(viewModel.torque.count)",
                     unit: Self.entries(viewModel.torque.count)),
            StatTile(eyebrow: "Dokumente", value: "\(documentCount)",
                     unit: documentCount == 1 ? "Datei" : "Dateien")
        ]
    }

    private static func entries(_ count: Int) -> String { count == 1 ? "Eintrag" : "Einträge" }

    var body: some View {
        MotorcycleWorkspace(motorcycle: viewModel.motorcycle, type: .workshop) {
            Menu {
                Button(viewModel.tirePressure == nil ? "Reifendruck erfassen" : "Reifendruck bearbeiten",
                       systemImage: "gauge.with.dots.needle.bottom.50percent") { showingTirePressure = true }
                Button("Detail hinzufügen", systemImage: "list.bullet.rectangle") { showingAddDetail = true }
                Button("Drehmoment hinzufügen", systemImage: "wrench.and.screwdriver") { showingAddTorque = true }
                Button("Dokument hochladen", systemImage: "doc.badge.plus") { showingDocumentImporter = true }
            } label: {
                Image(systemName: "plus")
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.onPhoto)
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.tint(Theme.Colors.navy950.opacity(0.5)), in: Circle())
            }
            .accessibilityLabel("Hinzufügen")
            .keyboardShortcut("n", modifiers: .command)
        } content: {
            RecordBrowser(selection: $presentedDocument, title: "Technische Daten",
                          emptyTitle: "Dokument auswählen", systemImage: "doc.text",
                          overview: AnyView(referenceOverview)) {
                referenceList
            } detail: { document in
                DocumentViewerView(document: document)
            }
        }
        .onChange(of: viewModel.documents + viewModel.commonDocuments) { _, documents in
            if let presentedDocument, !documents.contains(where: { $0.id == presentedDocument.id }) {
                self.presentedDocument = nil
            }
        }
        .onChange(of: torqueGroups) { _, groups in
            if !groups.contains(selectedTorqueGroup) { selectedTorqueGroup = "Alle" }
        }
        .sheet(isPresented: $showingAddTorque) {
            AddTorqueView(viewModel: viewModel)
                .glassSheet()
        }
        .sheet(item: $editingTorque) { spec in
            AddTorqueView(viewModel: viewModel, existingSpec: spec)
                .glassSheet()
        }
        .sheet(isPresented: $showingAddDetail) {
            AddDetailView(viewModel: viewModel)
                .glassSheet()
        }
        .sheet(item: $editingDetail) { detail in
            AddDetailView(viewModel: viewModel, existingDetail: detail)
                .glassSheet()
        }
        .sheet(isPresented: $showingTirePressure) {
            AddTirePressureView(viewModel: viewModel)
                .glassSheet()
        }
        .fileImporter(
            isPresented: $showingDocumentImporter,
            allowedContentTypes: [.pdf, .image, .data],
            allowsMultipleSelection: false,
            onCompletion: handleDocumentSelection
        )
        .alert("Dokument konnte nicht hochgeladen werden", isPresented: Binding(
            get: { documentUploadError != nil },
            set: { if !$0 { documentUploadError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(documentUploadError ?? "Unbekannter Fehler")
        }
        .alert("Drehmoment löschen?", isPresented: Binding(
            get: { pendingTorqueDelete != nil },
            set: { if !$0 { pendingTorqueDelete = nil } }
        ), presenting: pendingTorqueDelete) { spec in
            Button("Abbrechen", role: .cancel) {}
            Button("Löschen", role: .destructive) { _ = viewModel.deleteTorque(spec) }
        } message: { spec in
            Text(spec.name)
        }
        .alert("Detail löschen?", isPresented: Binding(
            get: { pendingDetailDelete != nil },
            set: { if !$0 { pendingDetailDelete = nil } }
        ), presenting: pendingDetailDelete) { detail in
            Button("Abbrechen", role: .cancel) {}
            Button("Löschen", role: .destructive) { _ = viewModel.deleteDetail(detail) }
        } message: { detail in
            Text(detail.title)
        }
    }

    private var referenceList: some View {
        List {
            WorkspaceListHeader(searchText: $searchText, prompt: "Technik durchsuchen …")

            if viewModel.isLoading && isEmpty {
                Section {
                    ForEach(0..<4, id: \.self) { _ in loadingPlaceholderRow.redacted(reason: .placeholder) }
                }
            } else if isSearching {
                if hasSearchResults {
                    detailsSection
                    torqueSection
                    documentsSection
                } else {
                    ContentUnavailableView.search(text: query)
                        .listRowBackground(Color.clear)
                }
            } else {
                tirePressureSection
                detailsSection
                torqueSection
                documentsSection
            }
            WorkspaceListFooter()
        }
        .accessibilityIdentifier("workshop.references")
        .tracksWorkspaceHeader()
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.Colors.background)
        .refreshable { await viewModel.reconnect() }
    }

    /// Detail column on iPad while no document is open. The list column
    /// already shows every section, so this only summarises.
    private var referenceOverview: some View {
        List {
            Section { StatStrip(statTiles).listRowInsets(EdgeInsets()) }
            Section {
                Label("Öffne ein Dokument, um es neben den technischen Daten zu lesen.", systemImage: "doc.text.magnifyingglass")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("workshop.overview")
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.background)
        .navigationTitle("Technik im Blick")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var loadingPlaceholderRow: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: Theme.Radius.controlInner)
                .fill(.quaternary)
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text("Ladeplatzhalter Titel")
                Text("Zweite Zeile mit Details")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    /// Plain section title with a trailing count — the same for every section.
    private func sectionHeader(_ title: String, count: Int? = nil, unit: String? = nil) -> some View {
        HStack {
            Text(title)
            Spacer()
            if let count {
                Text("\(count) \(unit ?? Self.entries(count))")
                    .monospacedDigit()
            }
        }
    }

    /// Compact per-section empty state with an explicit action button.
    private func emptySectionRow(
        _ message: String, icon: String, actionLabel: String, action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 10) {
            Label(message, systemImage: icon)
                .scaledFont(12, weight: .medium)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(actionLabel, action: action)
                .buttonStyle(.bordered)
                .tint(Theme.Colors.primary)
                .scaledFont(13, weight: .semibold)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    /// "Alle 12 anzeigen" / "Weniger anzeigen" row closing a collapsible section.
    private func expandRow(total: Int, expanded: Binding<Bool>) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) { expanded.wrappedValue.toggle() }
        } label: {
            HStack {
                Text(expanded.wrappedValue ? "Weniger anzeigen" : "Alle \(total) anzeigen")
                Spacer()
                Image(systemName: expanded.wrappedValue ? "chevron.up" : "chevron.down")
                    .scaledFont(12, weight: .semibold)
            }
            .scaledFont(13, weight: .semibold)
            .foregroundStyle(Theme.Colors.primary)
            .frame(minHeight: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tire pressure

    @ViewBuilder
    private var tirePressureSection: some View {
        Section {
            if let pressure = viewModel.tirePressure {
                Button { showingTirePressure = true } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        TirePressureTable(pressure: pressure)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("workshop.pressure")
                .accessibilityHint("Bearbeiten")
            } else {
                emptySectionRow(
                    "Keine Druckwerte erfasst",
                    icon: "gauge.with.dots.needle.bottom.50percent",
                    actionLabel: "Reifendruck erfassen"
                ) { showingTirePressure = true }
            }
        } header: {
            sectionHeader("Reifendruck")
        }
    }

    // MARK: - Details

    @ViewBuilder
    private var detailsSection: some View {
        let rows = filteredDetails
        if !(isSearching && rows.isEmpty) {
            Section {
                if viewModel.details.isEmpty {
                    emptySectionRow(
                        "Keine Details erfasst",
                        icon: "list.bullet.rectangle",
                        actionLabel: "Detail hinzufügen"
                    ) { showingAddDetail = true }
                } else {
                    let collapsed = !isSearching && !detailsExpanded && rows.count > Self.detailsPreviewCount + 1
                    ForEach(collapsed ? Array(rows.prefix(Self.detailsPreviewCount)) : rows, id: \.clientId) { detail in
                        Button { editingDetail = detail } label: {
                            MotorcycleDetailRow(detail: detail)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("workshop.detail.\(detail.clientId)")
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button { pendingDetailDelete = detail } label: {
                                Label("Löschen", systemImage: "trash")
                            }
                            .tint(.red)
                        }
                    }
                    if !isSearching && rows.count > Self.detailsPreviewCount + 1 {
                        expandRow(total: rows.count, expanded: $detailsExpanded)
                    }
                }
            } header: {
                sectionHeader("Details", count: isSearching ? rows.count : viewModel.details.count)
            }
        }
    }

    // MARK: - Torque

    @ViewBuilder
    private var torqueSection: some View {
        let rows = filteredTorque
        if !(isSearching && rows.isEmpty) {
            Section {
                if viewModel.torque.isEmpty {
                    emptySectionRow(
                        "Keine Drehmomente erfasst",
                        icon: "wrench.and.screwdriver",
                        actionLabel: "Drehmoment hinzufügen"
                    ) { showingAddTorque = true }
                } else {
                    let canCollapse = !isSearching && rows.count > Self.torquePreviewCount + 1
                    // Group filter only once the whole list is on screen — a
                    // filter over a three-row preview is noise.
                    if (torqueExpanded || isSearching) && torqueGroups.count > 2 {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(torqueGroups, id: \.self) { group in
                                    chip(group)
                                }
                            }
                            .padding(.horizontal, 2)
                            .padding(.vertical, 2)
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                    let visible = canCollapse && !torqueExpanded ? Array(rows.prefix(Self.torquePreviewCount)) : rows
                    ForEach(visible, id: \.clientId) { spec in
                        Button { editingTorque = spec } label: {
                            TorqueRow(spec: spec, showGroup: selectedTorqueGroup == "Alle")
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button { pendingTorqueDelete = spec } label: {
                                Label("Löschen", systemImage: "trash")
                            }
                            .tint(.red)
                        }
                    }
                    if canCollapse {
                        expandRow(total: rows.count, expanded: $torqueExpanded)
                    }
                }
            } header: {
                sectionHeader("Drehmomente", count: isSearching ? rows.count : viewModel.torque.count)
            }
        }
    }

    private func chip(_ label: String) -> some View {
        let active = label == selectedTorqueGroup
        // No withAnimation on the state change — a global transaction animates
        // the header pills too. The chip's own change is scoped below.
        return Button {
            selectedTorqueGroup = label
        } label: {
            Text(label)
                .scaledFont(12, weight: .semibold)
                .foregroundStyle(active ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .glassEffect(
                    active
                        ? .regular.tint(Theme.Colors.primary).interactive()
                        : .regular.interactive(),
                    in: Capsule()
                )
                // Invisible bleed toward the 44 pt hit-target minimum — the
                // capsule stays compact, only the tappable area grows.
                .padding(.vertical, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? [.isSelected] : [])
        .animation(.easeOut(duration: 0.2), value: selectedTorqueGroup)
    }

    // MARK: - Documents

    @ViewBuilder
    private var documentsSection: some View {
        let bike = bikeDocuments
        let common = commonDocuments
        if !(isSearching && bike.isEmpty && common.isEmpty) {
            Section {
                if viewModel.documents.isEmpty && viewModel.commonDocuments.isEmpty && !isUploadingDocument {
                    emptySectionRow(
                        "Keine Dokumente erfasst",
                        icon: "doc",
                        actionLabel: "Dokument hochladen"
                    ) { showingDocumentImporter = true }
                } else {
                    if !bike.isEmpty {
                        documentStrip(title: common.isEmpty ? nil : motoLabel, documents: bike)
                    }
                    if !common.isEmpty {
                        documentStrip(title: "Allgemein", documents: common)
                    }
                    if isUploadingDocument {
                        HStack(spacing: Theme.Spacing.s) {
                            ProgressView()
                            Text("Dokument wird hochgeladen …")
                                .scaledFont(13, weight: .semibold)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                let count = isSearching ? bike.count + common.count : documentCount
                sectionHeader("Dokumente", count: count, unit: count == 1 ? "Datei" : "Dateien")
            }
        }
    }

    /// Horizontally scrolling row of document cards — keeps a long document
    /// list to one row of height instead of a grid that pushes everything
    /// else off screen.
    private func documentStrip(title: String?, documents: [Document]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            if let title { FormLabel(title) }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(documents) { doc in
                        Button {
                            presentedDocument = doc
                        } label: {
                            DocumentTile(document: doc, offlineStatus: offlineStore.status(of: doc))
                                .frame(width: 132)
                        }
                        .buttonStyle(.plain)
                        .contextMenu { offlineMenu(for: doc) }
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
        }
        .listRowInsets(EdgeInsets(top: Theme.Spacing.s, leading: Theme.Spacing.m,
                                  bottom: Theme.Spacing.s, trailing: Theme.Spacing.m))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private func offlineMenu(for doc: Document) -> some View {
        switch offlineStore.status(of: doc) {
        case .available:
            Button(role: .destructive) {
                offlineStore.removeOffline(doc)
            } label: {
                Label("Offline-Kopie entfernen", systemImage: "xmark.icloud")
            }
        case .notAvailable:
            Button {
                offlineStore.makeAvailableOffline(doc)
            } label: {
                Label("Offline verfügbar machen", systemImage: "arrow.down.circle")
            }
        case .downloading:
            Label("Wird geladen …", systemImage: "arrow.down.circle.dotted")
        }
    }

    private func handleDocumentSelection(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            isUploadingDocument = true
            Task {
                defer { isUploadingDocument = false }
                let hasAccess = url.startAccessingSecurityScopedResource()
                defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
                do {
                    let data = try await Task.detached(priority: .userInitiated) {
                        try Data(contentsOf: url, options: .mappedIfSafe)
                    }.value
                    let type = UTType(filenameExtension: url.pathExtension)
                    try await viewModel.uploadDocument(
                        title: url.deletingPathExtension().lastPathComponent,
                        fileName: url.lastPathComponent,
                        mimeType: type?.preferredMIMEType ?? "application/octet-stream",
                        data: data
                    )
                } catch {
                    documentUploadError = error.localizedDescription
                }
            }
        } catch {
            documentUploadError = error.localizedDescription
        }
    }
}

/// Flat title/value row. Both sides wrap instead of truncating — long values
/// (e.g. part numbers plus descriptions) are expected. URL values render as a
/// tappable link (host only, not the raw URL) that opens in the browser; the
/// rest of the row still opens the edit sheet like every other row.
private struct MotorcycleDetailRow: View {
    let detail: SDMotorcycleDetail

    var body: some View {
        HStack(alignment: .top) {
            HStack(spacing: 6) {
                Text(detail.title)
                    .scaledFont(13, weight: .semibold)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if detail.syncState.isPending { PendingBadge() }
            }
            Spacer(minLength: 8)
            if let url = linkURL {
                // Nested inside the edit Button, but the inner Link wins the
                // tap, so the URL opens while the rest of the row still edits.
                Link(destination: url) {
                    HStack(spacing: 4) {
                        Text(url.host() ?? detail.value)
                            .scaledFont(13, weight: .semibold)
                        Image(systemName: "arrow.up.right")
                            .scaledFont(10, weight: .bold)
                    }
                    .foregroundStyle(Theme.Colors.primary)
                }
                .accessibilityLabel("\(detail.title) öffnen")
            } else {
                Text(detail.value)
                    .scaledFont(13, weight: .medium)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .contentShape(Rectangle())
    }

    private var linkURL: URL? {
        let trimmed = detail.value.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://"),
              let url = URL(string: trimmed) else { return nil }
        return url
    }
}

// MARK: - Tire pressure table

/// Matrix of the recorded pressures: one row per tire position (Vorne /
/// Hinten / Beiwagen), one column per recorded riding configuration —
/// mirrors the webapp card. Column headers only render when they carry
/// information (several configurations, or a single non-solo one).
private struct TirePressureTable: View {
    let pressure: TirePressure

    private var configs: [PressureConfig] { pressure.recordedConfigs }

    private var showHeader: Bool {
        configs.count > 1 || configs.contains { $0 != .solo }
    }

    var body: some View {
        if showHeader {
            HStack {
                Color.clear.frame(width: 70, height: 1)
                ForEach(configs) { cfg in
                    Text(cfg.label.uppercased())
                        .scaledFont(9, weight: .heavy)
                        .tracking(1.5)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }

        row(label: "Vorne") { $0.front }
        row(label: "Hinten") { $0.rear }
        if pressure.hasSidecarValues {
            row(label: "Beiwagen") { $0.sidecar }
        }
    }

    private func row(
        label: String,
        value: @escaping ((front: Double?, rear: Double?, sidecar: Double?)) -> Double?
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label.uppercased())
                .scaledFont(9, weight: .heavy)
                .tracking(1.5)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            ForEach(configs) { cfg in
                cell(bar: value(pressure.values(for: cfg)))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.vertical, 2)
    }

    private func cell(bar: Double?) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            if let bar {
                Text(PressureUnitFormat.display(bar: bar, unit: pressure.preferredUnit))
                    .scaledFont(14, weight: .bold)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Colors.primary)
                Text(PressureUnitFormat.secondary(bar: bar, unit: pressure.preferredUnit))
                    .scaledFont(9, weight: .semibold)
                    .foregroundStyle(.secondary)
            } else {
                Text("—")
                    .scaledFont(14, weight: .bold)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Torque row

/// Built to be read at arm's length at the bike: the torque value is the
/// largest thing on the row, the tool size sits in its own badge (it's what
/// you reach for), and every size scales with Dynamic Type.
private struct TorqueRow: View {
    let spec: SDTorqueSpec
    let showGroup: Bool

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(spec.name)
                        .scaledFont(17, weight: .semibold)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if spec.syncState.isPending { PendingBadge() }
                }

                if hasTool || showGroup || spec.unverified {
                    // Badges keep their text on one line and wrap as a whole
                    // when the value column leaves too little width.
                    BadgeFlow(spacing: 6) {
                        if let tool = spec.toolSize, !tool.isEmpty {
                            Label(tool, systemImage: "wrench.adjustable")
                                .labelStyle(.titleAndIcon)
                                .scaledFont(14, weight: .bold)
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.primary.opacity(0.08)))
                                .fixedSize()
                        }
                        if showGroup {
                            Text(spec.category.uppercased())
                                .scaledFont(11, weight: .heavy)
                                .tracking(0.4)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Theme.Colors.primary.opacity(0.16)))
                                .foregroundStyle(Theme.Colors.primary)
                                .fixedSize()
                        }
                        if spec.unverified {
                            Label("Unverifiziert", systemImage: "exclamationmark.triangle.fill")
                                .labelStyle(.titleAndIcon)
                                .scaledFont(11, weight: .heavy)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.orange.opacity(0.16)))
                                .foregroundStyle(.orange)
                                .fixedSize()
                        }
                    }
                }

                // Full description on its own line so it wraps and the row
                // grows vertically instead of truncating.
                if let description = spec.recordDescription, !description.isEmpty {
                    Text(description)
                        .scaledFont(14)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(valueText)
                        .scaledFont(30, weight: .bold, design: .rounded)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("Nm")
                        .scaledFont(15, weight: .bold, design: .rounded)
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(spec.unverified ? Color.orange : Theme.Colors.primary)
                if let tolerance = toleranceText {
                    Text(tolerance)
                        .scaledFont(14, weight: .semibold, design: .rounded)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var hasTool: Bool { !(spec.toolSize ?? "").isEmpty }

    /// "60", "25–30", "2,5" — German decimals, no truncation of halves.
    private var valueText: String {
        if let end = spec.torqueEnd, end != spec.torque {
            return "\(Self.format(spec.torque))–\(Self.format(end))"
        }
        return Self.format(spec.torque)
    }

    private var toleranceText: String? {
        guard let variation = spec.variation, variation > 0 else { return nil }
        return "± \(Self.format(variation)) Nm"
    }

    private var accessibilityText: String {
        var parts = [spec.name]
        if let end = spec.torqueEnd, end != spec.torque {
            parts.append("\(Self.format(spec.torque)) bis \(Self.format(end)) Newtonmeter")
        } else {
            parts.append("\(Self.format(spec.torque)) Newtonmeter")
        }
        if let variation = spec.variation, variation > 0 {
            parts.append("Toleranz plus minus \(Self.format(variation))")
        }
        if let tool = spec.toolSize, !tool.isEmpty { parts.append("Werkzeug \(tool)") }
        if showGroup { parts.append(spec.category) }
        if spec.unverified { parts.append("unverifiziert") }
        if let description = spec.recordDescription, !description.isEmpty { parts.append(description) }
        return parts.joined(separator: ", ")
    }

    static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)).locale(Formatters.displayLocale))
    }
}

/// Left-aligned row of badges that wraps onto further lines instead of
/// squeezing its children.
private struct BadgeFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                                      proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width && !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

// MARK: - Document tile

/// Width : height of every card in the documents grid. Both tile types use
/// it, so all cells end up the same size no matter what they contain.
private let documentCardAspect: CGFloat = 0.74

private struct DocumentTile: View {
    let document: Document
    let offlineStatus: DocumentOfflineStore.Status

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                // The preview fills whatever space the fixed card shape leaves
                // above the text block. `Color.clear` owns the layout so an
                // oddly-proportioned thumbnail (e.g. a landscape wiring
                // diagram) can never inflate the card — the image covers and
                // gets cropped instead.
                Color.clear
                    .overlay(DocumentThumbnailView(document: document))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.controlInner))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.controlInner)
                            .stroke(Theme.Glass.strongBorder, lineWidth: 0.5)
                    )

                Text(fileBadge)
                    .scaledFont(9, weight: .black)
                    .tracking(0.4)
                    .foregroundStyle(Theme.Colors.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Theme.Colors.accent.opacity(0.22))
                    )
                    .padding(8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 4) {
                Text(document.title)
                    .scaledFont(13, weight: .bold)
                    .foregroundStyle(.primary)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    Text(Formatters.mediumDate(String(document.createdAt.prefix(10))))
                        .scaledFont(10, weight: .medium)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    offlineBadge
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .aspectRatio(documentCardAspect, contentMode: .fit)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.field)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    @ViewBuilder
    private var offlineBadge: some View {
        switch offlineStatus {
        case .available:
            Image(systemName: "arrow.down.circle.fill")
                .scaledFont(11, weight: .semibold)
                .foregroundStyle(.green.opacity(0.85))
                .accessibilityLabel("Offline verfügbar")
        case .downloading:
            ProgressView()
                .controlSize(.mini)
                .accessibilityLabel("Wird für offline geladen")
        case .notAvailable:
            EmptyView()
        }
    }

    private var fileBadge: String {
        let ext = (document.filePath as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf": return "PDF"
        case "jpg", "jpeg", "png", "heic", "heif": return "IMG"
        case "": return "DOC"
        default: return ext.uppercased()
        }
    }
}

struct WorkshopView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            LiquidBackgroundView().ignoresSafeArea()
            WorkshopView(viewModel: .mock)
        }
    }
}
