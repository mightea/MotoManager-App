import Foundation
import CryptoKit

/// On-disk binary cache for documents (PDFs, images) keyed by URL string.
///
/// Preserves the source URL's path extension on the cached file so that
/// `QLPreviewController` can determine the file type. Backed by
/// `Application Support/MotoDocCache/`.
final class DocumentCache {
    static let shared = DocumentCache()

    private let directory: URL

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        directory = support.appendingPathComponent("MotoDocCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func filename(for url: String) -> String {
        let digest = SHA256.hash(data: Data(url.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        let ext = URL(string: url)?.pathExtension ?? ""
        return ext.isEmpty ? hex : "\(hex).\(ext.lowercased())"
    }

    /// Returns the cached file URL if present, otherwise nil.
    func cachedFileURL(for url: String) -> URL? {
        let path = directory.appendingPathComponent(filename(for: url))
        return FileManager.default.fileExists(atPath: path.path) ? path : nil
    }

    /// Persists data to disk and returns the resulting file URL on success.
    @discardableResult
    func save(_ data: Data, for url: String) -> URL? {
        let path = directory.appendingPathComponent(filename(for: url))
        do {
            try data.write(to: path, options: .atomic)
            return path
        } catch {
            return nil
        }
    }

    func clearAll() {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
