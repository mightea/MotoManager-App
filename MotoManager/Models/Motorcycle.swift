import Foundation

struct Motorcycle: Codable, Identifiable {
    let id: Int
    let make: String
    let model: String
    let modelYear: String?
    let userId: Int
    let vin: String?
    let engineNumber: String?
    let vehicleNr: String?
    let numberPlate: String?
    var image: String?
    let isVeteran: Bool
    let isArchived: Bool
    let firstRegistration: String?
    let initialOdo: Int
    let manualOdo: Int?
    let purchaseDate: String?
    let purchasePrice: Double?
    let normalizedPurchasePrice: Double?
    let currencyCode: String?
    let fuelTankSize: Double?
    
    // Stats if using MotorcycleWithStats
    let openIssues: Int?
    let maintenanceCount: Int?
    let latestOdo: Int?
    
    enum CodingKeys: String, CodingKey {
        case id, make, model
        case modelYear = "fabricationDate"
        case userId, vin, engineNumber, vehicleNr, numberPlate, image, isVeteran, isArchived, firstRegistration, initialOdo, manualOdo, purchaseDate, purchasePrice, normalizedPurchasePrice, currencyCode, fuelTankSize
        case openIssues, maintenanceCount, latestOdo
    }
}
