import SwiftUI
import QuickLook

/// SwiftUI viewer that downloads a document on demand, caches it to disk,
/// then renders it via QuickLook. Handles PDFs, images, and any other type
/// supported by `QLPreviewController`.
struct DocumentViewerView: View {
    let document: Document

    @Environment(\.dismiss) private var dismiss
    @State private var fileURL: URL?
    @State private var loadFailed = false
    @State private var loadWasOffline = false

    var body: some View {
        NavigationStack {
            Group {
                if let fileURL {
                    QuickLookPreview(url: fileURL)
                        .ignoresSafeArea()
                } else if loadFailed {
                    failureState
                } else {
                    loadingState
                }
            }
            .navigationTitle(document.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fertig") { dismiss() }
                        .fontWeight(.bold)
                }
            }
        }
        .task {
            await load()
        }
    }

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
        let urlString = resolvedURL(for: document)

        if let cached = DocumentCache.shared.cachedFileURL(for: urlString) {
            self.fileURL = cached
            return
        }

        do {
            let data = try await NetworkManager.shared.fetchBlob(url: urlString)
            if let saved = DocumentCache.shared.save(data, for: urlString) {
                self.fileURL = saved
            } else {
                loadFailed = true
            }
        } catch {
            if case APIError.offline = error { loadWasOffline = true }
            loadFailed = true
        }
    }

    private func resolvedURL(for document: Document) -> String {
        let path = document.filePath
        if path.hasPrefix("http") { return path }
        let base = NetworkManager.shared.baseURL
        let trimmedBase = base.hasSuffix("/") ? String(base.dropLast()) : base
        let prefixedPath = path.hasPrefix("/") ? path : "/\(path)"
        return trimmedBase + prefixedPath
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
