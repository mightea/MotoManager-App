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
    /// Sidecar rig — gates the sidecar-wheel tire pressure UI (optional so
    /// old cached blobs without the field still decode).
    let hasSidecar: Bool?
    let firstRegistration: String?
    let initialOdo: Int
    let manualOdo: Int?
    let purchaseDate: String?
    let purchasePrice: Double?
    let normalizedPurchasePrice: Double?
    let currencyCode: String?
    let fuelTankSize: Double?
    /// Model-series link for derived part compatibility (optional so old
    /// cached blobs without the field still decode).
    let seriesId: Int?

    // Stats if using MotorcycleWithStats
    let openIssues: Int?
    let maintenanceCount: Int?
    let latestOdo: Int?

    enum CodingKeys: String, CodingKey {
        case id, make, model
        case modelYear = "fabricationDate"
        case userId, vin, engineNumber, vehicleNr, numberPlate, image, isVeteran, isArchived, hasSidecar, firstRegistration, initialOdo, manualOdo, purchaseDate, purchasePrice, normalizedPurchasePrice, currencyCode, fuelTankSize, seriesId
        case openIssues, maintenanceCount, latestOdo
    }
    
    static let mock = Motorcycle(
        id: 1,
        make: "BMW",
        model: "R 1250 GS",
        modelYear: "2023",
        userId: 1,
        vin: "W1234567890",
        engineNumber: "E123456",
        vehicleNr: "V123",
        numberPlate: "M-GS 1250",
        image: nil,
        isVeteran: false,
        isArchived: false,
        hasSidecar: false,
        firstRegistration: "2023-01-01",
        initialOdo: 0,
        manualOdo: nil,
        purchaseDate: "2023-01-01",
        purchasePrice: 18000,
        normalizedPurchasePrice: 18000,
        currencyCode: "EUR",
        fuelTankSize: 20.0,
        seriesId: nil,
        openIssues: 1,
        maintenanceCount: 5,
        latestOdo: 12500
    )
}
