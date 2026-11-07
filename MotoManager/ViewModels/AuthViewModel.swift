import Foundation
import Combine
import AuthenticationServices

@MainActor
class AuthViewModel: NSObject, ObservableObject {
    @Published var isAuthenticated = false
    /// The current login step; `.idle` when no login is running.
    @Published private(set) var phase: LoginPhase = .idle
    /// Which login the user started, so only that button shows a spinner.
    @Published private(set) var activeMethod: LoginMethod?
    @Published var errorMessage: String?
    /// True after a login until the first garage load is done: the root view
    /// keeps showing the login screen ("Garage wird geladen…") meanwhile.
    /// Phase and spinner are left as they are when this turns false, so the
    /// login screen fades out unchanged instead of flashing back to idle.
    @Published private(set) var isAwaitingGarage = false

    /// True from tapping a login button until the garage is on screen (or the
    /// attempt failed). Fields and buttons are locked meanwhile. Stays true
    /// behind the app after a login; reset by `logout()` or the next attempt.
    var isBusy: Bool { phase != .idle }

    private var cancellables = Set<AnyCancellable>()
    private var currentChallengeId: String?
    
    override init() {
        super.init()
        if !ProcessInfo.processInfo.arguments.contains("--ui-testing-logged-out") {
            checkAuth()
        }
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

    private func begin(_ method: LoginMethod) {
        isAwaitingGarage = false
        activeMethod = method
        errorMessage = nil
        phase = .connecting
    }

    /// Ends a failed attempt. A nil message (user cancelled) shows nothing.
    private func fail(_ error: Error, method: LoginMethod) {
        phase = .idle
        activeMethod = nil
        currentChallengeId = nil
        errorMessage = LoginErrorMessage.text(for: error, method: method)
    }

    /// Logged in: keep the login screen up with "Garage wird geladen…" until
    /// `finishLogin()` is called once the first garage load is done.
    private func succeed() {
        phase = .loadingGarage
        isAwaitingGarage = true
        isAuthenticated = true
    }

    /// Called by the root view once the post-login load is done (or took too
    /// long); hands over from the login screen to the app.
    func finishLogin() {
        isAwaitingGarage = false
    }
    
    func login(identifier: String, password: String) async {
        guard !isBusy else { return }
        begin(.password)
        do {
            try await NetworkManager.shared.checkServer()
            phase = .verifying
            // Autofill and keyboard suggestions can leave an invisible trailing
            // space, which the backend would treat as a different username.
            let credentials = LoginRequest(
                identifier: identifier.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
            _ = try await NetworkManager.shared.login(credentials: credentials)
            succeed()
        } catch {
            fail(error, method: .password)
        }
    }
    
    func loginWithPasskey(username: String?) async {
        guard !isBusy else { return }
        begin(.passkey)
        do {
            // Fetching the options doubles as the server check.
            let response = try await NetworkManager.shared.fetchPasskeyLoginOptions(username: username)
            self.currentChallengeId = response.challengeId
            let options = response.options.publicKey

            let publicKeyProvider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: options.rpId ?? AuthConfig.relyingPartyId)

            // Use base64url decoding for the challenge
            guard let challengeData = Data(base64Encoded: options.challenge.base64URLtoBase64()) else {
                throw NSError(domain: "AuthError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid challenge data"])
            }
            
            let request = publicKeyProvider.createCredentialAssertionRequest(challenge: challengeData)
            
            let authController = ASAuthorizationController(authorizationRequests: [request])
            authController.delegate = self
            authController.presentationContextProvider = self
            phase = .awaitingPasskey
            authController.performRequests()
            
            // The rest of the flow continues in the delegate methods
        } catch {
            fail(error, method: .passkey)
        }
    }
    
    func logout() {
        NetworkManager.shared.deleteToken()
        CacheStore.shared.clearAll()
        ImageCache.shared.clearAll()
        DocumentCache.shared.clearAll()
        DocumentOfflineStore.shared.clearAll()
        // In-memory and URL-level caches too — the wipe must cover *every*
        // cache so a different account never sees the previous user's data.
        RemoteImageMemoryCache.shared.clearAll()
        URLCache.shared.removeAllCachedResponses()
        // Drop synced SwiftData rows and all sync cursors: a different account
        // must not inherit this user's local data or cursors (stale cursors
        // would silently skip the other account's records on first sync).
        SyncEngine.shared.resetLocalState()
        UserSettingsStore.shared.clear()
        MaintenanceReminderScheduler.shared.cancelAll()
        isAuthenticated = false
        isAwaitingGarage = false
        phase = .idle
        activeMethod = nil
    }
    
    func resetSession() {
        logout()
        errorMessage = nil
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AuthViewModel: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let challengeId = currentChallengeId,
              let credential = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion
        else {
            // No challenge in flight or an unexpected credential type — end
            // the attempt so the spinner doesn't hang.
            fail(ASAuthorizationError(.invalidResponse), method: .passkey)
            return
        }

        phase = .verifying
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
                self.currentChallengeId = nil
                self.succeed()
            } catch {
                self.fail(error, method: .passkey)
            }
        }
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        fail(error, method: .passkey)
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
        
        guard let scene = windowScene else {
            AppLog.error("No window scene available for passkey presentation")
            preconditionFailure("Passkey presentation requires a window scene")
        }
        return UIWindow(windowScene: scene)
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
