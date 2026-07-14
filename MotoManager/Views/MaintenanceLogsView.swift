import SwiftUI

struct MaintenanceLogsView: View {
    @ObservedObject var viewModel: MotorcycleDetailViewModel

    enum ServiceTab: Hashable { case issues, maintenance }
    @State private var tab: ServiceTab = .maintenance
    @State private var selectedRecord: SDMaintenanceRecord?
    @State private var showingAddIssue = false
    @State private var editingIssue: SDIssue?
    @State private var showingAddMaintenance = false

    private var serviceRecords: [SDMaintenanceRecord] {
        viewModel.serviceRecords
    }

    private var openIssuesCount: Int {
        viewModel.openIssuesCount
    }

    private var totalCost: Double {
        serviceRecords.compactMap { $0.cost }.reduce(0, +)
    }

    private var lastEntry: SDMaintenanceRecord? { serviceRecords.first }

    private var currency: String {
        lastEntry?.currency ?? viewModel.motorcycle.currencyCode ?? "EUR"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.m) {
                MotorcycleSummaryHeader(motorcycle: viewModel.motorcycle, type: .service, viewModel: viewModel)
                    .ignoresSafeArea(edges: .top)

                GlassSegmentedControl(
                    segments: [
                        .init(value: .issues, label: "Mängel", count: openIssuesCount),
                        .init(value: .maintenance, label: "Wartung", count: serviceRecords.count)
                    ],
                    selection: $tab
                )
                .padding(.horizontal, Theme.Spacing.pageH)

                if tab == .issues {
                    issuesContent
                        .padding(.horizontal, Theme.Spacing.pageH)
                } else {
                    statStrip
                        .padding(.horizontal, Theme.Spacing.pageH)

                    sectionHeader("Verlauf", count: serviceRecords.count)
                        .padding(.horizontal, Theme.Spacing.pageH + 6)

                    maintenanceContent
                        .padding(.horizontal, Theme.Spacing.pageH)
                }
            }
            .padding(.bottom, 110)
        }
        .ignoresSafeArea(edges: .top)
        .background(Color.clear)
        // One context-aware add button: red for Mängel, blue for Wartung.
        .bottomActionBar(
            detailVM: viewModel,
            addTint: tab == .issues ? Theme.Colors.accent : Theme.Colors.primary,
            addLabel: tab == .issues ? "Mangel erfassen" : "Wartung erfassen"
        ) {
            if tab == .issues { showingAddIssue = true } else { showingAddMaintenance = true }
        }
        .refreshable {
            await viewModel.reconnect()
        }
        .sheet(item: $selectedRecord) { record in
            MaintenanceDetailView(record: record, viewModel: viewModel)
                .presentationDetents([.large])
                .presentationCornerRadius(Theme.Glass.sheetRadius)
                .presentationBackground(.regularMaterial)
                .presentationDragIndicator(.hidden)
        }
        .sheet(isPresented: $showingAddIssue) {
            AddIssueView(viewModel: viewModel)
                .presentationDetents([.large])
                .presentationCornerRadius(Theme.Glass.sheetRadius)
                .presentationBackground(.regularMaterial)
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $editingIssue) { issue in
            AddIssueView(viewModel: viewModel, existingIssue: issue)
                .presentationDetents([.large])
                .presentationCornerRadius(Theme.Glass.sheetRadius)
                .presentationBackground(.regularMaterial)
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingAddMaintenance) {
            AddMaintenanceView(viewModel: viewModel)
                .presentationDetents([.large])
                .presentationCornerRadius(Theme.Glass.sheetRadius)
                .presentationBackground(.regularMaterial)
                .presentationDragIndicator(.visible)
        }
    }

    private var statStrip: some View {
        StatStrip([
            StatTile(
                eyebrow: "Gesamtkosten",
                value: Formatters.currency(totalCost, code: currency, fractionDigits: 0),
                accent: Theme.Colors.primary
            ),
            StatTile(
                eyebrow: "Letzte Wartung",
                value: lastEntry.map { Formatters.dayMonth($0.date) } ?? "—",
                unit: lastEntry.map { "bei \($0.odo) km" }
            )
        ])
    }

    @ViewBuilder
    private var issuesContent: some View {
        VStack(spacing: Theme.Spacing.s) {
            if viewModel.issues.isEmpty {
                IssuesEmptyCard(motorcycle: viewModel.motorcycle)
            } else {
                VStack(spacing: 10) {
                    ForEach(viewModel.issues, id: \.clientId) { issue in
                        Button { editingIssue = issue } label: {
                            IssueRow(issue: issue)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func sectionHeader(_ label: String, count: Int) -> some View {
        HStack {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .heavy))
                .tracking(2)
                .foregroundColor(.white.opacity(0.55))
            Spacer()
            Text("\(count) \(count == 1 ? "Eintrag" : "Einträge")")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
        }
    }

    @ViewBuilder
    private var maintenanceContent: some View {
        if viewModel.isLoading && serviceRecords.isEmpty {
            VStack(spacing: 10) {
                ForEach(0..<4, id: \.self) { _ in
                    GlassShimmerRow()
                }
            }
        } else if serviceRecords.isEmpty {
            EmptyStateView(
                title: "Keine Wartung erfasst",
                message: "Reparaturen und Wartungen tauchen hier auf.",
                icon: "wrench.and.screwdriver.fill"
            )
            .padding(.top, 60)
        } else {
            // Lazy so a long service history renders cards on demand.
            LazyVStack(spacing: 10) {
                ForEach(serviceRecords, id: \.clientId) { record in
                    Button {
                        selectedRecord = record
                    } label: {
                        MaintenanceCard(record: record, currency: currency)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

}

// MARK: - Issues views

private struct IssuesEmptyCard: View {
    let motorcycle: Motorcycle

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.18))
                    .frame(width: 56, height: 56)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.green)
            }

            Text("Super! Keine Mängel")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)

            Text("Es sind keine offenen Mängel für \(motorcycle.make) \(motorcycle.model) erfasst.")
                .font(.system(size: 13))
                .foregroundColor(Theme.Glass.mutedText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.Glass.cardRadius))
    }
}

private struct IssuesPlaceholderCard: View {
    let count: Int

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Theme.Colors.accent.opacity(0.22))
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.Colors.accent)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(count) offene\(count == 1 ? "r" : "") Mangel")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                Text("Detaillierte Mängel werden hier sichtbar, sobald sie verfügbar sind.")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.Glass.mutedText)
                    .lineLimit(3)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.Glass.fieldRadius))
    }
}

