import Testing
import Foundation
import Combine
import AuthenticationServices
@testable import MotoManager

// MARK: - Error texts

struct LoginErrorMessageTests {

    private func text(_ error: Error, _ method: LoginMethod = .password) -> String? {
        LoginErrorMessage.text(for: error, method: method)
    }

    @Test func wrongCredentialsDependOnMethod() {
        #expect(text(APIError.unauthorized) == LoginErrorMessage.wrongCredentials)
        #expect(text(APIError.unauthorized, .passkey) == LoginErrorMessage.passkeyUnknown)
    }

    @Test func connectionProblems() {
        #expect(text(URLError(.notConnectedToInternet)) == LoginErrorMessage.noInternet)
        #expect(text(URLError(.dataNotAllowed)) == LoginErrorMessage.noInternet)
        for code: URLError.Code in [.cannotFindHost, .cannotConnectToHost, .timedOut, .dnsLookupFailed, .secureConnectionFailed] {
            #expect(text(URLError(code)) == LoginErrorMessage.serverUnreachable, "\(code)")
        }
        #expect(text(URLError(.cancelled)) == nil)
    }

    @Test func wrongServerAddress() {
        #expect(text(APIError.http(status: 405, message: nil)) == LoginErrorMessage.notMotoManager)
        #expect(text(APIError.http(status: 404, message: nil)) == LoginErrorMessage.notMotoManager)
        let html = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "html"))
        #expect(text(APIError.decoding(underlying: html)) == LoginErrorMessage.notMotoManager)
        #expect(text(APIError.badURL) == LoginErrorMessage.invalidServerURL)
    }

    @Test func serverSideProblems() {
        #expect(text(APIError.http(status: 429, message: "Too Many Requests")) == LoginErrorMessage.tooManyAttempts)
        #expect(text(APIError.http(status: 502, message: nil))?.contains("(502)") == true)
        #expect(text(APIError.http(status: 400, message: "Challenge expired"), .passkey) == LoginErrorMessage.passkeyRejected)
    }

    @Test func passkeySheetOutcomes() {
        #expect(text(ASAuthorizationError(.canceled), .passkey) == nil)
        #expect(text(ASAuthorizationError(.failed), .passkey) == LoginErrorMessage.passkeyFailed)
        #expect(text(ASAuthorizationError(.notHandled), .passkey) == LoginErrorMessage.passkeyFailed)
    }

    @Test func everyStepHasStatusTextExceptIdle() {
        #expect(LoginPhase.idle.statusText == nil)
        #expect(LoginPhase.connecting.statusText == "Verbinde mit Server…")
        #expect(LoginPhase.awaitingPasskey.statusText == "Warte auf Passkey…")
        #expect(LoginPhase.verifying.statusText == "Anmeldung wird geprüft…")
        #expect(LoginPhase.loadingGarage.statusText == "Garage wird geladen…")
    }
}

// MARK: - Login flow against a stubbed server

