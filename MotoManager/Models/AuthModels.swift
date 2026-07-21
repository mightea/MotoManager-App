import Foundation

struct LoginRequest: Codable {
    let identifier: String
    let password: String
}

struct LoginResponse: Codable {
    let token: String
}

// MARK: - Passkey Models

nonisolated struct PasskeyOptionsResponse: Codable {
    let options: PasskeyRequestOptionsEnvelope
    let challengeId: String
}

/// The server (webauthn-rs `RequestChallengeResponse`) wraps the WebAuthn
/// request options in a `publicKey` envelope — the same shape browsers pass to
/// `navigator.credentials.get()`. Accept the bare options too, mirroring the
/// webapp's `options.publicKey || options` fallback.
nonisolated struct PasskeyRequestOptionsEnvelope: Codable {
    let publicKey: PublicKeyCredentialRequestOptions

    private enum CodingKeys: String, CodingKey {
        case publicKey
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let wrapped = try container.decodeIfPresent(PublicKeyCredentialRequestOptions.self, forKey: .publicKey) {
            publicKey = wrapped
        } else {
            publicKey = try PublicKeyCredentialRequestOptions(from: decoder)
        }
    }
}

nonisolated struct PublicKeyCredentialRequestOptions: Codable {
    let challenge: String
    let timeout: Int?
    let rpId: String?
    let allowCredentials: [AllowCredential]?
    let userVerification: String?
}

nonisolated struct AllowCredential: Codable {
    let id: String
    let type: String
    let transports: [String]?
}

struct PasskeyVerifyRequest: Codable {
    let challengeId: String
    let response: PasskeyResponse
}

struct PasskeyResponse: Codable {
    let id: String
    let rawId: String
    let type: String
    let response: AuthenticatorAssertionResponse
}

struct AuthenticatorAssertionResponse: Codable {
    let authenticatorData: String
    let clientDataJSON: String
    let signature: String
    let userHandle: String?
}
