import Foundation

/// The address of the user's self-hosted server: normalising what was typed,
/// and recovering it for a session that lost it.
nonisolated enum ServerAddress {
    /// Trimmed and without trailing slashes — or nil when the input isn't a
    /// usable http(s) URL. Requests append `/api/...` paths, so the stored
    /// base must not end in a slash.
    static func normalize(_ input: String) -> String? {
        var trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed = String(trimmed.dropLast()) }
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host() != nil
        else { return nil }
        return trimmed
    }

    /// Server-relative roots the backend serves uploaded files from. Cached
    /// records carry them as absolute URLs (`<base>/images/x.jpg`).
    private static let fileRoots = ["/images/", "/documents/"]

    /// The server base an absolute file URL was built from, or nil when the
    /// URL isn't one of the backend's file URLs.
    static func base(ofFileURL fileURL: String) -> String? {
        for root in fileRoots {
            guard let range = fileURL.range(of: root) else { continue }
            return normalize(String(fileURL[..<range.lowerBound]))
        }
        return nil
    }

    /// Recovers the server address from file URLs found in the local caches:
    /// the base most of them agree on. Builds up to 0.20 could run on an
    /// address baked into the build without ever storing it; when 0.21
    /// dropped the baked value, those sessions were left with a token but no
    /// server. The caches still know where the data came from.
    static func recover(fromFileURLs fileURLs: [String]) -> String? {
        var counts: [String: Int] = [:]
        for fileURL in fileURLs {
            if let base = base(ofFileURL: fileURL) { counts[base, default: 0] += 1 }
        }
        // Ties resolve alphabetically so the result is deterministic.
        return counts.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key
    }

    /// The same, straight from what the caches hold: the garage (bike photos)
    /// and the documents kept for offline use.
    static func recover(cachedMotorcycles: [Motorcycle], offlineDocuments: [OfflineDocumentEntry]) -> String? {
        recover(fromFileURLs: cachedMotorcycles.compactMap(\.image) + offlineDocuments.map(\.remoteURL))
    }
}
