import Foundation
import AuthenticationServices

/// How the user is logging in. Drives which button shows the spinner and
/// which wording an error gets.
enum LoginMethod: Equatable {
    case password
    case passkey
}

/// The visible steps of a login, from tapping the button to the garage being
/// on screen. `idle` means no login is running.
enum LoginPhase: Equatable {
    case idle
    /// Checking that the server address answers and runs MotoManager.
    case connecting
    /// Waiting for the system passkey sheet.
    case awaitingPasskey
    /// Credentials or passkey assertion are with the server.
    case verifying
    /// Logged in; the first garage load is running behind the login screen.
    case loadingGarage

    var statusText: String? {
        switch self {
        case .idle: nil
        case .connecting: "Verbinde mit Server…"
        case .awaitingPasskey: "Warte auf Passkey…"
        case .verifying: "Anmeldung wird geprüft…"
        case .loadingGarage: "Garage wird geladen…"
        }
    }
}

/// Turns any error from a login attempt into a German message that says what
/// went wrong and what to do. Returns nil when nothing should be shown
/// (the user cancelled).
enum LoginErrorMessage {
    static let wrongCredentials = "Benutzername oder Passwort ist falsch."
    static let noInternet = "Keine Internetverbindung."
    static let serverUnreachable = "Server nicht erreichbar. Prüfe die Serveradresse."
    static let notMotoManager = "Unter dieser Adresse läuft kein MotoManager-Server."
    static let invalidServerURL = "Ungültige Serveradresse."
    static let tooManyAttempts = "Zu viele Versuche, bitte kurz warten."
    static let passkeyUnknown = "Dieser Passkey ist auf dem Server nicht registriert."
    static let passkeyRejected = "Passkey konnte nicht bestätigt werden. Bitte erneut versuchen."
    static let passkeyNotSetUp = "Passkeys sind für diese Serveradresse nicht eingerichtet."
    static let passkeyFailed = "Passkey-Anmeldung fehlgeschlagen. Bitte erneut versuchen."
    static let generic = "Anmeldung fehlgeschlagen. Bitte erneut versuchen."

    static func text(for error: Error, method: LoginMethod) -> String? {
        if let apiError = error as? APIError {
            return text(for: apiError, method: method)
        }
        if let urlError = error as? URLError {
            return text(for: urlError)
        }
        if let authError = error as? ASAuthorizationError {
            return text(for: authError)
        }
        if error is CancellationError {
            return nil
        }
        return method == .passkey ? passkeyFailed : generic
    }

    private static func text(for error: APIError, method: LoginMethod) -> String? {
        switch error {
        case .unauthorized:
            return method == .passkey ? passkeyUnknown : wrongCredentials
        case .http(let status, _):
            switch status {
            case 404, 405:
                return notMotoManager
            case 429:
                return tooManyAttempts
            case 400 where method == .passkey:
                return passkeyRejected
            case 500...599:
                return "Der Server hat einen Fehler gemeldet (\(status)). Bitte später erneut versuchen."
            default:
                return "Anmeldung fehlgeschlagen (\(status)). Bitte erneut versuchen."
            }
        case .decoding:
            // A web page (or anything else) came back instead of the API's JSON.
            return notMotoManager
        case .badURL:
            return invalidServerURL
        case .offline:
            return noInternet
        case .unsupportedVersion:
            return error.errorDescription
        case .notAuthenticated:
            return generic
        }
    }

    private static func text(for error: URLError) -> String? {
        switch error.code {
        case .cancelled:
            return nil
        case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff:
            return noInternet
        case .badURL, .unsupportedURL:
            return invalidServerURL
        default:
            // DNS, refused connection, timeout, TLS: the address is wrong or
            // the server is down. Either way the user should check the address.
            return serverUnreachable
        }
    }

    private static func text(for error: ASAuthorizationError) -> String? {
        switch error.code {
        case .canceled:
            return nil
        case .failed:
            // The app isn't associated with the server's domain (AASA missing,
            // or a build without the Associated Domains entitlement).
            let detail = (error as NSError).localizedDescription.lowercased()
            if detail.contains("associated") || detail.contains("domain") {
                return passkeyNotSetUp
            }
            return passkeyFailed
        default:
            return passkeyFailed
        }
    }
}
