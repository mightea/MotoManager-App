import SwiftUI

/// Detail sheet for a storage location (opened by scanning its printed QR
/// label): the bin's name and path plus every part stocked there, each row
/// opening the part's detail sheet.
struct StorageLocationDetailView: View {
    let location: SDStorageLocation
    @ObservedObject var viewModel: PartsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPart: SDPart?
    @State private var showingPrintLabel = false

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
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                header
                partsSection
            }
            .padding(Theme.Spacing.l)
            .padding(.bottom, 40)
        }
        .background(Color.clear)
        .sheet(item: $selectedPart) { part in
            PartDetailView(part: part, viewModel: viewModel)
                .presentationDetents([.large])
                .presentationCornerRadius(Theme.Glass.sheetRadius)
                .presentationBackground(.regularMaterial)
                .presentationDragIndicator(.hidden)
        }
        .sheet(isPresented: $showingPrintLabel) {
            if let content = labelContent {
                PrintLabelView(content: content)
                    .presentationDetents([.large])
                    .presentationCornerRadius(Theme.Glass.sheetRadius)
                    .presentationBackground(.regularMaterial)
                    .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(location.name)
                    .font(.system(size: 24, weight: .heavy))
                    .foregroundColor(.white)
                if let path = viewModel.locationPath(location), path != location.name {
                    HStack(spacing: 4) {
                        Image(systemName: "archivebox.fill")
                            .font(.system(size: 10))
                        Text(path)
                            .lineLimit(2)
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
                }
                if let serverId = location.serverId {
                    Text("Lagerort #\(serverId)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            Spacer()
            if labelContent != nil {
                Button { showingPrintLabel = true } label: {
                    Image(systemName: "printer.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                }
                .accessibilityLabel("Etikett drucken")
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.white.opacity(0.12)))
            }
            .accessibilityLabel("Schließen")
        }
    }

    // MARK: - Stocked parts

    private var partsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Eingelagerte Teile", count: stockedParts.count)

            if stockedParts.isEmpty {
                Text("Keine Teile an diesem Lagerort eingelagert.")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.5))
            } else {
                VStack(spacing: 8) {
                    ForEach(stockedParts, id: \.part.clientId) { entry in
                        Button { selectedPart = entry.part } label: {
                            partRow(entry.part, quantity: entry.quantity)
                        }
                        .buttonStyle(.plain)
                    }
                }
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
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.Colors.primary)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Theme.Colors.primary.opacity(0.15)))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(part.name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(part.partNumber)
                    .font(.system(size: 11, weight: .semibold))
                    .monospaced()
                    .foregroundColor(.white.opacity(0.5))
            }
            Spacer(minLength: 0)
            Text("\(quantity)×")
                .font(.system(size: 16, weight: .heavy))
                .monospacedDigit()
                .foregroundColor(Theme.Colors.primary)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.3))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Theme.Glass.fieldRadius).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: Theme.Glass.fieldRadius).stroke(Theme.Glass.border, lineWidth: 0.5))
    }

    private func sectionHeader(_ label: String, count: Int) -> some View {
        HStack {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .heavy)).tracking(2)
                .foregroundColor(.white.opacity(0.55))
            Spacer()
            Text("\(count) \(count == 1 ? "Teil" : "Teile")")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
        }
    }
}
