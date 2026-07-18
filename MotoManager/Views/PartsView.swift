import SwiftUI

/// The "Teile" tab: the user's parts inventory (offline-first) plus a browse
/// segment for other users' public parts (online-only).
struct PartsView: View {
    @ObservedObject var viewModel: PartsViewModel
    /// The bike detail VM — drives the shared offline banner overlay.
    @ObservedObject var detailVM: MotorcycleDetailViewModel
    /// The currently selected bike, used for the "Passend für …" filter chip.
    let motorcycle: Motorcycle?

    enum PartsTab: Hashable { case mine, locations, publicParts }
    @State private var tab: PartsTab = .mine
    @State private var searchText = ""
    @State private var filterBySelectedBike = false
    @State private var showingAddPart = false
    @State private var selectedPart: SDPart?
    @State private var showingScanner = false
    @State private var pendingScan: ScannedLabel?
    @State private var selectedLocation: SDStorageLocation?
    @State private var showingScanNotFound = false
    @FocusState private var searchFocused: Bool
    @ObservedObject private var connectivity = ConnectivityMonitor.shared

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.m) {
                header
                    .padding(.horizontal, Theme.Spacing.pageH)

                GlassSegmentedControl(
                    segments: [
                        .init(value: PartsTab.mine, label: "Meine Teile", count: viewModel.parts.count),
                        .init(value: PartsTab.locations, label: "Lagerorte", count: viewModel.storageLocations.count),
                        .init(value: PartsTab.publicParts, label: "Öffentlich")
                    ],
                    selection: $tab
                )
                .padding(.horizontal, Theme.Spacing.m)

                searchField
                    .padding(.horizontal, Theme.Spacing.pageH)

                switch tab {
                case .mine:
                    mineContent
                        .padding(.horizontal, Theme.Spacing.pageH)
                case .locations:
                    locationsContent
                        .padding(.horizontal, Theme.Spacing.pageH)
                case .publicParts:
                    publicContent
                        .padding(.horizontal, Theme.Spacing.pageH)
                }
            }
            .padding(.top, Theme.Spacing.xl * 2)
            .padding(.bottom, 110)
        }
        // The search keyboard must always be escapable — scrolling dismisses
        // it, and the clear button in the field offers an explicit way out
        // (without either, the custom tab bar stays buried behind the keyboard).
        .scrollDismissesKeyboard(.immediately)
        .background(Color.clear)
        // Add and label scanning are only meaningful for the user's own
        // inventory; scanning also resolves bin labels, so it stays available
        // on the Lagerorte segment.
        .bottomActionBar(
            detailVM: detailVM,
            addLabel: tab == .mine ? "Teil hinzufügen" : nil,
            addAction: tab == .mine ? { showingAddPart = true } : nil,
            secondaryIcon: tab != .publicParts ? "qrcode.viewfinder" : nil,
            secondaryLabel: tab != .publicParts ? "Etikett scannen" : nil,
            secondaryAction: tab != .publicParts ? { showingScanner = true } : nil
        )
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
            }
        }
        .sheet(isPresented: $showingAddPart) {
            AddPartView(viewModel: viewModel)
                .presentationDetents([.large])
                .presentationCornerRadius(Theme.Glass.sheetRadius)
                .presentationBackground(.regularMaterial)
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedPart) { part in
            PartDetailView(part: part, viewModel: viewModel)
                .presentationDetents([.large])
                .presentationCornerRadius(Theme.Glass.sheetRadius)
                .presentationBackground(.regularMaterial)
                .presentationDragIndicator(.hidden)
        }
        // The scan result only gets stashed here; the part/location sheets are
        // siblings of the scanner sheet, so presenting them must wait for its
        // dismissal — onDismiss fires after the animation completes.
        .sheet(isPresented: $showingScanner, onDismiss: resolvePendingScan) {
            LabelScanSheet { pendingScan = $0 }
                .presentationDetents([.large])
                .presentationCornerRadius(Theme.Glass.sheetRadius)
                .presentationBackground(.regularMaterial)
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedLocation) { location in
            StorageLocationDetailView(location: location, viewModel: viewModel)
                .presentationDetents([.large])
                .presentationCornerRadius(Theme.Glass.sheetRadius)
                .presentationBackground(.regularMaterial)
                .presentationDragIndicator(.hidden)
        }
        .alert("Etikett nicht gefunden", isPresented: $showingScanNotFound) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Zu diesem QR-Code gibt es lokal keinen Eintrag. Möglicherweise wurde er noch nicht synchronisiert — zum Aktualisieren nach unten ziehen.")
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

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Teile")
                .font(.system(size: 30, weight: .heavy))
                .foregroundColor(.white)
            Spacer()
            Text("\(viewModel.parts.count) \(viewModel.parts.count == 1 ? "Teil" : "Teile")")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.55))
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
            TextField(
                "",
                text: $searchText,
                prompt: Text(tab == .locations ? "Lagerort suchen …" : "Name oder Teilenummer …")
                    .foregroundColor(.white.opacity(0.35))
            )
            .foregroundColor(.white)
            .autocorrectionDisabled()
            .focused($searchFocused)
            .submitLabel(.search)
            // Visible while typing OR focused: clears the query and drops
            // focus, so the keyboard can always be dismissed from the field.
            if searchFocused || !searchText.isEmpty {
                Button {
                    searchText = ""
                    searchFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.4))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: Theme.Glass.fieldRadius).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: Theme.Glass.fieldRadius).stroke(Theme.Glass.border, lineWidth: 0.5))
        .onSubmit {
            if tab == .publicParts {
                Task { await viewModel.loadPublicParts(query: searchText.isEmpty ? nil : searchText) }
            }
        }
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

    @ViewBuilder
    private var mineContent: some View {
        VStack(spacing: Theme.Spacing.s) {
            if let moto = motorcycle, moto.seriesId != nil {
                Toggle(isOn: $filterBySelectedBike) {
                    Text("Passend für \(moto.make) \(moto.model)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                }
                .tint(Theme.Colors.primary)
                .padding(.horizontal, 4)
            }

            if filteredParts.isEmpty {
                EmptyStateView(
                    title: viewModel.parts.isEmpty ? "Keine Teile erfasst" : "Keine Treffer",
                    message: viewModel.parts.isEmpty
                        ? "Lege dein erstes Ersatzteil an — Bestand und Verbrauch werden automatisch geführt."
                        : "Kein Teil passt zu Suche oder Filter.",
                    icon: "shippingbox.fill"
                )
                .padding(.top, 40)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(filteredParts, id: \.clientId) { part in
                        Button {
                            selectedPart = part
                        } label: {
                            PartCard(part: part, onHand: viewModel.onHand(for: part), viewModel: viewModel)
                        }
                        .buttonStyle(.plain)
                    }
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
    private var locationsContent: some View {
        if filteredLocations.isEmpty {
            EmptyStateView(
                title: viewModel.storageLocations.isEmpty ? "Keine Lagerorte" : "Keine Treffer",
                message: viewModel.storageLocations.isEmpty
                    ? "Lagerorte entstehen beim Erfassen von Beständen — oder scanne ein Etikett."
                    : "Kein Lagerort passt zur Suche.",
                icon: "archivebox.fill"
            )
            .padding(.top, 40)
        } else {
            LazyVStack(spacing: 10) {
                ForEach(filteredLocations, id: \.clientId) { location in
                    Button {
                        selectedLocation = location
                    } label: {
                        StorageLocationCard(
                            location: location,
                            parentPath: parentPath(location),
                            partCount: viewModel.stockedParts(at: location).count
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Breadcrumb of the ancestors only ("Garage › Regal A" for "Kiste 3"),
    /// nil for root locations.
    private func parentPath(_ location: SDStorageLocation) -> String? {
        guard let path = viewModel.locationPath(location) else { return nil }
        let ancestors = path.components(separatedBy: " › ").dropLast()
        return ancestors.isEmpty ? nil : ancestors.joined(separator: " › ")
    }

    // MARK: - Public browse

    @ViewBuilder
    private var publicContent: some View {
        if !connectivity.isOnline {
            EmptyStateView(
                title: "Offline",
                message: "Öffentliche Teile anderer Nutzer sind nur online verfügbar.",
                icon: "wifi.slash"
            )
            .padding(.top, 60)
        } else if viewModel.isLoadingPublic && viewModel.publicParts.isEmpty {
            VStack(spacing: 10) {
                ForEach(0..<4, id: \.self) { _ in
                    GlassShimmerRow()
                }
            }
        } else if let error = viewModel.publicError {
            EmptyStateView(
                title: "Fehler",
                message: error,
                icon: "exclamationmark.triangle.fill"
            )
            .padding(.top, 60)
        } else if viewModel.publicParts.isEmpty {
            EmptyStateView(
                title: "Keine öffentlichen Teile",
                message: "Andere Nutzer haben noch keine passenden Teile geteilt.",
                icon: "shippingbox"
            )
            .padding(.top, 60)
        } else {
            LazyVStack(spacing: 10) {
                ForEach(viewModel.publicParts) { part in
                    PublicPartCard(part: part, viewModel: viewModel)
                }
            }
        }
    }
}

// MARK: - Cards

private struct StorageLocationCard: View {
    let location: SDStorageLocation
    let parentPath: String?
    let partCount: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "archivebox.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Theme.Colors.primary)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Theme.Colors.primary.opacity(0.15)))
                .overlay(alignment: .topTrailing) {
                    if location.syncState.isPending { PendingBadge().offset(x: 5, y: -5) }
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(location.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
                if let parentPath {
                    Text(parentPath)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(partCount)")
                    .font(.system(size: 17, weight: .heavy))
                    .monospacedDigit()
                    .foregroundColor(partCount > 0 ? Theme.Colors.primary : .white.opacity(0.35))
                Text(partCount == 1 ? "Teil" : "Teile")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1)
                    .foregroundColor(.white.opacity(0.4))
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white.opacity(0.35))
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.l).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.l).stroke(Theme.Glass.border, lineWidth: 0.5))
    }
}

private struct PartCard: View {
    let part: SDPart
    let onHand: Int
    @ObservedObject var viewModel: PartsViewModel

    var body: some View {
        HStack(spacing: 12) {
            if let imageURL = part.image {
                RemoteImageView(url: imageURL, maxPixelWidth: 160)
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Theme.Colors.primary)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Theme.Colors.primary.opacity(0.15)))
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(part.name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    if part.isPublic {
                        Image(systemName: "globe")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.45))
                    }
                }
                Text(part.partNumber)
                    .font(.system(size: 11, weight: .semibold))
                    .monospaced()
                    .foregroundColor(.white.opacity(0.55))
                if !part.seriesIds.isEmpty {
                    Text(seriesSummary)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.45))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(onHand)")
                    .font(.system(size: 17, weight: .heavy))
                    .monospacedDigit()
                    .foregroundColor(onHand > 0 ? Theme.Colors.primary : .white.opacity(0.35))
                Text("Bestand")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1)
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.l).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.l).stroke(Theme.Glass.border, lineWidth: 0.5))
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
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(part.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(part.partNumber)
                    .font(.system(size: 11, weight: .semibold))
                    .monospaced()
                    .foregroundColor(.white.opacity(0.55))
                HStack(spacing: 6) {
                    Text("von \(part.ownerName)")
                    if !part.seriesIds.isEmpty {
                        Text("·")
                        Text(part.seriesIds.prefix(2).map { viewModel.seriesName($0) }.joined(separator: ", "))
                            .lineLimit(1)
                    }
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.45))
            }
            Spacer(minLength: 0)

            // Availability is only shared for public parts; private ones show
            // catalog data with a neutral badge.
            let availability = part.hasStock
            Text(availability == nil ? "Bestand privat" : (availability == true ? "Auf Lager" : "Nicht auf Lager"))
                .font(.system(size: 10, weight: .heavy))
                .foregroundColor(availability == true ? .white : .white.opacity(0.5))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(availability == true ? Theme.Colors.primary : Color.white.opacity(0.10))
                )
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.l).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.l).stroke(Theme.Glass.border, lineWidth: 0.5))
    }
}
