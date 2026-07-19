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
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.snappy) { expanded.toggle() }
                } label: {
                    header
                }
                .buttonStyle(.plain)

                if expanded {
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
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                }
            }
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.Glass.cardRadius))
            .overlay(alignment: .leading) {
                if let worst = worstStatus, worst != .ok {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color(for: worst))
                        .frame(width: 3)
                        .padding(.vertical, 10)
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Text("SERVICE-INTERVALLE")
                .font(.system(size: 11, weight: .heavy))
                .tracking(2)
                .foregroundColor(.white.opacity(0.55))
            Spacer(minLength: 8)
            tally
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white.opacity(0.5))
                .rotationEffect(.degrees(expanded ? 180 : 0))
        }
        .padding(14)
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
                .font(.system(size: 10, weight: .semibold))
            Text("\(count)")
                .font(.system(size: 10, weight: .heavy))
                .monospacedDigit()
        }
        .foregroundColor(color)
    }

    // MARK: - Body sections

    private func categorySection(_ category: MaintenanceInsight.Category, items: [MaintenanceInsight]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(category.rawValue.uppercased())
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.4)
                .foregroundColor(Theme.Glass.mutedText)
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
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(color(for: insight.status))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(insight.label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Text(meta(for: insight))
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(.white.opacity(0.5))
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
