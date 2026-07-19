import SwiftUI

/// The canonical maintenance category system, mirroring the webapp
/// (`app/utils/maintenance.ts` + `TYPE_TONE` in `maintenance-list.tsx`).
/// Single source of truth for labels, icons and tints — used by the service
/// list, the detail page, the add form and the intervals engine.
///
/// Legacy record types written by older iOS builds (`oil`, `tires`, `brakes`,
/// `coolant`, …) are folded into canonical categories via `normalize` — purely
/// for display; stored data is never rewritten.
enum MaintenanceCategory: String, CaseIterable, Identifiable {
    case tire, battery, brakepad, brakerotor, chain, fluid
    case general, repair, service, inspection, location, fuel

    var id: String { rawValue }

    /// German labels, verbatim from the webapp's `maintenanceTypeLabels`.
    var label: String {
        switch self {
        case .tire: "Reifenwechsel"
        case .battery: "Batterie"
        case .brakepad: "Bremsbeläge"
        case .brakerotor: "Bremsscheibe"
        case .chain: "Kette"
        case .fluid: "Flüssigkeit"
        case .general: "Allgemein"
        case .repair: "Reparatur"
        case .service: "Service"
        case .inspection: "MFK"
        case .location: "Standort"
        case .fuel: "Tanken"
        }
    }

    /// SF Symbol closest to the webapp's lucide icon per type.
    var icon: String {
        switch self {
        case .tire: "circle.dashed"
        case .battery: "minus.plus.batteryblock.fill"
        case .brakepad: "square.stack.3d.up.fill"
        case .brakerotor: "record.circle"
        case .chain: "link"
        case .fluid: "drop.fill"
        case .repair: "hammer.fill"
        case .service: "list.clipboard.fill"
        case .inspection: "checkmark.seal.fill"
        case .location: "mappin.and.ellipse"
        case .fuel: "fuelpump.fill"
        case .general: "wrench.and.screwdriver.fill"
        }
    }

    /// Accent tint per category, mapped from the webapp's `TYPE_TONE` onto the
    /// app's dark glass palette. Icon tiles use `tint.opacity(0.15)` as fill.
    var tint: Color {
        switch self {
        case .service: Theme.Colors.primary
        case .inspection, .fluid, .location: Color(hex: 0x0EA5E9)
        case .brakepad, .brakerotor: Theme.Colors.accent
        case .battery, .repair: Color(hex: 0xF59E0B)
        case .fuel: .green
        case .tire, .chain: Color(hex: 0x94A3B8)
        case .general: .white.opacity(0.6)
        }
    }

    // MARK: - Normalization

    /// Maps a stored `recordType` (canonical or legacy) to its display
    /// category plus an inferred `fluidType` for legacy oil/fluid types.
    /// An explicit `fluidType` on the record always wins over the inference.
    static func normalize(type: String, fluidType: String? = nil) -> (category: MaintenanceCategory, fluidType: String?) {
        let lowered = type.lowercased()
        if let canonical = MaintenanceCategory(rawValue: lowered) {
            return (canonical, fluidType)
        }
        switch lowered {
        case "oil", "engineoil": return (.fluid, fluidType ?? "engineoil")
        case "gearboxoil": return (.fluid, fluidType ?? "gearboxoil")
        case "finaldriveoil": return (.fluid, fluidType ?? "finaldriveoil")
        case "finaldrivegearboxoil": return (.fluid, fluidType ?? "finaldrivegearboxoil")
        case "forkoil": return (.fluid, fluidType ?? "forkoil")
        case "brakefluid": return (.fluid, fluidType ?? "brakefluid")
        case "coolant": return (.fluid, fluidType ?? "coolant")
        case "tires": return (.tire, fluidType)
        case "brakes": return (.brakepad, fluidType)
        case "battery", "electric": return (.battery, fluidType)
        default: return (.general, fluidType)
        }
    }

    // MARK: - Sub-label maps (webapp `maintenance.ts`)

    static let tirePositionLabels: [String: String] = [
        "front": "Vorne",
        "rear": "Hinten",
        "sidecar": "Beiwagen",
    ]

    static let batteryTypeLabels: [String: String] = [
        "lead-acid": "Blei-Säure",
        "gel": "Gel",
        "agm": "AGM",
        "lithium-ion": "Lithium-Ionen",
        "other": "Andere",
    ]

    static let oilTypeLabels: [String: String] = [
        "synthetic": "Synthetisch",
        "semi-synthetic": "Teilsynthetisch",
        "mineral": "Mineralisch",
    ]

    static let brakeTypeLabels: [String: String] = [
        "disc": "Scheibenbremse",
        "drum": "Trommelbremse",
    ]

    static let fuelTypeLabels: [String: String] = [
        "95E10": "Bleifrei 95",
        "98E5": "Super Plus",
        "Diesel": "Diesel",
    ]
}

extension SDMaintenanceRecord {
    /// The record's normalized display category (legacy types folded in).
    var category: MaintenanceCategory {
        MaintenanceCategory.normalize(type: recordType, fluidType: fluidType).category
    }

    /// The record's effective fluid type — explicit field, or inferred from a
    /// legacy oil/fluid `recordType`.
    var effectiveFluidType: String? {
        MaintenanceCategory.normalize(type: recordType, fluidType: fluidType).fluidType
    }
}