// MARK: - Issue row

private struct IssueRow: View {
    let issue: SDIssue

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(priorityColor.opacity(0.22))
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(priorityColor)
            }
            .frame(width: 36, height: 36)
            .overlay(alignment: .topTrailing) {
                if issue.syncState.isPending { PendingBadge().offset(x: 5, y: -5) }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(issue.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                if let notes = issue.recordDescription, !notes.isEmpty {
                    Text(notes)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.65))
                        .lineLimit(2)
                }
                HStack(spacing: 6) {
                    Text(statusLabel.uppercased())
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(0.4)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(priorityColor.opacity(0.22)))
                        .foregroundColor(priorityColor)
                    Text("·").foregroundColor(.white.opacity(0.4))
                    Text(Formatters.mediumDate(issue.date))
                    Text("·").foregroundColor(.white.opacity(0.4))
                    Text("\(issue.odo) km").monospacedDigit()
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.55))
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(statusLabel) Mangel: \(issue.title), \(Formatters.mediumDate(issue.date)), Kilometerstand \(issue.odo)")
    }

    private var priorityColor: Color {
        switch issue.priority.lowercased() {
        case "high": return Theme.Colors.accent
        case "low": return .green
        default: return .orange
        }
    }

    private var statusLabel: String {
        switch issue.status.lowercased() {
        case "in_progress": return "In Arbeit"
        case "done": return "Erledigt"
        default: return "Neu"
        }
    }
}

// MARK: - Card

private struct MaintenanceCard: View {
    let record: SDMaintenanceRecord
    let currency: String

