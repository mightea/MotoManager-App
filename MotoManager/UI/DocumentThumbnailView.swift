import SwiftUI
import QuickLookThumbnailing

/// Renders a real preview (first PDF page / image) for a document, falling back
/// to a type glyph while loading or when the type can't be thumbnailed. Reuses
/// the on-disk `DocumentCache`, so a thumbnail and a later full-screen open share
/// the same download.
struct DocumentThumbnailView: View {
    let document: Document

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle().fill(Theme.Colors.accent.opacity(0.16))
                Image(systemName: DocumentThumbnailer.iconName(for: document))
                    .scaledFont(20, weight: .semibold)
                    .foregroundColor(Theme.Colors.accent.opacity(0.9))
            }
        }
        .task(id: document.id) {
            image = await DocumentThumbnailer.shared.thumbnail(for: document, scale: displayScale)
        }
    }
}

/// On-device document thumbnailing via QuickLook. No dependencies, no server
/// preview needed (`Document.previewPath` is currently always nil).
final class DocumentThumbnailer {
    static let shared = DocumentThumbnailer()

    private let cache = NSCache<NSString, UIImage>()

    enum Kind { case pdf, image, other }

    static func kind(for document: Document) -> Kind {
        switch (document.filePath as NSString).pathExtension.lowercased() {
        case "pdf": return .pdf
        case "jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "tiff", "bmp": return .image
        default: return .other
        }
    }

    static func iconName(for document: Document) -> String {
        switch kind(for: document) {
        case .pdf: return "doc.richtext"
        case .image: return "photo"
        case .other: return "doc"
        }
    }

    /// Generate (or reuse a cached) thumbnail. Returns nil for types QuickLook
    /// shouldn't render here (so the caller shows the type glyph instead).
    func thumbnail(for document: Document,
                   size: CGSize = CGSize(width: 320, height: 440),
                   scale: CGFloat) async -> UIImage? {
        guard Self.kind(for: document) != .other else { return nil }

        let url = Self.resolvedURL(for: document)
        let key = url as NSString
        if let cached = cache.object(forKey: key) { return cached }

        guard let fileURL = await Self.fileURL(for: url) else { return nil }

        let request = QLThumbnailGenerator.Request(
            fileAt: fileURL, size: size, scale: scale, representationTypes: .thumbnail)
        guard let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
        else { return nil }

        cache.setObject(representation.uiImage, forKey: key)
        return representation.uiImage
    }

    /// On-disk file for `url`, downloading + caching it if we don't have it yet.
    private static func fileURL(for url: String) async -> URL? {
        if let cached = DocumentCache.shared.cachedFileURL(for: url) { return cached }
        guard let data = try? await NetworkManager.shared.fetchBlob(url: url) else { return nil }
        return DocumentCache.shared.save(data, for: url)
    }

    /// Mirror of `DocumentViewerView.resolvedURL` so the thumbnail and the viewer
    /// resolve to the same cache key.
    private static func resolvedURL(for document: Document) -> String {
        let path = document.filePath
        if path.hasPrefix("http") { return path }
        let base = NetworkManager.shared.baseURL
        let trimmedBase = base.hasSuffix("/") ? String(base.dropLast()) : base
        let prefixedPath = path.hasPrefix("/") ? path : "/\(path)"
        return trimmedBase + prefixedPath
    }
}
