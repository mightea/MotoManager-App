import Foundation

nonisolated struct MaintenanceRecord: Codable, Identifiable {
    let id: Int
    let date: String
    let odo: Int
    let motorcycleId: Int
    let cost: Double?
    let normalizedCost: Double?
    let currency: String?
    let description: String?
    let recordType: String // "oil", "fuel", "tire", etc.
    let brand: String?
    let model: String?
    let tirePosition: String?
    let tireSize: String?
    let dotCode: String?
    let batteryType: String?
    let fluidType: String?
    let viscosity: String?
    let oilType: String?
    let inspectionLocation: String?
    let locationId: Int?
    let fuelType: String?
    let fuelAmount: Double?
    let pricePerUnit: Double?
    let latitude: Double?
    let longitude: Double?
    let locationName: String?
    let fuelConsumption: Double?
    let tripDistance: Double?
    let fuelAdditiveAdded: Bool?
    let leadSubstituteAdded: Bool?
    let summary: String?
    let parentId: Int?
    // Sync metadata (server-provided; see backend migration 011).
    let clientId: String?
    let updatedAt: String?
    let deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, date, odo, motorcycleId, cost, normalizedCost, currency, description, summary
        case recordType = "type"
        case brand, model, tirePosition, tireSize, dotCode, batteryType, fluidType, viscosity, oilType, inspectionLocation, locationId, fuelType, fuelAmount, pricePerUnit, latitude, longitude, locationName, fuelConsumption, tripDistance, fuelAdditiveAdded, leadSubstituteAdded, parentId
        case clientId, updatedAt, deletedAt
    }
}

struct TorqueSpec: Codable, Identifiable {
    let id: Int
    let motorcycleId: Int
    let category: String
    let name: String
    let torque: Double
    let torqueEnd: Double?
    let variation: Double?
    let toolSize: String?
    let description: String?
    let unverified: Bool?
    let createdAt: String
    // Sync metadata (server-provided; see backend migration 011).
    let clientId: String?
    let updatedAt: String?
    let deletedAt: String?
}

/// Free-form Title/Value pair per motorcycle (e.g. spark plug brand/model).
struct MotorcycleDetail: Codable, Identifiable {
    let id: Int
    let motorcycleId: Int
    let title: String
    let value: String
    let createdAt: String
    // Sync metadata (server-provided).
    let clientId: String?
    let updatedAt: String?
    let deletedAt: String?
}

struct Document: Codable, Identifiable {
    let id: Int
    let title: String
    let filePath: String
    let previewPath: String?
    let uploadedBy: String?
    let ownerId: Int?
    let isPrivate: Bool
    let createdAt: String
    let updatedAt: String
    let motorcycleIds: [Int]?
}
