import SwiftUI

struct MaintenanceLogsView: View {
    @ObservedObject var viewModel: MotorcycleDetailViewModel
    @ObservedObject var partsVM: PartsViewModel
    @ObservedObject private var settingsStore = UserSettingsStore.shared
    @ObservedObject private var reminders = MaintenanceReminderScheduler.shared
    @ObservedObject private var quickActions = QuickActionRouter.shared
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// The tab's single filter. "Alle" is one timeline of maintenance,
    /// defects and location moves; each other chip narrows it to one kind.
    /// (Replaces the former Mängel/Wartung switch plus a second chip row.)
    enum ServiceFilter: Hashable, CaseIterable {
        case alle, wartung, maengel, standort

        var label: String {
            switch self {
            case .alle: "Alle"
            case .wartung: "Wartung"
            case .maengel: "Mängel"
            case .standort: "Standort"
            }
        }
    }

    /// One row of the timeline: a maintenance group or a defect.
    enum TimelineEntry: Identifiable {
        case record(MaintenanceGroup)
        case issue(SDIssue)

        var id: String {
            switch self {
            case .record(let group): "record-\(group.id)"
            case .issue(let issue): "issue-\(issue.clientId)"
            }
        }

        /// ISO day (`yyyy-MM-dd`) for sorting and year buckets.
        var day: String {
            switch self {
            case .record(let group): String(group.date.prefix(10))
            case .issue(let issue): String(issue.date.prefix(10))
            }
        }
    }

    @State private var filter: ServiceFilter = .alle
    @State private var showingSearch = false
    @State private var showingIntervals = false
    @State private var searchText = ""
    @State private var selectedRecord: SDMaintenanceRecord?
    @State private var showingAddIssue = false
    @State private var editingIssue: SDIssue?
    @State private var pendingIssueDelete: SDIssue?
    @State private var showingAddMaintenance = false
    /// "Als Wartung erfassen": the defect the new maintenance entry resolves.
    @State private var resolvingIssue: SDIssue?
    /// Resolved defects stay out of the way until asked for.
    @State private var showingDoneIssues = false

    private var serviceRecords: [SDMaintenanceRecord] {
        viewModel.serviceRecords
    }

    /// Records that are actual maintenance (location moves excluded) — the
    /// basis for the segment badge and the "Letzte Wartung" stat.
    private var wartungRecords: [SDMaintenanceRecord] {
        serviceRecords.filter { $0.category != .location }
    }

