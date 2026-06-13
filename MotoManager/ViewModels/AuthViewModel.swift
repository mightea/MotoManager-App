import Foundation
import Combine
import AuthenticationServices

@MainActor
class AuthViewModel: NSObject, ObservableObject {
    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private var cancellables = Set<AnyCancellable>()
    private var currentChallengeId: String?
    
    override init() {
        super.init()
        checkAuth()
        setupNotificationObservers()
    }
    
    func setupNotificationObservers() {
        NotificationCenter.default.publisher(for: NetworkManager.unauthorizedNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.resetSession()
            }
            .store(in: &cancellables)
    }
    
    func checkAuth() {
        if NetworkManager.shared.getToken() != nil {
            isAuthenticated = true
        }
    }
    
    func login(identifier: String, password: String) async {
        isLoading = true
        errorMessage = nil
        
        do {
            let credentials = LoginRequest(identifier: identifier, password: password)
            _ = try await NetworkManager.shared.login(credentials: credentials)
            isAuthenticated = true
        } catch {
            errorMessage = "Login failed: \(error.localizedDescription)"
            isAuthenticated = false
        }
        
        isLoading = false
    }
    
    func loginWithPasskey(username: String?) async {
        isLoading = true
        errorMessage = nil
        
        do {
            let response = try await NetworkManager.shared.fetchPasskeyLoginOptions(username: username)
            self.currentChallengeId = response.challengeId
            
            let publicKeyProvider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: response.options.rpId ?? AuthConfig.relyingPartyId)
            
            // Use base64url decoding for the challenge
            guard let challengeData = Data(base64Encoded: response.options.challenge.base64URLtoBase64()) else {
                throw NSError(domain: "AuthError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid challenge data"])
            }
            
            let request = publicKeyProvider.createCredentialAssertionRequest(challenge: challengeData)
            
            let authController = ASAuthorizationController(authorizationRequests: [request])
            authController.delegate = self
            authController.presentationContextProvider = self
            authController.performRequests()
            
            // The rest of the flow continues in the delegate methods
        } catch {
            errorMessage = "Passkey failed: \(error.localizedDescription)"
            isLoading = false
        }
    }
    
    func logout() {
        NetworkManager.shared.deleteToken()
        CacheStore.shared.clearAll()
        ImageCache.shared.clearAll()
        DocumentCache.shared.clearAll()
        isAuthenticated = false
    }
    
    func resetSession() {
        logout()
        errorMessage = nil
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AuthViewModel: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let challengeId = currentChallengeId else { return }
        
        if let credential = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion {
            Task {
                do {
                    let passkeyResponse = PasskeyResponse(
                        id: credential.credentialID.base64URLEncodedString(),
                        rawId: credential.credentialID.base64URLEncodedString(),
                        type: "public-key",
                        response: AuthenticatorAssertionResponse(
                            authenticatorData: credential.rawAuthenticatorData.base64URLEncodedString(),
                            clientDataJSON: credential.rawClientDataJSON.base64URLEncodedString(),
                            signature: credential.signature.base64URLEncodedString(),
                            userHandle: credential.userID?.base64URLEncodedString()
                        )
                    )
                    
                    _ = try await NetworkManager.shared.verifyPasskeyLogin(challengeId: challengeId, response: passkeyResponse)
                    self.isAuthenticated = true
                    self.isLoading = false
                } catch {
                    self.errorMessage = "Passkey verification failed: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        isLoading = false
        if (error as NSError).code != ASAuthorizationError.canceled.rawValue {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension AuthViewModel: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
            ?? scenes.first as? UIWindowScene
        
        if let window = windowScene?.windows.first {
            return window
        }
        
        if let scene = windowScene {
            return UIWindow(windowScene: scene)
        }

        // No active window scene — surface an error and return an empty anchor so
        // the authorization request fails gracefully instead of crashing the app.
        AppLog.error("No window scene available for passkey presentation")
        errorMessage = "Anmeldung konnte nicht angezeigt werden."
        isLoading = false
        return UIWindow(frame: .zero)
    }
}

// MARK: - Base64 Helpers

extension String {
    func base64URLtoBase64() -> String {
        var base64 = self
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        if base64.count % 4 != 0 {
            base64.append(String(repeating: "=", count: 4 - base64.count % 4))
        }
        return base64
    }
}

extension Data {
    func base64URLEncodedString() -> String {
        return self.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
