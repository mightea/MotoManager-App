import SwiftUI

struct MaintenanceLogsView: View {
    @ObservedObject var viewModel: MotorcycleDetailViewModel
    @ObservedObject var partsVM: PartsViewModel
    @Environment(\.chromeActions) private var chrome

    enum ServiceTab: Hashable { case issues, maintenance }
    /// History filter: actual maintenance by default — location moves are
    /// logistics, not wrenching, and they'd otherwise dominate the timeline.
    enum HistoryFilter: String, CaseIterable {
        case wartung = "Wartung"
        case standort = "Standort"
        case alle = "Alle"
    }
    @State private var tab: ServiceTab = .maintenance
    @State private var historyFilter: HistoryFilter = .wartung
    @State private var selectedRecord: SDMaintenanceRecord?
    @State private var showingAddIssue = false
    @State private var editingIssue: SDIssue?
    @State private var showingAddMaintenance = false

    private var serviceRecords: [SDMaintenanceRecord] {
        viewModel.serviceRecords
    }

    /// Records that are actual maintenance (location moves excluded) — the
    /// basis for the segment badge and the "Letzte Wartung" stat.
    private var wartungRecords: [SDMaintenanceRecord] {
        serviceRecords.filter { $0.category != .location }
    }

    /// The history slice the current filter chip selects.
    private var historyRecords: [SDMaintenanceRecord] {
        switch historyFilter {
        case .wartung: wartungRecords
        case .standort: serviceRecords.filter { $0.category == .location }
        case .alle: serviceRecords
        }
    }

    private var openIssuesCount: Int {
        viewModel.openIssuesCount
    }

    private var currentYearShort: String {
        String(Calendar.current.component(.year, from: Date()))
    }

    /// Costs of the current year's service records (dates are ISO strings).
    private var yearCost: Double {
        wartungRecords
            .filter { $0.date.hasPrefix(currentYearShort) }
            .compactMap { $0.cost }
            .reduce(0, +)
    }

    private var intervalInsights: [MaintenanceInsight] {
        MaintenanceIntervalsEngine.insights(records: serviceRecords, currentOdo: currentOdo)
    }

    /// Most recent *real* maintenance — a location move must not read as
    /// "Letzte Wartung" in the stat strip.
    private var lastEntry: SDMaintenanceRecord? { wartungRecords.first }

    private var currency: String {
        lastEntry?.currency ?? viewModel.motorcycle.currencyCode ?? "EUR"
    }

