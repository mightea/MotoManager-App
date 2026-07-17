import Foundation

/// Thin wrappers for the list-shaped API responses. Hoisted out of the
/// individual `NetworkManager` fetch methods so the decoding shape lives with
/// the models it wraps. (`MotorcycleListResponse` keeps its own file.)

struct MaintenanceListResponse: Codable {
    let maintenanceRecords: [MaintenanceRecord]
}

struct TorqueSpecListResponse: Codable {
    let torqueSpecs: [TorqueSpec]
}

struct MotorcycleDetailListResponse: Codable {
    let motorcycleDetails: [MotorcycleDetail]
}

struct DocumentListResponse: Codable {
    let docs: [Document]
}

struct CurrencyListResponse: Codable {
    let currencies: [Currency]
}

struct IssueListResponse: Codable {
    let issues: [Issue]
}

struct PartListResponse: Codable {
    let parts: [Part]
}

struct PublicPartListResponse: Codable {
    let parts: [PublicPart]
}

struct PartStockListResponse: Codable {
    let partStocks: [PartStock]
}

struct PartConsumptionListResponse: Codable {
    let partConsumptions: [PartConsumption]
}

struct StorageLocationListResponse: Codable {
    let storageLocations: [StorageLocation]
}

struct ModelSeriesListResponse: Codable {
    let modelSeries: [ModelSeries]
}

// Single-item create/update responses.
struct MaintenanceRecordResponse: Codable {
    let maintenanceRecord: MaintenanceRecord
}

struct TorqueSpecResponse: Codable {
    let torqueSpec: TorqueSpec
}

struct MotorcycleDetailResponse: Codable {
    let motorcycleDetail: MotorcycleDetail
}

struct IssueResponse: Codable {
    let issue: Issue
}

struct PartResponse: Codable {
    let part: Part
}

struct PartStockResponse: Codable {
    let partStock: PartStock
}

struct PartConsumptionResponse: Codable {
    let partConsumption: PartConsumption
}

struct StorageLocationResponse: Codable {
    let storageLocation: StorageLocation
}

struct ModelSeriesResponse: Codable {
    let modelSeries: ModelSeries
}
