import SwiftUI

/// The "Teile" tab: the user's parts inventory (offline-first) plus a browse
/// segment for other users' public parts (online-only).
struct PartsView: View {
    @ObservedObject var viewModel: PartsViewModel
    /// The bike detail VM — drives the shared header and status accessory.
    @ObservedObject var detailVM: MotorcycleDetailViewModel
    /// The currently selected bike, used for the "Passend für …" filter chip.
    private var motorcycle: Motorcycle? { detailVM.motorcycle }
    @ObservedObject private var quickActions = QuickActionRouter.shared

    enum PartsTab: Hashable { case mine, locations, publicParts }
    @State private var tab: PartsTab = .mine
    @State private var searchText = ""
    /// On by default: the tab lives under a specific bike, so parts fitting
    /// that bike are the expected view — the toggle widens to the whole
    /// inventory instead of narrowing it. Inert when the bike has no linked
    /// model series (`filteredParts` ignores it then, and the toggle is hidden).
    @State private var filterBySelectedBike = true
    /// Only parts with one piece or none left.
    @State private var lowStockOnly = false
    /// Only parts stocked at this place (or anywhere inside it).
    @State private var placeFilter: SDStorageLocation?
    /// Phones keep the search behind an icon in the chip row.
    @State private var showingSearch = false
    @State private var showingAddPart = false
    enum Destination: Hashable { case part(SDPart), location(SDStorageLocation) }
    @State private var selection: Destination?
    @State private var partPendingDeletion: SDPart?
    @State private var showingScanner = false
    @State private var pendingScan: ScannedLabel?
    @State private var showingScanNotFound = false
    @State private var showingAddLocation = false
    /// Whether the public browse has completed at least one load this session —
    /// before that, the segment shows placeholders instead of a flashing
    /// empty state.
    @State private var publicLoadedOnce = false
    @ObservedObject private var connectivity = ConnectivityMonitor.shared
    // Read the workspace width before NavigationSplitView narrows its columns.
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        MotorcycleWorkspace(motorcycle: detailVM.motorcycle, type: .parts, menuActions: [
            WorkspaceMenuAction(title: "Etikett scannen", systemImage: "qrcode.viewfinder",
                                isDisabled: tab == .publicParts) { showingScanner = true }
        ]) {
            WorkspaceAction(addLabel, systemImage: "plus", action: addAction)
                .disabled(tab == .publicParts)
                .keyboardShortcut("n", modifiers: .command)
        } content: {
            RecordBrowser(selection: $selection, title: "Teile & Lager",
                          emptyTitle: "Teil oder Lagerort auswählen", systemImage: "shippingbox",
                          overview: AnyView(inventoryOverview)) {
                partsList
            } detail: { destination in
                switch destination {
                case .part(let part):
                    PartDetailView(part: part, viewModel: viewModel)
                case .location(let location):
                    StorageLocationDetailView(location: location, viewModel: viewModel,
                        placeName: detailVM.location(id: location.locationId)?.name)
                }
            }
        }
        .onChange(of: tab) { _, _ in selection = nil }
        .onReceive(viewModel.$parts) { parts in
            if case .part(let part) = selection, !parts.contains(where: { $0.clientId == part.clientId }) {
                selection = nil
            }
        }
        .onReceive(viewModel.$storageLocations) { locations in
            if case .location(let location) = selection, !locations.contains(where: { $0.clientId == location.clientId }) {
                selection = nil
            }
        }
        .task {
            viewModel.reloadLocal()
            await viewModel.loadSeries()
        }
        .task(id: tab) {
            if tab == .publicParts {
                await viewModel.loadPublicParts(query: searchText.isEmpty ? nil : searchText)
                publicLoadedOnce = true
            }
        }
        .task(id: searchText) {
            guard tab == .publicParts else { return }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await viewModel.loadPublicParts(query: searchText.isEmpty ? nil : searchText)
            publicLoadedOnce = true
        }
        // Consume the "Etikett scannen" App Shortcut. `initial: true` covers
        // a cold launch where the intent fired before this view existed.
        .onChange(of: quickActions.pending, initial: true) { _, action in
            switch action {
            case .scanPart:
                quickActions.pending = nil
                showingScanner = true
            case .openLabel(let label):
                // Universal link from a printed label (Camera app, Safari):
                // same resolution as a scan, minus the scanner sheet.
                quickActions.pending = nil
                tab = label.isStorageLocation ? .locations : .mine
                pendingScan = label
                resolvePendingScan()
            default:
                break
            }
        }
        .sheet(isPresented: $showingAddPart) {
            AddPartView(viewModel: viewModel)
                .glassSheet()
        }
        // The scan result only gets stashed here; pushing the part/location
        // detail must wait for the scanner sheet's dismissal so the push
        // animation doesn't fight the sheet's — onDismiss fires after the
        // animation completes.
        .sheet(isPresented: $showingScanner, onDismiss: resolvePendingScan) {
            LabelScanSheet { pendingScan = $0 }
                .glassSheet()
        }
        .alert("Etikett nicht gefunden", isPresented: $showingScanNotFound) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Zu diesem QR-Code gibt es lokal keinen Eintrag. Möglicherweise wurde er noch nicht synchronisiert — zum Aktualisieren nach unten ziehen.")
        }
        .sheet(isPresented: $showingAddLocation) {
            AddStorageLocationView(
                viewModel: viewModel,
                places: detailVM.userLocations
            )
            .glassSheet()
        }
        // Warning tap when the destructive confirmation comes up (HIG:
        // haptics for consequential moments, used sparingly).
        .sensoryFeedback(.warning, trigger: partPendingDeletion != nil) { _, new in new }
        .alert("Teil löschen?", isPresented: Binding(
            get: { partPendingDeletion != nil },
            set: { if !$0 { partPendingDeletion = nil } }
        )) {
            Button("Abbrechen", role: .cancel) { partPendingDeletion = nil }
            Button("Löschen", role: .destructive) {
                if let part = partPendingDeletion { _ = viewModel.deletePart(part) }
                partPendingDeletion = nil
            }
        } message: {
            Text("Bestand und Verbrauch dieses Teils werden ebenfalls entfernt. Diese Aktion kann nicht rückgängig gemacht werden.")
        }
    }

    private var searchVisible: Bool { sizeClass == .regular || tab != .mine || showingSearch }

    private var partsList: some View {
        List {
            WorkspaceListHeader(searchText: searchVisible ? $searchText : nil,
                                prompt: tab == .locations ? "Lagerort suchen …" : "Name oder Teilenummer …")
            Section {
                GlassSegmentedControl(
                    segments: [
                        .init(value: PartsTab.mine, label: "Teile", count: viewModel.parts.count),
                        .init(value: PartsTab.locations, label: "Lagerorte", count: viewModel.storageLocations.count),
                        .init(value: PartsTab.publicParts, label: "Öffentlich")
                    ],
                    selection: $tab
                )
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            switch tab {
            case .mine:
                mineSections
            case .locations:
                locationSections
            case .publicParts:
                Section { publicRows }
            }
            WorkspaceListFooter()
        }
        .workspaceListStyle()
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.Colors.background)
        .accessibilityIdentifier("parts.inventory")
        .alignsWorkspaceColumn(.list)
        .tracksWorkspaceHeader()
        .refreshable {
            await SyncEngine.shared.sync(motorcycleIds: [])
            viewModel.reloadLocal()
            if tab == .publicParts {
                await viewModel.loadPublicParts(query: searchText.isEmpty ? nil : searchText)
            }
        }
    }

    private var addLabel: String {
        switch tab {
        case .mine, .publicParts: "Teil hinzufügen"
        case .locations: "Lagerort hinzufügen"
        }
    }

    private func addAction() {
        switch tab {
        case .mine: showingAddPart = true
        case .locations: showingAddLocation = true
        case .publicParts: break   // button is disabled on the public segment
        }
    }

    /// Opens the scanned part/location, or the not-found alert for ids that
    /// don't exist locally (not yet pulled, or someone else's label).
    private func resolvePendingScan() {
        defer { pendingScan = nil }
        switch pendingScan {
        case .part(let serverId):
            if let part = viewModel.part(serverId: serverId) {
                selection = .part(part)
            } else {
                showingScanNotFound = true
            }
        case .storageLocation(let serverId):
            if let location = viewModel.storageLocation(serverId: serverId) {
                selection = .location(location)
            } else {
                showingScanNotFound = true
            }
        case nil:
            break   // scanner cancelled
        }
    }

    // MARK: - Header stat strip

    /// Hierarchy-aware fitment count for the selected bike; nil when the bike
    /// has no linked model series (same condition as the Passend-für toggle).
    private var fittingCount: Int? {
        guard let seriesId = motorcycle?.seriesId else { return nil }
        return viewModel.parts.filter {
            ModelSeriesCatalog.matches(
                partSeriesIds: $0.seriesIds, bikeSeriesId: seriesId, in: viewModel.series)
        }.count
    }

    /// Purchase value of all stock entries, mirroring the part detail's
    /// `totalStockValue` (normalized to CHF where a conversion exists).
    private var inventoryValue: Double {
        viewModel.inventoryValue
    }

    private var statTiles: [StatTile] {
        [
            StatTile(
                eyebrow: "Gesamtes Lager",
                value: "\(viewModel.parts.count)",
                unit: viewModel.parts.count == 1 ? "Eintrag" : "Einträge",
                accent: Theme.Colors.primary
            ),
            StatTile(
                eyebrow: "Passend",
                value: fittingCount.map(String.init) ?? "—",
                unit: fittingCount != nil
                    ? "für \(motorcycle?.model ?? "")"
                    : "kein Modell verknüpft"
            ),
            StatTile(
                eyebrow: "Lagerwert",
                value: inventoryValue > 0
                    ? Formatters.currency(inventoryValue, code: "CHF", fractionDigits: 0)
                    : "—"
            )
        ]
    }

    // MARK: - Overview (wide layouts)

    /// Parts with one or no piece left, fewest first.
    private var lowStockParts: [(part: SDPart, onHand: Int)] {
        viewModel.parts
            .map { (part: $0, onHand: viewModel.onHand(for: $0)) }
            .filter { $0.onHand <= 1 }
            .sorted { ($0.onHand, $0.part.name) < ($1.onHand, $1.part.name) }
    }

    private var topLevelLocations: [SDStorageLocation] {
        viewModel.storageLocations
            .filter { $0.parentClientId == nil }
            .sorted { $0.name < $1.name }
    }

    private func stockPlaces(_ part: SDPart) -> String? {
        let names = Set(viewModel.stocks(for: part).compactMap {
            viewModel.storageLocation(clientId: $0.storageLocationClientId)?.name
        })
        return names.isEmpty ? nil : names.sorted().joined(separator: ", ")
    }

    private var inventoryOverview: some View {
        List {
            OverviewTitle("Lager im Überblick")
            Section { StatStrip(statTiles).listRowInsets(EdgeInsets()) }
            if !lowStockParts.isEmpty {
                Section {
                    ForEach(lowStockParts.prefix(8), id: \.part.clientId) { entry in
                        Button { selection = .part(entry.part) } label: {
                            HStack(spacing: Theme.Spacing.m) {
                                Text("\(entry.onHand)")
                                    .font(.subheadline.weight(.heavy))
                                    .monospacedDigit()
                                    .foregroundStyle(entry.onHand <= 0 ? Theme.Colors.accent : .orange)
                                    .frame(width: 34, height: 34)
                                    .background((entry.onHand <= 0 ? Theme.Colors.accent : .orange).opacity(0.16),
                                                in: RoundedRectangle(cornerRadius: Theme.Radius.controlInner))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.part.name).font(.subheadline.weight(.semibold))
                                    Text(stockPlaces(entry.part) ?? entry.part.partNumber)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("parts.lowStock.\(entry.part.clientId)")
                    }
                } header: {
                    HStack {
                        Text("Knapp im Lager")
                        Spacer()
                        Text("Bestand 1 oder weniger").textCase(nil)
                    }
                }
            }
            if !topLevelLocations.isEmpty {
                Section("Lagerorte") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: Theme.Spacing.s)],
                              spacing: Theme.Spacing.s) {
                        ForEach(topLevelLocations, id: \.clientId) { location in
                            Button { tab = .locations; selection = .location(location) } label: {
                                let count = viewModel.totalStockedPartCount(at: location)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(location.name)
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(2)
                                    Text(count == 1 ? "1 Teil" : "\(count) Teile")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
                                .padding(Theme.Spacing.m - 2)
                                .background(Theme.Colors.background, in: RoundedRectangle(cornerRadius: Theme.Radius.chip))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, Theme.Spacing.xs)
                }
            }
            if viewModel.parts.isEmpty {
                Section {
                    Label("Lege Teile an, um Bestand, Lagerwert und knappe Teile hier zu sehen.",
                          systemImage: "shippingbox")
                        .foregroundStyle(.secondary)
                    Button("Teil hinzufügen", systemImage: "plus") { showingAddPart = true }
                }
            }
        }
        .accessibilityIdentifier("parts.overview")
        .alignsWorkspaceColumn(.overview)
        .workspaceListStyle()
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.background)
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Mine

    private var filteredParts: [SDPart] {
        var result = viewModel.parts
        if filterBySelectedBike, let seriesId = motorcycle?.seriesId {
            // Hierarchy-aware: a part linked to the bike's Familie/Serie/Modell
            // chain (in either direction) counts as passend.
            result = result.filter {
                ModelSeriesCatalog.matches(
                    partSeriesIds: $0.seriesIds, bikeSeriesId: seriesId, in: viewModel.series)
            }
        }
        if lowStockOnly {
            result = result.filter { viewModel.onHand(for: $0) <= 1 }
        }
        if let placeFilter {
            let ids = viewModel.stockedPartIds(under: placeFilter)
            result = result.filter { ids.contains($0.clientId) }
        }
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if !query.isEmpty {
            result = result.filter {
                $0.name.lowercased().contains(query) || $0.partNumber.lowercased().contains(query)
                    || ($0.oemPartNumber?.lowercased().contains(query) ?? false)
            }
        }
        return result
    }

    /// True when the empty list is caused by the default bike filter alone —
    /// the message must then point at the toggle, not at a search query.
    private var emptyBecauseOfBikeFilter: Bool {
        filterBySelectedBike && motorcycle?.seriesId != nil && !lowStockOnly && placeFilter == nil
            && searchText.trimmingCharacters(in: .whitespaces).isEmpty
            && !viewModel.parts.isEmpty
    }

    private var emptyPartsTitle: String {
        if viewModel.parts.isEmpty { return "Keine Teile erfasst" }
        return emptyBecauseOfBikeFilter ? "Keine passenden Teile" : "Keine Treffer"
    }

    private var emptyPartsMessage: String {
        if viewModel.parts.isEmpty {
            return "Lege dein erstes Ersatzteil an — Bestand und Verbrauch werden automatisch geführt."
        }
        if emptyBecauseOfBikeFilter, let moto = motorcycle {
            let count = viewModel.parts.count
            return "Für \(moto.make) \(moto.model) ist kein Teil hinterlegt. "
                + "Deaktiviere den Filter, um alle \(count) Teile zu sehen."
        }
        return "Kein Teil passt zu Suche oder Filter."
    }

    private var lowStockCount: Int {
        viewModel.parts.filter { viewModel.onHand(for: $0) <= 1 }.count
    }

    @ViewBuilder
    private var mineSections: some View {
        Section { chipBar }
            .cardRow()

        if viewModel.parts.isEmpty && detailVM.showsLoadingPlaceholders {
            // The inventory arrives with the bike's initial sync; skeletons
            // until then instead of a flashing "Keine Teile erfasst".
            Section {
                ForEach(0..<4, id: \.self) { _ in
                    PartCard.placeholder.redacted(reason: .placeholder)
                }
            }
        } else if filteredParts.isEmpty {
            Section {
                emptyStateRow(title: emptyPartsTitle, message: emptyPartsMessage, icon: "shippingbox.fill")
                if emptyBecauseOfBikeFilter {
                    Button("Alle Teile anzeigen") { filterBySelectedBike = false }
                } else if viewModel.parts.isEmpty {
                    Button("Erstes Teil hinzufügen", systemImage: "plus") { showingAddPart = true }
                } else {
                    Button("Suche und Filter zurücksetzen") {
                        searchText = ""
                        filterBySelectedBike = false
                        lowStockOnly = false
                        placeFilter = nil
                    }
                }
            }
        } else {
            let low = filteredParts.filter { viewModel.onHand(for: $0) <= 1 }
            let stocked = filteredParts.filter { viewModel.onHand(for: $0) > 1 }
            if !low.isEmpty {
                Section {
                    ForEach(low, id: \.clientId) { partRow($0) }
                } header: {
                    groupHeader("Knapp im Lager", count: low.count, tint: .orange)
                }
            }
            if !stocked.isEmpty {
                Section {
                    ForEach(stocked, id: \.clientId) { partRow($0) }
                } header: {
                    groupHeader("Auf Lager", count: stocked.count, tint: nil)
                }
            }
            if sizeClass != .regular {
                Section { scopeSummary }
                    .cardRow()
            }
        }
    }

    /// Count and stock value under the list; the stats strip lives in the
    /// wide overview only.
    private var scopeSummary: some View {
        var text = "\(filteredParts.count) von \(viewModel.parts.count) Teilen"
        if inventoryValue > 0 {
            text += " · Lagerwert " + Formatters.currency(inventoryValue, code: "CHF", fractionDigits: 0)
        }
        return Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.horizontal, Theme.Spacing.s)
            .accessibilityIdentifier("parts.scopeSummary")
    }

    private func groupHeader(_ title: String, count: Int, tint: Color?) -> some View {
        HStack {
            Text(title).foregroundStyle(tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.secondary))
            Spacer()
            Text("\(count)").monospacedDigit()
        }
    }

    private func partRow(_ part: SDPart) -> some View {
        Button {
            selection = .part(part)
        } label: {
            PartCard(part: part, onHand: viewModel.onHand(for: part),
                     place: viewModel.stockLocationNames(for: part).first, viewModel: viewModel)
        }
        .buttonStyle(.plain)
        .selectedRecord(selection == .part(part))
        .accessibilityIdentifier("parts.row.\(part.clientId)")
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                partPendingDeletion = part
            } label: {
                Label("Löschen", systemImage: "trash")
            }
            .tint(.red)
        }
    }

    /// Fit, low-stock and place filters as chips, search behind an icon on
    /// phones.
    private var chipBar: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    if let moto = motorcycle, moto.seriesId != nil {
                        chip(filterBySelectedBike ? "Passend für \(moto.model)" : "Alle Motorräder",
                             systemImage: filterBySelectedBike ? "checkmark" : nil,
                             active: filterBySelectedBike) { filterBySelectedBike.toggle() }
                            .accessibilityIdentifier("parts.filter.fit")
                    }
                    chip("Knapp", count: lowStockCount, active: lowStockOnly) { lowStockOnly.toggle() }
                        .accessibilityIdentifier("parts.filter.low")
                    if !topLevelLocations.isEmpty {
                        Menu {
                            Button("Alle Orte") { placeFilter = nil }
                            ForEach(topLevelLocations, id: \.clientId) { location in
                                Button(location.name) { placeFilter = location }
                            }
                        } label: {
                            chipLabel(placeFilter?.name ?? "Alle Orte", systemImage: nil, count: nil,
                                      trailing: "chevron.down", active: placeFilter != nil)
                        }
                        .accessibilityIdentifier("parts.filter.place")
                    }
                }
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()

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
                .accessibilityLabel(showingSearch ? "Suche schliessen" : "Teile durchsuchen")
                .accessibilityIdentifier("parts.search")
            }
        }
        .sensoryFeedback(.selection, trigger: lowStockOnly)
    }

    private func chip(_ title: String, systemImage: String? = nil, count: Int? = nil,
                      active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            chipLabel(title, systemImage: systemImage, count: count, trailing: nil, active: active)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func chipLabel(_ title: String, systemImage: String?, count: Int?, trailing: String?,
                           active: Bool) -> some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage).scaledFont(11, weight: .bold) }
            Text(title)
            if let count { Text("\(count)").monospacedDigit().opacity(0.7) }
            if let trailing { Image(systemName: trailing).scaledFont(9, weight: .bold) }
        }
        .scaledFont(13, weight: .semibold)
        .lineLimit(1)
        .foregroundStyle(active ? AnyShapeStyle(Theme.Colors.primary) : AnyShapeStyle(.primary))
        .padding(.horizontal, 11)
        .frame(minHeight: 32)
        .background(Capsule().fill(active ? Theme.Colors.primary.opacity(0.15) : Theme.Colors.backgroundElevated))
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    // MARK: - Storage locations

    /// Name-or-path search over the user's storage locations, sorted by their
    /// full breadcrumb path so children group under their parents.
    private var filteredLocations: [SDStorageLocation] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        var result = viewModel.storageLocations
        if !query.isEmpty {
            result = result.filter {
                (viewModel.locationPath($0) ?? $0.name).lowercased().contains(query)
            }
        }
        return result.sorted {
            (viewModel.locationPath($0) ?? $0.name) < (viewModel.locationPath($1) ?? $1.name)
        }
    }

    /// Places (garage, workshop) with their storage locations nested below,
    /// so a box is found by walking the shelf. Searching flattens the tree
    /// and shows each hit's path instead.
    @ViewBuilder
    private var locationSections: some View {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty || filteredLocations.isEmpty || viewModel.storageLocations.isEmpty {
            Section { locationRows }
        } else {
            ForEach(placeGroups, id: \.name) { group in
                Section {
                    ForEach(group.rows, id: \.location.clientId) { row in
                        locationButton(row.location, depth: row.depth)
                    }
                } header: {
                    Label(group.name, systemImage: group.isPlace ? "mappin.and.ellipse" : "archivebox")
                }
            }
        }
    }

    /// Root locations grouped by the place they belong to, each flattened
    /// with its descendants in tree order.
    private var placeGroups: [(name: String, isPlace: Bool, rows: [(location: SDStorageLocation, depth: Int)])] {
        var order: [String] = []
        var groups: [String: [(location: SDStorageLocation, depth: Int)]] = [:]
        var places: Set<String> = []
        for root in topLevelLocations {
            let place = detailVM.location(id: root.locationId)?.name
            let name = place ?? "Ohne Ort"
            if place != nil { places.insert(name) }
            if groups[name] == nil { order.append(name) }
            groups[name, default: []].append(contentsOf: flatten(root, depth: 0))
        }
        // Places first, the unassigned group last.
        order.sort { ($0 == "Ohne Ort" ? 1 : 0, $0) < ($1 == "Ohne Ort" ? 1 : 0, $1) }
        return order.map { (name: $0, isPlace: places.contains($0), rows: groups[$0] ?? []) }
    }

    private func flatten(_ location: SDStorageLocation, depth: Int) -> [(location: SDStorageLocation, depth: Int)] {
        guard depth < 8 else { return [] }
        return [(location, depth)] + viewModel.children(of: location).flatMap { flatten($0, depth: depth + 1) }
    }

    private func locationButton(_ location: SDStorageLocation, depth: Int?) -> some View {
        Button {
            selection = .location(location)
        } label: {
            StorageLocationCard(
                location: location,
                parentPath: depth == nil ? viewModel.locationParentPath(location) : nil,
                placeName: depth == nil ? detailVM.location(id: location.locationId)?.name : nil,
                directCount: viewModel.stockedParts(at: location).count,
                totalCount: viewModel.totalStockedPartCount(at: location),
                depth: depth ?? 0
            )
        }
        .buttonStyle(.plain)
        .selectedRecord(selection == .location(location))
        .accessibilityIdentifier("parts.location.\(location.clientId)")
    }

    @ViewBuilder
    private var locationRows: some View {
        if viewModel.storageLocations.isEmpty && detailVM.showsLoadingPlaceholders {
            ForEach(0..<3, id: \.self) { _ in
                StorageLocationCard.placeholder
                    .redacted(reason: .placeholder)
            }
        } else if filteredLocations.isEmpty {
            emptyStateRow(
                title: viewModel.storageLocations.isEmpty ? "Keine Lagerorte" : "Keine Treffer",
                message: viewModel.storageLocations.isEmpty
                    ? "Lege mit dem Plus-Button einen Lagerort an — sie entstehen auch beim Erfassen von Beständen."
                    : "Kein Lagerort passt zur Suche.",
                icon: "archivebox.fill"
            )
            if viewModel.storageLocations.isEmpty {
                Button("Lagerort hinzufügen", systemImage: "plus") { showingAddLocation = true }
            }
        } else {
            ForEach(filteredLocations, id: \.clientId) { location in
                locationButton(location, depth: nil)
            }
        }
    }

    // MARK: - Public browse

    @ViewBuilder
    private var publicRows: some View {
        if !connectivity.isOnline {
            emptyStateRow(
                title: "Offline",
                message: "Öffentliche Teile anderer Nutzer sind nur online verfügbar.",
                icon: "wifi.slash"
            )
        } else if viewModel.publicParts.isEmpty && viewModel.publicError == nil
            && (viewModel.isLoadingPublic || !publicLoadedOnce) {
            // Placeholders from the very first frame: the load task only starts
            // *after* this renders, so gating on `isLoadingPublic` alone flashed
            // the empty state before every load.
            ForEach(0..<4, id: \.self) { _ in
                PartCard.placeholder
                    .redacted(reason: .placeholder)
            }
        } else if let error = viewModel.publicError {
            emptyStateRow(title: "Fehler", message: error, icon: "exclamationmark.triangle.fill")
        } else if viewModel.publicParts.isEmpty {
            emptyStateRow(
                title: "Keine öffentlichen Teile",
                message: "Andere Nutzer haben noch keine passenden Teile geteilt.",
                icon: "shippingbox"
            )
        } else {
            ForEach(viewModel.publicParts) { part in
                PublicPartCard(part: part, viewModel: viewModel)
            }
        }
    }

    private func emptyStateRow(title: String, message: String, icon: String) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
        } description: {
            Text(message)
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}

