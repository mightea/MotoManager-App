import Foundation

extension SDMaintenanceRecord {
    /// German display labels for the `fluidType` sub-kinds of a "fluid" record.
    /// Mirrors the webapp/backend `fluidTypeLabels` — keep the two in sync.
    static let fluidTypeLabels: [String: String] = [
        "engineoil": "Motoröl",
        "gearboxoil": "Getriebeöl",
        "finaldriveoil": "Kardanöl",
        "finaldrivegearboxoil": "Hinterachsgetriebeöl",
        "forkoil": "Gabelöl",
        "brakefluid": "Bremsflüssigkeit",
        "coolant": "Kühlflüssigkeit",
    ]

    /// The localized label for a fluid record's specific type (e.g. "Motoröl"),
    /// or `nil` when this isn't a fluid record or the type is unknown. Callers
    /// fall back to the coarse maintenance-kind label.
    var fluidTypeLabel: String? {
        guard recordType == "fluid", let type = fluidType else { return nil }
        return Self.fluidTypeLabels[type]
    }
}
