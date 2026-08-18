import SwiftUI

/// Collapsible "Service-Intervalle" card on the Wartung tab, mirroring the
/// webapp's MaintenanceInsightsCard: per-item ok/due/overdue statuses grouped
/// into Reifen / Batterie / Flüssigkeiten / Wartung, with a tally header.
struct ServiceIntervalsCard: View {
    let insights: [MaintenanceInsight]
    @State private var expanded = false

    private var overdueCount: Int { insights.count { $0.status == .overdue } }
    private var dueCount: Int { insights.count { $0.status == .due } }
    private var okCount: Int { insights.count { $0.status == .ok } }

    /// Worst status drives the header accent.
    private var worstStatus: MaintenanceInsight.Status? {
        insights.map(\.status).min()
    }

    var body: some View {
        if !insights.isEmpty {
            // Native disclosure row inside the surrounding List section — the
            // system provides chevron, animation and row chrome.
            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(MaintenanceInsight.Category.allCases, id: \.rawValue) { category in
                        let items = insights
                            .filter { $0.category == category }
                            .sorted { $0.status < $1.status }
                        if !items.isEmpty {
                            categorySection(category, items: items)
                        }
                    }
                }
                .padding(.top, 8)
            } label: {
                header
            }
            .tint(.secondary)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Text("SERVICE-INTERVALLE")
                .scaledFont(11, weight: .heavy)
                .tracking(2)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            tally
        }
        .contentShape(Rectangle())
        .accessibilityLabel(accessibilitySummary)
    }

    private var tally: some View {
        HStack(spacing: 8) {
            if overdueCount > 0 { tallyItem("xmark.circle.fill", count: overdueCount, color: Theme.Colors.accent) }
            if dueCount > 0 { tallyItem("exclamationmark.triangle.fill", count: dueCount, color: .orange) }
            if okCount > 0 { tallyItem("checkmark.circle.fill", count: okCount, color: .green) }
        }
    }

    private func tallyItem(_ icon: String, count: Int, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .scaledFont(10, weight: .semibold)
            Text("\(count)")
                .scaledFont(10, weight: .heavy)
                .monospacedDigit()
        }
        .foregroundStyle(color)
    }

    // MARK: - Body sections

    private func categorySection(_ category: MaintenanceInsight.Category, items: [MaintenanceInsight]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(category.rawValue.uppercased())
                .scaledFont(9, weight: .heavy)
                .tracking(1.4)
                .foregroundStyle(.secondary)
            VStack(spacing: 8) {
                ForEach(items) { insight in
                    row(insight)
                }
            }
        }
    }

    private func row(_ insight: MaintenanceInsight) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon(for: insight.status))
                .scaledFont(12, weight: .semibold)
                .foregroundStyle(color(for: insight.status))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(insight.label)
                    .scaledFont(13, weight: .semibold)
                    .foregroundStyle(.primary)
                Text(meta(for: insight))
                    .scaledFont(10, weight: .semibold)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                // The rule and the verdict, so a red row is actionable
                // ("interval is 8 years, you're 3 past it") instead of a bare
                // colored icon the user has to decode.
                Text(statusDetail(for: insight))
                    .scaledFont(10, weight: .semibold)
                    .monospacedDigit()
                    .foregroundStyle(color(for: insight.status).opacity(0.9))
            }
            Spacer(minLength: 0)
        }
    }

    private func meta(for insight: MaintenanceInsight) -> String {
        var parts = [
            "\(Self.monthYear(insight.lastDate)) (\(MaintenanceIntervalsEngine.relativeAge(from: insight.lastDate)))",
        ]
        if let kms = insight.kmsSinceLast {
            let formatted = kms.formatted(.number.locale(Locale(identifier: "de_CH")))
            parts.append("seit \(formatted) km")
        }
        return parts.joined(separator: " · ")
    }

    /// "Alle 8 Jahre · überfällig seit 3 Jahren" / "… · fällig in 2 Monaten" /
    /// "… · nächste Mai 2033".
    private func statusDetail(for insight: MaintenanceInsight) -> String {
        let rule = insight.intervalYears == 1 ? "Jedes Jahr" : "Alle \(insight.intervalYears) Jahre"
        let now = Date()
        switch insight.status {
        case .overdue:
            return "\(rule) · überfällig seit \(MaintenanceIntervalsEngine.relativeSpan(from: now, to: insight.nextDate))"
        case .due:
            return "\(rule) · fällig in \(MaintenanceIntervalsEngine.relativeSpan(from: now, to: insight.nextDate))"
        case .ok:
            return "\(rule) · nächste \(Self.monthYear(insight.nextDate))"
        }
    }

    private func icon(for status: MaintenanceInsight.Status) -> String {
        switch status {
        case .overdue: "xmark.circle.fill"
        case .due: "exclamationmark.triangle.fill"
        case .ok: "checkmark.circle.fill"
        }
    }

    private func color(for status: MaintenanceInsight.Status) -> Color {
        switch status {
        case .overdue: Theme.Colors.accent
        case .due: .orange
        case .ok: .green
        }
    }

    private var accessibilitySummary: String {
        "Service-Intervalle: \(overdueCount) überfällig, \(dueCount) fällig, \(okCount) in Ordnung"
    }

    private static func monthYear(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        formatter.locale = Locale(identifier: "de_CH")
        return formatter.string(from: date)
    }
}
