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

/// One document kept on the device for offline use. Carries enough of the
/// document to list it in Einstellungen › Offline-Dokumente without the
/// bike's document list being loaded.
struct OfflineDocumentEntry: Codable, Equatable, Identifiable {
    let filePath: String
    var title: String
    var motorcycleIds: [Int]
    var remoteURL: String
    var savedAt: Date
    var lastOpenedAt: Date?

    var id: String { filePath }
}

/// When opening a document should keep it on the device.
enum OfflineSaveMode: String, CaseIterable, Identifiable {
    /// Every opened document stays on the device (default).
    case automatic
    /// Only documents the user saves explicitly.
    case onRequest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "Automatisch beim Öffnen"
        case .onRequest: "Nur auf Wunsch"
        }
    }

    var detail: String {
        switch self {
        case .automatic: "Jedes geöffnete Dokument bleibt auf dem Gerät – bereit für die Werkstatt."
        case .onRequest: "Speichern über „Offline verfügbar“ im Dokument oder in der Liste."
        }
    }
}

/// Tracks which documents are kept on the device for offline use.
///
/// The registry (persisted in `UserDefaults`, keyed by the document's
/// server `filePath` so it survives base-URL changes) is separate from the
/// opportunistic `DocumentCache` that thumbnails and the viewer fill as a
/// side effect: an entry means "kept for offline use", and removing it also
/// deletes the cached file. Cleared on logout alongside the cache.
@MainActor
final class DocumentOfflineStore: ObservableObject {
    static let shared = DocumentOfflineStore()

    enum Status {
        case notAvailable
        case downloading
        case available
    }

    @Published private(set) var entries: [String: OfflineDocumentEntry]
    @Published private(set) var downloading: Set<String> = []
    @Published var saveMode: OfflineSaveMode {
        didSet { defaults.set(saveMode.rawValue, forKey: Self.modeKey) }
    }

    var pinned: Set<String> { Set(entries.keys) }

    private let defaults: UserDefaults
    private static let entriesKey = "com.motomanager.offlineDocumentEntries"
    /// Pre-metadata registry: a plain list of file paths.
    private static let legacyKey = "com.motomanager.offlineDocuments"
    private static let modeKey = "com.motomanager.documents.saveMode"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        saveMode = OfflineSaveMode(rawValue: defaults.string(forKey: Self.modeKey) ?? "") ?? .automatic
        if let data = defaults.data(forKey: Self.entriesKey),
           let decoded = try? JSONDecoder().decode([String: OfflineDocumentEntry].self, from: data) {
            entries = decoded
        } else {
            // Migrate the old path-only pins; titles come back the next time
            // the document is opened.
            let legacy = defaults.stringArray(forKey: Self.legacyKey) ?? []
            entries = Dictionary(uniqueKeysWithValues: legacy.map { path in
                (path, OfflineDocumentEntry(
                    filePath: path,
                    title: ((path as NSString).lastPathComponent as NSString).deletingPathExtension,
                    motorcycleIds: [], remoteURL: "", savedAt: Date(), lastOpenedAt: nil))
            })
        }
    }

    func status(of document: Document) -> Status {
        if downloading.contains(document.filePath) { return .downloading }
        // An entry only counts as available while the file is actually on
        // disk — logout clears the cache, and the registry alone is intent.
        if entries[document.filePath] != nil,
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
            keep(document)
            return
        }
        downloading.insert(key)
        Task {
            defer { downloading.remove(key) }
            guard let downloaded = try? await NetworkManager.shared.downloadBlob(url: url) else { return }
            defer { try? FileManager.default.removeItem(at: downloaded) }
            guard await DocumentCache.shared.save(downloadedFile: downloaded, for: url) != nil else { return }
            keep(document)
        }
    }

    /// The reader opened `document` (its file is in the cache by now): keep
    /// it when saving is automatic, and refresh its "last opened" date.
    func noteOpened(_ document: Document, now: Date = Date()) {
        if entries[document.filePath] == nil {
            guard saveMode == .automatic else { return }
            keep(document, now: now)
        }
        entries[document.filePath]?.lastOpenedAt = now
        persist()
    }

    func removeOffline(_ document: Document) {
        remove(filePath: document.filePath)
    }

    func remove(filePath: String) {
        guard let entry = entries.removeValue(forKey: filePath) else { return }
        persist()
        if !entry.remoteURL.isEmpty { DocumentCache.shared.remove(for: entry.remoteURL) }
    }

    /// Removes every offline copy (the documents stay on the server).
    func removeAll() {
        for entry in entries.values where !entry.remoteURL.isEmpty {
            DocumentCache.shared.remove(for: entry.remoteURL)
        }
        entries = [:]
        persist()
    }

    /// Logout: forget the registry (the cache itself is wiped separately).
    func clearAll() {
        entries = [:]
        downloading = []
        persist()
    }

    /// Bytes on disk for an entry; 0 when its file is gone.
    func size(of entry: OfflineDocumentEntry) -> Int64 {
        guard !entry.remoteURL.isEmpty,
              let url = DocumentCache.shared.cachedFileURL(for: entry.remoteURL),
              let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return 0 }
        return Int64(size)
    }

    private func keep(_ document: Document, now: Date = Date()) {
        let existing = entries[document.filePath]
        entries[document.filePath] = OfflineDocumentEntry(
            filePath: document.filePath, title: document.title,
            motorcycleIds: document.motorcycleIds ?? [], remoteURL: document.remoteFileURL,
            savedAt: existing?.savedAt ?? now, lastOpenedAt: existing?.lastOpenedAt)
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: Self.entriesKey)
        }
        defaults.removeObject(forKey: Self.legacyKey)
    }
}

/// Storage use of the offline copies, split by motorcycle for the bar in
/// Einstellungen › Offline-Dokumente. Pure, so it can be tested.
enum OfflineStorageSummary {
    struct Slice: Equatable {
        /// nil = shared by several (or no) motorcycles.
        let motorcycleId: Int?
        let bytes: Int64
    }

    /// Slices largest first; documents linked to more than one bike (or none)
    /// form one shared slice.
    static func slices(_ items: [(entry: OfflineDocumentEntry, bytes: Int64)]) -> [Slice] {
        var totals: [Int?: Int64] = [:]
        for item in items {
            let key: Int? = item.entry.motorcycleIds.count == 1 ? item.entry.motorcycleIds[0] : nil
            totals[key, default: 0] += item.bytes
        }
        return totals.map { Slice(motorcycleId: $0.key, bytes: $0.value) }
            .filter { $0.bytes > 0 }
            .sorted { $0.bytes > $1.bytes }
    }
}
