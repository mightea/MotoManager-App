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
    }

    private func filename(for url: String) -> String {
        let digest = SHA256.hash(data: Data(url.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func data(for url: String) -> Data? {
        try? Data(contentsOf: directory.appendingPathComponent(filename(for: url)))
    }

    func save(_ data: Data, for url: String) {
        let path = directory.appendingPathComponent(filename(for: url))
        try? data.write(to: path, options: .atomic)
    }

    func clearAll() {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
