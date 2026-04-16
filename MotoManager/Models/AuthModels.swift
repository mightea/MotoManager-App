import Foundation

struct LoginRequest: Codable {
    let identifier: String
    let password: String
}

struct LoginResponse: Codable {
    let token: String
}

// MARK: - Passkey Models

struct PasskeyOptionsResponse: Codable {
    let options: PublicKeyCredentialRequestOptions
    let challengeId: String
}

struct PublicKeyCredentialRequestOptions: Codable {
    let challenge: String
    let timeout: Int?
    let rpId: String?
    let allowCredentials: [AllowCredential]?
    let userVerification: String?
}

struct AllowCredential: Codable {
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

