import Combine
import Foundation

/// A "connect this app" link from the webapp's settings:
/// `motomanager://connect?server=https://api.example.com&user=marc`.
/// It only prefills the login screen — it never carries a password or token.
nonisolated struct ConnectLink: Equatable {
    /// API base URL, trimmed and without a trailing slash (like the login field).
    let server: String
    let username: String?

    static let scheme = "motomanager"

    static func parse(_ url: URL) -> ConnectLink? {
        guard url.scheme?.lowercased() == scheme,
              url.host()?.lowercased() == "connect",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        else { return nil }
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard var server = value("server") else { return nil }
        while server.hasSuffix("/") { server.removeLast() }
        guard let serverURL = URL(string: server),
              let s = serverURL.scheme?.lowercased(), s == "http" || s == "https",
              serverURL.host() != nil
        else { return nil }
        let user = value("user").flatMap { $0.isEmpty ? nil : $0 }
        return ConnectLink(server: server, username: user)
    }

    /// Host (and port) for messages, e.g. "moto-api.example.com".
    var displayHost: String {
        guard let url = URL(string: server), let host = url.host() else { return server }
        return url.port.map { "\(host):\($0)" } ?? host
    }
}

/// Holds a connect link until the login screen picks it up — also across a
/// cold launch, or a logout the user confirmed first.
final class ConnectLinkRouter: ObservableObject {
    static let shared = ConnectLinkRouter()
    @Published var pending: ConnectLink?
    private init() {}
}