// MARK: - Cards

private struct StorageLocationCard: View {
    let location: SDStorageLocation
    let parentPath: String?
    let placeName: String?
    /// Parts stocked directly at this location.
    let directCount: Int
    /// Parts stocked here or in any nested container — what the big number
    /// shows, so a parent full of stocked boxes never reads "0 Teile".
    let totalCount: Int
    /// Nesting level in the tree; nested rows indent and use a smaller icon.
    var depth: Int = 0

    /// Skeleton stand-in for the loading state (rendered `.redacted`).
    static var placeholder: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(.quaternary)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text("Regal A · Kiste 3")
                Text("Garage")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("4")
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: depth == 0 ? "archivebox.fill" : "shippingbox")
                .scaledFont(depth == 0 ? 16 : 14, weight: .semibold)
                .foregroundStyle(depth == 0 ? AnyShapeStyle(Theme.Colors.primary) : AnyShapeStyle(.secondary))
                .frame(width: depth == 0 ? 36 : 30, height: depth == 0 ? 36 : 30)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.badge)
                    .fill(depth == 0 ? Theme.Colors.primary.opacity(0.15) : Color.primary.opacity(0.06)))
                .padding(.leading, CGFloat(min(depth, 4)) * 22)
                .overlay(alignment: .topTrailing) {
                    if location.syncState.isPending { PendingBadge().offset(x: 5, y: -5) }
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(location.name)
                    .scaledFont(15, weight: .bold)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let parentPath {
                    Text(parentPath)
                        .scaledFont(11, weight: .semibold)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let placeName {
                    Label(placeName, systemImage: "mappin.and.ellipse")
                        .scaledFont(11, weight: .semibold)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(totalCount)")
                    .scaledFont(17, weight: .heavy)
                    .monospacedDigit()
                    .foregroundStyle(totalCount > 0 ? AnyShapeStyle(Theme.Colors.primary) : AnyShapeStyle(.tertiary))
                Text(totalCount != directCount ? "gesamt" : (totalCount == 1 ? "Teil" : "Teile"))
                    .scaledFont(9, weight: .heavy)
                    .tracking(1)
                    .foregroundStyle(.tertiary)
            }
            Image(systemName: "chevron.right")
                .scaledFont(12, weight: .bold)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Storage location creation

/// A new storage record can either live below another storage location or be
/// anchored directly to a physical garage/workshop. Those are mutually
/// exclusive relationships in the API, so one placement picker makes the
/// choice explicit.
private struct AddStorageLocationView: View {
    @ObservedObject var viewModel: PartsViewModel
    let places: [Location]

    @State private var name = ""
    @State private var placement: Placement = .none
    @State private var errorMessage: String?

    private enum Placement: Hashable {
        case none
        case storageLocation(UUID)
        case place(Int)
    }

    private var garages: [Location] {
        places
            .filter { $0.type == "storage" }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var workshops: [Location] {
        places
            .filter { $0.type == "maintenanceShop" }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        FormSheet(
            title: "Lagerort hinzufügen",
            canSave: canSave,
            tracked: [name, placement],
            error: errorMessage,
            onSave: save
        ) {
            FormField("Name") {
                TextField("", text: $name, prompt: formPrompt("z. B. Regal A"))
                    .textInputAutocapitalization(.sentences)
            }
            FormField(
                "Untergebracht in",
                hint: "Wähle einen bestehenden Lagerort, eine Garage oder eine Werkstatt."
            ) {
                Picker("Untergebracht in", selection: $placement) {
                    Text("Kein übergeordneter Ort")
                        .tag(Placement.none)

                    if !viewModel.storageLocations.isEmpty {
                        Section("Lagerorte") {
                            ForEach(viewModel.storageLocations, id: \.clientId) { location in
                                Text(viewModel.locationPath(location) ?? location.name)
                                    .tag(Placement.storageLocation(location.clientId))
                            }
                        }
                    }

                    if !garages.isEmpty {
                        Section("Garagen & Lager") {
                            ForEach(garages) { place in
                                Text(place.name)
                                    .tag(Placement.place(place.id))
                            }
                        }
                    }

                    if !workshops.isEmpty {
                        Section("Werkstätten") {
                            ForEach(workshops) { workshop in
                                Text(workshop.name)
                                    .tag(Placement.place(workshop.id))
                            }
                        }
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
        }
    }

    private func save() async -> Bool {
        errorMessage = nil
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }

        let created: SDStorageLocation?
        switch placement {
        case .none:
            created = viewModel.createStorageLocation(name: trimmedName, parent: nil)
        case .storageLocation(let clientId):
            created = viewModel.createStorageLocation(
                name: trimmedName,
                parent: viewModel.storageLocation(clientId: clientId)
            )
        case .place(let locationId):
            created = viewModel.createStorageLocation(
                name: trimmedName,
                parent: nil,
                locationId: locationId
            )
        }

        guard created != nil else {
            errorMessage = "Lagerort konnte nicht gespeichert werden."
            return false
        }
        return true
    }
}

private struct PartCard: View {
    let part: SDPart
    let onHand: Int
    /// Where the part is stocked (first place), shown after the number.
    var place: String? = nil
    @ObservedObject var viewModel: PartsViewModel

    /// Skeleton stand-in for the loading state (rendered `.redacted`).
    static var placeholder: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: Theme.Radius.controlInner)
                .fill(.quaternary)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text("Bremsbeläge vorn")
                Text("07BB37.SA · Regal A")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("2")
        }
        .padding(.vertical, 4)
    }

    /// Orange at one piece, red at none.
    private var stockTint: Color {
        onHand <= 0 ? Theme.Colors.accent : onHand == 1 ? .orange : Theme.Colors.primary
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.controlInner)
                    .fill(Theme.Colors.primary.opacity(0.10))
                if let imageURL = part.image {
                    RemoteImageView(url: imageURL, maxPixelWidth: 160)
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "shippingbox")
                        .scaledFont(18, weight: .semibold)
                        .foregroundStyle(Theme.Colors.primary)
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.controlInner))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    // Two lines: similar parts often differ only in the tail
                    // of the name, which a one-line clamp cuts off.
                    Text(part.name)
                        .scaledFont(15, weight: .bold)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if part.isPublic {
                        Image(systemName: "globe")
                            .scaledFont(10, weight: .bold)
                            .foregroundStyle(.tertiary)
                            .accessibilityLabel("Öffentlich")
                    }
                }
                HStack(spacing: 0) {
                    Text(part.partNumber).monospaced()
                    if let place { Text(" · \(place)") }
                }
                .scaledFont(12, weight: .medium)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 0)

            Text("\(onHand)")
                .scaledFont(16, weight: .heavy)
                .monospacedDigit()
                .foregroundStyle(stockTint)
                .padding(.horizontal, 8)
                .frame(minWidth: 40, minHeight: 34)
                .background(stockTint.opacity(0.15), in: RoundedRectangle(cornerRadius: Theme.Radius.controlInner))
                .accessibilityLabel("Bestand \(onHand)")
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

