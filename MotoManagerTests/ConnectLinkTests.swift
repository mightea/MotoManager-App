import Foundation
import Testing
@testable import MotoManager

struct ConnectLinkTests {
    private func parse(_ s: String) -> ConnectLink? { ConnectLink.parse(URL(string: s)!) }

    @Test func parsesServerAndUser() {
        let link = parse("motomanager://connect?server=https%3A%2F%2Fapi.example.com%2F&user=marc")
        #expect(link == ConnectLink(server: "https://api.example.com", username: "marc"))
        #expect(link?.displayHost == "api.example.com")
    }

    @Test func userIsOptional() {
        #expect(parse("motomanager://connect?server=http://localhost:3010")?.username == nil)
        #expect(parse("motomanager://connect?server=http://localhost:3010")?.displayHost == "localhost:3010")
    }

    @Test func rejectsOtherLinks() {
        #expect(parse("motomanager://connect?server=ftp://x.example") == nil)
        #expect(parse("motomanager://connect?user=marc") == nil)
        #expect(parse("motomanager://other?server=https://api.example.com") == nil)
        #expect(parse("https://moto.herrmann.ltd/parts/1") == nil)
    }
}
