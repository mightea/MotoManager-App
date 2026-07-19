import Foundation

/// A composite row in the service history: records sharing date + odometer +
/// category collapse into one group (webapp `groupMaintenanceRecords` in
/// `maintenance-list.tsx`). Child records (`parentId` set) fold into their
/// parent's group without counting toward the badge or cost.
struct MaintenanceGroup: Identifiable {
    let id: String
    let date: String
    let odo: Int
    let category: MaintenanceCategory
    var count: Int = 0
    var cost: Double = 0
    var currency: String?
    var summaries: [String] = []
    /// Parents first, then children (webapp ordering).
    var records: [SDMaintenanceRecord] = []

    /// The record a tap navigates to: the first parent, else the first record.
    var primary: SDMaintenanceRecord? {
        records.first { $0.parentId == nil } ?? records.first
    }

    var isPending: Bool {
        records.contains { $0.syncState.isPending }
    }
}

enum MaintenanceGrouper {
    /// Groups records by `date-odo-category` with parentId child folding.
    /// Input order is preserved for group creation; output is date-descending
    /// (string compare works on ISO dates).
    static func group(_ records: [SDMaintenanceRecord], locations: [Location] = []) -> [MaintenanceGroup] {
        var groups: [String: MaintenanceGroup] = [:]
        var order: [String] = []
        let byServerId = Dictionary(
            records.compactMap { r in r.serverId.map { ($0, r) } },
            uniquingKeysWith: { first, _ in first }
        )

        for record in records {
            // A child adopts its parent's grouping key when the parent is present.
            var effective = record
            if let parentId = record.parentId, let parent = byServerId[parentId] {
                effective = parent
            }

            let category = effective.category
            let key = "\(effective.date)-\(effective.odo)-\(category.rawValue)"

            if groups[key] == nil {
                groups[key] = MaintenanceGroup(
                    id: key,
                    date: effective.date,
                    odo: effective.odo,
                    category: category,
                    currency: effective.currency
                )
                order.append(key)
            }

            // Children don't count toward the badge or the summed cost.
            if record.parentId == nil {
                groups[key]!.count += 1
                groups[key]!.cost += record.cost ?? 0
                if groups[key]!.currency == nil { groups[key]!.currency = record.currency }
            }

            let summary = MaintenanceSummarizer.summarize(record, locations: locations)
            if !summary.isEmpty, !groups[key]!.summaries.contains(summary) {
                groups[key]!.summaries.append(summary)
            }

            groups[key]!.records.append(record)
        }

        var result = order.compactMap { groups[$0] }
        for index in result.indices {
            result[index].records.sort { a, b in
                if a.parentId == nil && b.parentId != nil { return true }
                if a.parentId != nil && b.parentId == nil { return false }
                return (a.serverId ?? Int.max) < (b.serverId ?? Int.max)
            }
        }
        return result.sorted { $0.date > $1.date }
    }

    /// Buckets date-descending groups into year sections, newest year first.
    static func byYear(_ groups: [MaintenanceGroup]) -> [(year: String, groups: [MaintenanceGroup])] {
        var sections: [(year: String, groups: [MaintenanceGroup])] = []
        for group in groups {
            let year = String(group.date.prefix(4))
            if sections.last?.year == year {
                sections[sections.count - 1].groups.append(group)
            } else {
                sections.append((year: year, groups: [group]))
            }
        }
        return sections
    }

    /// The right-hand metric of a collapsed row (webapp `getCollapsedMetric`):
    /// tire → unique position labels ("Vorne & Hinten"), else the summed cost.
    static func collapsedMetric(_ group: MaintenanceGroup, fallbackCurrency: String?) -> String? {
        if group.category == .tire {
            var seen = Set<String>()
            let positions = group.records.compactMap { record -> String? in
                guard let position = record.tirePosition,
                      let label = MaintenanceCategory.tirePositionLabels[position],
                      seen.insert(label).inserted else { return nil }
                return label
            }
            return positions.isEmpty ? nil : positions.joined(separator: " & ")
        }
        guard group.cost > 0 else { return nil }
        return Formatters.currency(group.cost, code: group.currency ?? fallbackCurrency ?? "CHF")
    }
}
