import Foundation

// DTOs for the parts inventory (backend migration 012). `Part` carries the
// server-derived inventory meta (`onHand`, `stockCount`) and the fitment
// (`seriesIds`) embedded by the API; on-device the SwiftData models re-derive
// on-hand locally so offline writes stay consistent.

struct Part: Codable, Identifiable {
    let id: Int
    let userId: Int
    let partNumber: String
    let name: String
    let manufacturer: String
    let description: String?
    let isPublic: Bool
    /// Absolutized by NetworkManager (server sends "/images/<uuid>.jpg").
    var image: String?
    let createdAt: String
    let seriesIds: [Int]
    let onHand: Int
    let stockCount: Int
    // Sync metadata (server-provided; see backend migration 012).
    let clientId: String?
    let updatedAt: String?
    let deletedAt: String?
}

struct PartStock: Codable, Identifiable {
    let id: Int
    let partId: Int
    let quantity: Int
    let price: Double?
    let currency: String?
    let normalizedPrice: Double?
    let purchaseDate: String?
    let storageLocationId: Int?
    let notes: String?
    let createdAt: String
    // Sync metadata (server-provided; see backend migration 012).
    let clientId: String?
    let updatedAt: String?
    let deletedAt: String?
}

struct PartConsumption: Codable, Identifiable {
    let id: Int
    let partId: Int
    let maintenanceRecordId: Int?
    let quantity: Int
    let date: String
    let notes: String?
    let createdAt: String
    // Sync metadata (server-provided; see backend migration 012).
    let clientId: String?
    let updatedAt: String?
    let deletedAt: String?
}

struct StorageLocation: Codable, Identifiable {
    let id: Int
    let userId: Int
    let name: String
    let parentId: Int?
    let createdAt: String
    // Sync metadata (server-provided; see backend migration 012).
    let clientId: String?
    let updatedAt: String?
    let deletedAt: String?
}

/// Series lookup (global seed rows have `userId == nil`; custom entries carry
/// the creator's id). Fetched and cached like `Currency`.
struct ModelSeries: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let manufacturer: String
    let userId: Int?
    let createdAt: String

    /// "R 1150 GS" for BMW (the common case), "Yamaha XSR 700" otherwise.
    var displayName: String {
        manufacturer == "BMW" ? name : "\(manufacturer) \(name)"
    }
}

/// Another user's shared part as returned by `/api/parts/public`. The server
/// whitelists catalog data + availability; prices/locations never appear.
struct PublicPart: Codable, Identifiable {
    let id: Int
    let partNumber: String
    let name: String
    let manufacturer: String
    let description: String?
    /// Absolutized by NetworkManager (server sends "/images/<uuid>.jpg").
    var image: String?
    let seriesIds: [Int]
    let ownerName: String
    let hasStock: Bool
    let totalQuantity: Int
}
