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
        DetailPage(
            accent: Theme.Colors.primary,
            eyebrow: location.syncState.isPending ? "LAGERORT · NICHT SYNCHRON" : "LAGERORT",
            title: location.name,
            subtitle: pathSubtitle,
            heroContent: {
                if let serverId = location.serverId {
                    Text("Lagerort #\(serverId)")
                        .scaledFont(11, weight: .semibold)
                        .foregroundStyle(.tertiary)
                }
            },
            body: { partsSection }
        )
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
        if let path = viewModel.locationPath(location), path != location.name { return path }
        return placeName
    }

    // MARK: - Stocked parts

    private var partsSection: some View {
        Section {
            if stockedParts.isEmpty {
                Text("Keine Teile an diesem Lagerort eingelagert.")
                    .scaledFont(13)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(stockedParts, id: \.part.clientId) { entry in
                    Button { selectedPart = entry.part } label: {
                        partRow(entry.part, quantity: entry.quantity)
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            HStack {
                Text("Eingelagerte Teile")
                Spacer()
                Text("\(stockedParts.count) \(stockedParts.count == 1 ? "Teil" : "Teile")")
            }
        }
    }

    private func partRow(_ part: SDPart, quantity: Int) -> some View {
        HStack(spacing: 12) {
            if let imageURL = part.image {
                RemoteImageView(url: imageURL, maxPixelWidth: 160)
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                Image(systemName: "shippingbox.fill")
                    .scaledFont(15, weight: .semibold)
                    .foregroundStyle(Theme.Colors.primary)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Theme.Colors.primary.opacity(0.15)))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(part.name)
                    .scaledFont(13, weight: .bold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(part.partNumber)
                    .scaledFont(11, weight: .semibold)
                    .monospaced()
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            Text("\(quantity)×")
                .scaledFont(16, weight: .heavy)
                .monospacedDigit()
                .foregroundStyle(Theme.Colors.primary)
            Image(systemName: "chevron.right")
                .scaledFont(11, weight: .semibold)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
