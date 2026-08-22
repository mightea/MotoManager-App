import SwiftUI
import UniformTypeIdentifiers

struct WorkshopView: View {
    @ObservedObject var viewModel: MotorcycleDetailViewModel
    @Environment(\.chromeActions) private var chrome
    @State private var presentedDocument: Document?
    @ObservedObject private var offlineStore = DocumentOfflineStore.shared
    @State private var selectedTorqueGroup: String = "Alle"
    @State private var showingAddTorque = false
    @State private var editingTorque: SDTorqueSpec?
    @State private var showingAddDetail = false
    @State private var editingDetail: SDMotorcycleDetail?
    @State private var showingTirePressure = false
    @State private var showingDocumentImporter = false
    @State private var isUploadingDocument = false
    @State private var documentUploadError: String?

    enum DocScope: Hashable { case moto, common }
    @State private var docScope: DocScope = .moto

    private var displayedDocuments: [Document] {
        switch docScope {
        case .moto: return viewModel.documents
        case .common: return viewModel.commonDocuments
        }
    }

    private var motoLabel: String {
        let make = viewModel.motorcycle.make
        let model = viewModel.motorcycle.model
        let full = "\(make) \(model)"
        return full.count > 14 ? make : full
    }

    private var groupedTorqueSpecs: [(category: String, specs: [SDTorqueSpec])] {
        Dictionary(grouping: viewModel.torque) { $0.category }
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { (category: $0.key, specs: $0.value) }
    }

    private var torqueGroups: [String] {
        ["Alle"] + groupedTorqueSpecs.map { $0.category }
    }

    private var filteredTorque: [SDTorqueSpec] {
        if selectedTorqueGroup == "Alle" { return viewModel.torque }
        return viewModel.torque.filter { $0.category == selectedTorqueGroup }
    }

    private var bothEmpty: Bool {
        viewModel.torque.isEmpty
            && viewModel.details.isEmpty
            && viewModel.documents.isEmpty
            && viewModel.commonDocuments.isEmpty
            && viewModel.tirePressure == nil
    }

    // MARK: - Header stat strip

    private var documentCount: Int {
        viewModel.documents.count + viewModel.commonDocuments.count
    }

    private var statStrip: some View {
        StatStrip([
            pressureTile,
            StatTile(
                eyebrow: "Drehmomente",
                value: "\(viewModel.torque.count)",
                unit: viewModel.torque.count == 1 ? "Eintrag" : "Einträge"
            ),
            StatTile(
                eyebrow: "Dokumente",
                value: "\(documentCount)",
                unit: documentCount == 1 ? "Datei" : "Dateien"
            )
        ])
    }

    /// Front/rear pressure of the first recorded configuration, in the unit
    /// the user entered them in (mirrors `TirePressureTable`).
    private var pressureTile: StatTile {
        guard let pressure = viewModel.tirePressure,
              let config = pressure.recordedConfigs.first else {
            return StatTile(eyebrow: "Reifendruck", value: "—", unit: "nicht erfasst")
        }
        let values = pressure.values(for: config)
        let unit = pressure.preferredUnit
        func text(_ bar: Double?) -> String {
            bar.map { PressureUnitFormat.fieldText(bar: $0, unit: unit) } ?? "—"
        }
        return StatTile(
            eyebrow: "Reifendruck",
            value: "\(text(values.front)) / \(text(values.rear))",
            unit: "\(unit) vorne / hinten",
            accent: Theme.Colors.primary
        )
    }

