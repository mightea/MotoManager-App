import Foundation
import CryptoKit

/// On-disk binary cache for remote images keyed by URL string.
///
/// Filenames are SHA-256 hashes of the URL to keep them within filesystem limits
/// and to avoid path-traversal characters. Backed by `Application Support/MotoImageCache/`.
final class ImageCache {
    static let shared = ImageCache()

    private let directory: URL

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        directory = support.appendingPathComponent("MotoImageCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var directoryURL = directory
        try? directoryURL.setResourceValues(values)
    }

    private func filename(for url: String) -> String {
        let digest = SHA256.hash(data: Data(url.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func data(for url: String) async -> Data? {
        let path = directory.appendingPathComponent(filename(for: url))
        return await Task.detached(priority: .utility) {
            try? Data(contentsOf: path, options: .mappedIfSafe)
        }.value
    }

    func save(_ data: Data, for url: String) async {
        let path = directory.appendingPathComponent(filename(for: url))
        let directory = directory
        await Task.detached(priority: .utility) {
            try? data.write(to: path, options: .atomic)
            Self.prune(directory: directory, limit: 150 * 1_024 * 1_024)
        }.value
    }

    /// Keep opportunistic thumbnails out of unbounded Application Support.
    private nonisolated static func prune(directory: URL, limit: Int) {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]
        ) else { return }
        let entries = files.compactMap { url -> (URL, Int, Date)? in
            guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else { return nil }
            return (url, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }
        var total = entries.reduce(0) { $0 + $1.1 }
        guard total > limit else { return }
        for entry in entries.sorted(by: { $0.2 < $1.2 }) where total > limit {
            if (try? FileManager.default.removeItem(at: entry.0)) != nil { total -= entry.1 }
        }
    }

    func clearAll() {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
