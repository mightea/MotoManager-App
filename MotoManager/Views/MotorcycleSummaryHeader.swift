import SwiftUI

enum HeaderType {
    case fuel, service, workshop

    var title: String {
        switch self {
        case .fuel: return "Tanken"
        case .service: return "Service"
        case .workshop: return "Werkstatt"
        }
    }
}

/// Immersive header used at the top of every screen.
///
/// Matches the prototype's **Variant C — Button switcher** (`glass.jsx::ButtonSwitcher`).
/// The bike name stays fully visible at 24 pt (2-line clamp for long names like
/// "BMW R 1250 GS Adventure"), the meta line shows year · plate · km, and a
/// dedicated glass "Wechseln" pill button to the right opens the searchable
/// picker. Settings gear sits top-right.
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

    private let contentHeight: CGFloat = 180
    private var totalHeight: CGFloat { contentHeight + bottomExtension }

    var body: some View {
        ZStack(alignment: .topLeading) {
            backgroundImage
            darkeningOverlay

            VStack(alignment: .leading, spacing: 0) {
                topActions
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

    // MARK: - Top row (gear only)

    private var topActions: some View {
        HStack(spacing: 8) {
            Spacer()
            // Group the two adjacent glass chips so they blend as one cluster.
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    SyncStatusPill()
                    Button(action: chrome.openSettings) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .glassEffect(.regular, in: Circle())
                    }
                    .accessibilityLabel("Einstellungen")
                }
            }
        }
    }

    // MARK: - Bike block

    private var bikeBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Eyebrow + VETERAN badge
            HStack(spacing: 6) {
                Text(type.title.uppercased())
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.75))
                    .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                if motorcycle.isVeteran {
                    veteranBadge
                }
            }

            HStack(alignment: .bottom, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(motorcycle.make) \(motorcycle.model)")
                        .font(.system(size: 24, weight: .heavy))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .shadow(color: .black.opacity(0.4), radius: 3, x: 0, y: 1)

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
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(.white.opacity(0.78))
        .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
        .lineLimit(1)
    }

    private var wechselnButton: some View {
        Button(action: chrome.openGarage) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 11, weight: .heavy))
                Text("Wechseln")
                    .font(.system(size: 12, weight: .heavy))
            }
            .foregroundColor(.white)
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
            .font(.system(size: 9, weight: .black))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(Theme.Colors.accent.opacity(0.92))
                    .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 0.5))
            )
    }
}
