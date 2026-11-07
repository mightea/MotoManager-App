import SwiftUI
import VisionKit

// MARK: - Shared bits

/// Short type label for a document, from its file extension.
enum DocumentKind {
    static func label(_ document: Document) -> String {
        let ext = (document.filePath as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf": return "PDF"
        case "jpg", "jpeg": return "JPG"
        case "png": return "PNG"
        case "heic", "heif": return "HEIC"
        case "": return "DOC"
        default: return ext.uppercased()
        }
    }

    static func tint(_ document: Document) -> Color {
        label(document) == "PDF" ? Theme.Colors.accent : Theme.Colors.primary
    }
}

/// Small page preview with the type badge on its corner.
struct DocumentPreview: View {
    let document: Document
    var width: CGFloat = 34
    var height: CGFloat = 44

    var body: some View {
        Color.clear
            .overlay(DocumentThumbnailView(document: document))
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.Glass.strongBorder, lineWidth: 0.5))
            .overlay(alignment: .bottomLeading) {
                Text(DocumentKind.label(document))
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(DocumentKind.tint(document))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(DocumentKind.tint(document).opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
                    .background(Theme.Colors.backgroundElevated, in: RoundedRectangle(cornerRadius: 4))
                    .offset(x: -4, y: 4)
            }
            .accessibilityHidden(true)
    }
}

/// Offline state at the trailing edge of a document row.
struct DocumentOfflineMark: View {
    let status: DocumentOfflineStore.Status

    var body: some View {
        switch status {
        case .available:
            Image(systemName: "checkmark.icloud.fill")
                .foregroundStyle(.green)
                .accessibilityLabel("Offline verfügbar")
        case .downloading:
            ProgressView().controlSize(.small)
                .accessibilityLabel("Wird für offline geladen")
        case .notAvailable:
            Image(systemName: "icloud")
                .foregroundStyle(.tertiary)
                .accessibilityLabel("Nur online")
        }
    }
}

/// Context-menu items that pin or unpin a document for offline use.
struct DocumentOfflineMenu: View {
    let document: Document
    @ObservedObject var store: DocumentOfflineStore

    var body: some View {
        switch store.status(of: document) {
        case .available:
            Button(role: .destructive) { store.removeOffline(document) } label: {
                Label("Offline-Kopie entfernen", systemImage: "xmark.icloud")
            }
        case .notAvailable:
            Button { store.makeAvailableOffline(document) } label: {
                Label("Offline verfügbar machen", systemImage: "arrow.down.circle")
            }
        case .downloading:
            Label("Wird geladen …", systemImage: "arrow.down.circle.dotted")
        }
    }
}

// MARK: - Technik card

/// The three latest documents at the top of Technik, with the way into the
/// whole library.
struct RecentDocumentsCard: View {
    let documents: [Document]
    let total: Int
    let onOpen: (Document) -> Void
    let onShowAll: () -> Void
    @Environment(\.workspaceIsCondensed) private var isCondensed

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text("Dokumente").font(.headline)
                Spacer()
                Button(action: onShowAll) {
                    Text("Alle \(total)").fontWeight(.semibold) + Text(" ›")
                }
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.primary)
                .buttonStyle(.borderless)
                .accessibilityLabel("Alle \(total) Dokumente anzeigen")
                .accessibilityIdentifier("workshop.documents.all")
            }
            HStack(alignment: .top, spacing: Theme.Spacing.s) {
                ForEach(documents.prefix(3)) { document in
                    Button { onOpen(document) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Color.clear
                                .overlay(DocumentThumbnailView(document: document))
                                .frame(height: isCondensed ? 70 : 96)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.controlInner))
                                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.controlInner)
                                    .stroke(Theme.Glass.strongBorder, lineWidth: 0.5))
                                .overlay(alignment: .bottomLeading) {
                                    Text(DocumentKind.label(document))
                                        .font(.system(size: 9, weight: .heavy))
                                        .foregroundStyle(DocumentKind.tint(document))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(DocumentKind.tint(document).opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
                                        .background(Theme.Colors.backgroundElevated, in: RoundedRectangle(cornerRadius: 4))
                                        .padding(6)
                                }
                            Text(document.title)
                                .font(.caption.weight(.semibold))
                                .lineLimit(2, reservesSpace: true)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(document.title), \(DocumentKind.label(document))")
                }
                // Keep tile widths stable with fewer than three documents.
                ForEach(0..<max(0, 3 - min(3, documents.count)), id: \.self) { _ in
                    Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                }
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workshop.documents.recent")
    }
}

