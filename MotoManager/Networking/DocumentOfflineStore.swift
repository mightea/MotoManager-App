import Combine
import Foundation

extension Document {
    /// Absolute download URL for the document's file. Single source of truth
    /// for the cache key used by the thumbnailer, the viewer, and the
    /// offline store.
    var remoteFileURL: String {
        if filePath.hasPrefix("http") { return filePath }
        let base = NetworkManager.shared.baseURL
        let trimmedBase = base.hasSuffix("/") ? String(base.dropLast()) : base
        let prefixedPath = filePath.hasPrefix("/") ? filePath : "/\(filePath)"
        return trimmedBase + prefixedPath
    }
}

/// Tracks which documents the user pinned for offline use.
///
/// The pin registry (persisted in `UserDefaults`, keyed by the document's
/// server `filePath` so it survives base-URL changes) is separate from the
/// opportunistic `DocumentCache` that thumbnails and the viewer fill as a
/// side effect: a pin means "explicitly downloaded and kept", and unpinning
/// also deletes the cached file. Cleared on logout alongside the cache.
@MainActor
final class DocumentOfflineStore: ObservableObject {
    static let shared = DocumentOfflineStore()

    enum Status {
        case notAvailable
        case downloading
        case available
    }

    @Published private(set) var pinned: Set<String>
    @Published private(set) var downloading: Set<String> = []

    private let defaultsKey = "com.motomanager.offlineDocuments"

    private init() {
        pinned = Set(UserDefaults.standard.stringArray(forKey: defaultsKey) ?? [])
    }

    func status(of document: Document) -> Status {
        if downloading.contains(document.filePath) { return .downloading }
        // A pin only counts as available while the file is actually on disk —
        // logout clears the cache, and the registry alone is just intent.
        if pinned.contains(document.filePath),
           DocumentCache.shared.cachedFileURL(for: document.remoteFileURL) != nil {
            return .available
        }
        return .notAvailable
    }

    func makeAvailableOffline(_ document: Document) {
        let key = document.filePath
        guard !downloading.contains(key) else { return }
        let url = document.remoteFileURL
        if DocumentCache.shared.cachedFileURL(for: url) != nil {
            addPin(key)
            return
        }
        downloading.insert(key)
        Task {
            defer { downloading.remove(key) }
            guard let downloaded = try? await NetworkManager.shared.downloadBlob(url: url) else { return }
            defer { try? FileManager.default.removeItem(at: downloaded) }
            guard await DocumentCache.shared.save(downloadedFile: downloaded, for: url) != nil else { return }
            addPin(key)
        }
    }

    func removeOffline(_ document: Document) {
        pinned.remove(document.filePath)
        persist()
        DocumentCache.shared.remove(for: document.remoteFileURL)
    }

    func clearAll() {
        pinned = []
        downloading = []
        persist()
    }

    private func addPin(_ key: String) {
        pinned.insert(key)
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(Array(pinned).sorted(), forKey: defaultsKey)
    }
}
