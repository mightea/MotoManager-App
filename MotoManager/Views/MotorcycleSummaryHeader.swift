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

/// Persistent photo identity above the workspace content. The content scrolls
/// beneath it and its offset drives `progress`: the name and the switcher pill
/// move continuously from the bottom of the photo into the row with the
/// actions, so the header follows the finger instead of playing a timed
/// animation, and every control keeps a single identity throughout.
struct MotorcycleSummaryHeader<Actions: View>: View {
    let motorcycle: Motorcycle
    let type: HeaderType
    /// Short landscape windows use the single row permanently.
    var isCondensed = false
    @ObservedObject var metrics: WorkspaceHeaderMetrics
    @ObservedObject var scroll: WorkspaceScrollProgress
    @ViewBuilder var actions: () -> Actions
    @Environment(\.chromeActions) private var chrome
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title2) private var minimumHeight: CGFloat = 180
    @ScaledMetric(relativeTo: .title2) private var titleSize: CGFloat = 22
    @ScaledMetric(relativeTo: .headline) private var headlineSize: CGFloat = 17
    @ScaledMetric(relativeTo: .footnote) private var footnoteSize: CGFloat = 13
    @ScaledMetric(relativeTo: .caption) private var captionSize: CGFloat = 12
    @State private var actionsSize = CGSize(width: 96, height: 44)
    @State private var pillSize = CGSize(width: 44, height: 44)
    @State private var labelWidth: CGFloat = 0
    @State private var expandedIdentityHeight: CGFloat = 50
    @State private var minimizedIdentityHeight: CGFloat = 40

    private var progress: CGFloat { isCondensed ? 1 : scroll.progress }
    private var isAccessibility: Bool { dynamicTypeSize.isAccessibilitySize }
    /// The pill loses its label and the actions make room for it during the
    /// first half of the collapse, before the pill arrives in the row.
    private var labelFactor: CGFloat { isAccessibility ? 0 : max(0, 1 - progress / 0.5) }
    private var slotFactor: CGFloat { min(1, progress / 0.5) }

    // MARK: Geometry (content coordinates, inside the padding)

    private var rowHeight: CGFloat { max(44, actionsSize.height, pillSize.height) }
    private var minimumContentHeight: CGFloat {
        isAccessibility ? 0 : minimumHeight + (sizeClass == .compact ? 20 : 0) - 2 * Theme.Spacing.m
    }
    private var expandedContentHeight: CGFloat {
        isCondensed ? minimizedContentHeight
            : max(minimumContentHeight, rowHeight + Theme.Spacing.l + expandedIdentityHeight)
    }
    private var minimizedContentHeight: CGFloat { max(rowHeight, minimizedIdentityHeight) }
    private var verticalPadding: CGFloat { lerp(Theme.Spacing.m, Theme.Spacing.s, progress) }
    private var contentHeight: CGFloat { lerp(expandedContentHeight, minimizedContentHeight, progress) }
    private var expandedHeight: CGFloat {
        isCondensed ? minimizedHeight : expandedContentHeight + 2 * Theme.Spacing.m
    }
    private var minimizedHeight: CGFloat { minimizedContentHeight + 2 * Theme.Spacing.s }
    /// Vertical position of the action row, centered once minimized.
    private var rowY: CGFloat { progress * (minimizedContentHeight - rowHeight) / 2 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            identityRow
            actionRow
            switchButton
        }
        // Measurements sit in a background so they never size the stack.
        .background(alignment: .topLeading) { measurements }
        // Fill the fixed frame from the top: a stack of another height would
        // otherwise be centered in it and every offset would land off.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .frame(height: contentHeight)
        .clipped()
        .foregroundStyle(Theme.Colors.onPhoto)
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, verticalPadding)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workspace.header")
        .background { photo }
        .onChange(of: expandedHeight, initial: true) { metrics.expandedHeight = expandedHeight }
        .onChange(of: minimizedHeight, initial: true) { metrics.minimizedHeight = minimizedHeight }
    }

    // MARK: Rows

    private var actionRow: some View {
        HStack(spacing: Theme.Spacing.s) {
            if !isAccessibility {
                Text(type.title)
                    .font(.headline)
                    .lineLimit(1)
                    .opacity(1 - progress)
            }
            Spacer(minLength: 0)
            actions()
                .onGeometryChange(for: CGSize.self) { $0.size } action: { actionsSize = $0 }
                .padding(.trailing, labelFactor == 0 ? pillSize.width + Theme.Spacing.s
                                                     : slotFactor * (44 + Theme.Spacing.s))
        }
        .frame(height: rowHeight)
        .offset(y: rowY)
    }

    private var identityRow: some View {
        HStack(spacing: 0) {
            identity(progress: progress)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("workspace.motorcycleIdentity")
            Spacer(minLength: Theme.Spacing.s)
            Color.clear
                .frame(width: pillSize.width + slotFactor * (actionsSize.width + Theme.Spacing.s), height: 1)
        }
        .offset(y: lerp(expandedContentHeight - expandedIdentityHeight,
                        (minimizedContentHeight - minimizedIdentityHeight) / 2, progress))
    }

    private func identity(progress: CGFloat) -> some View {
        let nameSize = lerp(isAccessibility ? headlineSize : titleSize, headlineSize, progress)
        let metaSize = lerp(isAccessibility ? captionSize : footnoteSize, captionSize, progress)
        return VStack(alignment: .leading, spacing: lerp(Theme.Spacing.xs, 2, progress)) {
            Text("\(motorcycle.make) \(motorcycle.model)")
                .font(.system(size: nameSize, weight: .bold))
                .lineLimit(1)
            Text(metadata)
                .font(.system(size: metaSize))
                .monospacedDigit()
                .foregroundStyle(Theme.Colors.onPhotoSecondary)
                .lineLimit(1)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var metadata: String {
        var items: [String] = []
        if !isAccessibility,
           let year = motorcycle.modelYear.flatMap(Formatters.modelYear) { items.append(year) }
        if let plate = motorcycle.numberPlate, !plate.isEmpty { items.append(plate) }
        items.append(Formatters.kilometers(motorcycle.latestOdo ?? motorcycle.initialOdo))
        return items.joined(separator: " · ")
    }

    private var switchButton: some View {
        Button(action: chrome.openGarage) {
            HStack(spacing: 0) {
                Image(systemName: "chevron.down")
                Text("Wechseln")
                    .padding(.leading, Theme.Spacing.xs)
                    .fixedSize()
                    .frame(width: labelFactor * (labelWidth + Theme.Spacing.xs), alignment: .leading)
                    .clipped()
                    // Gone before the width closes, so no half letters show.
                    .opacity(max(0, (labelFactor - 0.4) / 0.6))
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, lerp(Theme.Spacing.s, Theme.Spacing.m, labelFactor))
            .frame(minWidth: 44, minHeight: 44)
            .glassEffect(.regular.tint(Theme.Colors.navy950.opacity(0.5)), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Motorrad wechseln")
        .accessibilityIdentifier("workspace.switchMotorcycle")
        .onGeometryChange(for: CGSize.self) { $0.size } action: { pillSize = $0 }
        .frame(maxWidth: .infinity, alignment: .topTrailing)
        .offset(y: lerp(expandedContentHeight - pillSize.height, rowY + (rowHeight - pillSize.height) / 2, progress))
    }

    /// Invisible copies that report the identity's height at both ends and
    /// the pill label's width, so positions are exact at any progress.
    private var measurements: some View {
        VStack(alignment: .leading, spacing: 0) {
            identity(progress: 0)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { expandedIdentityHeight = $0 }
            identity(progress: 1)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { minimizedIdentityHeight = $0 }
            Text("Wechseln")
                .font(.subheadline.weight(.semibold))
                .fixedSize()
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { labelWidth = $0 }
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Photo

    private var photo: some View {
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

    private func lerp(_ from: CGFloat, _ to: CGFloat, _ t: CGFloat) -> CGFloat {
        from + (to - from) * t
    }
}
