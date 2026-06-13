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

struct DocumentListResponse: Codable {
    let docs: [Document]
}

struct CurrencyListResponse: Codable {
    let currencies: [Currency]
}
