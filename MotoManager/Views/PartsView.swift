import SwiftUI

/// The "Teile" tab: the user's parts inventory (offline-first) plus a browse
/// segment for other users' public parts (online-only).
struct PartsView: View {
    @ObservedObject var viewModel: PartsViewModel
    /// The bike detail VM — drives the shared header and status accessory.
    @ObservedObject var detailVM: MotorcycleDetailViewModel
    /// The currently selected bike, used for the "Passend für …" filter chip.
    let motorcycle: Motorcycle?
    @Environment(\.chromeActions) private var chrome
    @ObservedObject private var quickActions = QuickActionRouter.shared

    enum PartsTab: Hashable { case mine, locations, publicParts }
    @State private var tab: PartsTab = .mine
    @State private var searchText = ""
    /// On by default: the tab lives under a specific bike, so parts fitting
    /// that bike are the expected view — the toggle widens to the whole
    /// inventory instead of narrowing it. Inert when the bike has no linked
    /// model series (`filteredParts` ignores it then, and the toggle is hidden).
    @State private var filterBySelectedBike = true
    @State private var showingAddPart = false
    @State private var selectedPart: SDPart?
    @State private var partPendingDeletion: SDPart?
    @State private var showingScanner = false
    @State private var pendingScan: ScannedLabel?
    @State private var selectedLocation: SDStorageLocation?
    @State private var showingScanNotFound = false
    @State private var showingAddLocation = false
    /// Whether the public browse has completed at least one load this session —
    /// before that, the segment shows placeholders instead of a flashing
    /// empty state.
    @State private var publicLoadedOnce = false
    @ObservedObject private var connectivity = ConnectivityMonitor.shared

