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
    
    // Internal request helper to handle 401s
    private func performRequest(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        if httpResponse.statusCode == 401 {
            NotificationCenter.default.post(name: NetworkManager.unauthorizedNotification, object: nil)
            throw NSError(domain: "AuthError", code: 401, userInfo: [NSLocalizedDescriptionKey: "Session expired"])
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        
        return data
    }
    
    func login(credentials: LoginRequest) async throws -> String {
        guard let url = URL(string: "\(baseURL)/api/auth/login") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(credentials)
        
        let data = try await performRequest(request)
        
        if let jsonString = String(data: data, encoding: .utf8) {
            print("Login Response: \(jsonString)")
        }
        
        let loginResponse = try JSONDecoder().decode(LoginResponse.self, from: data)
        saveToken(loginResponse.token)
        return loginResponse.token
    }
    
    func fetchMotorcycles() async throws -> [Motorcycle] {
        guard let url = URL(string: "\(baseURL)/api/motorcycles") else {
            throw URLError(.badURL)
        }
        
        guard let token = getToken() else {
            throw NSError(domain: "AuthError", code: 401, userInfo: [NSLocalizedDescriptionKey: "No token found"])
        }
        
        var request = URLRequest(url: url)
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let data = try await performRequest(request)
        
        if let jsonString = String(data: data, encoding: .utf8) {
            print("Fetch Motorcycles Response: \(jsonString)")
        }
        
        let decoder = JSONDecoder()
        let responseWrapper = try decoder.decode(MotorcycleListResponse.self, from: data)
        
        // Prepend baseURL to each image path if it's just a path
        let motorcycles = responseWrapper.motorcycles.map { m in
            var moto = m
            if let imagePath = moto.image {
                if !imagePath.hasPrefix("http") {
                    let base = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
                    let path = imagePath.hasPrefix("/") ? imagePath : "/\(imagePath)"
                    moto.image = base + path
                }
            }
            return moto
        }

        CacheStore.shared.save(motorcycles, key: CacheKey.motorcycles)
        return motorcycles
    }
    
    func fetchMaintenance(motorcycleId: Int) async throws -> [MaintenanceRecord] {
        guard let url = URL(string: "\(baseURL)/api/motorcycles/\(motorcycleId)/maintenance") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        if let token = getToken() {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        let data = try await performRequest(request)
        
        if let jsonString = String(data: data, encoding: .utf8) {
            print("Fetch Maintenance Response for ID \(motorcycleId): \(jsonString)")
        }
        
        struct MaintenanceListResponse: Codable {
            let maintenanceRecords: [MaintenanceRecord]
        }
        
        let wrapper = try JSONDecoder().decode(MaintenanceListResponse.self, from: data)
        CacheStore.shared.save(wrapper.maintenanceRecords, key: CacheKey.maintenance(motorcycleId: motorcycleId))
        return wrapper.maintenanceRecords
    }
    
    func fetchTorqueSpecs(motorcycleId: Int) async throws -> [TorqueSpec] {
        guard let url = URL(string: "\(baseURL)/api/motorcycles/\(motorcycleId)/torque-specs") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        if let token = getToken() {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        let data = try await performRequest(request)
        
        if let jsonString = String(data: data, encoding: .utf8) {
            print("Fetch Torque Specs Response for ID \(motorcycleId): \(jsonString)")
        }
        
        struct TorqueSpecListResponse: Codable {
            let torqueSpecs: [TorqueSpec]
        }
        
        let wrapper = try JSONDecoder().decode(TorqueSpecListResponse.self, from: data)
        CacheStore.shared.save(wrapper.torqueSpecs, key: CacheKey.torque(motorcycleId: motorcycleId))
        return wrapper.torqueSpecs
    }
    
    func fetchDocuments() async throws -> [Document] {
        guard let url = URL(string: "\(baseURL)/api/documents") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        if let token = getToken() {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        let data = try await performRequest(request)
        
        if let jsonString = String(data: data, encoding: .utf8) {
            print("Fetch Documents Response: \(jsonString)")
        }
        
        struct DocWrapper: Codable {
            let docs: [Document]
        }
        
        let wrapper = try JSONDecoder().decode(DocWrapper.self, from: data)
        CacheStore.shared.save(wrapper.docs, key: CacheKey.documents)
        return wrapper.docs
    }
    
    /// Authenticated GET for arbitrary binary blobs (documents, attachments).
    func fetchBlob(url: String) async throws -> Data {
        guard let url = URL(string: url) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        if let token = getToken() {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        return try await performRequest(request)
    }
    
    func createMaintenance(motorcycleId: Int, record: [String: Any]) async throws {
        guard let url = URL(string: "\(baseURL)/api/motorcycles/\(motorcycleId)/maintenance") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = getToken() {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: record)
        
        _ = try await performRequest(request)
    }
    
    // MARK: - Passkey Methods
    
    func fetchPasskeyLoginOptions(username: String?) async throws -> PasskeyOptionsResponse {
        var urlString = "\(baseURL)/api/auth/passkey/login/options"
        if let username = username {
            urlString += "?username=\(username)"
        }
        
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        let request = URLRequest(url: url)
        let data = try await performRequest(request)
        return try JSONDecoder().decode(PasskeyOptionsResponse.self, from: data)
    }
    
    func verifyPasskeyLogin(challengeId: String, response: PasskeyResponse) async throws -> String {
        guard let url = URL(string: "\(baseURL)/api/auth/passkey/login/verify") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = PasskeyVerifyRequest(challengeId: challengeId, response: response)
        request.httpBody = try JSONEncoder().encode(body)
        
        let data = try await performRequest(request)
        let loginResponse = try JSONDecoder().decode(LoginResponse.self, from: data)
        saveToken(loginResponse.token)
        return loginResponse.token
    }
}
