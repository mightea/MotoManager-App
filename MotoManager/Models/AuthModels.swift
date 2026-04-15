import Foundation

struct LoginRequest: Codable {
    let identifier: String
    let password: String
}

struct LoginResponse: Codable {
    let token: String
}
