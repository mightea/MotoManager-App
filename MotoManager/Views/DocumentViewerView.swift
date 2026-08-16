import SwiftUI
import PDFKit
import QuickLook

/// Pushed document reader: downloads a document on demand, caches it to disk,
/// then renders PDFs via PDFKit (with in-document search) and everything else
/// via QuickLook. Sharing exports the cached file.
///
/// Designed for push presentation inside a `NavigationStack` (native back
/// button + swipe-back), mirroring `DetailPage`'s navigation conventions.
struct DocumentViewerView: View {
    let document: Document

    @State private var fileURL: URL?
    @State private var shareURL: URL?
    @State private var pdfDocument: PDFDocument?
    @State private var loadFailed = false
    @State private var loadWasOffline = false

    @State private var showingSearch = false
    @State private var searchText = ""
    @State private var matches: [PDFSelection] = []
    @State private var matchIndex = 0
    @FocusState private var searchFocused: Bool

    var body: some View {
        Group {
            if let fileURL {
                VStack(spacing: 0) {
                    if pdfDocument != nil && showingSearch {
                        searchBar
                    }
                    if let pdfDocument {
                        PDFKitView(
                            document: pdfDocument,
                            highlights: matches,
                            current: matches.indices.contains(matchIndex) ? matches[matchIndex] : nil
                        )
                        .ignoresSafeArea(edges: .bottom)
                    } else {
                        QuickLookPreview(url: fileURL)
                            .ignoresSafeArea(edges: .bottom)
                    }
                }
            } else if loadFailed {
                failureState
            } else {
                loadingState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.navy950.ignoresSafeArea())
        .toolbar(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if pdfDocument != nil {
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) { showingSearch.toggle() }
                        if showingSearch {
                            searchFocused = true
                        } else {
                            clearSearch()
                        }
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel("Im Dokument suchen")
                }
                if let shareURL {
                    ShareLink(item: shareURL, subject: Text(document.title))
                        .accessibilityLabel("Dokument teilen")
                }
            }
        }
        .task {
            await load()
        }
        .onChange(of: searchText) { _, query in
            performSearch(query)
        }
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .scaledFont(12, weight: .semibold)
                    .foregroundColor(.white.opacity(0.5))
                TextField("Im Dokument suchen …", text: $searchText)
                    .focused($searchFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .submitLabel(.search)
                    .scaledFont(14, weight: .medium)
                    .foregroundColor(.white)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .scaledFont(13)
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .accessibilityLabel("Suche löschen")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.10))
            )

            if !matches.isEmpty {
                Text("\(matchIndex + 1)/\(matches.count)")
                    .scaledFont(12, weight: .semibold)
                    .monospacedDigit()
                    .foregroundColor(.white.opacity(0.6))
            } else if searchText.count >= 2 {
                Text("0")
                    .scaledFont(12, weight: .semibold)
                    .foregroundColor(.white.opacity(0.4))
            }

            Button { step(-1) } label: {
                Image(systemName: "chevron.up")
                    .scaledFont(13, weight: .bold)
            }
            .disabled(matches.isEmpty)
            .accessibilityLabel("Vorheriger Treffer")

            Button { step(1) } label: {
                Image(systemName: "chevron.down")
                    .scaledFont(13, weight: .bold)
            }
            .disabled(matches.isEmpty)
            .accessibilityLabel("Nächster Treffer")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.Colors.navy950)
    }

    /// PDFKit's `findString` is synchronous and fast enough for the manuals
    /// this app handles; matches get the standard yellow marker and the
    /// current one additionally becomes the view's selection.
    private func performSearch(_ query: String) {
        matchIndex = 0
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard let pdfDocument, trimmed.count >= 2 else {
            matches = []
            return
        }
        let found = pdfDocument.findString(trimmed, withOptions: [.caseInsensitive, .diacriticInsensitive])
        found.forEach { $0.color = UIColor.systemYellow.withAlphaComponent(0.45) }
        matches = found
    }

    private func step(_ delta: Int) {
        guard !matches.isEmpty else { return }
        matchIndex = (matchIndex + delta + matches.count) % matches.count
        searchFocused = false
    }

    private func clearSearch() {
        searchText = ""
        matches = []
        matchIndex = 0
        searchFocused = false
    }

    // MARK: - Loading

    private var loadingState: some View {
        VStack(spacing: Theme.Spacing.m) {
            ProgressView()
            Text("Dokument wird geladen …")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var failureState: some View {
        VStack(spacing: Theme.Spacing.m) {
            Image(systemName: loadWasOffline ? "wifi.slash" : "exclamationmark.triangle.fill")
                .scaledFont(48)
                .foregroundColor(.orange)
            Text(loadWasOffline ? "Offline" : "Dokument konnte nicht geladen werden")
                .font(.headline)
            Text("Bitte Verbindung prüfen und erneut versuchen.")
                .font(.subheadline)
                .foregroundColor(.secondary)
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
            let data = try await NetworkManager.shared.fetchBlob(url: urlString)
            if let saved = DocumentCache.shared.save(data, for: urlString) {
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
        }
        fileURL = url
        shareURL = titledShareURL(for: url)
    }

    /// The cache stores files under a URL hash; sharing that leaks an ugly
    /// filename into AirDrop/Files. Hand ShareLink a temp copy named after
    /// the document instead.
    private func titledShareURL(for url: URL) -> URL {
        let safeTitle = document.title
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

// MARK: - PDFKit bridge

private struct PDFKitView: UIViewRepresentable {
    let document: PDFDocument
    let highlights: [PDFSelection]
    let current: PDFSelection?

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.backgroundColor = UIColor(Theme.Colors.navy950)
        view.document = document
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document !== document {
            view.document = document
        }
        view.highlightedSelections = highlights.isEmpty ? nil : highlights
        if let current {
            view.setCurrentSelection(current, animate: false)
            view.go(to: current)
        } else {
            view.clearSelection()
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