// MARK: - Library

enum DocumentFilter: Hashable, CaseIterable {
    case all, bike, common, offline
}

/// Every document of the bike plus the shared ones: search, filters by bike /
/// shared / offline, one row per file. Phones push it from Technik; the iPad
/// shows it in the list column, with the open file beside it.
struct DocumentLibraryView: View {
    @ObservedObject var viewModel: MotorcycleDetailViewModel
    @ObservedObject var offlineStore: DocumentOfflineStore
    @Binding var selection: Document?
    let isUploading: Bool
    let onUpload: () -> Void
    let onScan: () -> Void
    /// Set in the iPad list column, which has no navigation bar of its own.
    var onBack: (() -> Void)? = nil

    @State private var searchText = ""
    @State private var filter: DocumentFilter = .all

    private var query: String { searchText.trimmingCharacters(in: .whitespaces) }

    private func matches(_ document: Document) -> Bool {
        guard query.isEmpty || document.title.localizedStandardContains(query) else { return false }
        if filter == .offline { return offlineStore.status(of: document) == .available }
        return true
    }

    private var bikeDocuments: [Document] {
        filter == .common ? [] : sorted(viewModel.documents.filter(matches))
    }

    private var commonDocuments: [Document] {
        filter == .bike ? [] : sorted(viewModel.commonDocuments.filter(matches))
    }

    private func sorted(_ documents: [Document]) -> [Document] {
        documents.sorted { $0.createdAt > $1.createdAt }
    }

    private var offlineCount: Int {
        (viewModel.documents + viewModel.commonDocuments)
            .filter { offlineStore.status(of: $0) == .available }.count
    }

    private var bikeName: String { "\(viewModel.motorcycle.make) \(viewModel.motorcycle.model)" }

    var body: some View {
        List {
            if let onBack {
                Section {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        HStack {
                            Button(action: onBack) {
                                Label("Technische Daten", systemImage: "chevron.left")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(minHeight: 44)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier("documents.back")
                            Spacer()
                            addMenu
                        }
                        Text("Dokumente")
                            .font(.headline)
                            // Shares a baseline with the overview's title.
                            .background(alignment: .top) { ColumnTitleMarker(column: .list) }
                            .padding(.horizontal, Theme.Spacing.s)
                            .accessibilityAddTraits(.isHeader)
                    }
                }
                .cardRow()
            }
            Section {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    searchField
                    chips
                }
            }
            .cardRow()

            if isUploading {
                Section {
                    HStack(spacing: Theme.Spacing.s) {
                        ProgressView()
                        Text("Dokument wird hochgeladen …").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }

            if viewModel.documents.isEmpty && viewModel.commonDocuments.isEmpty && !isUploading {
                Section {
                    ListEmptyState {
                        Label("Keine Dokumente", systemImage: "doc")
                    } description: {
                        Text("Lade Anleitungen, Rechnungen oder den Fahrzeugausweis hoch – auf Wunsch auch offline verfügbar.")
                    } actions: {
                        Button("Dokument hochladen", systemImage: "doc.badge.plus", action: onUpload)
                    }
                }
                .cardRow()
            } else if bikeDocuments.isEmpty && commonDocuments.isEmpty {
                Section {
                    ContentUnavailableView(query.isEmpty ? "Keine Dokumente in diesem Filter" : "Keine Treffer",
                                           systemImage: "doc.text.magnifyingglass")
                }
                .cardRow()
            } else {
                if !bikeDocuments.isEmpty {
                    Section {
                        ForEach(bikeDocuments) { row($0, shared: false) }
                    } header: {
                        header(bikeName, count: bikeDocuments.count)
                    }
                }
                if !commonDocuments.isEmpty {
                    Section {
                        ForEach(commonDocuments) { row($0, shared: true) }
                    } header: {
                        header("Allgemein · für mehrere Motorräder", count: commonDocuments.count)
                    }
                }
            }
            WorkspaceListFooter()
        }
        .accessibilityIdentifier("documents.library")
        .alignsWorkspaceColumn(.list)
        .workspaceListStyle()
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.Colors.background)
        .refreshable { await viewModel.reconnect() }
        .navigationTitle("Dokumente")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(onBack == nil ? .visible : .hidden, for: .navigationBar)
        .toolbar {
            if onBack == nil {
                ToolbarItem(placement: .topBarTrailing) { addMenu }
            }
        }
    }

