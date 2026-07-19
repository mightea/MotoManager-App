import Testing
import Foundation
@testable import MotoManager

// MARK: - Passkey options decoding

/// The backend (webauthn-rs) wraps the WebAuthn request options in a
/// `publicKey` envelope. These fixtures mirror the live response of
/// GET /api/auth/passkey/login-options.
struct PasskeyModelTests {
    @Test func decodesPublicKeyWrappedOptions() throws {
        let json = """
        {"challengeId":"4946fe23-3fac-4c98-b18e-107c43f224f9",
         "options":{"publicKey":{
           "allowCredentials":[{"id":"Y2eylQKXFNt7wGWTYl9nfQkVqIg","type":"public-key"}],
           "challenge":"WOWAAhGw0EnyxYh-R7RObNKGzDCxyXeZ8BcW2tsx4dE",
           "rpId":"moto.herrmann.ltd","timeout":300000,"userVerification":"required"}}}
        """
        let response = try JSONDecoder().decode(PasskeyOptionsResponse.self, from: Data(json.utf8))
        #expect(response.challengeId == "4946fe23-3fac-4c98-b18e-107c43f224f9")
        #expect(response.options.publicKey.rpId == "moto.herrmann.ltd")
        #expect(response.options.publicKey.challenge == "WOWAAhGw0EnyxYh-R7RObNKGzDCxyXeZ8BcW2tsx4dE")
        #expect(response.options.publicKey.allowCredentials?.count == 1)
    }

    @Test func decodesBareOptionsFallback() throws {
        let json = """
        {"challengeId":"abc",
         "options":{"challenge":"Y2hhbGxlbmdl","rpId":"moto.herrmann.ltd"}}
        """
        let response = try JSONDecoder().decode(PasskeyOptionsResponse.self, from: Data(json.utf8))
        #expect(response.options.publicKey.challenge == "Y2hhbGxlbmdl")
        #expect(response.options.publicKey.rpId == "moto.herrmann.ltd")
    }
}
