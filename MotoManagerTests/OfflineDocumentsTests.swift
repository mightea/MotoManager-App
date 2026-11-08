import Foundation
import Testing
@testable import MotoManager

@MainActor
struct OfflineDocumentsTests {
    private func defaults() -> UserDefaults {
        let name = "offline-tests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    private func document(_ path: String, bikes: [Int]? = [1]) -> Document {
        Document(id: 1, title: "Serviceplan", filePath: path, previewPath: nil, uploadedBy: nil, ownerId: nil,
                 isPrivate: false, createdAt: "2026-11-08", updatedAt: "2026-11-08", motorcycleIds: bikes)
    }

    private func entry(_ path: String, bikes: [Int]) -> OfflineDocumentEntry {
        OfflineDocumentEntry(filePath: path, title: path, motorcycleIds: bikes, remoteURL: "", savedAt: Date(),
                             lastOpenedAt: nil)
    }

    @Test func automaticModeKeepsOpenedDocuments() {
        let store = DocumentOfflineStore(defaults: defaults())
        #expect(store.saveMode == .automatic)
        store.noteOpened(document("/docs/a.pdf"))
        #expect(store.entries["/docs/a.pdf"]?.title == "Serviceplan")
        #expect(store.entries["/docs/a.pdf"]?.lastOpenedAt != nil)
    }

    @Test func onRequestModeOnlyTracksKeptDocuments() {
        let d = defaults()
        let store = DocumentOfflineStore(defaults: d)
        store.saveMode = .onRequest
        store.noteOpened(document("/docs/a.pdf"))
        #expect(store.entries.isEmpty)
        // The mode survives a relaunch.
        #expect(DocumentOfflineStore(defaults: d).saveMode == .onRequest)
    }

    @Test func entriesPersistAndRemoveAllClears() {
        let d = defaults()
        let store = DocumentOfflineStore(defaults: d)
        store.noteOpened(document("/docs/a.pdf"))
        store.noteOpened(document("/docs/b.pdf"))
        #expect(DocumentOfflineStore(defaults: d).entries.count == 2)
        store.remove(filePath: "/docs/a.pdf")
        #expect(DocumentOfflineStore(defaults: d).entries.keys.sorted() == ["/docs/b.pdf"])
        store.removeAll()
        #expect(DocumentOfflineStore(defaults: d).entries.isEmpty)
    }

    @Test func legacyPinsMigrate() {
        let d = defaults()
        d.set(["/uploads/Serviceplan.pdf"], forKey: "com.motomanager.offlineDocuments")
        let store = DocumentOfflineStore(defaults: d)
        #expect(store.entries["/uploads/Serviceplan.pdf"]?.title == "Serviceplan")
    }

    @Test func storageSplitsByBikeWithSharedSlice() {
        let slices = OfflineStorageSummary.slices([
            (entry("a", bikes: [1]), 300), (entry("b", bikes: [1]), 200),
            (entry("c", bikes: [2]), 100), (entry("d", bikes: [1, 2]), 700), (entry("e", bikes: [3]), 0)
        ])
        #expect(slices == [
            .init(motorcycleId: nil, bytes: 700), .init(motorcycleId: 1, bytes: 500), .init(motorcycleId: 2, bytes: 100)
        ])
    }

    @Test func bookmarksToggleRenameAndPersist() {
        let d = defaults()
        let store = DocumentBookmarkStore(defaults: d)
        store.toggle(filePath: "/a.pdf", page: 3, title: "Einstellwerte")
        store.toggle(filePath: "/a.pdf", page: 0, title: "Intervalle")
        #expect(store.bookmarks(for: "/a.pdf").map(\.page) == [0, 3])
        let id = store.bookmark(for: "/a.pdf", page: 3)!.id
        store.rename(filePath: "/a.pdf", id: id, to: "  Ventilspiel ")
        #expect(DocumentBookmarkStore(defaults: d).bookmark(for: "/a.pdf", page: 3)?.title == "Ventilspiel")
        store.toggle(filePath: "/a.pdf", page: 3, title: "ignored")
        #expect(store.bookmarks(for: "/a.pdf").map(\.page) == [0])
    }

    @Test func bookmarkTitleFromPageText() {
        #expect(DocumentBookmarkStore.defaultTitle(pageText: "\n  Einstellwerte\nVentilspiel kalt", page: 0) == "Einstellwerte")
        #expect(DocumentBookmarkStore.defaultTitle(pageText: nil, page: 4) == "Seite 5")
        let long = String(repeating: "x", count: 60)
        #expect(DocumentBookmarkStore.defaultTitle(pageText: long, page: 0).count == 40)
    }
}