    /// The maintenance slice the current filter selects.
    private var historyRecords: [SDMaintenanceRecord] {
        switch filter {
        case .wartung: wartungRecords
        case .standort: serviceRecords.filter { $0.category == .location }
        case .alle: serviceRecords
        case .maengel: []
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
        MaintenanceIntervalsEngine.insights(
            records: serviceRecords, currentOdo: currentOdo, settings: settingsStore.settings)
    }

    /// Cheap change key for the reminder rescheduling: the reminder dates
    /// only depend on each item's due date.
    private var reminderSignature: String {
        let items = intervalInsights.map { "\($0.key)@\(Int($0.nextDate.timeIntervalSince1970))" }
        return "\(reminders.isEnabled)|" + items.joined(separator: ",")
    }

    /// Most recent *real* maintenance — a location move must not read as
    /// "Letzte Wartung" in the stat strip.
    private var lastEntry: SDMaintenanceRecord? { wartungRecords.first }

    private var currency: String {
        lastEntry?.currency ?? viewModel.motorcycle.currencyCode ?? "EUR"
    }

    /// Free-text filter over the current history slice (summary, notes,
    /// location) — long histories span years, and "the entry where I changed
    /// the fork oil" shouldn't require scrolling through them.
    private var searchedRecords: [SDMaintenanceRecord] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return historyRecords }
        return historyRecords.filter { record in
            [record.summary, record.recordDescription, record.locationName]
                .compactMap { $0?.lowercased() }
                .contains { $0.contains(query) }
        }
    }

    private var searchedIssues: [SDIssue] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return viewModel.issues }
        return viewModel.issues.filter {
            "\($0.title) \($0.recordDescription ?? "")".localizedStandardContains(query)
        }
    }

    private var openIssues: [SDIssue] { searchedIssues.filter { !Self.isDone($0) } }
    private var doneIssues: [SDIssue] { searchedIssues.filter { Self.isDone($0) } }

    private static func isDone(_ issue: SDIssue) -> Bool { issue.status.lowercased() == "done" }

    /// Composite maintenance groups (same date+odo+category merge, children
    /// folded in) plus — under "Alle" — the defects, newest first, bucketed by
    /// year. Each year carries its maintenance cost for the section header.
    private var timeline: [(year: String, entries: [TimelineEntry], cost: Double)] {
        let groups = MaintenanceGrouper.group(searchedRecords, locations: viewModel.userLocations)
        var entries = groups.map(TimelineEntry.record)
        if filter == .alle {
            entries += searchedIssues.map(TimelineEntry.issue)
        }
        entries.sort { $0.day > $1.day }

        var sections: [(year: String, entries: [TimelineEntry], cost: Double)] = []
        for entry in entries {
            let year = String(entry.day.prefix(4))
            var cost: Double = 0
            if case .record(let group) = entry { cost = group.cost }
            if sections.last?.year == year {
                sections[sections.count - 1].entries.append(entry)
                sections[sections.count - 1].cost += cost
            } else {
                sections.append((year: year, entries: [entry], cost: cost))
            }
        }
        return sections
    }

    private var currentOdo: Int {
        viewModel.motorcycle.latestOdo
            ?? serviceRecords.map(\.odo).max()
            ?? viewModel.motorcycle.initialOdo
    }

    var body: some View {
        MotorcycleWorkspace(motorcycle: viewModel.motorcycle, type: .service) {
            WorkspaceAction(filter == .maengel ? "Mangel erfassen" : "Wartung erfassen", systemImage: "plus") {
                if filter == .maengel { showingAddIssue = true } else { showingAddMaintenance = true }
            }
            .keyboardShortcut("n", modifiers: .command)
        } content: {
            RecordBrowser(selection: $selectedRecord, title: "Wartung & Mängel",
                          emptyTitle: "Wartung auswählen", systemImage: "checklist",
                          overview: AnyView(attentionOverview)) {
                serviceList
            } detail: { record in
                MaintenanceDetailView(record: record, viewModel: viewModel, partsVM: partsVM)
            }
        }
        .onChange(of: filter) { _, _ in selectedRecord = nil }
        // Consume the "Mangel erfassen" App Shortcut. `initial: true` covers
        // a cold launch where the intent fired before this view existed.
        .onChange(of: quickActions.pending, initial: true) { _, action in
            guard action == .addIssue else { return }
            quickActions.pending = nil
            filter = .maengel
            showingAddIssue = true
        }
        // Local reminders follow the insights shown here; this is the only
        // place that has the bike's records, so each bike is (re)scheduled
        // when its Wartung tab is on screen.
        .onChange(of: reminderSignature, initial: true) { _, _ in
            reminders.schedule(for: viewModel.motorcycle, insights: intervalInsights)
        }
        .onReceive(viewModel.$serviceRecords) { records in
            if let selectedRecord, !records.contains(where: { $0.clientId == selectedRecord.clientId }) {
                self.selectedRecord = nil
            }
        }
        .alert("Mangel löschen?", isPresented: Binding(
            get: { pendingIssueDelete != nil },
            set: { if !$0 { pendingIssueDelete = nil } }
        ), presenting: pendingIssueDelete) { issue in
            Button("Abbrechen", role: .cancel) {}
            Button("Löschen", role: .destructive) { _ = viewModel.deleteIssue(issue) }
        } message: { issue in
            Text(issue.title)
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
        .sheet(isPresented: $showingIntervals) {
            intervalsSheet
                .glassSheet()
        }
        .sheet(item: $resolvingIssue) { issue in
            AddMaintenanceView(viewModel: viewModel, resolvingIssue: issue) { _ in
                _ = viewModel.setIssueStatus(issue, status: "done")
            }
            .glassSheet()
        }
    }

    private var serviceList: some View {
        List {
            // Search is on demand on phones (the icon in the filter row);
            // wide layouts keep the column title and field as before.
            if sizeClass == .regular || showingSearch || !searchText.isEmpty {
                WorkspaceListHeader(searchText: $searchText, prompt: filter == .maengel ? "Mängel durchsuchen …" : "Verlauf durchsuchen …")
            }
            if sizeClass != .regular {
                // Wide layouts show this in the overview column instead.
                attentionCard
            }
            Section {
                filterBar
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            if filter == .maengel {
                issuesContent
            } else {
                timelineContent
            }
            WorkspaceListFooter()
        }
        .accessibilityIdentifier("service.history")
        .tracksWorkspaceHeader()
        .workspaceListStyle()
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.Colors.background)
        .refreshable {
            await viewModel.reconnect()
        }
    }

    private var attentionOverview: some View {
        List {
            Section { StatStrip(statTiles).listRowInsets(EdgeInsets()) }
            Section("Handlungsbedarf") {
                if !intervalInsights.isEmpty {
                    ServiceIntervalsCard(insights: intervalInsights, initiallyExpanded: true)
                }
                // The Mängel filter already shows these records in the list.
                if filter != .maengel {
                    if openIssuesCount > 0 {
                        Label("\(openIssuesCount) offene Mängel", systemImage: "exclamationmark.circle")
                            .foregroundStyle(Theme.Colors.accent)
                    }
                    ForEach(viewModel.issues.filter { $0.status.lowercased() != "done" }, id: \.clientId) { issue in
                        Button { editingIssue = issue } label: { IssueRow(issue: issue) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("service.issue.\(issue.clientId)")
                    }
                }
                Button("Wartung erfassen", systemImage: "plus") { showingAddMaintenance = true }
                Button("Mangel erfassen", systemImage: "exclamationmark.bubble") { showingAddIssue = true }
            }
        }
        .accessibilityIdentifier("service.overview")
        .workspaceListStyle()
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.Colors.background)
        .navigationTitle("Wartung im Blick")
        .navigationBarTitleDisplayMode(.inline)
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
        if viewModel.showsLoadingPlaceholders && viewModel.issues.isEmpty {
            Section {
                ForEach(0..<3, id: \.self) { _ in
                    IssueRow.placeholder
                        .redacted(reason: .placeholder)
                }
            }
        } else if viewModel.issues.isEmpty {
            Section {
                ListEmptyState {
                    Label("Super! Keine Mängel", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } description: {
                    Text("Es sind keine offenen Mängel für \(viewModel.motorcycle.make) \(viewModel.motorcycle.model) erfasst.")
                } actions: {
                    Button("Mangel erfassen", systemImage: "plus") { showingAddIssue = true }
                }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } else if searchedIssues.isEmpty {
            Section { ContentUnavailableView.search(text: searchText) }
        } else {
            if openIssues.isEmpty {
                // Everything is resolved: say so instead of showing nothing
                // above the collapsed "Erledigt" section.
                Section {
                    Label("Keine offenen Mängel", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline.weight(.semibold))
                }
            } else {
                Section {
                    ForEach(openIssues, id: \.clientId) { issue in
                        issueRow(issue)
                    }
                }
                .listRowInsets(denseRowInsets)
            }
            if !doneIssues.isEmpty {
                doneIssuesSection
            }
        }
    }

    /// Resolved defects, collapsed by default — they're history, not a to-do.
    private var doneIssuesSection: some View {
        Section {
            if showingDoneIssues {
                ForEach(doneIssues, id: \.clientId) { issue in
                    issueRow(issue)
                        .opacity(0.75)
                }
                .listRowInsets(denseRowInsets)
            }
        } header: {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { showingDoneIssues.toggle() }
            } label: {
                HStack {
                    Text("Erledigt")
                    Spacer()
                    Text("\(doneIssues.count)")
                        .monospacedDigit()
                    Image(systemName: "chevron.down")
                        .scaledFont(11, weight: .semibold)
                        .rotationEffect(.degrees(showingDoneIssues ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showingDoneIssues ? "Erledigte Mängel ausblenden" : "\(doneIssues.count) erledigte Mängel anzeigen")
        }
    }

    /// One defect row: tap edits; swipe leading toggles done/open; the
    /// context menu adds "Als Wartung erfassen" (repair entry that closes
    /// the defect) and delete.
    private func issueRow(_ issue: SDIssue) -> some View {
        let done = Self.isDone(issue)
        return Button { editingIssue = issue } label: {
            IssueRow(issue: issue)
        }
        .buttonStyle(.plain)
        // Explicit, like the maintenance rows: the wide-layout list column
        // otherwise paints unstyled rows grey.
        .listRowBackground(Theme.Colors.backgroundElevated)
        .accessibilityIdentifier("service.issue.\(issue.clientId)")
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if done {
                Button {
                    _ = viewModel.setIssueStatus(issue, status: "new")
                } label: {
                    Label("Wieder öffnen", systemImage: "arrow.uturn.backward.circle.fill")
                }
                .tint(.orange)
            } else {
                Button {
                    _ = viewModel.setIssueStatus(issue, status: "done")
                } label: {
                    Label("Erledigt", systemImage: "checkmark.circle.fill")
                }
                .tint(.green)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                pendingIssueDelete = issue
            } label: {
                Label("Löschen", systemImage: "trash")
            }
            .tint(.red)
        }
        .contextMenu {
            if done {
                Button("Wieder öffnen", systemImage: "arrow.uturn.backward.circle") {
                    _ = viewModel.setIssueStatus(issue, status: "new")
                }
            } else {
                Button("Erledigt", systemImage: "checkmark.circle") {
                    _ = viewModel.setIssueStatus(issue, status: "done")
                }
                Button("Als Wartung erfassen", systemImage: "wrench.and.screwdriver") {
                    resolvingIssue = issue
                }
            }
            Button("Bearbeiten", systemImage: "pencil") { editingIssue = issue }
            Divider()
            Button("Löschen", systemImage: "trash", role: .destructive) { pendingIssueDelete = issue }
        }
        .sensoryFeedback(.success, trigger: issue.status) { _, new in new.lowercased() == "done" }
    }


    // MARK: - Attention card

    /// The phone summary: open defects and interval health, one line each.
    /// Replaces the cost/last-service stat card, the intervals card and the
    /// Mängel/Wartung switch that used to stack above the history.
    private var attentionCard: some View {
        Section {
            Button { filter = .maengel } label: {
                AttentionRow(color: openIssuesCount > 0 ? .orange : .green,
                             title: openIssuesTitle, detail: openIssuesDetail)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("service.attention.issues")

            if !intervalInsights.isEmpty {
                let status = intervalStatus
                Button { showingIntervals = true } label: {
                    AttentionRow(color: status.color, title: status.title, detail: status.detail)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("service.attention.intervals")
            }
        }
        .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
    }

    private var openIssuesTitle: String {
        switch openIssuesCount {
        case 0: "Keine offenen Mängel"
        case 1: "1 offener Mangel"
        default: "\(openIssuesCount) offene Mängel"
        }
    }

    /// First word of the newest open defects: "Vergaser, Rücklicht".
    private var openIssuesDetail: String? {
        let titles = viewModel.issues
            .filter { !Self.isDone($0) }
            .prefix(2)
            .map { $0.title.split(separator: " ").first.map(String.init) ?? $0.title }
        return titles.isEmpty ? nil : titles.joined(separator: ", ")
    }

    /// Worst bucket wins: overdue, then due, then "all in plan".
    private var intervalStatus: (color: Color, title: String, detail: String?) {
        let overdue = intervalInsights.filter { $0.status == .overdue }.sorted { $0.nextDate < $1.nextDate }
        if let worst = overdue.first {
            let title = overdue.count == 1 ? "1 Intervall überfällig" : "\(overdue.count) Intervalle überfällig"
            return (Theme.Colors.accent, title, worst.label)
        }
        let due = intervalInsights.filter { $0.status == .due }.sorted { $0.nextDate < $1.nextDate }
        if let next = due.first {
            let title = due.count == 1 ? "1 Intervall bald fällig" : "\(due.count) Intervalle bald fällig"
            return (.orange, title, "\(next.label) \(Self.shortMonthYear(next.nextDate))")
        }
        let count = intervalInsights.count
        let next = intervalInsights.min { $0.nextDate < $1.nextDate }
        return (.green,
                count == 1 ? "1 Intervall im Plan" : "\(count) Intervalle im Plan",
                next.map { "\($0.label) \(Self.shortMonthYear($0.nextDate))" })
    }

    private static let shortMonthYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Formatters.displayLocale
        f.dateFormat = "MM/yy"
        return f
    }()

    private static func shortMonthYear(_ date: Date) -> String {
        shortMonthYearFormatter.string(from: date)
    }

    private var intervalsSheet: some View {
        NavigationStack {
            List {
                Section {
                    ServiceIntervalsCard(insights: intervalInsights, initiallyExpanded: true, showsHeader: false)
                }
            }
            .workspaceListStyle()
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.background)
            .navigationTitle("Service-Intervalle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { showingIntervals = false }
                }
            }
        }
    }

    // MARK: - Filter

    /// "Alle · Wartung · Mängel · Standort" chips plus the search toggle.
    /// `.plain` buttons are load-bearing — multiple non-plain Buttons in one
    /// List row fire *all* their actions on a row tap, so the last one always
    /// won and the filter stuck.
    private var filterBar: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(ServiceFilter.allCases, id: \.self) { option in
                        filterChip(option)
                    }
                }
            }
            .scrollIndicators(.hidden)

            if sizeClass != .regular {
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        showingSearch.toggle()
                        if !showingSearch { searchText = "" }
                    }
                } label: {
                    Image(systemName: showingSearch ? "xmark" : "magnifyingglass")
                        .scaledFont(13, weight: .semibold)
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Theme.Colors.backgroundElevated))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showingSearch ? "Suche schliessen" : "Verlauf durchsuchen")
                .accessibilityIdentifier("service.search")
            }
        }
        .animation(.easeOut(duration: 0.18), value: filter)
        .sensoryFeedback(.selection, trigger: filter)
    }

    private func chipCount(_ option: ServiceFilter) -> Int? {
        switch option {
        case .wartung: wartungRecords.isEmpty ? nil : wartungRecords.count
        case .maengel: openIssuesCount == 0 ? nil : openIssuesCount
        case .alle, .standort: nil
        }
    }

    private func filterChip(_ option: ServiceFilter) -> some View {
        let isActive = filter == option
        let count = chipCount(option)
        return Button {
            filter = option
        } label: {
            HStack(spacing: 4) {
                Text(option.label)
                if let count {
                    Text("\(count)")
                        .monospacedDigit()
                        .opacity(0.7)
                }
            }
            .scaledFont(13, weight: .semibold)
            .lineLimit(1)
            .foregroundStyle(isActive ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, 11)
            .frame(height: 32)
            .background(
                Capsule().fill(isActive ? AnyShapeStyle(Theme.Colors.primary) : AnyShapeStyle(Theme.Colors.backgroundElevated))
            )
            // Keep the ~44pt hit target (HIG) without the visual bulk.
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(count.map { "\(option.label), \($0)" } ?? option.label)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
        .accessibilityIdentifier("service.filter.\(option)")
    }

    // MARK: - Timeline

    private var denseRowInsets: EdgeInsets {
        EdgeInsets(top: Theme.Spacing.rowV, leading: 12, bottom: Theme.Spacing.rowV, trailing: 12)
    }

    private func yearHeader(_ year: String, cost: Double) -> some View {
        HStack {
            Text(year)
            Spacer()
            if cost > 0 {
                Text(Formatters.currency(cost, code: currency, fractionDigits: 0))
                    .monospacedDigit()
            }
        }
        .scaledFont(13, weight: .semibold)
        .foregroundStyle(.secondary)
        .textCase(nil)
    }

    @ViewBuilder
    private var timelineContent: some View {
        let sections = timeline
        if viewModel.showsLoadingPlaceholders && serviceRecords.isEmpty {
            Section {
                ForEach(0..<4, id: \.self) { _ in
                    MaintenanceGroupRow.placeholder
                        .redacted(reason: .placeholder)
                }
            }
            .listRowInsets(denseRowInsets)
        } else if sections.isEmpty {
            Section {
                if !searchText.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    ListEmptyState {
                        Label(
                            filter == .standort ? "Keine Standortwechsel" : "Keine Wartung erfasst",
                            systemImage: filter == .standort ? "mappin.and.ellipse" : "wrench.and.screwdriver.fill"
                        )
                    } description: {
                        Text(filter == .standort
                            ? "Standortwechsel tauchen hier auf."
                            : "Reparaturen und Wartungen tauchen hier auf.")
                    } actions: {
                        Button("Eintrag erfassen", systemImage: "plus") { showingAddMaintenance = true }
                    }
                }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } else {
            ForEach(sections, id: \.year) { section in
                Section {
                    ForEach(section.entries) { entry in
                        switch entry {
                        case .record(let group):
                            Button {
                                selectedRecord = group.primary
                            } label: {
                                MaintenanceGroupRow(group: group, fallbackCurrency: currency)
                            }
                            .buttonStyle(.plain)
                            .selectedRecord(selectedRecord?.clientId == group.primary?.clientId)
                        case .issue(let issue):
                            issueRow(issue)
                        }
                    }
                } header: {
                    yearHeader(section.year, cost: section.cost)
                }
                .listRowInsets(denseRowInsets)
            }
        }
    }

}

