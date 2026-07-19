import SwiftUI

struct MaintenanceLogsView: View {
    @ObservedObject var viewModel: MotorcycleDetailViewModel
    @ObservedObject var partsVM: PartsViewModel

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

    /// Composite groups (same date+odo+category merge, children folded in),
    /// bucketed by year for the section headers.
    private var groupedByYear: [(year: String, groups: [MaintenanceGroup])] {
        MaintenanceGrouper.byYear(
            MaintenanceGrouper.group(serviceRecords, locations: viewModel.userLocations))
    }

    private var groupCount: Int {
        groupedByYear.reduce(0) { $0 + $1.groups.count }
    }

    private var currentOdo: Int {
        viewModel.motorcycle.latestOdo
            ?? serviceRecords.map(\.odo).max()
            ?? viewModel.motorcycle.initialOdo
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

                    ServiceIntervalsCard(
                        insights: MaintenanceIntervalsEngine.insights(
                            records: serviceRecords, currentOdo: currentOdo)
                    )
                    .padding(.horizontal, Theme.Spacing.pageH)

                    sectionHeader("Verlauf", count: groupCount)
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
        .navigationDestination(item: $selectedRecord) { record in
            MaintenanceDetailView(record: record, viewModel: viewModel, partsVM: partsVM)
        }
        .sheet(isPresented: $showingAddIssue) {
            AddIssueView(viewModel: viewModel)
                .glassSheet()
        }
        .sheet(item: $editingIssue) { issue in
            AddIssueView(viewModel: viewModel, existingIssue: issue)
                .glassSheet()
        }
        .sheet(isPresented: $showingAddMaintenance) {
            AddMaintenanceView(viewModel: viewModel)
                .glassSheet()
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
                ForEach(groupedByYear, id: \.year) { section in
                    yearHeader(section.year)
                    ForEach(section.groups) { group in
                        Button {
                            selectedRecord = group.primary
                        } label: {
                            MaintenanceGroupRow(group: group, fallbackCurrency: currency)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// hairline — year — hairline divider between year sections.
    private func yearHeader(_ year: String) -> some View {
        HStack(spacing: 10) {
            Rectangle().fill(Theme.Glass.hairline).frame(height: 0.5)
            Text(year)
                .font(.system(size: 11, weight: .heavy))
                .monospacedDigit()
                .tracking(1.5)
                .foregroundColor(.white.opacity(0.45))
            Rectangle().fill(Theme.Glass.hairline).frame(height: 0.5)
        }
        .padding(.vertical, 4)
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

// MARK: - Composite group row (webapp maintenance-list style)

private struct MaintenanceGroupRow: View {
    let group: MaintenanceGroup
    let fallbackCurrency: String

    var body: some View {
        let category = group.category
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(category.tint.opacity(0.15))
                Image(systemName: category.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(category.tint)
            }
            .frame(width: 38, height: 38)
            .overlay(alignment: .topTrailing) {
                if group.isPending { PendingBadge().offset(x: 5, y: -5) }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(Formatters.mediumDate(group.date))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                    Spacer(minLength: 8)
                    Text("\(group.odo) km")
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundColor(.white.opacity(0.55))
                }

                if !group.summaries.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if group.count > 1 {
                            Text("\(group.count)×")
                                .font(.system(size: 11, weight: .heavy))
                                .monospacedDigit()
                                .foregroundColor(.white.opacity(0.55))
                        }
                        Text(group.summaries.joined(separator: ", "))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(category.tint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(spacing: 6) {
                    if let metric = MaintenanceGrouper.collapsedMetric(group, fallbackCurrency: fallbackCurrency) {
                        Text(metric)
                            .monospacedDigit()
                        Text("·").foregroundColor(.white.opacity(0.4))
                    }
                    Text(category.label.uppercased())
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(0.6)
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.55))
            }
        }
        .padding(14)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts = ["\(group.category.label): \(group.summaries.joined(separator: ", "))"]
        parts.append("am \(Formatters.mediumDate(group.date))")
        parts.append("Kilometerstand \(group.odo)")
        if group.count > 1 { parts.append("\(group.count) Einträge") }
        if group.cost > 0 {
            parts.append("Kosten \(Formatters.currency(group.cost, code: group.currency ?? fallbackCurrency, fractionDigits: 0))")
        }
        return parts.joined(separator: ", ")
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
            MaintenanceLogsView(viewModel: .mock, partsVM: PartsViewModel())
        }
    }
}
