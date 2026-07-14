import Foundation

/// Typed error surfaced by `NetworkManager`. Carries enough detail for the UI to
/// distinguish "not logged in" from "session expired" from a real server failure,
/// instead of collapsing everything into `URLError(.badServerResponse)`.
enum APIError: LocalizedError {
    /// A URL string could not be turned into a `URL`.
    case badURL
    /// No JWT is present locally — the caller is not logged in.
    case notAuthenticated
    /// The server rejected the token (HTTP 401). The unauthorized notification
    /// is posted separately so `AuthViewModel` can clear the session.
    case unauthorized
    /// A non-2xx response. `message` is the server's error text when available.
    case http(status: Int, message: String?)
    /// The response body could not be decoded into the expected type.
    case decoding(underlying: Error)
    /// The request failed because the device has no connection or the backend
    /// is unreachable (a connectivity-class `URLError`). Surfaced to the user as
    /// "Offline" rather than a raw transport error.
    case offline

    var errorDescription: String? {
        switch self {
        case .badURL:
            return "Ungültige Serveradresse."
        case .notAuthenticated:
            return "Nicht angemeldet."
        case .unauthorized:
            return "Sitzung abgelaufen. Bitte erneut anmelden."
        case .http(let status, let message):
            if let message, !message.isEmpty {
                return message
            }
            return "Serverfehler (\(status))."
        case .decoding:
            return "Antwort konnte nicht verarbeitet werden."
        case .offline:
            return "Offline"
        }
    }
}