    /// Composite groups (same date+odo+category merge, children folded in),
    /// bucketed by year for the section headers. Fed from the filtered slice.
    private var groupedByYear: [(year: String, groups: [MaintenanceGroup])] {
        MaintenanceGrouper.byYear(
            MaintenanceGrouper.group(historyRecords, locations: viewModel.userLocations))
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
        List {
            // Match the fuel page: stat strip on the extended photo, below it
            // at accessibility text sizes.
            Section {
                MotorcycleHeaderWithStats(
                    motorcycle: viewModel.motorcycle, type: .service, viewModel: viewModel,
                    tiles: statTiles
                )
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listSectionMargins(.all, 0)

            Section {
                GlassSegmentedControl(
                    segments: [
                        .init(value: .issues, label: "Mängel", count: openIssuesCount),
                        .init(value: .maintenance, label: "Wartung", count: wartungRecords.count)
                    ],
                    selection: $tab
                )
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            if tab == .issues {
                issuesContent
            } else {
                if !intervalInsights.isEmpty {
                    Section {
                        ServiceIntervalsCard(insights: intervalInsights)
                    }
                }

                Section {
                    historyFilterControl
                } header: {
                    HStack {
                        Text("Verlauf")
                        Spacer()
                        Text("\(groupCount) \(groupCount == 1 ? "Eintrag" : "Einträge")")
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                maintenanceContent
            }
        }
        .adaptiveContentWidth()
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .ignoresSafeArea(edges: .top)
        .refreshable {
            await viewModel.reconnect()
        }
        .toolbar {
            // One context-aware add button. Always the app accent — a red
            // button reads as destructive, and adding a Mangel isn't.
            ToolbarItem(placement: .topBarTrailing) {
                Button(
                    tab == .issues ? "Mangel erfassen" : "Wartung erfassen",
                    systemImage: "plus"
                ) {
                    if tab == .issues { showingAddIssue = true } else { showingAddMaintenance = true }
                }
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) {
                Button("Einstellungen", systemImage: "gearshape") {
                    chrome.openSettings()
                }
            }
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

    private var statTiles: [StatTile] {
        [
            StatTile(
                eyebrow: "Kosten \(currentYearShort)",
                value: Formatters.currency(yearCost, code: currency, fractionDigits: 0),
                accent: Theme.Colors.primary
            ),
            StatTile(
                eyebrow: "Letzte Wartung",
                value: lastEntry.map { Formatters.dayMonth($0.date) } ?? "—",
                unit: lastEntry.map { "bei \(Formatters.kilometers($0.odo))" }
            ),
            intervalTile
        ]
    }

    /// Interval health at a glance, colored like `ServiceIntervalsCard`:
    /// overdue beats due beats all-ok.
    private var intervalTile: StatTile {
        let overdue = intervalInsights.filter { $0.status == .overdue }.count
        let due = intervalInsights.filter { $0.status == .due }.count
        if overdue > 0 {
            return StatTile(
                eyebrow: "Intervalle", value: "\(overdue)",
                unit: "überfällig", accent: Theme.Colors.accent)
        }
        if due > 0 {
            return StatTile(
                eyebrow: "Intervalle", value: "\(due)",
                unit: "fällig", accent: .orange)
        }
        return StatTile(
            eyebrow: "Intervalle", value: "OK",
            unit: "alles im Plan", accent: .green)
    }

    @ViewBuilder
    private var issuesContent: some View {
        if viewModel.issues.isEmpty {
            Section {
                ContentUnavailableView {
                    Label("Super! Keine Mängel", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } description: {
                    Text("Es sind keine offenen Mängel für \(viewModel.motorcycle.make) \(viewModel.motorcycle.model) erfasst.")
                }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } else {
            Section {
                ForEach(viewModel.issues, id: \.clientId) { issue in
                    Button { editingIssue = issue } label: {
                        IssueRow(issue: issue)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            _ = viewModel.deleteIssue(issue)
                        } label: {
                            Label("Löschen", systemImage: "trash")
                        }
                        .tint(.red)
                    }
                }
            }
        }
    }

    /// "Wartung / Standort / Alle" as a full-width GlassSegmentedControl.
    /// Standortwechsel are logistics, so they're out of the default view but
    /// one tap away. Not loose chip buttons: multiple non-plain Buttons in one
    /// List row fire *all* their actions on a row tap, so the last one (Alle)
    /// always won and the filter appeared stuck.
    private var historyFilterControl: some View {
        GlassSegmentedControl(
            segments: HistoryFilter.allCases.map { .init(value: $0, label: $0.rawValue) },
            selection: $historyFilter
        )
    }

    @ViewBuilder
    private var maintenanceContent: some View {
        if viewModel.isLoading && serviceRecords.isEmpty {
            Section {
                ForEach(0..<4, id: \.self) { _ in
                    MaintenanceGroupRow.placeholder
                        .redacted(reason: .placeholder)
                }
            }
        } else if historyRecords.isEmpty {
            Section {
                ContentUnavailableView {
                    Label(
                        historyFilter == .standort ? "Keine Standortwechsel" : "Keine Wartung erfasst",
                        systemImage: historyFilter == .standort ? "mappin.and.ellipse" : "wrench.and.screwdriver.fill"
                    )
                } description: {
                    Text(historyFilter == .standort
                        ? "Standortwechsel tauchen hier auf."
                        : "Reparaturen und Wartungen tauchen hier auf.")
                }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } else {
            ForEach(groupedByYear, id: \.year) { section in
                Section(section.year) {
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

}

// MARK: - Issue row

private struct IssueRow: View {
    let issue: SDIssue

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.controlInner)
                    .fill(statusColor.opacity(0.22))
                Image(systemName: statusIcon)
                    .scaledFont(16, weight: .semibold)
                    .foregroundStyle(statusColor)
            }
            .frame(width: 36, height: 36)
            .overlay(alignment: .topTrailing) {
                if issue.syncState.isPending { PendingBadge().offset(x: 5, y: -5) }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(issue.title)
                    .scaledFont(14, weight: .bold)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if let notes = issue.recordDescription, !notes.isEmpty {
                    Text(notes)
                        .scaledFont(12)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 6) {
                    Text(statusLabel.uppercased())
                        .scaledFont(9, weight: .heavy)
                        .tracking(0.4)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(statusColor.opacity(0.22)))
                        .foregroundStyle(statusColor)
                    Text("·").foregroundStyle(.tertiary)
                    Text(Formatters.mediumDate(issue.date))
                    Text("·").foregroundStyle(.tertiary)
                    Text("\(issue.odo) km").monospacedDigit()
                }
                .scaledFont(10, weight: .semibold)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(statusLabel) Mangel: \(issue.title), \(Formatters.mediumDate(issue.date)), Kilometerstand \(issue.odo)")
    }

    /// Color follows the *status*, not the priority: elsewhere in the app
    /// green means "ok/done", so an open defect must never render green.
    /// Open defects are orange (red for high priority), in-progress is the
    /// app accent, and only resolved defects turn green.
    private var statusColor: Color {
        switch issue.status.lowercased() {
        case "done": return .green
        case "in_progress": return Theme.Colors.primary
        default: return issue.priority.lowercased() == "high" ? Theme.Colors.accent : .orange
        }
    }

    private var statusIcon: String {
        switch issue.status.lowercased() {
        case "done": return "checkmark.circle.fill"
        case "in_progress": return "wrench.adjustable.fill"
        default: return "exclamationmark.triangle.fill"
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

    /// Skeleton stand-in for the loading state (rendered `.redacted`).
    static var placeholder: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: Theme.Radius.controlInner)
                .fill(.quaternary)
                .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 4) {
                Text("15. August 2026")
                Text("Ölwechsel, Kette gespannt")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    var body: some View {
        let category = group.category
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.controlInner)
                    .fill(category.tint.opacity(0.15))
                Image(systemName: category.icon)
                    .scaledFont(16, weight: .semibold)
                    .foregroundStyle(category.tint)
            }
            .frame(width: 38, height: 38)
            .overlay(alignment: .topTrailing) {
                if group.isPending { PendingBadge().offset(x: 5, y: -5) }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(Formatters.mediumDate(group.date))
                        .scaledFont(14, weight: .bold)
                        .foregroundStyle(.primary)
                    Spacer(minLength: 8)
                    Text("\(group.odo) km")
                        .scaledFont(12, weight: .semibold)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                if !group.summaries.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if group.count > 1 {
                            Text("\(group.count)×")
                                .scaledFont(11, weight: .heavy)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Text(group.summaries.joined(separator: ", "))
                            .scaledFont(13, weight: .medium)
                            .foregroundStyle(category.tint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(spacing: 6) {
                    if let metric = MaintenanceGrouper.collapsedMetric(group, fallbackCurrency: fallbackCurrency) {
                        Text(metric)
                            .monospacedDigit()
                        Text("·").foregroundStyle(.tertiary)
                    }
                    Text(category.label.uppercased())
                        .scaledFont(9, weight: .heavy)
                        .tracking(0.6)
                }
                .scaledFont(10, weight: .semibold)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
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

struct MaintenanceLogsView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            LiquidBackgroundView().ignoresSafeArea()
            MaintenanceLogsView(viewModel: .mock, partsVM: PartsViewModel())
        }
    }
}