    private var addMenu: some View {
        Menu {
            Button("Datei hochladen", systemImage: "doc.badge.plus", action: onUpload)
            if VNDocumentCameraViewController.isSupported {
                Button("Dokument scannen", systemImage: "doc.viewfinder", action: onScan)
            }
        } label: {
            Label("Dokument hinzufügen", systemImage: "plus")
                .labelStyle(.iconOnly)
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityIdentifier("documents.add")
    }

    private var searchField: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
            TextField("Dokumente durchsuchen", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !searchText.isEmpty {
                Button("Suche löschen", systemImage: "xmark.circle.fill") { searchText = "" }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
                    .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, Theme.Spacing.m)
        .frame(minHeight: 44)
        .background(Theme.Colors.backgroundElevated, in: Capsule())
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip(.all, "Alle", count: viewModel.documents.count + viewModel.commonDocuments.count)
                chip(.bike, viewModel.motorcycle.model, count: viewModel.documents.count)
                if !viewModel.commonDocuments.isEmpty {
                    chip(.common, "Allgemein", count: viewModel.commonDocuments.count)
                }
                chip(.offline, "Offline", count: offlineCount)
            }
        }
        .scrollClipDisabled()
    }

    private func chip(_ value: DocumentFilter, _ title: String, count: Int) -> some View {
        let active = filter == value
        return Button { filter = value } label: {
            HStack(spacing: 4) {
                Text(title).lineLimit(1)
                Text("\(count)").opacity(0.7).monospacedDigit()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(active ? Color.white : Color.primary)
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .background(active ? Theme.Colors.primary : Theme.Colors.backgroundElevated, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func header(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(count)").monospacedDigit()
        }
    }

    private func row(_ document: Document, shared: Bool) -> some View {
        Button { selection = document } label: {
            HStack(spacing: Theme.Spacing.m - 4) {
                DocumentPreview(document: document)
                VStack(alignment: .leading, spacing: 2) {
                    Text(document.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(subtitle(document, shared: shared))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                DocumentOfflineMark(status: offlineStore.status(of: document))
                    .font(.subheadline)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .selectedRecord(selection?.id == document.id)
        .contextMenu { DocumentOfflineMenu(document: document, store: offlineStore) }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if offlineStore.status(of: document) == .available {
                Button { offlineStore.removeOffline(document) } label: {
                    Label("Offline entfernen", systemImage: "xmark.icloud")
                }
            } else {
                Button { offlineStore.makeAvailableOffline(document) } label: {
                    Label("Offline", systemImage: "arrow.down.circle")
                }
                .tint(Theme.Colors.primary)
            }
        }
        .accessibilityIdentifier("documents.row.\(document.id)")
    }

    private func subtitle(_ document: Document, shared: Bool) -> String {
        var parts = [Formatters.mediumDate(String(document.createdAt.prefix(10)))]
        if document.isPrivate { parts.append("privat") }
        if shared, let ids = document.motorcycleIds, ids.count > 1 {
            parts.append("\(ids.count) Motorräder")
        } else if shared {
            parts.append("alle Motorräder")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Scanner

/// The system document scanner; hands back the scanned pages as one PDF.
struct DocumentScannerView: UIViewControllerRepresentable {
    let onFinish: (Data?) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onFinish: (Data?) -> Void
        init(onFinish: @escaping (Data?) -> Void) { self.onFinish = onFinish }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            let pages = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
            onFinish(Self.pdf(from: pages))
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onFinish(nil)
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFailWithError error: Error) {
            onFinish(nil)
        }

        /// A4-wide pages sized to each scan's aspect ratio.
        static func pdf(from images: [UIImage]) -> Data? {
            guard let first = images.first else { return nil }
            let width: CGFloat = 595
            let bounds = CGRect(x: 0, y: 0, width: width, height: width * first.size.height / max(first.size.width, 1))
            return UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
                for image in images {
                    let height = width * image.size.height / max(image.size.width, 1)
                    let page = CGRect(x: 0, y: 0, width: width, height: height)
                    context.beginPage(withBounds: page, pageInfo: [:])
                    image.draw(in: page)
                }
            }
        }
    }
}
