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
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let urlError as URLError where Self.isOffline(urlError) {
            // No connection or the backend is unreachable — surface as "Offline"
            // rather than leaking Foundation's raw transport message.
            throw APIError.offline
        }

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

    /// Connectivity-class transport failures: the device is offline or the
    /// backend can't be reached (DNS/host/timeout). These map to `APIError.offline`
    /// so the whole app can show "Offline"; other `URLError`s propagate unchanged.
    private static func isOffline(_ error: URLError) -> Bool {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost,
             .cannotFindHost, .dnsLookupFailed, .timedOut, .dataNotAllowed,
             .internationalRoamingOff:
            return true
        default:
            return false
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

    func fetchMaintenance(motorcycleId: Int, since: String? = nil) async throws -> [MaintenanceRecord] {
        let wrapper: MaintenanceListResponse = try await get(syncPath(
            "/api/motorcycles/\(motorcycleId)/maintenance", since: since))
        // Only the full (no-since) fetch represents the complete set worth caching.
        if since == nil {
            CacheStore.shared.save(wrapper.maintenanceRecords, key: CacheKey.maintenance(motorcycleId: motorcycleId))
        }
        AppLog.debug("Fetched \(wrapper.maintenanceRecords.count) maintenance records for \(motorcycleId)")
        return wrapper.maintenanceRecords
    }

    func fetchTorqueSpecs(motorcycleId: Int, since: String? = nil) async throws -> [TorqueSpec] {
        let wrapper: TorqueSpecListResponse = try await get(syncPath(
            "/api/motorcycles/\(motorcycleId)/torque-specs", since: since))
        if since == nil {
            CacheStore.shared.save(wrapper.torqueSpecs, key: CacheKey.torque(motorcycleId: motorcycleId))
        }
        AppLog.debug("Fetched \(wrapper.torqueSpecs.count) torque specs for \(motorcycleId)")
        return wrapper.torqueSpecs
    }

    func fetchMotorcycleDetails(motorcycleId: Int, since: String? = nil) async throws -> [MotorcycleDetail] {
        let wrapper: MotorcycleDetailListResponse = try await get(syncPath(
            "/api/motorcycles/\(motorcycleId)/details", since: since))
        if since == nil {
            CacheStore.shared.save(wrapper.motorcycleDetails, key: CacheKey.details(motorcycleId: motorcycleId))
        }
        AppLog.debug("Fetched \(wrapper.motorcycleDetails.count) motorcycle details for \(motorcycleId)")
        return wrapper.motorcycleDetails
    }

    /// Tire pressures are a 1:1 record without sync metadata — plain
    /// fetch + cache like documents, not SwiftData/SyncEngine.
    func fetchTirePressure(motorcycleId: Int) async throws -> TirePressure? {
        let wrapper: TirePressureResponse = try await get("/api/motorcycles/\(motorcycleId)/tire-pressure")
        let key = CacheKey.tirePressure(motorcycleId: motorcycleId)
        if let pressure = wrapper.tirePressure {
            CacheStore.shared.save(pressure, key: key)
        } else {
            CacheStore.shared.remove(key: key)
        }
        return wrapper.tirePressure
    }

    /// Full-record upsert: configurations absent from the payload are cleared.
    func upsertTirePressure(motorcycleId: Int, payload: [String: Any]) async throws -> TirePressure {
        let body = try JSONSerialization.data(withJSONObject: payload)
        let request = try makeRequest(path: "/api/motorcycles/\(motorcycleId)/tire-pressure", method: "PUT", authorized: true, jsonBody: body)
        let data = try await performRequest(request)
        let wrapper = try Self.decode(TirePressureResponse.self, from: data)
        guard let pressure = wrapper.tirePressure else {
            throw APIError.decoding(underlying: NSError(domain: "TirePressure", code: 0))
        }
        CacheStore.shared.save(pressure, key: CacheKey.tirePressure(motorcycleId: motorcycleId))
        return pressure
    }

    func deleteTirePressure(motorcycleId: Int) async throws {
        let request = try makeRequest(path: "/api/motorcycles/\(motorcycleId)/tire-pressure", method: "DELETE", authorized: true)
        _ = try await performRequest(request)
        CacheStore.shared.remove(key: CacheKey.tirePressure(motorcycleId: motorcycleId))
    }

    func fetchIssues(motorcycleId: Int, since: String? = nil) async throws -> [Issue] {
        let wrapper: IssueListResponse = try await get(syncPath(
            "/api/motorcycles/\(motorcycleId)/issues", since: since))
        AppLog.debug("Fetched \(wrapper.issues.count) issues for \(motorcycleId)")
        return wrapper.issues
    }

    /// Appends a percent-encoded `?since=` cursor when present.
    private func syncPath(_ path: String, since: String?) -> String {
        guard let since, let encoded = since.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return path
        }
        return "\(path)?since=\(encoded)"
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

    // MARK: - Sync mutations
    //
    // These return the server's stored record (with serverId/clientId/updatedAt)
    // so the SyncEngine can reconcile the local SwiftData row. Creates carry a
    // clientId in the payload, making retries idempotent (backend migration 011).

    func createMaintenanceRecord(motorcycleId: Int, payload: [String: Any]) async throws -> MaintenanceRecord {
        let body = try JSONSerialization.data(withJSONObject: payload)
        let request = try makeRequest(path: "/api/motorcycles/\(motorcycleId)/maintenance", method: "POST", authorized: true, jsonBody: body)
        let data = try await performRequest(request)
        return try Self.decode(MaintenanceRecordResponse.self, from: data).maintenanceRecord
    }

    func updateMaintenanceRecord(motorcycleId: Int, recordId: Int, payload: [String: Any]) async throws -> MaintenanceRecord {
        let body = try JSONSerialization.data(withJSONObject: payload)
        let request = try makeRequest(path: "/api/motorcycles/\(motorcycleId)/maintenance/\(recordId)", method: "PUT", authorized: true, jsonBody: body)
        let data = try await performRequest(request)
        return try Self.decode(MaintenanceRecordResponse.self, from: data).maintenanceRecord
    }

    func deleteMaintenanceRecord(motorcycleId: Int, recordId: Int) async throws {
        let request = try makeRequest(path: "/api/motorcycles/\(motorcycleId)/maintenance/\(recordId)", method: "DELETE", authorized: true)
        _ = try await performRequest(request)
    }

    func createTorqueSpec(motorcycleId: Int, payload: [String: Any]) async throws -> TorqueSpec {
        let body = try JSONSerialization.data(withJSONObject: payload)
        let request = try makeRequest(path: "/api/motorcycles/\(motorcycleId)/torque-specs", method: "POST", authorized: true, jsonBody: body)
        let data = try await performRequest(request)
        return try Self.decode(TorqueSpecResponse.self, from: data).torqueSpec
    }

    func updateTorqueSpec(motorcycleId: Int, specId: Int, payload: [String: Any]) async throws -> TorqueSpec {
        let body = try JSONSerialization.data(withJSONObject: payload)
        let request = try makeRequest(path: "/api/motorcycles/\(motorcycleId)/torque-specs/\(specId)", method: "PUT", authorized: true, jsonBody: body)
        let data = try await performRequest(request)
        return try Self.decode(TorqueSpecResponse.self, from: data).torqueSpec
    }

    func deleteTorqueSpec(motorcycleId: Int, specId: Int) async throws {
        let request = try makeRequest(path: "/api/motorcycles/\(motorcycleId)/torque-specs/\(specId)", method: "DELETE", authorized: true)
        _ = try await performRequest(request)
    }

    func createMotorcycleDetail(motorcycleId: Int, payload: [String: Any]) async throws -> MotorcycleDetail {
        let body = try JSONSerialization.data(withJSONObject: payload)
        let request = try makeRequest(path: "/api/motorcycles/\(motorcycleId)/details", method: "POST", authorized: true, jsonBody: body)
        let data = try await performRequest(request)
        return try Self.decode(MotorcycleDetailResponse.self, from: data).motorcycleDetail
    }

    func updateMotorcycleDetail(motorcycleId: Int, detailId: Int, payload: [String: Any]) async throws -> MotorcycleDetail {
        let body = try JSONSerialization.data(withJSONObject: payload)
        let request = try makeRequest(path: "/api/motorcycles/\(motorcycleId)/details/\(detailId)", method: "PUT", authorized: true, jsonBody: body)
        let data = try await performRequest(request)
        return try Self.decode(MotorcycleDetailResponse.self, from: data).motorcycleDetail
    }

    func deleteMotorcycleDetail(motorcycleId: Int, detailId: Int) async throws {
        let request = try makeRequest(path: "/api/motorcycles/\(motorcycleId)/details/\(detailId)", method: "DELETE", authorized: true)
        _ = try await performRequest(request)
    }

    func createIssue(motorcycleId: Int, payload: [String: Any]) async throws -> Issue {
        let body = try JSONSerialization.data(withJSONObject: payload)
        let request = try makeRequest(path: "/api/motorcycles/\(motorcycleId)/issues", method: "POST", authorized: true, jsonBody: body)
        let data = try await performRequest(request)
        return try Self.decode(IssueResponse.self, from: data).issue
    }

    func updateIssue(motorcycleId: Int, issueId: Int, payload: [String: Any]) async throws -> Issue {
        let body = try JSONSerialization.data(withJSONObject: payload)
        let request = try makeRequest(path: "/api/motorcycles/\(motorcycleId)/issues/\(issueId)", method: "PUT", authorized: true, jsonBody: body)
        let data = try await performRequest(request)
        return try Self.decode(IssueResponse.self, from: data).issue
    }

    func deleteIssue(motorcycleId: Int, issueId: Int) async throws {
        let request = try makeRequest(path: "/api/motorcycles/\(motorcycleId)/issues/\(issueId)", method: "DELETE", authorized: true)
        _ = try await performRequest(request)
    }

    // MARK: - Parts inventory (user-scoped, not motorcycle-scoped)

    /// Prefix a server-relative image path ("/images/x.jpg") with the base URL.
    private func absolutizeImage(_ path: String?) -> String? {
        guard let path, !path.hasPrefix("http") else { return path }
        let base = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        return base + (path.hasPrefix("/") ? path : "/\(path)")
    }

    func fetchParts(since: String? = nil) async throws -> [Part] {
        let wrapper: PartListResponse = try await get(syncPath("/api/parts", since: since))
        AppLog.debug("Fetched \(wrapper.parts.count) parts")
        return wrapper.parts.map { part in
            var p = part
            p.image = absolutizeImage(p.image)
            return p
        }
    }

    func createPart(payload: [String: Any]) async throws -> Part {
        let body = try JSONSerialization.data(withJSONObject: payload)
        let request = try makeRequest(path: "/api/parts", method: "POST", authorized: true, jsonBody: body)
        let data = try await performRequest(request)
        return try Self.decode(PartResponse.self, from: data).part
    }

    func updatePart(partId: Int, payload: [String: Any]) async throws -> Part {
        let body = try JSONSerialization.data(withJSONObject: payload)
        let request = try makeRequest(path: "/api/parts/\(partId)", method: "PUT", authorized: true, jsonBody: body)
        let data = try await performRequest(request)
        return try Self.decode(PartResponse.self, from: data).part
    }

    func deletePart(partId: Int) async throws {
        let request = try makeRequest(path: "/api/parts/\(partId)", method: "DELETE", authorized: true)
        _ = try await performRequest(request)
    }

    /// Other users' shared parts (catalog + availability only). Online-only —
    /// results are not cached.
    func fetchPublicParts(query: String? = nil, seriesId: Int? = nil) async throws -> [PublicPart] {
        var items: [String] = []
        if let query, !query.isEmpty,
           let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            items.append("query=\(encoded)")
        }
        if let seriesId { items.append("seriesId=\(seriesId)") }
        let path = "/api/parts/public" + (items.isEmpty ? "" : "?" + items.joined(separator: "&"))
        let wrapper: PublicPartListResponse = try await get(path)
        return wrapper.parts.map { part in
            var p = part
            p.image = absolutizeImage(p.image)
            return p
        }
    }

    func fetchPartStocks(since: String? = nil) async throws -> [PartStock] {
        let wrapper: PartStockListResponse = try await get(syncPath("/api/part-stocks", since: since))
        return wrapper.partStocks
    }

    func createPartStock(payload: [String: Any]) async throws -> PartStock {
        let body = try JSONSerialization.data(withJSONObject: payload)
        let request = try makeRequest(path: "/api/part-stocks", method: "POST", authorized: true, jsonBody: body)
        let data = try await performRequest(request)
        return try Self.decode(PartStockResponse.self, from: data).partStock
    }

    func updatePartStock(stockId: Int, payload: [String: Any]) async throws -> PartStock {
        let body = try JSONSerialization.data(withJSONObject: payload)
        let request = try makeRequest(path: "/api/part-stocks/\(stockId)", method: "PUT", authorized: true, jsonBody: body)
        let data = try await performRequest(request)
        return try Self.decode(PartStockResponse.self, from: data).partStock
    }

    func deletePartStock(stockId: Int) async throws {
        let request = try makeRequest(path: "/api/part-stocks/\(stockId)", method: "DELETE", authorized: true)
        _ = try await performRequest(request)
    }

    func fetchPartConsumptions(since: String? = nil) async throws -> [PartConsumption] {
        let wrapper: PartConsumptionListResponse = try await get(syncPath("/api/part-consumptions", since: since))
        return wrapper.partConsumptions
    }

    func createPartConsumption(payload: [String: Any]) async throws -> PartConsumption {
        let body = try JSONSerialization.data(withJSONObject: payload)
        let request = try makeRequest(path: "/api/part-consumptions", method: "POST", authorized: true, jsonBody: body)
        let data = try await performRequest(request)
        return try Self.decode(PartConsumptionResponse.self, from: data).partConsumption
    }

    func updatePartConsumption(consumptionId: Int, payload: [String: Any]) async throws -> PartConsumption {
        let body = try JSONSerialization.data(withJSONObject: payload)
        let request = try makeRequest(path: "/api/part-consumptions/\(consumptionId)", method: "PUT", authorized: true, jsonBody: body)
        let data = try await performRequest(request)
        return try Self.decode(PartConsumptionResponse.self, from: data).partConsumption
    }

    func deletePartConsumption(consumptionId: Int) async throws {
        let request = try makeRequest(path: "/api/part-consumptions/\(consumptionId)", method: "DELETE", authorized: true)
        _ = try await performRequest(request)
    }

    func fetchStorageLocations(since: String? = nil) async throws -> [StorageLocation] {
        let wrapper: StorageLocationListResponse = try await get(syncPath("/api/storage-locations", since: since))
        return wrapper.storageLocations
    }

    func createStorageLocation(payload: [String: Any]) async throws -> StorageLocation {
        let body = try JSONSerialization.data(withJSONObject: payload)
        let request = try makeRequest(path: "/api/storage-locations", method: "POST", authorized: true, jsonBody: body)
        let data = try await performRequest(request)
        return try Self.decode(StorageLocationResponse.self, from: data).storageLocation
    }

    func updateStorageLocation(locationId: Int, payload: [String: Any]) async throws -> StorageLocation {
        let body = try JSONSerialization.data(withJSONObject: payload)
        let request = try makeRequest(path: "/api/storage-locations/\(locationId)", method: "PUT", authorized: true, jsonBody: body)
        let data = try await performRequest(request)
        return try Self.decode(StorageLocationResponse.self, from: data).storageLocation
    }

    func deleteStorageLocation(locationId: Int) async throws {
        let request = try makeRequest(path: "/api/storage-locations/\(locationId)", method: "DELETE", authorized: true)
        _ = try await performRequest(request)
    }

    // MARK: - Locations (GPS places, e.g. fuel stations)

    /// All user locations (garages, MFK stations, fuel stops, …), cached for
    /// offline display of location names on maintenance records.
    func fetchLocations() async throws -> [Location] {
        let wrapper: LocationListResponse = try await get("/api/locations")
        CacheStore.shared.save(wrapper.locations, key: CacheKey.locations)
        return wrapper.locations
    }

    /// Fuel stations (or other `types`) within `radiusMeters` of a point, nearest
    /// first. Backed by the `/api/locations` proximity params.
    func fetchNearbyLocations(
        latitude: Double, longitude: Double, radiusMeters: Double, types: String = "fuelStation"
    ) async throws -> [Location] {
        let path = String(
            format: "/api/locations?types=%@&lat=%.6f&lon=%.6f&radius=%.0f",
            types, latitude, longitude, radiusMeters
        )
        let wrapper: LocationListResponse = try await get(path)
        return wrapper.locations
    }

    func createLocation(
        name: String, type: String = "fuelStation", latitude: Double, longitude: Double
    ) async throws -> Location {
        let payload: [String: Any] = [
            "name": name, "type": type, "latitude": latitude, "longitude": longitude,
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let request = try makeRequest(path: "/api/locations", method: "POST", authorized: true, jsonBody: body)
        let data = try await performRequest(request)
        return try Self.decode(LocationResponse.self, from: data).location
    }

    /// Series lookup, cached like currencies.
    func fetchModelSeries() async throws -> [ModelSeries] {
        let wrapper: ModelSeriesListResponse = try await get("/api/model-series")
        CacheStore.shared.save(wrapper.modelSeries, key: CacheKey.modelSeries)
        return wrapper.modelSeries
    }

    func createModelSeries(name: String, manufacturer: String) async throws -> ModelSeries {
        let body = try JSONSerialization.data(withJSONObject: ["name": name, "manufacturer": manufacturer])
        let request = try makeRequest(path: "/api/model-series", method: "POST", authorized: true, jsonBody: body)
        let data = try await performRequest(request)
        return try Self.decode(ModelSeriesResponse.self, from: data).modelSeries
    }

    // MARK: - Passkey

    func fetchPasskeyLoginOptions(username: String?) async throws -> PasskeyOptionsResponse {
        var path = "/api/auth/passkey/login-options"
        if let username,
           let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "?username=\(encoded)"
        }
        return try await get(path, authorized: false)
    }

    func verifyPasskeyLogin(challengeId: String, response: PasskeyResponse) async throws -> String {
        let body = try JSONEncoder().encode(PasskeyVerifyRequest(challengeId: challengeId, response: response))
        let request = try makeRequest(path: "/api/auth/passkey/login-verify", method: "POST", authorized: false, jsonBody: body)
        let data = try await performRequest(request)
        let loginResponse = try Self.decode(LoginResponse.self, from: data)
        saveToken(loginResponse.token)
        return loginResponse.token
    }
}
