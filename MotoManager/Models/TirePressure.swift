import Foundation

/// Recommended tire pressures for one motorcycle — one optional front/rear
/// pair per riding configuration (solo / with passenger / offroad), plus an
/// optional sidecar-wheel value inside each configuration. Values are stored
/// canonically in bar; `preferredUnit` remembers what the user typed.
/// 1:1 with the motorcycle (`PUT`/`DELETE /api/motorcycles/{id}/tire-pressure`).
struct TirePressure: Codable, Equatable {
    let id: Int
    let motorcycleId: Int
    let frontBar: Double?
    let rearBar: Double?
    let frontPassengerBar: Double?
    let rearPassengerBar: Double?
    let frontOffroadBar: Double?
    let rearOffroadBar: Double?
    let sidecarBar: Double?
    let sidecarPassengerBar: Double?
    let sidecarOffroadBar: Double?
    let preferredUnit: String
    let createdAt: String
    let updatedAt: String
}

struct TirePressureResponse: Codable {
    let tirePressure: TirePressure?
}

/// The riding configurations a pressure set can be recorded for.
enum PressureConfig: String, CaseIterable, Identifiable {
    case solo, passenger, offroad

    var id: String { rawValue }

    var label: String {
        switch self {
        case .solo: return "Solo"
        case .passenger: return "Sozius"
        case .offroad: return "Offroad"
        }
    }
}

extension TirePressure {
    /// Front / rear / sidecar bar values of one configuration.
    func values(for config: PressureConfig) -> (front: Double?, rear: Double?, sidecar: Double?) {
        switch config {
        case .solo: return (frontBar, rearBar, sidecarBar)
        case .passenger: return (frontPassengerBar, rearPassengerBar, sidecarPassengerBar)
        case .offroad: return (frontOffroadBar, rearOffroadBar, sidecarOffroadBar)
        }
    }

    /// Configurations that actually hold values, in display order.
    var recordedConfigs: [PressureConfig] {
        PressureConfig.allCases.filter {
            let v = values(for: $0)
            return v.front != nil || v.rear != nil
        }
    }

    var hasSidecarValues: Bool {
        recordedConfigs.contains { values(for: $0).sidecar != nil }
    }
}

/// bar ⇆ psi conversion and display formatting, mirroring the webapp
/// (`app/utils/pressure.ts`): bar with one decimal, psi as an integer.
enum PressureUnitFormat {
    static let psiPerBar = 14.5037738

    static func display(bar: Double, unit: String) -> String {
        unit == "psi"
            ? "\(Int((bar * psiPerBar).rounded())) psi"
            : String(format: "%.1f bar", bar)
    }

    /// The converted-unit twin, e.g. "≈ 32 psi" next to a bar value.
    static func secondary(bar: Double, unit: String) -> String {
        unit == "psi"
            ? String(format: "≈ %.1f bar", bar)
            : "≈ \(Int((bar * psiPerBar).rounded())) psi"
    }

    /// Editable field text for a bar value in the given unit.
    static func fieldText(bar: Double, unit: String) -> String {
        if unit == "psi" {
            let psi = bar * psiPerBar
            return psi == psi.rounded() ? String(Int(psi)) : String(format: "%.1f", psi)
        }
        return bar == bar.rounded() ? String(format: "%.1f", bar) : String(format: "%.2f", bar).replacingOccurrences(of: "0$", with: "", options: .regularExpression)
    }

    /// Parse a user-typed value in the given unit to canonical bar.
    static func parseToBar(_ text: String, unit: String) -> Double? {
        guard let value = Double(text.replacingOccurrences(of: ",", with: ".")), value > 0 else { return nil }
        return unit == "psi" ? value / psiPerBar : value
    }
}
