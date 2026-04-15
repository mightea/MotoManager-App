import Foundation

class NetworkManager {
    static let shared = NetworkManager()
    
    let baseURL = "https://moto-api.herrmann.ltd"
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
    
    func login(credentials: LoginRequest) async throws -> String {
        guard let url = URL(string: "\(baseURL)/api/auth/login") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(credentials)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let jsonString = String(data: data, encoding: .utf8) {
            print("Login Response: \(jsonString)")
        }
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
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
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let jsonString = String(data: data, encoding: .utf8) {
            print("Fetch Motorcycles Response: \(jsonString)")
        }
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        let decoder = JSONDecoder()
        let responseWrapper = try decoder.decode(MotorcycleListResponse.self, from: data)
        
        // Prepend baseURL to each image path
        let motorcycles = responseWrapper.motorcycles.map { m in
            var moto = m
            if let imagePath = moto.image {
                moto.image = baseURL + imagePath
            }
            return moto
        }
        
        return motorcycles
    }
    
    func fetchImage(url: String) async throws -> Data {
        guard let url = URL(string: url) else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        if let token = getToken() {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        return data
    }
}
