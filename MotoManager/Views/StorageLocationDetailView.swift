import SwiftUI

/// Pushed detail page for a storage location (opened from the parts tab or by
/// scanning its printed QR label): the bin's name and path plus every part
/// stocked there, each row pushing the part's detail page.
struct StorageLocationDetailView: View {
    let location: SDStorageLocation
    @ObservedObject var viewModel: PartsViewModel
    let placeName: String?
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPart: SDPart?
    @State private var selectedChild: SDStorageLocation?
    /// Wide panes show the contents as cards, narrow ones as rows.
    @State private var width: CGFloat = 0
    @State private var showingPrintLabel = false
    @State private var didAutoDismiss = false
    /// Captured at init so the auto-pop guard never reads a deleted model.
    private let locationClientId: UUID

    init(location: SDStorageLocation, viewModel: PartsViewModel, placeName: String? = nil) {
        self.location = location
        self.viewModel = viewModel
        self.placeName = placeName
        self.locationClientId = location.clientId
    }

    private var stockedParts: [(part: SDPart, quantity: Int)] {
        viewModel.stockedParts(at: location)
    }

    /// Label for this bin — same content the per-stock print in
    /// `PartDetailView` builds. Requires a server id (the QR links to the
    /// location's web page), so it's unavailable while waiting to sync.
    private var labelContent: LabelContent? {
        guard let serverId = location.serverId else { return nil }
        return LabelContent(
            url: LabelWebLinks.storageLocationURL(serverId: serverId),
            code: nil,
            title: location.name,
            // Ancestors only — the name is already the label title.
            subtitle: viewModel.locationParentPath(location),
            footer: "MotoManager · Lagerort #\(serverId)"
        )
    }