    var body: some View {
        let kind = MaintenanceKind.kind(for: record.recordType)
        return HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(kind.tint.opacity(0.22))
                Image(systemName: kind.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(kind.tint)
            }
            .frame(width: 36, height: 36)
            .overlay(alignment: .topTrailing) {
                if record.syncState.isPending { PendingBadge().offset(x: 5, y: -5) }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(displayTitle(for: record, kind: kind))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    if let cost = record.cost {
                        Text(Formatters.currency(cost, code: currency, fractionDigits: 0))
                            .font(.system(size: 14, weight: .bold))
                            .monospacedDigit()
                            .foregroundColor(.white)
                    }
                }

                if let notes = record.summary, !notes.isEmpty {
                    Text(notes)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.65))
                        .lineLimit(3)
                }

                HStack(spacing: 6) {
                    Text(kind.label.uppercased())
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(0.4)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(kind.tint.opacity(0.22))
                        )
                        .foregroundColor(kind.tint)

                    Text("·").foregroundColor(.white.opacity(0.4))
                    Text(formatDateFull(record.date))
                    Text("·").foregroundColor(.white.opacity(0.4))
                    Text("\(record.odo) km").monospacedDigit()
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.55))
            }
        }
        .padding(14)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(for: record, kind: kind))
    }

    private func accessibilityText(for record: SDMaintenanceRecord, kind: MaintenanceKind) -> String {
        var parts: [String] = ["\(kind.label): \(displayTitle(for: record, kind: kind))"]
        parts.append("am \(Formatters.mediumDate(record.date))")
        parts.append("Kilometerstand \(record.odo)")
        if let cost = record.cost {
            parts.append("Kosten \(Formatters.currency(cost, code: currency, fractionDigits: 0))")
        }
        return parts.joined(separator: ", ")
    }

    private func displayTitle(for record: SDMaintenanceRecord, kind: MaintenanceKind) -> String {
        if let desc = record.recordDescription, !desc.isEmpty { return desc }
        if let summary = record.summary, !summary.isEmpty { return summary }
        return record.fluidTypeLabel ?? kind.label
    }

    private func formatDateFull(_ iso: String) -> String {
        Formatters.mediumDate(iso)
    }
}

private struct MaintenanceKind {
    let label: String
    let icon: String
    let tint: Color

    static func kind(for type: String) -> MaintenanceKind {
        switch type.lowercased() {
        case "oil", "engineoil", "gearboxoil", "finaldriveoil", "forkoil":
            return MaintenanceKind(label: "Öl", icon: "drop.fill", tint: .green)
        case "tire", "tires":
            return MaintenanceKind(label: "Reifen", icon: "circle.dotted", tint: Color(hex: 0x0EA5E9))
        case "inspection":
            return MaintenanceKind(label: "Inspektion", icon: "list.clipboard.fill", tint: .orange)
        case "chain":
            return MaintenanceKind(label: "Antrieb", icon: "link", tint: .purple)
        case "brakes", "brakefluid":
            return MaintenanceKind(label: "Bremsen", icon: "hammer.fill", tint: Theme.Colors.accent)
        case "battery", "electric":
            return MaintenanceKind(label: "Elektrik", icon: "bolt.fill", tint: Color(hex: 0xF59E0B))
        case "coolant", "fluid":
            return MaintenanceKind(label: "Kühler", icon: "drop.halffull", tint: Color(hex: 0x0EA5E9))
        default:
            return MaintenanceKind(label: type.capitalized, icon: "wrench.and.screwdriver.fill", tint: Theme.Colors.primary)
        }
    }
}

struct EmptyStateView: View {
    let title: String
    let message: String
    var icon: String = "bicycle.circle.fill"

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            ZStack {
                Circle()
                    .fill(Theme.Colors.primary.opacity(0.15))
                    .frame(width: 100, height: 100)

                Image(systemName: icon)
                    .font(.system(size: 42))
                    .foregroundColor(Theme.Colors.primary.opacity(0.85))
            }
            .padding(.bottom, Theme.Spacing.s)

            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.xl)
        }
        .padding(Theme.Spacing.l)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22))
    }
}

struct MaintenanceLogsView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            LiquidBackgroundView().ignoresSafeArea()
            MaintenanceLogsView(viewModel: .mock)
        }
    }
}