private struct PublicPartCard: View {
    let part: PublicPart
    @ObservedObject var viewModel: PartsViewModel

    var body: some View {
        HStack(spacing: 12) {
            if let imageURL = part.image {
                RemoteImageView(url: imageURL, maxPixelWidth: 160)
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.controlInner))
            } else {
                Image(systemName: "globe")
                    .scaledFont(17, weight: .semibold)
                    .foregroundStyle(.secondary)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.primary.opacity(0.08)))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(part.name)
                    .scaledFont(15, weight: .bold)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(part.partNumber)
                    .scaledFont(11, weight: .semibold)
                    .monospaced()
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text("von \(part.ownerName)")
                    if !part.seriesIds.isEmpty {
                        Text("·")
                        Text(part.seriesIds.prefix(2).map { viewModel.seriesName($0) }.joined(separator: ", "))
                            .lineLimit(1)
                    }
                }
                .scaledFont(10, weight: .semibold)
                .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)

            // Availability is only shared for public parts; private ones show
            // catalog data with a neutral badge.
            let availability = part.hasStock
            Text(availability == nil ? "Bestand privat" : (availability == true ? "Auf Lager" : "Nicht auf Lager"))
                .scaledFont(10, weight: .heavy)
                .foregroundStyle(availability == true ? AnyShapeStyle(Color.white) : AnyShapeStyle(.secondary))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(availability == true ? AnyShapeStyle(Theme.Colors.primary) : AnyShapeStyle(Color.primary.opacity(0.10)))
                )
        }
        .padding(.vertical, 4)
    }
}