    var body: some View {
        List {
            headerSection
            Section { StatStrip(statTiles).listRowInsets(EdgeInsets()) }
            if !children.isEmpty { childrenSection }
            partsSection
        }
        .workspaceListStyle()
        .scrollContentBackground(.hidden)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .frame(maxWidth: 900)
        .frame(maxWidth: .infinity)
        .background(Theme.Colors.background.ignoresSafeArea())
        .toolbar(.visible, for: .navigationBar)
        .navigationTitle(location.name)
        .navigationBarTitleDisplayMode(.inline)
        // The header below already shows the name; the bar keeps it only
        // for the back button's history menu.
        .toolbar {
            ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1).accessibilityHidden(true) }
        }
        .accessibilityIdentifier("location.detail")
        .navigationDestination(item: $selectedChild) { child in
            StorageLocationDetailView(location: child, viewModel: viewModel, placeName: placeName)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingPrintLabel = true } label: {
                    Image(systemName: "printer.fill")
                }
                .accessibilityLabel("Etikett drucken")
                .disabled(labelContent == nil)
            }
        }
        .navigationDestination(item: $selectedPart) { part in
            PartDetailView(part: part, viewModel: viewModel)
        }
        .sheet(isPresented: $showingPrintLabel) {
            if let content = labelContent {
                PrintLabelView(content: content)
                    .glassSheet()
            }
        }
        // Pop back if the location disappears underneath us (remote delete
        // via sync).
        .onReceive(viewModel.$storageLocations) { locations in
            guard !didAutoDismiss,
                  !locations.contains(where: { $0.clientId == locationClientId }) else { return }
            didAutoDismiss = true
            dismiss()
        }
    }

    private var pathSubtitle: String? {
        if let parent = viewModel.locationParentPath(location) {
            return [placeName, parent].compactMap { $0 }.joined(separator: " › ")
        }
        return placeName
    }

    private var children: [SDStorageLocation] { viewModel.children(of: location) }

    private var pieces: Int { stockedParts.reduce(0) { $0 + $1.quantity } }

    private var value: Double {
        viewModel.stocks(at: location).reduce(0) { $0 + ($1.normalizedPrice ?? $1.price ?? 0) }
    }

    private var statTiles: [StatTile] {
        [
            StatTile(eyebrow: "Teile", value: "\(stockedParts.count)", accent: Theme.Colors.primary),
            StatTile(eyebrow: "Stück", value: "\(pieces)"),
            StatTile(eyebrow: "Wert", value: value > 0 ? Formatters.currency(value, code: "CHF", fractionDigits: 0) : "—")
        ]
    }

    // MARK: - Header

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 3) {
                if let pathSubtitle {
                    Text(pathSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(location.name)
                    .font(.title2.weight(.bold))
                HStack(spacing: Theme.Spacing.s) {
                    if let serverId = location.serverId {
                        Text("Lagerort #\(serverId)")
                    }
                    if location.syncState.isPending {
                        Label("Noch nicht synchronisiert", systemImage: "arrow.triangle.2.circlepath")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
            }
            .accessibilityElement(children: .combine)
        }
        .listRowInsets(EdgeInsets(top: Theme.Spacing.s, leading: Theme.Spacing.xs,
                                  bottom: 0, trailing: Theme.Spacing.xs))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    // MARK: - Nested places

    private var childrenSection: some View {
        Section {
            ForEach(children, id: \.clientId) { child in
                Button { selectedChild = child } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "shippingbox")
                            .scaledFont(14, weight: .semibold)
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 30)
                            .background(RoundedRectangle(cornerRadius: Theme.Radius.badge).fill(Color.primary.opacity(0.06)))
                        Text(child.name).scaledFont(14.5, weight: .semibold)
                        Spacer(minLength: 0)
                        let count = viewModel.totalStockedPartCount(at: child)
                        Text(count == 1 ? "1 Teil" : "\(count) Teile")
                            .scaledFont(12)
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .scaledFont(11, weight: .semibold)
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Enthält")
        }
    }

    // MARK: - Stocked parts

    @ViewBuilder
    private var partsSection: some View {
        if stockedParts.isEmpty {
            Section {
                Text("Keine Teile an diesem Lagerort eingelagert.")
                    .scaledFont(13)
                    .foregroundStyle(.secondary)
            } header: { partsHeader }
        } else if width >= 600 {
            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: Theme.Spacing.listSection)],
                          spacing: Theme.Spacing.listSection) {
                    ForEach(stockedParts, id: \.part.clientId) { entry in
                        Button { selectedPart = entry.part } label: {
                            partCard(entry.part, quantity: entry.quantity)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: { partsHeader }
            .cardRow()
        } else {
            Section {
                ForEach(stockedParts, id: \.part.clientId) { entry in
                    Button { selectedPart = entry.part } label: {
                        partRow(entry.part, quantity: entry.quantity)
                    }
                    .buttonStyle(.plain)
                }
            } header: { partsHeader }
        }
    }

    private var partsHeader: some View {
        HStack {
            Text("Eingelagerte Teile")
            Spacer()
            Text("\(stockedParts.count) \(stockedParts.count == 1 ? "Teil" : "Teile")")
        }
    }

    private func thumbnail(_ part: SDPart, size: CGFloat?) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Radius.controlInner)
                .fill(Theme.Colors.primary.opacity(0.10))
            if let imageURL = part.image {
                RemoteImageView(url: imageURL, maxPixelWidth: 400)
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "shippingbox")
                    .scaledFont(size == nil ? 30 : 18, weight: .semibold)
                    .foregroundStyle(Theme.Colors.primary)
            }
        }
        .frame(width: size, height: size ?? 110)
        .frame(maxWidth: size == nil ? .infinity : nil)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.controlInner))
        .accessibilityHidden(true)
    }

    private func quantityPill(_ quantity: Int) -> some View {
        Text("\(quantity)×")
            .scaledFont(14, weight: .heavy)
            .monospacedDigit()
            .foregroundStyle(Theme.Colors.primary)
            .padding(.horizontal, 7)
            .frame(minWidth: 36, minHeight: 30)
            .background(Theme.Colors.primary.opacity(0.15), in: RoundedRectangle(cornerRadius: Theme.Radius.badge))
    }

    private func partCard(_ part: SDPart, quantity: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            thumbnail(part, size: nil)
            HStack(alignment: .top, spacing: Theme.Spacing.s) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(part.name).scaledFont(14.5, weight: .bold).lineLimit(2)
                    Text(part.partNumber).scaledFont(12).monospaced().foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                quantityPill(quantity)
            }
        }
        .padding(Theme.Spacing.m - 2)
        .background(Theme.Colors.backgroundElevated, in: RoundedRectangle(cornerRadius: Theme.Radius.field))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func partRow(_ part: SDPart, quantity: Int) -> some View {
        HStack(spacing: 12) {
            thumbnail(part, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(part.name)
                    .scaledFont(14.5, weight: .bold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(part.partNumber)
                    .scaledFont(12)
                    .monospaced()
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            quantityPill(quantity)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
