import Foundation

/// User-level settings DTO (`GET /api/settings` → `settings`). Carries the
/// service-interval rules the webapp lets the user configure: years per
/// item, and optional km limits. Mirrors the backend `userSettings` table.
struct UserSettings: Codable, Equatable {
    var tireInterval: Int
    var batteryLithiumInterval: Int
    var batteryDefaultInterval: Int
    var engineOilInterval: Int
    var gearboxOilInterval: Int
    var finalDriveOilInterval: Int
    var finalDriveGearboxOilInterval: Int
    var forkOilInterval: Int
    var brakeFluidInterval: Int
    var coolantInterval: Int
    var chainInterval: Int
    var tireKmInterval: Int?
    var engineOilKmInterval: Int?
    var gearboxOilKmInterval: Int?
    var finalDriveOilKmInterval: Int?
    var finalDriveGearboxOilKmInterval: Int?
    var forkOilKmInterval: Int?
    var brakeFluidKmInterval: Int?
    var coolantKmInterval: Int?
    var chainKmInterval: Int?
    var minKmPerYear: Int?

    /// The webapp's `DEFAULT_MAINTENANCE_INTERVALS`, used until the server
    /// settings have been fetched once.
    static let defaults = UserSettings(
        tireInterval: 8,
        batteryLithiumInterval: 10,
        batteryDefaultInterval: 6,
        engineOilInterval: 2,
        gearboxOilInterval: 2,
        finalDriveOilInterval: 2,
        finalDriveGearboxOilInterval: 2,
        forkOilInterval: 4,
        brakeFluidInterval: 4,
        coolantInterval: 4,
        chainInterval: 1,
        tireKmInterval: nil,
        engineOilKmInterval: nil,
        gearboxOilKmInterval: nil,
        finalDriveOilKmInterval: nil,
        finalDriveGearboxOilKmInterval: nil,
        forkOilKmInterval: nil,
        brakeFluidKmInterval: nil,
        coolantKmInterval: nil,
        chainKmInterval: nil,
        minKmPerYear: nil
    )

    /// Years + optional km for a fluid subtype, keyed like the records'
    /// `fluidType`.
    func fluidInterval(_ fluidType: String) -> (years: Int, kms: Int?)? {
        switch fluidType {
        case "engineoil": (engineOilInterval, engineOilKmInterval)
        case "gearboxoil": (gearboxOilInterval, gearboxOilKmInterval)
        case "finaldriveoil": (finalDriveOilInterval, finalDriveOilKmInterval)
        case "finaldrivegearboxoil": (finalDriveGearboxOilInterval, finalDriveGearboxOilKmInterval)
        case "forkoil": (forkOilInterval, forkOilKmInterval)
        case "brakefluid": (brakeFluidInterval, brakeFluidKmInterval)
        case "coolant": (coolantInterval, coolantKmInterval)
        default: nil
        }
    }

    /// JSON body for `PUT /api/settings` — every field, so the server state
    /// equals what the editor shows (absent fields keep their server value,
    /// which would otherwise silently resurrect a cleared km limit).
    var updatePayload: [String: Any] {
        func km(_ value: Int?) -> Any { value.map { $0 as Any } ?? NSNull() }
        return [
            "tireInterval": tireInterval,
            "batteryLithiumInterval": batteryLithiumInterval,
            "batteryDefaultInterval": batteryDefaultInterval,
            "engineOilInterval": engineOilInterval,
            "gearboxOilInterval": gearboxOilInterval,
            "finalDriveOilInterval": finalDriveOilInterval,
            "finalDriveGearboxOilInterval": finalDriveGearboxOilInterval,
            "forkOilInterval": forkOilInterval,
            "brakeFluidInterval": brakeFluidInterval,
            "coolantInterval": coolantInterval,
            "chainInterval": chainInterval,
            "tireKmInterval": km(tireKmInterval),
            "engineOilKmInterval": km(engineOilKmInterval),
            "gearboxOilKmInterval": km(gearboxOilKmInterval),
            "finalDriveOilKmInterval": km(finalDriveOilKmInterval),
            "finalDriveGearboxOilKmInterval": km(finalDriveGearboxOilKmInterval),
            "forkOilKmInterval": km(forkOilKmInterval),
            "brakeFluidKmInterval": km(brakeFluidKmInterval),
            "coolantKmInterval": km(coolantKmInterval),
            "chainKmInterval": km(chainKmInterval),
        ]
    }
}

struct UserSettingsResponse: Codable {
    let settings: UserSettings
}