/// Answers requests to the stub host from `LoginStubProtocol.respond`.
nonisolated final class LoginStubProtocol: URLProtocol {
    struct Reply {
        var status: Int
        var body: String
        var contentType = "application/json"
    }

    nonisolated(unsafe) static var respond: (URLRequest) -> Reply = { _ in Reply(status: 500, body: "") }
    nonisolated(unsafe) static var requestedPaths: [String] = []

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "login-stub.test"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requestedPaths.append(request.url?.path ?? "")
        let reply = Self.respond(request)
        let response = HTTPURLResponse(
            url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": reply.contentType]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Serialized, and the only suite that touches the network: it repoints the
/// shared `NetworkManager.baseURL` and registers a global URL protocol.
@MainActor
@Suite(.serialized)
struct LoginFlowTests {

    private let upgradeOK = LoginStubProtocol.Reply(status: 200, body: #"{"softUpgradeBuild":0,"hardUpgradeBuild":0}"#)

    /// Runs `body` against the stub server and returns the phases it went through.
    private func withStubServer(
        _ respond: @escaping (URLRequest) -> LoginStubProtocol.Reply,
        _ body: (AuthViewModel) async -> Void
    ) async -> [LoginPhase] {
        let original = NetworkManager.shared.baseURL
        NetworkManager.shared.baseURL = "https://login-stub.test"
        LoginStubProtocol.respond = respond
        LoginStubProtocol.requestedPaths = []
        URLProtocol.registerClass(LoginStubProtocol.self)
        defer {
            URLProtocol.unregisterClass(LoginStubProtocol.self)
            NetworkManager.shared.baseURL = original
            NetworkManager.shared.deleteToken()
        }

        let vm = AuthViewModel()
        vm.isAuthenticated = false
        var phases: [LoginPhase] = []
        let sub = vm.$phase.removeDuplicates().sink { phases.append($0) }
        await body(vm)
        sub.cancel()
        return phases
    }

    @Test func successfulLoginGoesThroughEveryStep() async {
        var vmAfter: AuthViewModel?
        let phases = await withStubServer({ request in
            request.url?.path == "/api/auth/login"
                ? .init(status: 200, body: #"{"token":"abc"}"#)
                : upgradeOK
        }) { vm in
            await vm.login(identifier: " alice ", password: "pw")
            #expect(vm.isAuthenticated)
            #expect(vm.errorMessage == nil)
            #expect(vm.activeMethod == .password)
            #expect(vm.isAwaitingGarage)
            vm.finishLogin()
            vmAfter = vm
        }
        #expect(phases == [.idle, .connecting, .verifying, .loadingGarage])
        // The login screen fades out unchanged; only the hand-over flag flips.
        #expect(vmAfter?.isAwaitingGarage == false)
        #expect(vmAfter?.isAuthenticated == true)
        #expect(LoginStubProtocol.requestedPaths == ["/api/app-upgrade", "/api/auth/login"])
    }

    @Test func wrongPasswordShowsMessageAndUnlocks() async {
        let phases = await withStubServer({ request in
            request.url?.path == "/api/auth/login" ? .init(status: 401, body: "") : upgradeOK
        }) { vm in
            await vm.login(identifier: "alice", password: "wrong")
            #expect(!vm.isAuthenticated)
            #expect(!vm.isBusy)
            #expect(vm.activeMethod == nil)
            #expect(vm.errorMessage == LoginErrorMessage.wrongCredentials)
            #expect(!vm.isAwaitingGarage)
        }
        #expect(phases == [.idle, .connecting, .verifying, .idle])
    }

    @Test func websiteAddressStopsBeforeSendingThePassword() async {
        _ = await withStubServer({ _ in
            .init(status: 200, body: "<!doctype html><html></html>", contentType: "text/html")
        }) { vm in
            await vm.login(identifier: "alice", password: "pw")
            #expect(vm.errorMessage == LoginErrorMessage.notMotoManager)
        }
        #expect(LoginStubProtocol.requestedPaths == ["/api/app-upgrade"])
    }

    @Test func tooManyAttempts() async {
        _ = await withStubServer({ request in
            request.url?.path == "/api/auth/login" ? .init(status: 429, body: "Too Many Requests") : upgradeOK
        }) { vm in
            await vm.login(identifier: "alice", password: "pw")
            #expect(vm.errorMessage == LoginErrorMessage.tooManyAttempts)
        }
    }

    // Non-login requests keep collapsing connection failures to "Offline".
    @Test func offlineDescriptionReadsOffline() {
        #expect(APIError.offline.errorDescription == "Offline")
    }

    @Test func unreachableBackendMapsToOfflineOutsideLogin() async {
        let original = NetworkManager.shared.baseURL
        NetworkManager.shared.baseURL = "http://127.0.0.1:1"
        defer { NetworkManager.shared.baseURL = original }

        do {
            _ = try await NetworkManager.shared.fetchAppUpgradeInfo()
            Issue.record("expected an offline error, but the request succeeded")
        } catch let error as APIError {
            guard case .offline = error else {
                Issue.record("expected APIError.offline, got \(error)")
                return
            }
        } catch {
            Issue.record("expected APIError.offline, got \(type(of: error)): \(error)")
        }
    }

    @Test func unreachableServerIsNamedAsSuch() async {
        let original = NetworkManager.shared.baseURL
        // Port 1 refuses instantly -> URLError.cannotConnectToHost.
        NetworkManager.shared.baseURL = "http://127.0.0.1:1"
        defer { NetworkManager.shared.baseURL = original }

        let vm = AuthViewModel()
        vm.isAuthenticated = false
        await vm.login(identifier: "alice", password: "pw")
        #expect(vm.errorMessage == LoginErrorMessage.serverUnreachable)
        #expect(!vm.isBusy)
    }
}
