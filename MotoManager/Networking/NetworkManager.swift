import Foundation

class NetworkManager {
    static let shared = NetworkManager()
    static let unauthorizedNotification = Notification.Name("com.motomanager.unauthorized")

    private let baseURLKey = "com.motomanager.baseURL"
    private let defaultBaseURL = "https://moto-api.herrmann.ltd"

    var baseURL: String {
        get {
            UserDefaults.standard.string(forKey: baseURLKey) ?? defaultBaseURL
        }
        set {
            UserDefaults.standard.set(newValue, forKey: baseURLKey)
        }
    }

    private let tokenService = "com.motomanager.auth"
    private let tokenAccount = "jwt-token"

    private init() {}

    // MARK: - Token storage

    func saveToken(_ token: String) {
        if let data = token.data(using: .utf8) {
            KeychainHelper.shared.save(data, service: tokenService, account: tokenAccount)
        }
    }

    func getToken() -> String? {
        if let data = KeychainHelper.shared.read(service: tokenService, account: tokenAccount) {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }

    func deleteToken() {
        KeychainHelper.shared.delete(service: tokenService, account: tokenAccount)
    }

    // MARK: - Request building & execution

    /// Builds a request against `baseURL` (or an absolute URL if `path` already
    /// starts with `http`). When `authorized` is true a bearer token is required
    /// and `APIError.notAuthenticated` is thrown if none is stored — removing the
    /// per-endpoint token boilerplate that used to be copy-pasted everywhere.
    private func makeRequest(
        path: String,
        method: String = "GET",
        authorized: Bool,
        jsonBody: Data? = nil
    ) throws -> URLRequest {
        let urlString = path.hasPrefix("http") ? path : "\(baseURL)\(path)"
        guard let url = URL(string: urlString) else {
            throw APIError.badURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method

        if let jsonBody {
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = jsonBody
        }

        if authorized {
            guard let token = getToken() else {
                throw APIError.notAuthenticated
            }
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        return request
    }

    /// Executes a request, mapping transport and HTTP errors to `APIError`.
    /// Posts `unauthorizedNotification` on 401 so the session can be cleared.
    private func performRequest(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.http(status: -1, message: nil)
        }

        if httpResponse.statusCode == 401 {
            NotificationCenter.default.post(name: NetworkManager.unauthorizedNotification, object: nil)
            throw APIError.unauthorized
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.http(status: httpResponse.statusCode, message: Self.serverMessage(from: data))
        }

        return data
    }

    /// GET `path` and decode the body into `T`.
    private func get<T: Decodable>(_ path: String, authorized: Bool = true) async throws -> T {
        let request = try makeRequest(path: path, authorized: authorized)
        let data = try await performRequest(request)
        return try Self.decode(T.self, from: data)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw APIError.decoding(underlying: error)
        }
    }

    /// Best-effort extraction of a human-readable error message from a non-2xx body.
    private static func serverMessage(from data: Data) -> String? {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["message", "error", "detail"] {
                if let msg = obj[key] as? String, !msg.isEmpty { return msg }
            }
        }
        let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let raw, !raw.isEmpty, raw.count <= 300 { return raw }
        return nil
    }

    // MARK: - Auth

    func login(credentials: LoginRequest) async throws -> String {
        let body = try JSONEncoder().encode(credentials)
        let request = try makeRequest(path: "/api/auth/login", method: "POST", authorized: false, jsonBody: body)
        let data = try await performRequest(request)
        let loginResponse = try Self.decode(LoginResponse.self, from: data)
        saveToken(loginResponse.token)
        return loginResponse.token
    }

    // MARK: - Fleet & records