    var body: some View {
        List {
            // Match the other tabs: stat strip on the extended photo, below it
            // at accessibility text sizes.
            Section {
                MotorcycleHeaderWithStats(
                    motorcycle: detailVM.motorcycle, type: .parts, viewModel: detailVM,
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
                        .init(value: PartsTab.mine, label: "Meine Teile", count: viewModel.parts.count),
                        .init(value: PartsTab.locations, label: "Lagerorte", count: viewModel.storageLocations.count),
                        .init(value: PartsTab.publicParts, label: "Öffentlich")
                    ],
                    selection: $tab
                )
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            // One stable section whose *rows* switch with the segment — swapping
            // whole sections made the list rebuild its section chrome on every
            // switch, which showed as brief content flashes.
            Section {
                switch tab {
                case .mine:
                    mineRows
                case .locations:
                    locationRows
                case .publicParts:
                    publicRows
                }
            }
        }
        .adaptiveContentWidth()
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .ignoresSafeArea(edges: .top)
        .searchable(
            text: $searchText,
            prompt: tab == .locations ? "Lagerort suchen …" : "Name oder Teilenummer …"
        )
        // Collapse the search field into a toolbar button (iOS 26 pattern) —
        // an always-open drawer would float over the full-bleed hero photo.
        .searchToolbarBehavior(.minimize)
        .toolbar {
            // Adding targets whatever the segment shows (part or storage
            // location); the public segment is read-only. Scan is a standalone
            // button — it is the most frequent action at the shelf and must
            // not hide behind a menu. The items stay in the bar permanently
            // and merely disable on Öffentlich — removing them made the whole
            // toolbar re-layout (a visible flash) on every segment switch.
            ToolbarItem(placement: .topBarTrailing) {
                Button("Etikett scannen", systemImage: "qrcode.viewfinder") {
                    showingScanner = true
                }
                .disabled(tab == .publicParts)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(addLabel, systemImage: "plus", action: addAction)
                    .disabled(tab == .publicParts)
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) {
                Button("Einstellungen", systemImage: "gearshape") {
                    chrome.openSettings()
                }
            }
        }
        .refreshable {
            await SyncEngine.shared.sync(motorcycleIds: [])
            viewModel.reloadLocal()
            if tab == .publicParts {
                await viewModel.loadPublicParts(query: searchText.isEmpty ? nil : searchText)
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
            guard action == .scanPart else { return }
            quickActions.pending = nil
            showingScanner = true
        }
        .sheet(isPresented: $showingAddPart) {
            AddPartView(viewModel: viewModel)
                .glassSheet()
        }
        .navigationDestination(item: $selectedPart) { part in
            PartDetailView(part: part, viewModel: viewModel)
        }
        // The scan result only gets stashed here; pushing the part/location
        // detail must wait for the scanner sheet's dismissal so the push
        // animation doesn't fight the sheet's — onDismiss fires after the
        // animation completes.
        .sheet(isPresented: $showingScanner, onDismiss: resolvePendingScan) {
            LabelScanSheet { pendingScan = $0 }
                .glassSheet()
        }
        .navigationDestination(item: $selectedLocation) { location in
            StorageLocationDetailView(
                location: location,
                viewModel: viewModel,
                placeName: detailVM.location(id: location.locationId)?.name
            )
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
                selectedPart = part
            } else {
                showingScanNotFound = true
            }
        case .storageLocation(let serverId):
            if let location = viewModel.storageLocation(serverId: serverId) {
                selectedLocation = location
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
                eyebrow: "Teile",
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
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if !query.isEmpty {
            result = result.filter {
                $0.name.lowercased().contains(query) || $0.partNumber.lowercased().contains(query)
            }
        }
        return result
    }

    /// True when the empty list is caused by the default bike filter alone —
    /// the message must then point at the toggle, not at a search query.
    private var emptyBecauseOfBikeFilter: Bool {
        filterBySelectedBike && motorcycle?.seriesId != nil
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

    @ViewBuilder
    private var mineRows: some View {
        if let moto = motorcycle, moto.seriesId != nil {
            Toggle(isOn: $filterBySelectedBike) {
                Text("Passend für \(moto.make) \(moto.model)")
                    .scaledFont(13, weight: .semibold)
            }
            .tint(Theme.Colors.primary)
        }

        if filteredParts.isEmpty {
            emptyStateRow(title: emptyPartsTitle, message: emptyPartsMessage, icon: "shippingbox.fill")
        } else {
            ForEach(filteredParts, id: \.clientId) { part in
                Button {
                    selectedPart = part
                } label: {
                    PartCard(part: part, onHand: viewModel.onHand(for: part), viewModel: viewModel)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        partPendingDeletion = part
                    } label: {
                        Label("Löschen", systemImage: "trash")
                    }
                    .tint(.red)
                }
            }
        }
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

    @ViewBuilder
    private var locationRows: some View {
        if filteredLocations.isEmpty {
            emptyStateRow(
                title: viewModel.storageLocations.isEmpty ? "Keine Lagerorte" : "Keine Treffer",
                message: viewModel.storageLocations.isEmpty
                    ? "Lege mit dem Plus-Button einen Lagerort an — sie entstehen auch beim Erfassen von Beständen."
                    : "Kein Lagerort passt zur Suche.",
                icon: "archivebox.fill"
            )
        } else {
            ForEach(filteredLocations, id: \.clientId) { location in
                Button {
                    selectedLocation = location
                } label: {
                    StorageLocationCard(
                        location: location,
                        parentPath: viewModel.locationParentPath(location),
                        placeName: detailVM.location(id: location.locationId)?.name,
                        directCount: viewModel.stockedParts(at: location).count,
                        totalCount: viewModel.totalStockedPartCount(at: location)
                    )
                }
                .buttonStyle(.plain)
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

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "archivebox.fill")
                .scaledFont(17, weight: .semibold)
                .foregroundStyle(Theme.Colors.primary)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Theme.Colors.primary.opacity(0.15)))
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

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var placement: Placement = .none

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

    var body: some View {
        NavigationStack {
            Form {
                Section("Lagerort") {
                    TextField("Name, z. B. Regal A", text: $name)
                        .textInputAutocapitalization(.sentences)
                }

                Section {
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
                    .pickerStyle(.navigationLink)
                } footer: {
                    Text("Wähle einen bestehenden Lagerort, eine Garage oder eine Werkstatt.")
                }
            }
            .navigationTitle("Neuer Lagerort")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Anlegen", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

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

        if created != nil { dismiss() }
    }
}

private struct PartCard: View {
    let part: SDPart
    let onHand: Int
    @ObservedObject var viewModel: PartsViewModel

    /// Skeleton stand-in for the loading state (rendered `.redacted`).
    static var placeholder: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: Theme.Radius.controlInner)
                .fill(.quaternary)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text("Bremsbeläge vorn")
                Text("07BB37.SA")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("2")
        }
        .padding(.vertical, 4)
    }

    var body: some View {
        HStack(spacing: 12) {
            if let imageURL = part.image {
                RemoteImageView(url: imageURL, maxPixelWidth: 160)
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.controlInner))
            } else {
                Image(systemName: "shippingbox.fill")
                    .scaledFont(17, weight: .semibold)
                    .foregroundStyle(Theme.Colors.primary)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Theme.Colors.primary.opacity(0.15)))
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .top, spacing: 6) {
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
                    }
                }
                Text(part.partNumber)
                    .scaledFont(11, weight: .semibold)
                    .monospaced()
                    .foregroundStyle(.secondary)
                if !part.seriesIds.isEmpty {
                    Text(seriesSummary)
                        .scaledFont(10, weight: .semibold)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(onHand)")
                    .scaledFont(17, weight: .heavy)
                    .monospacedDigit()
                    .foregroundStyle(onHand > 0 ? AnyShapeStyle(Theme.Colors.primary) : AnyShapeStyle(.tertiary))
                Text("Bestand")
                    .scaledFont(9, weight: .heavy)
                    .tracking(1)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private var seriesSummary: String {
        let names = part.seriesIds.prefix(3).map { viewModel.seriesName($0) }
        let more = part.seriesIds.count - names.count
        return names.joined(separator: " · ") + (more > 0 ? " +\(more)" : "")
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
