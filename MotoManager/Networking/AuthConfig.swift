import Foundation

/// Authentication configuration constants.
enum AuthConfig {
    /// WebAuthn relying-party identifier used as a fallback when the server's
    /// passkey options omit `rpId`.
    ///
    /// IMPORTANT: this value must stay in sync with the `webcredentials:` host in
    /// `MotoManager.entitlements` and with the rpId the backend issues. The relying
    /// party domain must serve `/.well-known/apple-app-site-association`.
    static let relyingPartyId = "moto.herrmann.ltd"
}