    func fetchMotorcycles() async throws -> [Motorcycle] {
        let wrapper: MotorcycleListResponse = try await get("/api/motorcycles")

        // Prepend baseURL to each image path if it's just a path.
        let motorcycles = wrapper.motorcycles.map { m -> Motorcycle in
            var moto = m
            if let imagePath = moto.image, !imagePath.hasPrefix("http") {
                let base = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
                let path = imagePath.hasPrefix("/") ? imagePath : "/\(imagePath)"
                moto.image = base + path
            }
            return moto
        }

        CacheStore.shared.save(motorcycles, key: CacheKey.motorcycles)
        AppLog.debug("Fetched \(motorcycles.count) motorcycles")
        return motorcycles
    }

    func fetchMaintenance(motorcycleId: Int) async throws -> [MaintenanceRecord] {
        let wrapper: MaintenanceListResponse = try await get("/api/motorcycles/\(motorcycleId)/maintenance")
        CacheStore.shared.save(wrapper.maintenanceRecords, key: CacheKey.maintenance(motorcycleId: motorcycleId))
        AppLog.debug("Fetched \(wrapper.maintenanceRecords.count) maintenance records for \(motorcycleId)")
        return wrapper.maintenanceRecords
    }

    func fetchTorqueSpecs(motorcycleId: Int) async throws -> [TorqueSpec] {
        let wrapper: TorqueSpecListResponse = try await get("/api/motorcycles/\(motorcycleId)/torque-specs")
        CacheStore.shared.save(wrapper.torqueSpecs, key: CacheKey.torque(motorcycleId: motorcycleId))
        AppLog.debug("Fetched \(wrapper.torqueSpecs.count) torque specs for \(motorcycleId)")
        return wrapper.torqueSpecs
    }

    func fetchDocuments() async throws -> [Document] {
        let wrapper: DocumentListResponse = try await get("/api/documents")
        CacheStore.shared.save(wrapper.docs, key: CacheKey.documents)
        AppLog.debug("Fetched \(wrapper.docs.count) documents")
        return wrapper.docs
    }

    func fetchCurrencies() async throws -> [Currency] {
        let wrapper: CurrencyListResponse = try await get("/api/currencies")
        CacheStore.shared.save(wrapper.currencies, key: CacheKey.currencies)
        return wrapper.currencies
    }

    /// Authenticated GET for arbitrary binary blobs (documents, attachments).
    func fetchBlob(url: String) async throws -> Data {
        let request = try makeRequest(path: url, authorized: true)
        return try await performRequest(request)
    }

    func createMaintenance(motorcycleId: Int, record: [String: Any]) async throws {
        let body = try JSONSerialization.data(withJSONObject: record)
        let request = try makeRequest(
            path: "/api/motorcycles/\(motorcycleId)/maintenance",
            method: "POST",
            authorized: true,
            jsonBody: body
        )
        _ = try await performRequest(request)
    }

    func updateMaintenance(motorcycleId: Int, recordId: Int, record: [String: Any]) async throws {
        let body = try JSONSerialization.data(withJSONObject: record)
        let request = try makeRequest(
            path: "/api/motorcycles/\(motorcycleId)/maintenance/\(recordId)",
            method: "PUT",
            authorized: true,
            jsonBody: body
        )
        _ = try await performRequest(request)
    }

    // MARK: - Passkey

    func fetchPasskeyLoginOptions(username: String?) async throws -> PasskeyOptionsResponse {
        var path = "/api/auth/passkey/login/options"
        if let username,
           let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "?username=\(encoded)"
        }
        return try await get(path, authorized: false)
    }

    func verifyPasskeyLogin(challengeId: String, response: PasskeyResponse) async throws -> String {
        let body = try JSONEncoder().encode(PasskeyVerifyRequest(challengeId: challengeId, response: response))
        let request = try makeRequest(path: "/api/auth/passkey/login/verify", method: "POST", authorized: false, jsonBody: body)
        let data = try await performRequest(request)
        let loginResponse = try Self.decode(LoginResponse.self, from: data)
        saveToken(loginResponse.token)
        return loginResponse.token
    }
}
