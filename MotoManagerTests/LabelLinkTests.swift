import Testing
import Foundation
@testable import MotoManager

// MARK: - Label URL building ↔ parsing

struct LabelLinkTests {

    // Builder and parser live side by side in LabelWebLinks — these
    // round-trips are the drift guard between printing and scanning.

    @Test func partURLRoundTrips() {
        #expect(LabelWebLinks.parse(LabelWebLinks.partURL(serverId: 42)) == .part(serverId: 42))
    }

    @Test func storageLocationURLRoundTrips() {
        #expect(LabelWebLinks.parse(LabelWebLinks.storageLocationURL(serverId: 7))
            == .storageLocation(serverId: 7))
    }

    @Test func defaultOriginURLsParse() {
        #expect(LabelWebLinks.parse("https://moto.example.com/parts/123") == .part(serverId: 123))
        #expect(LabelWebLinks.parse("https://moto.example.com/storage-locations/9")
            == .storageLocation(serverId: 9))
    }

    @Test func overriddenOriginRoundTrips() {
        UserDefaults.standard.set("https://other.example/", forKey: LabelWebLinks.originKey)
        defer { UserDefaults.standard.removeObject(forKey: LabelWebLinks.originKey) }
        #expect(LabelWebLinks.origin == "https://other.example")
        #expect(LabelWebLinks.parse(LabelWebLinks.partURL(serverId: 5)) == .part(serverId: 5))
    }

    /// The parser deliberately ignores the host: labels printed under an old
    /// or dev origin must keep scanning after the setting changes.
    @Test func foreignOriginStillParses() {
        #expect(LabelWebLinks.parse("https://old.example.com/parts/7") == .part(serverId: 7))
        #expect(LabelWebLinks.parse("http://localhost:3000/storage-locations/2")
            == .storageLocation(serverId: 2))
    }

    @Test func surroundingWhitespaceIsTolerated() {
        #expect(LabelWebLinks.parse("  https://moto.example.com/parts/1\n") == .part(serverId: 1))
    }

    @Test(arguments: [
        "https://moto.example.com/parts/abc",     // non-numeric id
        "https://moto.example.com/parts",         // missing id
        "https://moto.example.com/parts/1/edit",  // extra path component
        "https://moto.example.com/bikes/3",       // unknown resource
        "https://moto.example.com/parts/0",       // non-positive id
        "https://moto.example.com/parts/-4",      // negative id
        "mailto:x@y.z",                            // non-http scheme
        "just some text",                          // arbitrary QR payload
        "",
    ])
    func rejectsNonLabelPayloads(payload: String) {
        #expect(LabelWebLinks.parse(payload) == nil)
    }
}
