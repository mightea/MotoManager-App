import Foundation
import Testing
@testable import MotoManager

struct ServerAddressTests {

    // MARK: - Normalising typed input

    @Test func normalizeTrimsWhitespaceAndTrailingSlashes() {
        #expect(ServerAddress.normalize("  https://api.example.com// \n") == "https://api.example.com")
        #expect(ServerAddress.normalize("http://localhost:3010") == "http://localhost:3010")
    }

    @Test(arguments: ["", "api.example.com", "ftp://api.example.com", "https://", "just text"])
    func normalizeRejectsUnusableInput(input: String) {
        #expect(ServerAddress.normalize(input) == nil)
    }

    // MARK: - Recovering a lost address (issue #24)

    @Test func baseIsEverythingBeforeTheFileRoot() {
        #expect(ServerAddress.base(ofFileURL: "https://api.example.com/images/bike.jpg")
            == "https://api.example.com")
        #expect(ServerAddress.base(ofFileURL: "http://10.0.0.5:3001/documents/manual.pdf")
            == "http://10.0.0.5:3001")
        // A server mounted under a path prefix keeps the prefix.
        #expect(ServerAddress.base(ofFileURL: "https://example.com/moto/images/bike.jpg")
            == "https://example.com/moto")
    }

    @Test(arguments: [
        "/images/bike.jpg",                      // still server-relative: no base in it
        "https://cdn.example.net/photos/1.jpg",  // not one of the backend's file URLs
        "",
    ])
    func baseIgnoresURLsWithoutAServerBase(fileURL: String) {
        #expect(ServerAddress.base(ofFileURL: fileURL) == nil)
    }

    @Test func recoversTheAddressFromCachedFileURLs() {
        let cached = [
            "https://api.example.com/images/a.jpg",
            "https://api.example.com/documents/b.pdf",
        ]
        #expect(ServerAddress.recover(fromFileURLs: cached) == "https://api.example.com")
    }

    @Test func recoveryPrefersTheBaseMostURLsAgreeOn() {
        let cached = [
            "https://old.example.com/images/a.jpg",
            "https://api.example.com/images/b.jpg",
            "https://api.example.com/images/c.jpg",
            "/images/relative.jpg",
        ]
        #expect(ServerAddress.recover(fromFileURLs: cached) == "https://api.example.com")
    }

    @Test func recoveryFindsNothingWithoutAbsoluteFileURLs() {
        #expect(ServerAddress.recover(fromFileURLs: []) == nil)
        #expect(ServerAddress.recover(fromFileURLs: ["/images/a.jpg", ""]) == nil)
    }

    /// The garage cache as a 0.20 build wrote it: bike photos are stored with
    /// the server base already prepended.
    @Test func recoversTheAddressFromTheGarageCacheOfAnOlderBuild() throws {
        let cache = """
        [{"id":1,"make":"BMW","model":"R 80 G/S","userId":1,"isVeteran":true,"initialOdo":0,
          "image":"https://api.example.com/images/r80gs.jpg"},
         {"id":2,"make":"BMW","model":"R 1250 GS","userId":1,"isVeteran":false,"initialOdo":0}]
        """
        let motorcycles = try JSONDecoder().decode([Motorcycle].self, from: Data(cache.utf8))
        #expect(ServerAddress.recover(cachedMotorcycles: motorcycles, offlineDocuments: [])
            == "https://api.example.com")
    }

    @Test func recoversTheAddressFromOfflineDocumentsWhenNoBikeHasAPhoto() throws {
        let cache = """
        [{"id":2,"make":"BMW","model":"R 1250 GS","userId":1,"isVeteran":false,"initialOdo":0}]
        """
        let motorcycles = try JSONDecoder().decode([Motorcycle].self, from: Data(cache.utf8))
        let document = OfflineDocumentEntry(
            filePath: "/documents/manual.pdf", title: "Handbuch", motorcycleIds: [2],
            remoteURL: "https://api.example.com/documents/manual.pdf", savedAt: Date(), lastOpenedAt: nil)
        #expect(ServerAddress.recover(cachedMotorcycles: motorcycles, offlineDocuments: [document])
            == "https://api.example.com")
        // Nothing to go on: the app has to ask.
        #expect(ServerAddress.recover(cachedMotorcycles: motorcycles, offlineDocuments: []) == nil)
    }

    @Test func rejectedSessionReadsAsWrongServerNotWrongPassword() {
        let text = ServerAddressRequiredView.message(for: APIError.unauthorized)
        #expect(text.contains("Server"))
        #expect(!text.contains("Passwort"))
    }
}
