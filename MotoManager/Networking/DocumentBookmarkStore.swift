import Combine
import Foundation

/// A named page in a document.
struct DocumentBookmark: Codable, Equatable, Identifiable {
    var id = UUID()
    /// Zero-based page index.
    let page: Int
    var title: String
    var createdAt = Date()
}

/// Bookmarks per document, kept on this device only (not synced). Keyed by
/// the document's server `filePath`, like the offline registry, so they
/// survive removing the offline copy.
@MainActor
final class DocumentBookmarkStore: ObservableObject {
    static let shared = DocumentBookmarkStore()

    @Published private(set) var bookmarks: [String: [DocumentBookmark]]
    private let defaults: UserDefaults
    private static let key = "com.motomanager.documentBookmarks"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([String: [DocumentBookmark]].self, from: data) {
            bookmarks = decoded
        } else {
            bookmarks = [:]
        }
    }

    /// Sorted by page.
    func bookmarks(for filePath: String) -> [DocumentBookmark] {
        (bookmarks[filePath] ?? []).sorted { ($0.page, $0.createdAt) < ($1.page, $1.createdAt) }
    }

    func bookmark(for filePath: String, page: Int) -> DocumentBookmark? {
        bookmarks[filePath]?.first { $0.page == page }
    }

    /// Adds a bookmark for `page`, or removes the existing one.
    func toggle(filePath: String, page: Int, title: String) {
        if let existing = bookmark(for: filePath, page: page) {
            remove(filePath: filePath, id: existing.id)
        } else {
            bookmarks[filePath, default: []].append(DocumentBookmark(page: page, title: title))
            persist()
        }
    }

    func rename(filePath: String, id: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = bookmarks[filePath]?.firstIndex(where: { $0.id == id }) else { return }
        bookmarks[filePath]?[index].title = trimmed
        persist()
    }

    func remove(filePath: String, id: UUID) {
        bookmarks[filePath]?.removeAll { $0.id == id }
        if bookmarks[filePath]?.isEmpty == true { bookmarks[filePath] = nil }
        persist()
    }

    /// Logout: bookmarks belong to the account's documents.
    func clearAll() {
        bookmarks = [:]
        persist()
    }

    /// A short bookmark name from the page's first line of text, falling
    /// back to "Seite N".
    nonisolated static func defaultTitle(pageText: String?, page: Int) -> String {
        let line = (pageText ?? "")
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.count >= 3 }
        guard let line else { return "Seite \(page + 1)" }
        return line.count > 40 ? String(line.prefix(39)) + "…" : line
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(bookmarks) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
