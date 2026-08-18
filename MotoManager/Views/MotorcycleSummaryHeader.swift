import SwiftUI

enum HeaderType {
    case fuel, service, workshop, parts

    var title: String {
        switch self {
        case .fuel: return "Tanken"
        case .service: return "Service"
        case .workshop: return "Werkstatt"
        case .parts: return "Teile"
        }
    }
}

/// Immersive header used at the top of every screen — pure *content* below the
/// system navigation bar (which owns settings/add as toolbar items and applies
/// its own scroll-edge treatment).
///
/// The bike name stays fully visible at 24 pt (2-line clamp for long names like
/// "BMW R 1250 GS Adventure"), the meta line shows year · plate · km, and a
/// dedicated glass "Wechseln" pill button to the right opens the searchable
/// picker.
///
/// Ink is `onPhoto` (always white): the background is a photo, which doesn't
/// adapt to appearance. The scrim gradient exists for the same reason — it
/// guarantees text contrast against arbitrary photo content (an HIG-sanctioned
/// use; it is *not* a tint stacked on system glass).
struct MotorcycleSummaryHeader: View {
    let motorcycle: Motorcycle
    let type: HeaderType
    @ObservedObject var viewModel: MotorcycleDetailViewModel
    /// Extra image height added *below* the header content. The bike block stays
    /// anchored to the top `contentHeight` region while the photo continues down,
    /// so an overlapping element (e.g. the stat strip) sits on the image instead
    /// of a hard black cut-off.
    var bottomExtension: CGFloat = 0

    @Environment(\.chromeActions) private var chrome

    /// Scales with Dynamic Type so the two-line name + meta line never get
    /// clipped out of a fixed box at accessibility sizes.
    @ScaledMetric(relativeTo: .title) private var contentHeight: CGFloat = 180
    private var totalHeight: CGFloat { contentHeight + bottomExtension }

    var body: some View {
        ZStack(alignment: .topLeading) {
            backgroundImage
            darkeningOverlay

            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)
                bikeBlock
            }
            .padding(.horizontal, 14)
            .padding(.top, 54)
            .padding(.bottom, 14)
            // Keep the content in the top region; the extension below is pure image.
            .frame(height: contentHeight, alignment: .bottom)
        }
        .frame(height: totalHeight)
        .clipped()
    }

    // MARK: - Background

    @ViewBuilder
    private var backgroundImage: some View {
        if let url = motorcycle.image {
            RemoteImageView(url: url, maxPixelWidth: 1200)
                .aspectRatio(contentMode: .fill)
                .frame(height: totalHeight)
                .clipped()
        } else {
            Theme.Colors.primary.opacity(0.8)
                .frame(height: totalHeight)
        }
    }

    private var darkeningOverlay: some View {
        // Compress the original 3-stop gradient into the content region so the
        // bike block keeps its exact look; when there's an extension, add a
        // lighter tail below it so the photo shows through behind the stat strip.
        let boundary = contentHeight / totalHeight   // 1.0 when bottomExtension == 0
        var stops: [Gradient.Stop] = [
            .init(color: .black.opacity(0.40), location: 0.0),
            .init(color: .black.opacity(0.10), location: 0.38 * boundary),
            .init(color: .black.opacity(0.78), location: boundary)
        ]
        if bottomExtension > 0 {
            stops.append(.init(color: .black.opacity(0.45), location: 1.0))
        }
        return LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
    }

    // MARK: - Bike block

    private var bikeBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Eyebrow + VETERAN badge
            HStack(spacing: 6) {
                Text(type.title.uppercased())
                    .scaledFont(10, weight: .heavy)
                    .tracking(2)
                    .foregroundStyle(Theme.Colors.onPhotoSecondary)
                if motorcycle.isVeteran {
                    veteranBadge
                }
            }

            HStack(alignment: .bottom, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(motorcycle.make) \(motorcycle.model)")
                        .scaledFont(24, weight: .heavy)
                        .foregroundStyle(Theme.Colors.onPhoto)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    metaLine
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                wechselnButton
            }
        }
    }

    private var metaLine: some View {
        HStack(spacing: 6) {
            if let year = motorcycle.modelYear?.prefix(4), !year.isEmpty {
                Text(String(year)).monospaced()
                Text("·").opacity(0.6)
            }
            if let plate = motorcycle.numberPlate, !plate.isEmpty {
                Text(plate).monospaced()
                Text("·").opacity(0.6)
            }
            Text("\(motorcycle.latestOdo ?? motorcycle.initialOdo) km")
                .monospaced()
        }
        .scaledFont(11, weight: .semibold)
        .foregroundStyle(Theme.Colors.onPhotoSecondary)
        .lineLimit(1)
    }

    private var wechselnButton: some View {
        Button(action: chrome.openGarage) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.arrow.down")
                    .scaledFont(11, weight: .heavy)
                Text("Wechseln")
                    .scaledFont(12, weight: .heavy)
            }
            .foregroundStyle(Theme.Colors.onPhoto)
            .padding(.leading, 10)
            .padding(.trailing, 12)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Motorrad wechseln")
    }

    private var veteranBadge: some View {
        Text("VETERAN")
            .scaledFont(9, weight: .black)
            .foregroundStyle(Theme.Colors.onPhoto)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(Theme.Colors.accent.opacity(0.92))
                    .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 0.5))
            )
    }
}
