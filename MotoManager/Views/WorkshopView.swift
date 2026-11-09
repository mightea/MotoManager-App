import SwiftUI
import UniformTypeIdentifiers
import VisionKit

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
    @Environment(\.chromeActions) private var chrome
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
    /// The document library: pushed on phones, swapped into the list
    /// column on wide layouts.
    @State private var showingLibrary = false
    @State private var showingScanner = false
    /// The scan the scanner handed back, offered for upload once it closed.
    @State private var scannedPDF: Data?
    /// A picked file or scan waiting for its title and type.
    @State private var pendingUpload: PendingDocumentUpload?
    @State private var editingDocument: Document?
    // Read the workspace width before NavigationSplitView narrows its columns.
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// Rows a collapsed section shows before "Alle … anzeigen".
    private static let torquePreviewCount = 3
    private static let detailsPreviewCount = 4

    private var query: String { searchText.trimmingCharacters(in: .whitespaces) }
    private var isSearching: Bool { !query.isEmpty }

    private func matchesSearch(_ text: String) -> Bool {
        !isSearching || text.localizedStandardContains(query)
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
                if VNDocumentCameraViewController.isSupported {
                    Button("Dokument scannen", systemImage: "doc.viewfinder") { showingScanner = true }
                }
            } label: {
                WorkspaceActionLabel(title: "Hinzufügen", systemImage: "plus", prominent: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Hinzufügen")
            .keyboardShortcut("n", modifiers: .command)
        } content: {
            RecordBrowser(selection: $presentedDocument, title: "Technische Daten",
                          emptyTitle: "Dokument auswählen", systemImage: "doc.text",
                          overview: AnyView(referenceOverview)) {
                if showingLibrary && sizeClass == .regular {
                    library(onBack: { showingLibrary = false })
                } else {
                    referenceList
                }
            } detail: { document in
                DocumentViewerView(document: document,
                                   onEdit: viewModel.canEdit(document) ? { editingDocument = document } : nil)
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
        .fullScreenCover(isPresented: $showingScanner, onDismiss: {
            // Ask for title and type only once the scanner is gone — a sheet
            // presented while the cover dismisses would be dropped.
            guard let pdf = scannedPDF else { return }
            scannedPDF = nil
            let stamp = Date().formatted(.dateTime.day().month(.twoDigits).year().locale(Formatters.displayLocale))
            pendingUpload = PendingDocumentUpload(title: "Scan \(stamp)", fileName: "Scan.pdf",
                                                  mimeType: "application/pdf") { pdf }
        }) {
            DocumentScannerView { pdf in
                scannedPDF = pdf
                showingScanner = false
            }
            .ignoresSafeArea()
        }
        .sheet(item: $pendingUpload) { pending in
            DocumentFormView(mode: .upload(pending), viewModel: viewModel, onUpload: { pending, title, docType in
                upload(title: title, docType: docType, fileName: pending.fileName, mimeType: pending.mimeType,
                       data: pending.data)
            })
            .glassSheet()
        }
        .sheet(item: $editingDocument) { document in
            DocumentFormView(mode: .edit(document), viewModel: viewModel, onSaved: { updated in
                if presentedDocument?.id == updated.id { presentedDocument = updated }
            })
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

            if viewModel.showsLoadingPlaceholders && isEmpty {
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
                documentsSection
                vehicleSection
                tirePressureSection
                detailsSection
                torqueSection
            }
            WorkspaceListFooter()
        }
        .accessibilityIdentifier("workshop.references")
        .alignsWorkspaceColumn(.list)
        .navigationDestination(isPresented: Binding(
            get: { showingLibrary && sizeClass != .regular },
            set: { showingLibrary = $0 }
        )) {
            library(onBack: nil)
        }
        .tracksWorkspaceHeader()
        .workspaceListStyle()
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.Colors.background)
        .refreshable { await viewModel.reconnect() }
    }

    /// Detail column on iPad while no document is open. The list column
    /// already shows every section, so this only summarises.
    private var referenceOverview: some View {
        List {
            OverviewTitle("Technik im Blick")
            Section { StatTileGrid(statTiles).cardRow() }
            Section {
                Label("Öffne ein Dokument, um es neben den technischen Daten zu lesen.", systemImage: "doc.text.magnifyingglass")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("workshop.overview")
        .alignsWorkspaceColumn(.overview)
        .workspaceListStyle()
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.background)
        .toolbar(.hidden, for: .navigationBar)
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

    // MARK: - Vehicle (identity data, edited via the bike sheet)

    /// (label, value) rows for the registration data the bike carries.
    private var vehicleRows: [(String, String)] {
        let m = viewModel.motorcycle
        var rows: [(String, String)] = []
        if let vin = m.vin, !vin.isEmpty { rows.append(("Fahrgestellnummer", vin)) }
        if let engine = m.engineNumber, !engine.isEmpty { rows.append(("Motornummer", engine)) }
        if let nr = m.vehicleNr, !nr.isEmpty { rows.append(("Stammnummer", nr)) }
        if let first = m.firstRegistration, !first.isEmpty {
            rows.append(("Erstzulassung", Formatters.mediumDate(String(first.prefix(10)))))
        }
        if let tank = m.fuelTankSize, tank > 0 { rows.append(("Tankinhalt", String(format: "%g L", tank))) }
        return rows
    }

    @ViewBuilder
    private var vehicleSection: some View {
        Section {
            if vehicleRows.isEmpty {
                emptySectionRow(
                    "Keine Fahrzeugdaten erfasst",
                    icon: "doc.text",
                    actionLabel: "Fahrzeugdaten ergänzen"
                ) { chrome.editMotorcycle() }
            } else {
                ForEach(vehicleRows, id: \.0) { row in
                    HStack(alignment: .top) {
                        Text(row.0)
                            .scaledFont(13, weight: .semibold)
                        Spacer(minLength: 8)
                        Text(row.1)
                            .scaledFont(13, weight: .medium)
                            .monospaced()
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                            .textSelection(.enabled)
                    }
                    .accessibilityElement(children: .combine)
                }
                Button {
                    chrome.editMotorcycle()
                } label: {
                    Label("Motorrad bearbeiten", systemImage: "pencil")
                        .scaledFont(13, weight: .semibold)
                }
                .tint(Theme.Colors.primary)
                .accessibilityIdentifier("workshop.editMotorcycle")
            }
        } header: {
            sectionHeader("Fahrzeug")
        }
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

    /// Not searching: the three latest documents and the way into the
    /// library, first thing in Technik. Searching: every matching file.
    @ViewBuilder
    private var documentsSection: some View {
        let all = (viewModel.documents + viewModel.commonDocuments).sorted { $0.createdAt > $1.createdAt }
        if isSearching {
            let matches = bikeDocuments + commonDocuments
            if !matches.isEmpty {
                Section {
                    ForEach(matches) { document in
                        Button { presentedDocument = document } label: {
                            HStack(spacing: Theme.Spacing.m - 4) {
                                DocumentPreview(document: document)
                                Text(document.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                                Spacer(minLength: 0)
                                DocumentOfflineMark(status: offlineStore.status(of: document)).font(.subheadline)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu { DocumentOfflineMenu(document: document, store: offlineStore) }
                    }
                } header: {
                    sectionHeader("Dokumente", count: matches.count, unit: matches.count == 1 ? "Datei" : "Dateien")
                }
            }
        } else if all.isEmpty && !isUploadingDocument {
            Section {
                emptySectionRow("Keine Dokumente erfasst", icon: "doc", actionLabel: "Dokument hochladen") {
                    showingDocumentImporter = true
                }
            } header: {
                sectionHeader("Dokumente", count: 0, unit: "Dateien")
            }
        } else {
            Section {
                RecentDocumentsCard(documents: all, total: all.count,
                                    onOpen: { presentedDocument = $0 },
                                    onShowAll: { showingLibrary = true })
                if isUploadingDocument {
                    HStack(spacing: Theme.Spacing.s) {
                        ProgressView()
                        Text("Dokument wird hochgeladen …")
                            .scaledFont(13, weight: .semibold)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func library(onBack: (() -> Void)?) -> some View {
        DocumentLibraryView(viewModel: viewModel, offlineStore: offlineStore, selection: $presentedDocument,
                            isUploading: isUploadingDocument,
                            onUpload: { showingDocumentImporter = true },
                            onScan: { showingScanner = true },
                            onEdit: { editingDocument = $0 },
                            onBack: onBack)
    }

    /// Uploads one file and reports failures in the shared alert.
    private func upload(title: String, docType: DocumentType?, fileName: String, mimeType: String,
                        data: @escaping @Sendable () throws -> Data) {
        isUploadingDocument = true
        Task {
            defer { isUploadingDocument = false }
            do {
                let bytes = try await Task.detached(priority: .userInitiated) { try data() }.value
                try await viewModel.uploadDocument(title: title, docType: docType, fileName: fileName,
                                                   mimeType: mimeType, data: bytes)
            } catch {
                documentUploadError = error.localizedDescription
            }
        }
    }

    private func handleDocumentSelection(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let type = UTType(filenameExtension: url.pathExtension)
            pendingUpload = PendingDocumentUpload(
                title: url.deletingPathExtension().lastPathComponent,
                fileName: url.lastPathComponent,
                mimeType: type?.preferredMIMEType ?? "application/octet-stream"
            ) {
                let hasAccess = url.startAccessingSecurityScopedResource()
                defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
                return try Data(contentsOf: url, options: .mappedIfSafe)
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
                    Text(NoteBrandPalette.display(description: description, markup: spec.descriptionMarkup))
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

struct WorkshopView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            LiquidBackgroundView().ignoresSafeArea()
            WorkshopView(viewModel: .mock)
        }
    }
}
