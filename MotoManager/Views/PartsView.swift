import SwiftUI

/// The "Teile" tab: the user's parts inventory (offline-first) plus a browse
/// segment for other users' public parts (online-only).
struct PartsView: View {
    @ObservedObject var viewModel: PartsViewModel
    /// The currently selected bike, used for the "Passend für …" filter chip.
    let motorcycle: Motorcycle?

    enum PartsTab: Hashable { case mine, publicParts }
    @State private var tab: PartsTab = .mine
    @State private var searchText = ""
    @State private var filterBySelectedBike = false
    @State private var showingAddPart = false
    @State private var selectedPart: SDPart?
    @ObservedObject private var connectivity = ConnectivityMonitor.shared

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.m) {
                header
                    .padding(.horizontal, Theme.Spacing.m)

                GlassSegmentedControl(
                    segments: [
                        .init(value: PartsTab.mine, label: "Meine Teile", count: viewModel.parts.count),
                        .init(value: PartsTab.publicParts, label: "Öffentlich")
                    ],
                    selection: $tab
                )
                .padding(.horizontal, Theme.Spacing.m)

                searchField
                    .padding(.horizontal, Theme.Spacing.m)

                if tab == .mine {
                    mineContent
                        .padding(.horizontal, Theme.Spacing.m)
                } else {
                    publicContent
                        .padding(.horizontal, Theme.Spacing.m)
                }
            }
            .padding(.top, Theme.Spacing.xl * 2)
            .padding(.bottom, 110)
        }
        .background(Color.clear)
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
                prompt: Text("Name oder Teilenummer …").foregroundColor(.white.opacity(0.35))
            )
            .foregroundColor(.white)
            .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button {
                    searchText = ""
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
            result = result.filter { $0.seriesIds.contains(seriesId) }
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
            addPartCTA

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

    private var addPartCTA: some View {
        Button { showingAddPart = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 16, weight: .semibold))
                Text("Teil hinzufügen")
                    .font(.system(size: 15, weight: .bold))
                Spacer(minLength: 0)
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .bold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Theme.Colors.primary, in: RoundedRectangle(cornerRadius: 18))
            .shadow(color: Theme.Colors.primary.opacity(0.4), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(.plain)
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

            Text(part.hasStock ? "Auf Lager" : "Nicht auf Lager")
                .font(.system(size: 10, weight: .heavy))
                .foregroundColor(part.hasStock ? .white : .white.opacity(0.5))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(part.hasStock ? Theme.Colors.primary : Color.white.opacity(0.10))
                )
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.l).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.l).stroke(Theme.Glass.border, lineWidth: 0.5))
    }
}
