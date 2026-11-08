import Combine
import PDFKit
import QuickLook
import SwiftUI

/// Document reader built for the workshop: works from the offline copy,
/// searches inside the PDF, zooms freely (not remembered), keeps named
/// bookmarks on the device, and opens full screen on iPad with a side panel
/// for pages, bookmarks and search. Whether opening stores the document for
/// offline use follows Einstellungen › Offline-Dokumente.
struct DocumentViewerView: View {
    let document: Document

    @ObservedObject private var offlineStore = DocumentOfflineStore.shared
    @StateObject private var reader = PDFReaderController()
    @StateObject private var search = PDFSearchModel()
    @AppStorage("com.motomanager.documents.keepScreenOn") private var keepScreenOn = true

    @State private var fileURL: URL?
    @State private var shareURL: URL?
    @State private var pdfDocument: PDFDocument?
    @State private var loadFailed = false
    @State private var loadWasOffline = false
    @State private var showingSearch = false
    @State private var showingPanel = false
    @State private var showingFullScreen = false
    @FocusState private var searchFocused: Bool

    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.Colors.background.ignoresSafeArea())
            .toolbar(.visible, for: .navigationBar)
            .navigationTitle(document.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    ReaderTitle(title: document.title, status: statusLine, statusColor: statusColor)
                }
                ToolbarItemGroup(placement: .topBarTrailing) { toolbarButtons }
            }
            .sheet(isPresented: $showingPanel) {
                if let pdfDocument {
                    NavigationStack {
                        ReaderPanel(document: document, pdf: pdfDocument, reader: reader, search: search,
                                    modes: [.bookmarks, .pages]) { showingPanel = false }
                            .navigationTitle("Lesezeichen")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) {
                                    Button("Fertig") { showingPanel = false }
                                }
                            }
                    }
                    .presentationDetents([.medium, .large])
                }
            }
            .fullScreenCover(isPresented: $showingFullScreen) {
                if let fileURL {
                    DocumentFullScreenReader(document: document, fileURL: fileURL, pdf: pdfDocument,
                                             startPage: reader.pageIndex)
                }
            }
            .task { await load() }
            .onAppear { applyKeepScreenOn() }
            .onChange(of: keepScreenOn) { _, _ in applyKeepScreenOn() }
            .onDisappear { if !showingFullScreen { UIApplication.shared.isIdleTimerDisabled = false } }
            .onChange(of: showingFullScreen) { _, presented in
                // The cover's own reader handles the idle timer while it is up.
                if !presented { applyKeepScreenOn() }
            }
    }

    @ViewBuilder
    private var content: some View {
        if let fileURL {
            VStack(spacing: 0) {
                if pdfDocument != nil && showingSearch {
                    ReaderSearchBar(search: search, reader: reader, focused: $searchFocused) {
                        withAnimation(.easeOut(duration: 0.18)) { showingSearch = false }
                        search.clear()
                    }
                }
                if let banner = offlineBanner { banner }
                if let pdfDocument {
                    PDFReaderSurface(document: document, pdf: pdfDocument, reader: reader, search: search)
                } else {
                    QuickLookPreview(url: fileURL).ignoresSafeArea(edges: .bottom)
                }
            }
        } else if loadFailed {
            failureState
        } else {
            loadingState
        }
    }

    @ViewBuilder
    private var toolbarButtons: some View {
        if pdfDocument != nil {
            Button("Im Dokument suchen", systemImage: "magnifyingglass") {
                withAnimation(.easeOut(duration: 0.18)) { showingSearch.toggle() }
                if showingSearch { searchFocused = true } else { search.clear() }
            }
            .accessibilityIdentifier("reader.search")
            if !isPad {
                Button("Lesezeichen", systemImage: "bookmark") { showingPanel = true }
                    .accessibilityIdentifier("reader.bookmarks")
            }
        }
        if isPad && fileURL != nil {
            Button("Vollbild", systemImage: "arrow.up.left.and.arrow.down.right") { showingFullScreen = true }
                .accessibilityIdentifier("reader.fullScreen")
        }
        ReaderMoreMenu(document: document, shareURL: shareURL, keepScreenOn: $keepScreenOn)
    }

    // MARK: - Offline state

    private var status: DocumentOfflineStore.Status { offlineStore.status(of: document) }

    private var pageSuffix: String {
        guard let count = pdfDocument?.pageCount else { return "" }
        return count == 1 ? " · 1 Seite" : " · \(count) Seiten"
    }

    private var statusLine: String {
        switch status {
        case .available: "Offline verfügbar" + pageSuffix
        case .downloading: "Wird gespeichert …"
        case .notAvailable: "Nur online" + pageSuffix
        }
    }

    private var statusColor: Color {
        status == .available ? .green : .secondary
    }

    /// Offers to keep the document when saving is on request; shows progress
    /// while a save runs.
    private var offlineBanner: AnyView? {
        switch status {
        case .available:
            return nil
        case .downloading:
            return AnyView(ReaderBanner(title: "Für die Werkstatt speichern", detail: "Wird gespeichert …",
                                        progress: true, action: nil))
        case .notAvailable:
            guard offlineStore.saveMode == .onRequest else { return nil }
            return AnyView(ReaderBanner(title: "Für die Werkstatt speichern",
                                        detail: "Danach auch ohne Netz lesbar.", progress: false) {
                offlineStore.makeAvailableOffline(document)
            })
        }
    }

    private func applyKeepScreenOn() {
        UIApplication.shared.isIdleTimerDisabled = keepScreenOn && fileURL != nil
    }

    // MARK: - Loading

    private var loadingState: some View {
        VStack(spacing: Theme.Spacing.m) {
            ProgressView()
            Text("Dokument wird geladen …")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var failureState: some View {
        VStack(spacing: Theme.Spacing.m) {
            Image(systemName: loadWasOffline ? "wifi.slash" : "exclamationmark.triangle.fill")
                .scaledFont(48)
                .foregroundStyle(.orange)
            Text(loadWasOffline ? "Offline" : "Dokument konnte nicht geladen werden")
                .font(.headline)
            Text(loadWasOffline
                 ? "Dieses Dokument ist nicht auf dem Gerät gespeichert. Mit Netz öffnen, damit es für die Werkstatt bereitliegt."
                 : "Bitte Verbindung prüfen und erneut versuchen.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .accessibilityElement(children: .combine)
    }

    private func load() async {
        loadFailed = false
        loadWasOffline = false
        let urlString = document.remoteFileURL

        if let cached = DocumentCache.shared.cachedFileURL(for: urlString) {
            present(cached)
            return
        }

        do {
            let downloaded = try await NetworkManager.shared.downloadBlob(url: urlString)
            defer { try? FileManager.default.removeItem(at: downloaded) }
            if let saved = await DocumentCache.shared.save(downloadedFile: downloaded, for: urlString) {
                present(saved)
            } else {
                loadFailed = true
            }
        } catch {
            if case APIError.offline = error { loadWasOffline = true }
            loadFailed = true
        }
    }

    private func present(_ url: URL) {
        // PDFs go through PDFKit so search works; anything else through
        // QuickLook. A PDF that PDFKit can't parse falls back to QuickLook.
        if DocumentThumbnailer.kind(for: document) == .pdf {
            pdfDocument = PDFDocument(url: url)
            search.pdf = pdfDocument
        }
        fileURL = url
        shareURL = Self.titledShareURL(for: url, title: document.title)
        offlineStore.noteOpened(document)
        applyKeepScreenOn()
    }

    /// The cache stores files under a URL hash; sharing that leaks an ugly
    /// filename into AirDrop/Files. Hand ShareLink a temp copy named after
    /// the document instead.
    static func titledShareURL(for url: URL, title: String) -> URL {
        let safeTitle = title
            .components(separatedBy: CharacterSet(charactersIn: "/:\\"))
            .joined(separator: "-")
        let ext = url.pathExtension
        let name = ext.isEmpty ? safeTitle : "\(safeTitle).\(ext)"
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.copyItem(at: url, to: dest)
            return dest
        } catch {
            return url
        }
    }
}

// MARK: - Full screen (iPad)

/// Full-screen reader: no sidebar, header or tabs. A side panel switches
/// between pages, bookmarks and search; floating bars carry the tools.
struct DocumentFullScreenReader: View {
    let document: Document
    let fileURL: URL
    let pdf: PDFDocument?
    var startPage = 0

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var offlineStore = DocumentOfflineStore.shared
    @StateObject private var reader = PDFReaderController()
    @StateObject private var search = PDFSearchModel()
    @AppStorage("com.motomanager.documents.keepScreenOn") private var keepScreenOn = true
    @State private var panel: ReaderPanel.Mode? = .pages
    @State private var nightMode = false

    var body: some View {
        HStack(spacing: 0) {
            if let pdf, let mode = panel {
                ReaderPanel(document: document, pdf: pdf, reader: reader, search: search,
                            modes: [.pages, .bookmarks, .search], initial: mode, onSelect: nil)
                    .id(mode)
                    .frame(width: 300)
                    .padding(.top, 64)
                    .background(Theme.Colors.background)
                    .transition(.move(edge: .leading))
                Divider()
            }
            ZStack {
                Theme.Colors.background.opacity(0.6)
                if let pdf {
                    PDFReaderSurface(document: document, pdf: pdf, reader: reader, search: search,
                                     topInset: 64, nightMode: nightMode)
                } else {
                    QuickLookPreview(url: fileURL)
                }
            }
        }
        .overlay(alignment: .top) { topBar }
        .background(Theme.Colors.background.ignoresSafeArea())
        .ignoresSafeArea(edges: .bottom)
        .animation(.easeOut(duration: 0.2), value: panel)
        .onAppear {
            search.pdf = pdf
            reader.pendingPage = startPage
            UIApplication.shared.isIdleTimerDisabled = keepScreenOn
        }
        .onChange(of: keepScreenOn) { _, on in UIApplication.shared.isIdleTimerDisabled = on }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private var topBar: some View {
        HStack(spacing: Theme.Spacing.s) {
            Button { dismiss() } label: {
                Label("Fertig", systemImage: "arrow.down.right.and.arrow.up.left")
                    .font(.subheadline.weight(.bold))
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
            }
            .glassEffect(.regular.interactive(), in: Capsule())
            .keyboardShortcut(.cancelAction)
            .accessibilityIdentifier("reader.exitFullScreen")

            HStack(spacing: 6) {
                Text(document.title).font(.subheadline.weight(.bold)).lineLimit(1)
                if offlineStore.status(of: document) == .available {
                    Text("● offline").font(.caption.weight(.semibold)).foregroundStyle(.green)
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .glassEffect(.regular, in: Capsule())

            Spacer(minLength: 0)

            HStack(spacing: 2) {
                if pdf != nil {
                    toolButton("Suchen", "magnifyingglass", active: panel == .search) { togglePanel(.search) }
                    toolButton("Lesezeichen", "bookmark", active: panel == .bookmarks) { togglePanel(.bookmarks) }
                    toolButton("Seiten", "square.grid.2x2", active: panel == .pages) { togglePanel(.pages) }
                    toolButton("Verkleinern", "minus.magnifyingglass", active: false) { reader.zoom(by: 0.8) }
                    toolButton("Vergrössern", "plus.magnifyingglass", active: false) { reader.zoom(by: 1.25) }
                    toolButton("Nachtmodus", "circle.lefthalf.filled", active: nightMode) { nightMode.toggle() }
                }
                toolButton(keepScreenOn ? "Bildschirm bleibt an" : "Bildschirm darf ausgehen",
                           keepScreenOn ? "sun.max.fill" : "sun.max", active: keepScreenOn) { keepScreenOn.toggle() }
            }
            .padding(3)
            .glassEffect(.regular, in: Capsule())
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.top, Theme.Spacing.s)
    }

    private func togglePanel(_ mode: ReaderPanel.Mode) {
        panel = panel == mode ? nil : mode
    }

    private func toolButton(_ title: String, _ image: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: image)
                .font(.body.weight(.semibold))
                .foregroundStyle(active ? Color.white : Theme.Colors.primary)
                .frame(width: 44, height: 40)
                .background(Capsule().fill(active ? Theme.Colors.primary : .clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

// MARK: - Reader surface

/// The PDF with its floating page bar: page number, scrubber with bookmark
/// ticks, zoom level, and one tap to bookmark the current page.
struct PDFReaderSurface: View {
    let document: Document
    let pdf: PDFDocument
    @ObservedObject var reader: PDFReaderController
    @ObservedObject var search: PDFSearchModel
    var topInset: CGFloat = 0
    var nightMode = false
    @ObservedObject private var bookmarks = DocumentBookmarkStore.shared
    @State private var scrubPage: Double = 0
    @State private var scrubbing = false

    private var marks: [DocumentBookmark] { bookmarks.bookmarks(for: document.filePath) }
    private var currentMark: DocumentBookmark? { bookmarks.bookmark(for: document.filePath, page: reader.pageIndex) }

    var body: some View {
        PDFKitView(document: pdf, controller: reader, highlights: search.matches, current: search.current,
                   topInset: topInset)
            .modifier(NightMode(on: nightMode))
            .ignoresSafeArea(edges: .bottom)
            .overlay(alignment: .bottom) { pageBar }
            .onChange(of: reader.pageIndex) { _, page in if !scrubbing { scrubPage = Double(page) } }
    }

    private var pageBar: some View {
        HStack(spacing: Theme.Spacing.s + 2) {
            Text("\(reader.pageIndex + 1) / \(max(reader.pageCount, 1))")
                .font(.footnote.weight(.bold))
                .monospacedDigit()
                .fixedSize()
            if reader.pageCount > 1 {
                Slider(value: $scrubPage, in: 0...Double(reader.pageCount - 1), step: 1) { editing in
                    scrubbing = editing
                    if !editing { reader.go(to: Int(scrubPage)) }
                }
                .onChange(of: scrubPage) { _, page in if scrubbing { reader.go(to: Int(page)) } }
                .tint(Theme.Colors.primary)
                .background { ticks }
                .accessibilityLabel("Seite")
            } else {
                Spacer(minLength: 0)
            }
            Button { reader.fitWidth() } label: {
                Text("\(reader.zoomPercent) %").font(.footnote.weight(.bold)).monospacedDigit().fixedSize()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Zoom \(reader.zoomPercent) Prozent, auf Seitenbreite zurücksetzen")
            Button {
                let text = pdf.page(at: reader.pageIndex)?.string
                bookmarks.toggle(filePath: document.filePath, page: reader.pageIndex,
                                 title: DocumentBookmarkStore.defaultTitle(pageText: text, page: reader.pageIndex))
            } label: {
                Image(systemName: currentMark == nil ? "bookmark" : "bookmark.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(currentMark == nil ? Theme.Colors.primary : .white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(currentMark == nil ? Color.primary.opacity(0.08) : Theme.Colors.primary))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(currentMark == nil ? "Seite merken" : "Lesezeichen entfernen")
            .accessibilityIdentifier("reader.bookmarkPage")
        }
        .padding(.horizontal, Theme.Spacing.m)
        .frame(minHeight: 54)
        .glassEffect(.regular, in: Capsule())
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.bottom, Theme.Spacing.m)
    }

    /// Red ticks under the slider where bookmarks are.
    private var ticks: some View {
        GeometryReader { proxy in
            let inset: CGFloat = 12
            let width = max(1, proxy.size.width - 2 * inset)
            ForEach(marks) { mark in
                Capsule()
                    .fill(Theme.Colors.accent)
                    .frame(width: 3, height: 14)
                    .position(x: inset + width * CGFloat(mark.page) / CGFloat(max(1, reader.pageCount - 1)),
                              y: proxy.size.height / 2)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct NightMode: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on { content.colorInvert().hueRotation(.degrees(180)) } else { content }
    }
}

// MARK: - Panel: pages, bookmarks, search

/// Page thumbnails, bookmarks and search results. A side panel in full
/// screen, a sheet on iPhone.
struct ReaderPanel: View {
    enum Mode: Hashable { case pages, bookmarks, search }

    let document: Document
    let pdf: PDFDocument
    @ObservedObject var reader: PDFReaderController
    @ObservedObject var search: PDFSearchModel
    let modes: [Mode]
    var initial: Mode? = nil
    /// Called after jumping somewhere (the iPhone sheet closes itself).
    var onSelect: (() -> Void)?

    @ObservedObject private var bookmarks = DocumentBookmarkStore.shared
    @State private var mode: Mode = .bookmarks
    @State private var renaming: DocumentBookmark?
    @State private var newName = ""
    @FocusState private var searchFocused: Bool

    init(document: Document, pdf: PDFDocument, reader: PDFReaderController, search: PDFSearchModel,
         modes: [Mode], initial: Mode? = nil, onSelect: (() -> Void)?) {
        self.document = document
        self.pdf = pdf
        self.reader = reader
        self.search = search
        self.modes = modes
        self.initial = initial
        self.onSelect = onSelect
        _mode = State(initialValue: initial ?? modes.first ?? .bookmarks)
    }

    private var marks: [DocumentBookmark] { bookmarks.bookmarks(for: document.filePath) }

    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            if modes.count > 1 && initial == nil {
                Picker("Ansicht", selection: $mode) {
                    ForEach(modes, id: \.self) { Text(label($0)).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Theme.Spacing.m)
            }
            switch mode {
            case .pages: pages
            case .bookmarks: bookmarkList
            case .search: searchList
            }
        }
        .padding(.top, Theme.Spacing.s)
        .alert("Lesezeichen umbenennen", isPresented: Binding(
            get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Abbrechen", role: .cancel) {}
            Button("Sichern") {
                if let renaming { bookmarks.rename(filePath: document.filePath, id: renaming.id, to: newName) }
            }
        }
    }

    private func label(_ mode: Mode) -> String {
        switch mode {
        case .pages: "Seiten"
        case .bookmarks: marks.isEmpty ? "Lesezeichen" : "Lesezeichen \(marks.count)"
        case .search: "Suche"
        }
    }

    private func jump(_ page: Int) {
        reader.go(to: page)
        onSelect?()
    }

    // Pages

    private var pages: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: Theme.Spacing.m)], spacing: Theme.Spacing.m) {
                ForEach(0..<pdf.pageCount, id: \.self) { index in
                    Button { jump(index) } label: {
                        VStack(spacing: 4) {
                            PageThumbnail(pdf: pdf, index: index)
                                .overlay(RoundedRectangle(cornerRadius: 4)
                                    .stroke(index == reader.pageIndex ? Theme.Colors.primary : Theme.Glass.border,
                                            lineWidth: index == reader.pageIndex ? 2 : 0.5))
                                .overlay(alignment: .topTrailing) {
                                    if bookmarks.bookmark(for: document.filePath, page: index) != nil {
                                        Image(systemName: "bookmark.fill")
                                            .font(.caption)
                                            .foregroundStyle(Theme.Colors.accent)
                                            .padding(4)
                                    }
                                }
                            Text("\(index + 1)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Seite \(index + 1)")
                }
            }
            .padding(Theme.Spacing.m)
        }
    }

    // Bookmarks

    private var bookmarkList: some View {
        List {
            Section {
                let current = reader.pageIndex
                let isMarked = bookmarks.bookmark(for: document.filePath, page: current) != nil
                Button {
                    bookmarks.toggle(filePath: document.filePath, page: current,
                                     title: DocumentBookmarkStore.defaultTitle(pageText: pdf.page(at: current)?.string,
                                                                              page: current))
                } label: {
                    Label(isMarked ? "Lesezeichen auf Seite \(current + 1) entfernen" : "Seite \(current + 1) merken",
                          systemImage: isMarked ? "bookmark.slash" : "bookmark")
                }
                .accessibilityIdentifier("reader.addBookmark")
            }
            Section {
                if marks.isEmpty {
                    Text("Noch keine Lesezeichen. Sie bleiben auf diesem Gerät, auch offline.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ForEach(marks) { mark in
                    Button { jump(mark.page) } label: {
                        HStack(spacing: Theme.Spacing.m - 4) {
                            PageThumbnail(pdf: pdf, index: mark.page)
                                .frame(width: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mark.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                                Text("Seite \(mark.page + 1)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button(role: .destructive) { bookmarks.remove(filePath: document.filePath, id: mark.id) } label: {
                            Label("Löschen", systemImage: "trash")
                        }
                        Button { newName = mark.title; renaming = mark } label: {
                            Label("Umbenennen", systemImage: "pencil")
                        }
                        .tint(Theme.Colors.primary)
                    }
                    .contextMenu {
                        Button("Umbenennen", systemImage: "pencil") { newName = mark.title; renaming = mark }
                        Button("Löschen", systemImage: "trash", role: .destructive) {
                            bookmarks.remove(filePath: document.filePath, id: mark.id)
                        }
                    }
                }
            } footer: {
                if !marks.isEmpty { Text("Lesezeichen bleiben auf diesem Gerät.") }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    // Search

    private var searchList: some View {
        VStack(spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Im Dokument suchen", text: $search.query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($searchFocused)
                if !search.matches.isEmpty {
                    Text("\(search.matches.count) Treffer").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, Theme.Spacing.m - 4)
            .frame(minHeight: 44)
            .background(Theme.Colors.backgroundElevated, in: RoundedRectangle(cornerRadius: Theme.Radius.chip))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.chip).stroke(Theme.Colors.primary, lineWidth: searchFocused ? 2 : 0))
            .padding(.horizontal, Theme.Spacing.m)

            List {
                ForEach(Array(search.results.enumerated()), id: \.offset) { index, result in
                    Button {
                        search.index = index
                        reader.go(to: result.page)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Seite \(result.page + 1)").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                            Text(result.context).font(.subheadline).lineLimit(3)
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(index == search.index ? Color.yellow.opacity(0.25) : Theme.Colors.backgroundElevated)
                }
                if search.query.count >= 2 && search.results.isEmpty {
                    Text("Keine Treffer").foregroundStyle(.secondary)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            Text("Sucht im gespeicherten Dokument, auch ohne Netz.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, Theme.Spacing.m)
        }
        .onAppear { searchFocused = search.query.isEmpty }
    }
}

private struct PageThumbnail: View {
    let pdf: PDFDocument
    let index: Int
    @State private var image: UIImage?

    var body: some View {
        Color.white
            .aspectRatio(0.71, contentMode: .fit)
            .overlay { if let image { Image(uiImage: image).resizable().scaledToFit() } }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .task(id: index) {
                image = pdf.page(at: index)?.thumbnail(of: CGSize(width: 240, height: 340), for: .cropBox)
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Small pieces

private struct ReaderTitle: View {
    let title: String
    let status: String
    let statusColor: Color

    var body: some View {
        VStack(spacing: 0) {
            Text(title).font(.subheadline.weight(.bold)).lineLimit(1)
            HStack(spacing: 4) {
                if statusColor == .green { Circle().fill(.green).frame(width: 6, height: 6) }
                Text(status).font(.caption2.weight(.medium)).foregroundStyle(statusColor).lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("reader.title")
    }
}

private struct ReaderBanner: View {
    let title: String
    let detail: String
    let progress: Bool
    let action: (() -> Void)?

    var body: some View {
        HStack(spacing: Theme.Spacing.m - 4) {
            Image(systemName: "arrow.down.circle")
                .font(.title3)
                .foregroundStyle(Theme.Colors.primary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.bold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if progress {
                ProgressView()
            } else if let action {
                Button("Speichern", action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.Colors.primary)
                    .accessibilityIdentifier("reader.saveOffline")
            }
        }
        .padding(Theme.Spacing.m - 4)
        .background(Theme.Colors.backgroundElevated, in: RoundedRectangle(cornerRadius: Theme.Radius.field))
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s)
    }
}

private struct ReaderMoreMenu: View {
    let document: Document
    let shareURL: URL?
    @Binding var keepScreenOn: Bool
    @ObservedObject private var offlineStore = DocumentOfflineStore.shared

    var body: some View {
        Menu {
            if let shareURL {
                ShareLink(item: shareURL, subject: Text(document.title)) {
                    Label("Teilen", systemImage: "square.and.arrow.up")
                }
            }
            switch offlineStore.status(of: document) {
            case .available:
                Button("Offline-Kopie entfernen", systemImage: "xmark.icloud", role: .destructive) {
                    offlineStore.removeOffline(document)
                }
            case .notAvailable:
                Button("Offline verfügbar machen", systemImage: "arrow.down.circle") {
                    offlineStore.makeAvailableOffline(document)
                }
            case .downloading:
                Label("Wird gespeichert …", systemImage: "arrow.down.circle.dotted")
            }
            Toggle(isOn: $keepScreenOn) {
                Label("Bildschirm bleibt an", systemImage: "sun.max")
            }
        } label: {
            Label("Mehr", systemImage: "ellipsis")
        }
        .accessibilityIdentifier("reader.more")
    }
}

private struct ReaderSearchBar: View {
    @ObservedObject var search: PDFSearchModel
    @ObservedObject var reader: PDFReaderController
    var focused: FocusState<Bool>.Binding
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .scaledFont(12, weight: .semibold)
                    .foregroundStyle(.tertiary)
                TextField("Im Dokument suchen …", text: $search.query)
                    .focused(focused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .submitLabel(.search)
                    .onSubmit { step(1) }
                    .scaledFont(15, weight: .medium)
                    .accessibilityIdentifier("reader.searchField")
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 40)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.08)))

            if !search.matches.isEmpty {
                Text("\(search.index + 1) von \(search.matches.count)")
                    .scaledFont(12, weight: .semibold)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .fixedSize()
            } else if search.query.count >= 2 {
                Text("0").scaledFont(12, weight: .semibold).foregroundStyle(.tertiary)
            }
            Button { step(-1) } label: { Image(systemName: "chevron.up").scaledFont(14, weight: .bold) }
                .disabled(search.matches.isEmpty)
                .frame(minWidth: 36, minHeight: 44)
                .accessibilityLabel("Vorheriger Treffer")
            Button { step(1) } label: { Image(systemName: "chevron.down").scaledFont(14, weight: .bold) }
                .disabled(search.matches.isEmpty)
                .frame(minWidth: 36, minHeight: 44)
                .accessibilityLabel("Nächster Treffer")
            Button("Schliessen", systemImage: "xmark", action: onClose)
                .labelStyle(.iconOnly)
                .frame(minWidth: 36, minHeight: 44)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .background(Theme.Colors.background)
    }

    private func step(_ delta: Int) {
        search.step(delta)
        if let page = search.currentPage { reader.go(to: page) }
        focused.wrappedValue = false
    }
}

// MARK: - Search model

/// In-document search over the stored copy. PDFKit's `findString` is
/// synchronous and fast enough for the manuals this app handles.
@MainActor
final class PDFSearchModel: ObservableObject {
    struct Result { let page: Int; let context: String }

    weak var pdf: PDFDocument?
    @Published var query = "" { didSet { schedule() } }
    @Published private(set) var matches: [PDFSelection] = []
    @Published private(set) var results: [Result] = []
    @Published var index = 0

    private var task: Task<Void, Never>?

    var current: PDFSelection? { matches.indices.contains(index) ? matches[index] : nil }

    var currentPage: Int? {
        guard let page = current?.pages.first, let pdf else { return nil }
        return pdf.index(for: page)
    }

    func step(_ delta: Int) {
        guard !matches.isEmpty else { return }
        index = (index + delta + matches.count) % matches.count
    }

    func clear() {
        query = ""
        matches = []
        results = []
        index = 0
    }

    private func schedule() {
        task?.cancel()
        task = Task {
            // Avoid rescanning a long manual for every keystroke.
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            run()
        }
    }

    private func run() {
        index = 0
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard let pdf, trimmed.count >= 2 else {
            matches = []
            results = []
            return
        }
        let found = pdf.findString(trimmed, withOptions: [.caseInsensitive, .diacriticInsensitive])
        found.forEach { $0.color = UIColor.systemYellow.withAlphaComponent(0.45) }
        matches = found
        results = found.map { selection in
            let line = selection.copy() as? PDFSelection ?? selection
            line.extendForLineBoundaries()
            let page = selection.pages.first.map { pdf.index(for: $0) } ?? 0
            let text = (line.string ?? selection.string ?? "")
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespaces)
            return Result(page: page, context: text)
        }
    }
}

// MARK: - PDFKit bridge

/// Owns the PDFView's navigation state: current page, page count and zoom
/// relative to "fit width". Zoom is never stored — every document opens
/// fitted to its width.
@MainActor
final class PDFReaderController: ObservableObject {
    @Published private(set) var pageIndex = 0
    @Published private(set) var pageCount = 0
    @Published private(set) var zoomPercent = 100
    /// A page to show as soon as the view exists (full screen hand-over).
    var pendingPage: Int?
    fileprivate weak var view: PDFView?

    fileprivate func attach(_ view: PDFView) {
        self.view = view
        pageCount = view.document?.pageCount ?? 0
        if let pendingPage { go(to: pendingPage); self.pendingPage = nil }
        refresh()
    }

    fileprivate func refresh() {
        guard let view else { return }
        (view as? FittingPDFView)?.minScaleFactor = max(0.1, view.scaleFactorForSizeToFit * 0.5)
        if let page = view.currentPage, let document = view.document {
            pageIndex = document.index(for: page)
        }
        pageCount = view.document?.pageCount ?? 0
        let fit = view.scaleFactorForSizeToFit
        zoomPercent = fit > 0 ? Int((view.scaleFactor / fit * 100).rounded()) : 100
    }

    func go(to index: Int) {
        guard let view, let page = view.document?.page(at: max(0, min(index, pageCount - 1))) else {
            pendingPage = index
            return
        }
        view.go(to: page)
        refresh()
    }

    func zoom(by factor: CGFloat) {
        guard let view else { return }
        (view as? FittingPDFView)?.isFitted = false
        view.autoScales = false
        view.scaleFactor = min(view.maxScaleFactor, max(view.minScaleFactor, view.scaleFactor * factor))
        refresh()
    }

    func fitWidth() {
        guard let view else { return }
        (view as? FittingPDFView)?.isFitted = true
        view.scaleFactor = view.scaleFactorForSizeToFit
        view.autoScales = true
        refresh()
    }
}

private struct PDFKitView: UIViewRepresentable {
    let document: PDFDocument
    let controller: PDFReaderController
    let highlights: [PDFSelection]
    let current: PDFSelection?
    var topInset: CGFloat = 0

    func makeUIView(context: Context) -> PDFView {
        let view = FittingPDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = UIColor(Theme.Colors.background)
        view.document = document
        view.maxScaleFactor = 8
        context.coordinator.observe(view)
        DispatchQueue.main.async { controller.attach(view) }
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document !== document { view.document = document }
        view.highlightedSelections = highlights.isEmpty ? nil : highlights
        if let current, context.coordinator.lastCurrent !== current {
            context.coordinator.lastCurrent = current
            view.setCurrentSelection(current, animate: false)
            view.go(to: current)
        } else if current == nil, context.coordinator.lastCurrent != nil {
            context.coordinator.lastCurrent = nil
            view.clearSelection()
        }
        if topInset > 0, let scroll = view.subviews.compactMap({ $0 as? UIScrollView }).first,
           scroll.contentInset.top != topInset {
            scroll.contentInset.top = topInset
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }

    @MainActor
    final class Coordinator: NSObject {
        let controller: PDFReaderController
        var lastCurrent: PDFSelection?
        init(controller: PDFReaderController) { self.controller = controller }

        func observe(_ view: PDFView) {
            for name in [Notification.Name.PDFViewPageChanged, .PDFViewScaleChanged] {
                NotificationCenter.default.addObserver(self, selector: #selector(changed(_:)), name: name, object: view)
            }
        }

        @objc private func changed(_ note: Notification) {
            // A pinch the user made ends "fit to width"; our own fitting in
            // layout doesn't.
            if note.name == .PDFViewScaleChanged, let view = note.object as? FittingPDFView, !view.isAdjusting {
                view.isFitted = abs(view.scaleFactor - view.scaleFactorForSizeToFit) < 0.01
            }
            controller.refresh()
        }
    }
}

/// Keeps the page fitted to the width until the user zooms: PDFKit computes
/// its fit before the view has its final size (the page opened at 137 % on
/// iPhone and 72 % on iPad), so the fit is re-applied on every layout while
/// the document is still "fitted". Zoom is never stored.
final class FittingPDFView: PDFView {
    var isFitted = true
    private(set) var isAdjusting = false

    override func layoutSubviews() {
        super.layoutSubviews()
        guard isFitted, bounds.width > 0 else { return }
        let fit = scaleFactorForSizeToFit
        if fit > 0, abs(scaleFactor - fit) > 0.001 {
            isAdjusting = true
            minScaleFactor = min(minScaleFactor, fit * 0.5)
            scaleFactor = fit
            isAdjusting = false
        }
    }
}

// MARK: - QuickLook bridge

private struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        context.coordinator.url = url
        controller.reloadData()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL
        init(url: URL) { self.url = url }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as QLPreviewItem
        }
    }
}
