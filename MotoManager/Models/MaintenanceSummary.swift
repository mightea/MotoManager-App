import Foundation

/// Builds the concise German one-liner for a maintenance record, mirroring the
/// webapp's `summarizeMaintenanceRecord` (`app/utils/maintenance.ts`).
/// Operates on the normalized category so legacy record types summarize the
/// same way canonical ones do.
enum MaintenanceSummarizer {
    static func summarize(_ record: SDMaintenanceRecord, locations: [Location] = []) -> String {
        let category = record.category
        var parts: [String] = []

        switch category {
        case .tire:
            let brandModel = [record.brand, record.model].compactMap { $0 }.joined(separator: " ")
            if !brandModel.isEmpty { parts.append(brandModel) }
            if let position = record.tirePosition {
                parts.append("(\(MaintenanceCategory.tirePositionLabels[position] ?? position))")
            }
            if let size = record.tireSize, !size.isEmpty { parts.append(size) }
            if let dot = record.dotCode, !dot.isEmpty {
                parts.append("DOT \(Self.formattedDot(dot))")
            }
            return parts.isEmpty ? "Reifenwechsel" : parts.joined(separator: " ")

        case .battery:
            let brandModel = [record.brand, record.model].compactMap { $0 }.joined(separator: " ")
            if !brandModel.isEmpty { parts.append(brandModel) }
            if let type = record.batteryType {
                parts.append("(\(MaintenanceCategory.batteryTypeLabels[type] ?? type))")
            }
            return parts.isEmpty ? "Batteriewechsel" : parts.joined(separator: " ")

        case .fluid:
            if let fluidType = record.effectiveFluidType {
                parts.append(SDMaintenanceRecord.fluidTypeLabels[fluidType] ?? fluidType)
            }
            if let brand = record.brand, !brand.isEmpty { parts.append(brand) }
            if let viscosity = record.viscosity, !viscosity.isEmpty { parts.append(viscosity) }
            return parts.isEmpty ? "Flüssigkeitswechsel" : parts.joined(separator: " ")

        case .inspection:
            if let loc = locations.first(where: { $0.id == record.locationId }) {
                return "MFK bei \(loc.name)"
            }
            return "MFK"

        case .location:
            if let loc = locations.first(where: { $0.id == record.locationId }) {
                return "Standortwechsel nach \(loc.name)"
            }
            return "Standortwechsel"

        case .fuel:
            if let amount = record.fuelAmount, amount > 0 {
                parts.append(String(format: "%.0fL", amount))
            }
            if let fuelType = record.fuelType, !fuelType.isEmpty {
                parts.append(MaintenanceCategory.fuelTypeLabels[fuelType] ?? fuelType)
            }
            if let loc = locations.first(where: { $0.id == record.locationId }) {
                parts.append("@ \(loc.name)")
            }
            var stats: [String] = []
            if let consumption = record.fuelConsumption {
                stats.append(String(format: "%.2f L/100km", consumption))
            }
            if let trip = record.tripDistance {
                stats.append("\(Int(trip)) km")
            }
            if !stats.isEmpty { parts.append("(\(stats.joined(separator: ", ")))") }
            return parts.isEmpty ? "Tanken" : parts.joined(separator: " ")

        case .brakepad, .brakerotor, .chain, .repair, .service, .general:
            let brandModel = [record.brand, record.model].compactMap { $0 }.joined(separator: " ")
            if !brandModel.isEmpty { return brandModel }
            if let description = record.recordDescription, !description.isEmpty { return description }
            // `summary` is never sent by the server anymore — last-chance
            // fallback for stale local values only.
            if let summary = record.summary, !summary.isEmpty { return summary }
            return category.label
        }
    }

    /// "2423" → "24/23"; anything without a trailing 4-digit code stays as-is.
    static func formattedDot(_ dotCode: String) -> String {
        let cleaned = dotCode.replacingOccurrences(of: " ", with: "")
        guard cleaned.count >= 4 else { return dotCode }
        let suffix = String(cleaned.suffix(4))
        guard suffix.allSatisfy(\.isNumber) else { return dotCode }
        return "\(suffix.prefix(2))/\(suffix.suffix(2))"
    }

    // MARK: - DOT code parsing (webapp `parseDotCode`)

    /// Parses the trailing WWYY of a DOT code into an approximate production
    /// date (week-of-year, 2000+YY). Returns nil for missing/invalid codes.
    static func parseDotCode(_ dotCode: String?) -> Date? {
        guard let dotCode else { return nil }
        let cleaned = dotCode.filter { !$0.isWhitespace }
        guard cleaned.count >= 4 else { return nil }
        let suffix = String(cleaned.suffix(4))
        guard suffix.allSatisfy(\.isNumber),
              let week = Int(suffix.prefix(2)),
              let yearShort = Int(suffix.suffix(2)),
              (1...53).contains(week) else { return nil }

        var components = DateComponents()
        components.year = 2000 + yearShort
        components.month = 1
        components.day = 1
        guard let jan1 = Calendar.current.date(from: components) else { return nil }
        return Calendar.current.date(byAdding: .day, value: (week - 1) * 7, to: jan1)
    }

    /// Tire age in years derived from the DOT date, e.g. 2.3 — nil without a
    /// parseable code.
    static func dotAgeYears(_ dotCode: String?, asOf now: Date = Date()) -> Double? {
        guard let date = parseDotCode(dotCode) else { return nil }
        let seconds = now.timeIntervalSince(date)
        guard seconds > 0 else { return 0 }
        return seconds / (365.25 * 24 * 3600)
    }
}
