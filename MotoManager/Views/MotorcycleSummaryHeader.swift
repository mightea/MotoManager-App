import SwiftUI

enum HeaderType {
    case fuel, service, workshop, parts

    var title: String {
        switch self {
        case .fuel: "Tanken"
        case .service: "Wartung"
        case .workshop: "Technik"
        case .parts: "Teile"
        }
    }
}

/// Persistent photo identity above the workspace content. Statistics are
/// ordinary content and scroll independently below this header; scrolling
/// them sets `isMinimized`, which shrinks the header to a single row.
struct MotorcycleSummaryHeader<Actions: View>: View {
    let motorcycle: Motorcycle
    let type: HeaderType
    var isCondensed = false
    var isMinimized = false
    @ViewBuilder var actions: () -> Actions
    @Environment(\.chromeActions) private var chrome
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title2) private var minimumHeight: CGFloat = 180
    @ScaledMetric(relativeTo: .headline) private var condensedHeight: CGFloat = 96

    var body: some View {
        Group {
            if isMinimized {
                minimizedHeader
            } else if isCondensed && !dynamicTypeSize.isAccessibilitySize {
                ViewThatFits(in: .horizontal) {
                    condensedHeader
                    expandedHeader
                }
            } else {
                expandedHeader
            }
        }
        .foregroundStyle(Theme.Colors.onPhoto)
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, isMinimized ? Theme.Spacing.s : Theme.Spacing.m)
        .frame(maxWidth: .infinity,
               minHeight: (dynamicTypeSize.isAccessibilitySize || isMinimized) ? 0
                   : isCondensed ? condensedHeight : minimumHeight + (sizeClass == .compact ? 20 : 0),
               alignment: .bottomLeading)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workspace.header")
        .background {
            GeometryReader { proxy in
                let wide = proxy.size.width > 700
                let height = max(0, proxy.size.height)
                let photoWidth = max(0, wide ? min(proxy.size.width * 0.6, height * 2) : proxy.size.width)
                ZStack(alignment: .trailing) {
                    Theme.Colors.navy950
                    if let url = motorcycle.image {
                        RemoteImageView(url: url, maxPixelWidth: 1800)
                            .aspectRatio(contentMode: .fill)
                            .frame(width: photoWidth, height: height, alignment: .bottom)
                            .clipped()
                            .mask {
                                if wide {
                                    LinearGradient(stops: [.init(color: .clear, location: 0),
                                        .init(color: .black, location: 0.2)],
                                        startPoint: .leading, endPoint: .trailing)
                                } else { Rectangle() }
                            }
                    }
                    LinearGradient(
                        colors: wide
                            ? [.black.opacity(0.15), .black.opacity(0.05), .black.opacity(0.4)]
                            : [.black.opacity(0.6), .black.opacity(0.45), .black.opacity(0.85)],
                        startPoint: .top, endPoint: .bottom
                    )
                    if wide {
                        LinearGradient(colors: [Theme.Colors.navy950.opacity(0.85), .clear],
                            startPoint: .leading, endPoint: .trailing)
                    }
                }
            }
            .ignoresSafeArea(.container, edges: .top)
            .accessibilityHidden(true)
        }

    }

    private var expandedHeader: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(alignment: .top, spacing: Theme.Spacing.s) {
                if !dynamicTypeSize.isAccessibilitySize {
                    Text(type.title)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Theme.Spacing.s)
                }
                Spacer(minLength: 0)
                actions()
            }
            Spacer(minLength: dynamicTypeSize.isAccessibilitySize ? Theme.Spacing.xs : Theme.Spacing.l)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .bottom, spacing: Theme.Spacing.m) {
                    identity
                    Spacer(minLength: Theme.Spacing.s)
                    switchButton
                }
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    identity
                    switchButton
                }
            }
        }
    }

    private var condensedHeader: some View {
        HStack(spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(type.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Colors.onPhotoSecondary)
                identity
            }
            Spacer(minLength: Theme.Spacing.s)
            actions()
            switchButton
        }
    }

    /// Single row while the content is scrolled: name, metadata and the
    /// actions stay reachable, the photo shrinks to a strip behind them.
    private var minimizedHeader: some View {
        HStack(spacing: Theme.Spacing.s) {
            identity
            Spacer(minLength: Theme.Spacing.s)
            actions()
            switchButton
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: isMinimized ? 2 : Theme.Spacing.xs) {
            Text("\(motorcycle.make) \(motorcycle.model)")
                .font((dynamicTypeSize.isAccessibilitySize || isCondensed || isMinimized) ? .headline : .title2.weight(.bold))
                .lineLimit(isMinimized ? 1 : nil)
                .fixedSize(horizontal: false, vertical: true)
            Text(metadata)
                .font((dynamicTypeSize.isAccessibilitySize || isMinimized) ? .caption : .footnote)
                .monospacedDigit()
                .foregroundStyle(Theme.Colors.onPhotoSecondary)
                .lineLimit(isMinimized ? 1 : nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("workspace.motorcycleIdentity")
    }

    private var metadata: String {
        var items: [String] = []
        if !dynamicTypeSize.isAccessibilitySize,
           let year = motorcycle.modelYear.flatMap(Formatters.modelYear) { items.append(year) }
        if let plate = motorcycle.numberPlate, !plate.isEmpty { items.append(plate) }
        items.append(Formatters.kilometers(motorcycle.latestOdo ?? motorcycle.initialOdo))
        return items.joined(separator: " · ")
    }

    private var switchButton: some View {
        let iconOnly = dynamicTypeSize.isAccessibilitySize || isMinimized
        return Button(action: chrome.openGarage) {
            Group {
                if iconOnly { Image(systemName: "chevron.down") }
                else { Label("Wechseln", systemImage: "chevron.down") }
            }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, iconOnly ? Theme.Spacing.s : Theme.Spacing.m)
                .frame(minWidth: 44, minHeight: 44)
                .glassEffect(.regular.tint(Theme.Colors.navy950.opacity(0.5)), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Motorrad wechseln")
        .accessibilityIdentifier("workspace.switchMotorcycle")
    }
}
