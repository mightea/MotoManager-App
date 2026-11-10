import Foundation

/// Authentication configuration constants.
nonisolated enum AuthConfig {
    /// Host of the deployed webapp, injected at build time: the
    /// `MOTO_WEB_HOST` build setting (`Supporting/Deployment.xcconfig`, real
    /// value from a gitignored local override or the CI secret) lands in the
    /// `MotoWebHost` Info.plist key. The same setting feeds the
    /// `webcredentials:` / `applinks:` hosts in `MotoManager.entitlements`,
    /// so code and entitlements cannot drift apart.
    static let webHost: String = {
        let value = (Bundle.main.object(forInfoDictionaryKey: "MotoWebHost") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "moto.example.com" : value
    }()

    /// WebAuthn relying-party identifier used as a fallback when the server's
    /// passkey options omit `rpId`.
    ///
    /// IMPORTANT: this must equal the rpId the backend issues. The relying
    /// party domain must serve `/.well-known/apple-app-site-association`.
    static var relyingPartyId: String { webHost }
}
