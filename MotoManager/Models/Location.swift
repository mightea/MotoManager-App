import Foundation

/// A user-scoped place stored on the backend (`/api/locations`). Fuel stations
/// use `type == "fuelStation"` and carry GPS coordinates. Only the fields the app
/// needs are decoded; the server also returns `userId`/`createdAt`/`updatedAt`.
struct Location: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let type: String
    let latitude: Double?
    let longitude: Double?
}

struct LocationListResponse: Codable {
    let locations: [Location]
}

struct LocationResponse: Codable {
    let location: Location
}
