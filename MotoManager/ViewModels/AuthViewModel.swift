import Foundation
import Combine

@MainActor
class AuthViewModel: ObservableObject {
    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    init() {
        checkAuth()
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
    
    func logout() {
        NetworkManager.shared.deleteToken()
        isAuthenticated = false
    }
}