// MARK: - Attention row

private struct AttentionRow: View {
    let color: Color
    let title: String
    let detail: String?

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .scaledFont(15, weight: .semibold)
                .foregroundStyle(.primary)
                .lineLimit(1)
                // The status must stay whole on an SE; the detail truncates.
                .layoutPriority(1)
            Spacer(minLength: 8)
            if let detail {
                Text(detail)
                    .scaledFont(13)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Image(systemName: "chevron.right")
                .scaledFont(11, weight: .semibold)
                .foregroundStyle(.tertiary)
        }
        .frame(minHeight: 28)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}


// MARK: - Issue row

private struct IssueRow: View {
    let issue: SDIssue

    /// Skeleton stand-in for the loading state (rendered `.redacted`).
    static var placeholder: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: Theme.Radius.controlInner)
                .fill(.quaternary)
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text("Bremslicht flackert")
                Text("OFFEN · 15. Aug. 2026 · 12'345 km")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    /// Two lines, like the maintenance rows: what's wrong, then date and the
    /// first line of the note. The status sits in a pill on the right.
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.badge)
                    .fill(statusColor.opacity(0.16))
                Image(systemName: statusIcon)
                    .scaledFont(14, weight: .semibold)
                    .foregroundStyle(statusColor)
            }
            .frame(width: 32, height: 32)
            .overlay(alignment: .topTrailing) {
                if issue.syncState.isPending { PendingBadge().offset(x: 5, y: -5) }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(issue.title)
                    .scaledFont(15, weight: .semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(subtitle)
                    .scaledFont(12.5)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(statusLabel)
                .scaledFont(11, weight: .bold)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(statusColor.opacity(0.16)))
                .foregroundStyle(pillTextColor)
        }
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

    /// Darker shade of the status color, so the pill text keeps contrast on
    /// its tinted background.
    private var pillTextColor: Color {
        switch issue.status.lowercased() {
        case "done": return Color(light: Color(hex: 0x166534), dark: .green)
        case "in_progress": return Theme.Colors.primary
        default:
            return issue.priority.lowercased() == "high"
                ? Theme.Colors.accent
                : Color(light: Color(hex: 0x9A3412), dark: .orange)
        }
    }

    private var subtitle: String {
        let note = issue.recordDescription?
            .split(whereSeparator: \.isNewline).first
            .map { String($0).trimmingCharacters(in: .whitespaces) }
        return [Formatters.dayMonthName(issue.date), note]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: " · ")
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
        default: return "Offen"
        }
    }
}