    var body: some View {
        List {
            // Match the fuel page: the photo extends below the content so
            // the stat strip overlaps the image instead of a hard cut-off.
            Section {
                ZStack(alignment: .bottom) {
                    MotorcycleSummaryHeader(
                        motorcycle: viewModel.motorcycle, type: .workshop, viewModel: viewModel,
                        bottomExtension: 96
                    )

                    statStrip
                        .padding(.horizontal, Theme.Spacing.pageH)
                        .padding(.bottom, 12)
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listSectionMargins(.all, 0)

            if viewModel.isLoading && bothEmpty {
                Section {
                    ForEach(0..<5, id: \.self) { _ in
                        loadingPlaceholderRow
                            .redacted(reason: .placeholder)
                    }
                }
            } else {
                tirePressureSection
                documentsSection
                detailsSection
                torqueSection
            }
        }
        .adaptiveContentWidth()
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .ignoresSafeArea(edges: .top)
        .refreshable {
            await viewModel.reconnect()
        }
        .toolbar {
            // Workshop's adds are per-section — the nav bar only carries settings.
            ToolbarItem(placement: .topBarTrailing) {
                Button("Einstellungen", systemImage: "gearshape") {
                    chrome.openSettings()
                }
            }
        }
        .navigationDestination(item: $presentedDocument) { doc in
            DocumentViewerView(document: doc)
        }
        .sheet(isPresented: $showingAddTorque) {
            AddTorqueView(viewModel: viewModel)
                .glassSheet(detents: [.medium, .large])
        }
        .sheet(item: $editingTorque) { spec in
            AddTorqueView(viewModel: viewModel, existingSpec: spec)
                .glassSheet(detents: [.medium, .large])
        }
        .sheet(isPresented: $showingAddDetail) {
            AddDetailView(viewModel: viewModel)
                .glassSheet(detents: [.medium, .large])
        }
        .sheet(item: $editingDetail) { detail in
            AddDetailView(viewModel: viewModel, existingDetail: detail)
                .glassSheet(detents: [.medium, .large])
        }
        .sheet(isPresented: $showingTirePressure) {
            AddTirePressureView(viewModel: viewModel)
                .glassSheet(detents: [.medium, .large])
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

    /// Section header with a small trailing add/edit action — the native
    /// list-header idiom for per-section adds.
    private func sectionHeader(_ title: String, icon: String, label: String, action: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
            Spacer()
            Button(action: action) {
                Image(systemName: icon)
                    .scaledFont(11, weight: .heavy)
            }
            .buttonStyle(.borderless)
            .tint(Theme.Colors.primary)
            .accessibilityLabel(label)
        }
    }

    // MARK: - Tire pressure

    @ViewBuilder
    private var tirePressureSection: some View {
        Section {
            if let pressure = viewModel.tirePressure {
                TirePressureTable(pressure: pressure)
            } else {
                Button { showingTirePressure = true } label: {
                    Text("Keine Werte erfasst — tippen zum Hinzufügen.")
                        .scaledFont(12, weight: .medium)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        } header: {
            sectionHeader(
                "Reifendruck",
                icon: viewModel.tirePressure == nil ? "plus" : "pencil",
                label: viewModel.tirePressure == nil ? "Reifendruck erfassen" : "Reifendruck bearbeiten"
            ) { showingTirePressure = true }
        }
    }

    // MARK: - Documents

    @ViewBuilder
    private var documentsSection: some View {
        Section {
            GlassSegmentedControl(
                segments: [
                    .init(value: .moto, label: motoLabel),
                    .init(value: .common, label: "Allgemein")
                ],
                selection: $docScope
            )
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            if displayedDocuments.isEmpty {
                // Explain what the segment *means* — "Allgemein" being empty
                // is expected as long as every document is bound to a bike,
                // but a blank grid doesn't say so.
                Text(docScope == .common
                    ? "Keine allgemeinen Dokumente — Dokumente ohne Motorrad-Zuordnung erscheinen hier."
                    : "Keine Dokumente für \(motoLabel) erfasst.")
                    .scaledFont(12, weight: .medium)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            } else {
                documentsGrid
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .padding(.vertical, 2)
            }

            Button {
                showingDocumentImporter = true
            } label: {
                Group {
                    if isUploadingDocument {
                        Label("Dokument wird hochgeladen …", systemImage: "arrow.up.circle")
                    } else {
                        Label("Dokument hochladen", systemImage: "plus")
                    }
                }
                .scaledFont(13, weight: .semibold)
            }
            .tint(Theme.Colors.primary)
            .disabled(isUploadingDocument)
        } header: {
            HStack {
                Text("Dokumente")
                Spacer()
                Text("\(displayedDocuments.count) \(displayedDocuments.count == 1 ? "Eintrag" : "Einträge")")
            }
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

    private var documentsGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
            spacing: 10
        ) {
            ForEach(displayedDocuments) { doc in
                    Button {
                        presentedDocument = doc
                    } label: {
                        DocumentTile(document: doc, offlineStatus: offlineStore.status(of: doc))
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
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
            }
        }
    }

    // MARK: - Torque

    @ViewBuilder
    private var torqueSection: some View {
        Section {
            if viewModel.torque.isEmpty {
                Button { showingAddTorque = true } label: {
                    Text("Keine Werte erfasst — tippen zum Hinzufügen.")
                        .scaledFont(12, weight: .medium)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            } else {
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

                ForEach(filteredTorque, id: \.clientId) { spec in
                    Button { editingTorque = spec } label: {
                        TorqueRow(spec: spec, showGroup: selectedTorqueGroup == "Alle")
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            _ = viewModel.deleteTorque(spec)
                        } label: {
                            Label("Löschen", systemImage: "trash")
                        }
                        .tint(.red)
                    }
                }
            }
        } header: {
            sectionHeader(
                "Drehmoment-Spezifikationen",
                icon: "plus",
                label: "Drehmoment hinzufügen"
            ) { showingAddTorque = true }
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
                .padding(.vertical, 6)
                .glassEffect(
                    active
                        ? .regular.tint(Theme.Colors.primary).interactive()
                        : .regular.interactive(),
                    in: Capsule()
                )
        }
        .animation(.easeOut(duration: 0.2), value: selectedTorqueGroup)
    }
}

// MARK: - Details

extension WorkshopView {
    @ViewBuilder
    private var detailsSection: some View {
        Section {
            if viewModel.details.isEmpty {
                Button { showingAddDetail = true } label: {
                    Text("Keine Details erfasst — tippen zum Hinzufügen.")
                        .scaledFont(12, weight: .medium)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            } else {
                ForEach(viewModel.details, id: \.clientId) { detail in
                    Button { editingDetail = detail } label: {
                        MotorcycleDetailRow(detail: detail)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            _ = viewModel.deleteDetail(detail)
                        } label: {
                            Label("Löschen", systemImage: "trash")
                        }
                        .tint(.red)
                    }
                }
            }
        } header: {
            sectionHeader("Details", icon: "plus", label: "Detail hinzufügen") {
                showingAddDetail = true
            }
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

private struct TorqueRow: View {
    let spec: SDTorqueSpec
    let showGroup: Bool

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(spec.name)
                        .scaledFont(13, weight: .semibold)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if spec.syncState.isPending { PendingBadge() }
                    if spec.unverified {
                        Label("Unverifiziert", systemImage: "exclamationmark.triangle.fill")
                            .labelStyle(.titleAndIcon)
                            .scaledFont(9, weight: .heavy)
                            .tracking(0.4)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(Color.orange.opacity(0.16)))
                            .foregroundStyle(.orange)
                    }
                }

                if showGroup || (spec.toolSize.map { !$0.isEmpty } ?? false) {
                    HStack(spacing: 6) {
                        if showGroup {
                            Text(spec.category.uppercased())
                                .scaledFont(9, weight: .heavy)
                                .tracking(0.4)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1.5)
                                .background(Capsule().fill(Theme.Colors.primary.opacity(0.22)))
                                .foregroundStyle(Theme.Colors.primary)
                        }
                        if let tool = spec.toolSize, !tool.isEmpty {
                            Text(tool)
                                .scaledFont(10, weight: .semibold)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Full description on its own line so it wraps and the row grows
                // vertically instead of truncating.
                if let description = spec.recordDescription, !description.isEmpty {
                    Text(description)
                        .scaledFont(11)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Text(torqueDisplay)
                .scaledFont(15, weight: .bold)
                .monospacedDigit()
                .foregroundStyle(spec.unverified ? Color.orange : Theme.Colors.primary)
        }
        .contentShape(Rectangle())
    }

    private var torqueDisplay: String {
        if let end = spec.torqueEnd, end != spec.torque {
            return "\(Int(spec.torque))–\(Int(end)) Nm"
        }
        return "\(Int(spec.torque)) Nm"
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
