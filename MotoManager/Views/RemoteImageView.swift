import SwiftUI

struct RemoteImageView: View {
    let url: String
    /// When set, a server-resized variant is requested via `?width=` (for the
    /// `/images/` route) and the caches are keyed by size — so list cells fetch
    /// small thumbnails instead of full-resolution originals.
    var maxPixelWidth: Int?

    @State private var image: UIImage?
    @State private var loadFailed = false

    init(url: String, maxPixelWidth: Int? = nil) {
        self.url = url
        self.maxPixelWidth = maxPixelWidth
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
            } else if loadFailed {
                fallbackImage
            } else {
                ZStack {
                    Color.secondary.opacity(0.1)
                    ProgressView()
                }
            }
        }
        .task(id: effectiveURL) {
            await load()
        }
    }

    /// The URL actually fetched — with a `?width=` hint when a size is requested
    /// and the path supports server-side resizing (`/images/`).
    private var effectiveURL: String {
        guard let w = maxPixelWidth, url.contains("/images/"), !url.contains("?") else {
            return url
        }
        return "\(url)?width=\(w)"
    }

    private func load() async {
        loadFailed = false
        let key = effectiveURL

        // 1. In-memory cache — instant, no disk read or decode.
        if let cached = RemoteImageMemoryCache.shared.image(forKey: key) {
            self.image = cached
            return
        }

        // 2. Disk cache — keeps images visible offline.
        if let data = ImageCache.shared.data(for: key),
           let decoded = await Self.decode(data) {
            RemoteImageMemoryCache.shared.set(decoded, forKey: key)
            self.image = decoded
            return
        }

        // 3. Network.
        guard let requestURL = URL(string: key) else {
            loadFailed = true
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: requestURL)
            guard let decoded = await Self.decode(data) else {
                loadFailed = true
                return
            }
            ImageCache.shared.save(data, for: key)
            RemoteImageMemoryCache.shared.set(decoded, forKey: key)
            self.image = decoded
        } catch {
            loadFailed = true
        }
    }

    /// Decode off the main actor so a large image can't block scrolling.
    private static func decode(_ data: Data) async -> UIImage? {
        await Task.detached(priority: .userInitiated) { UIImage(data: data) }.value
    }

    private var fallbackImage: some View {
        ZStack {
            Color.secondary.opacity(0.1)
            Image(systemName: "bicycle")
                .font(.largeTitle)
                .foregroundColor(.secondary.opacity(0.3))
        }
    }
}

/// Process-wide in-memory image cache. Avoids re-reading disk and re-decoding an
/// image on every re-appearance (e.g. while scrolling a list).
final class RemoteImageMemoryCache {
    static let shared = RemoteImageMemoryCache()
    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 150
    }

    func image(forKey key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func set(_ image: UIImage, forKey key: String) {
        cache.setObject(image, forKey: key as NSString)
    }
}