// MARK: - Composite group row (webapp maintenance-list style)

private struct MaintenanceGroupRow: View {
    let group: MaintenanceGroup
    let fallbackCurrency: String

    /// Skeleton stand-in for the loading state (rendered `.redacted`).
    static var placeholder: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: Theme.Radius.badge)
                .fill(.quaternary)
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text("Ölwechsel, Kette gespannt")
                Text("15. Aug. · 12'345 km")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    /// Two lines: what was done (the summaries), then when and where on the
    /// odometer. Cost sits on the right; the year header carries the total.
    /// The category is the icon alone, in neutral grey — colour is reserved
    /// for defects, so orange keeps meaning "needs attention".
    var body: some View {
        let category = group.category
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.badge)
                    .fill(Color.primary.opacity(0.06))
                Image(systemName: category.icon)
                    .scaledFont(14, weight: .semibold)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 32, height: 32)
            .overlay(alignment: .topTrailing) {
                if group.isPending { PendingBadge().offset(x: 5, y: -5) }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .scaledFont(15, weight: .semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(subtitle)
                    .scaledFont(12.5)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if group.cost > 0 {
                Text(Formatters.currency(group.cost, code: group.currency ?? fallbackCurrency, fractionDigits: 0))
                    .scaledFont(14, weight: .semibold)
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var title: String {
        group.summaries.isEmpty ? group.category.label : group.summaries.joined(separator: ", ")
    }

    /// "2. Aug. · 83'420 km · Reparatur": the category name only where the
    /// summary is free text and doesn't already say what kind of job it was.
    private var subtitle: String {
        var parts = [Formatters.dayMonthName(group.date)]
        if group.odo > 0 { parts.append(Formatters.kilometers(group.odo)) }
        if group.count > 1 { parts.append("\(group.count) Einträge") }
        if let positions = MaintenanceGrouper.tirePositions(group) { parts.append(positions) }
        switch group.category {
        case .repair, .general, .brakepad, .brakerotor, .chain:
            if title != group.category.label { parts.append(group.category.label) }
        default:
            break
        }
        return parts.joined(separator: " · ")
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
