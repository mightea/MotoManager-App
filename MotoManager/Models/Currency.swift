import Foundation

struct Currency: Codable, Identifiable, Hashable {
    let id: Int
    let code: String
    let symbol: String
    let label: String?
    let conversionFactor: Double
    let createdAt: String
}
