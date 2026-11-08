import SwiftUI

/// The fleet under the tabs in the iPad sidebar: switching bikes is one tap
/// instead of a sheet. The selected bike carries its open-issue count.
struct SidebarGarage: View {
    @ObservedObject var fleetVM: MotorcycleViewModel
    let openIssues: Int
    let onAdd: () -> Void

    /// More bikes than this and the sidebar would run under its bottom bar:
    /// show the selected one plus the most recent others, and a link to the
    /// whole garage.
    private static let visibleLimit = 4

    private var visibleMotorcycles: [Motorcycle] {
        let all = fleetVM.motorcycles
        guard all.count > Self.visibleLimit else { return all }
        let selected = all.filter { $0.id == fleetVM.selectedMotorcycle?.id }
        let others = all.filter { $0.id != fleetVM.selectedMotorcycle?.id }
        return selected + others.prefix(Self.visibleLimit - selected.count)
    }

    private var isTruncated: Bool { fleetVM.motorcycles.count > Self.visibleLimit }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Garage")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, Theme.Spacing.s)
                .padding(.top, Theme.Spacing.m)
                .accessibilityAddTraits(.isHeader)
            ForEach(visibleMotorcycles) { motorcycle in
                row(motorcycle)
            }
            Button(action: onAdd) {
                Label(isTruncated ? "Alle \(fleetVM.motorcycles.count) Motorräder" : "Motorrad hinzufügen",
                      systemImage: isTruncated ? "square.grid.2x2" : "plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.horizontal, Theme.Spacing.s)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.Colors.primary)
        }
    }

    private func row(_ motorcycle: Motorcycle) -> some View {
        let selected = fleetVM.selectedMotorcycle?.id == motorcycle.id
        return Button {
            if !selected { fleetVM.selectMotorcycle(motorcycle) }
        } label: {
            HStack(spacing: Theme.Spacing.m - 4) {
                thumbnail(motorcycle)
                VStack(alignment: .leading, spacing: 2) {
                    // Two lines: model names like "R 90 S Daytona Orange"
                    // differ only at the end.
                    Text("\(motorcycle.make) \(motorcycle.model)")
                        .font(.subheadline.weight(.bold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(Formatters.kilometers(motorcycle.latestOdo ?? motorcycle.initialOdo))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    // Own line, so neither the km reading nor the count
                    // truncates in the narrow sidebar.
                    if selected, openIssues > 0 {
                        Text(openIssues == 1 ? "1 offener Mangel" : "\(openIssues) offene Mängel")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(Theme.Spacing.s)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: Theme.Radius.chip)
                        .fill(Theme.Colors.backgroundElevated)
                        .strokeBorder(Theme.Colors.primary, lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("sidebar.motorcycle.\(motorcycle.id)")
    }

    private func thumbnail(_ motorcycle: Motorcycle) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Radius.controlInner)
                .fill(Theme.Colors.primary.opacity(0.12))
            if let url = motorcycle.image {
                RemoteImageView(url: url, maxPixelWidth: 200)
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "motorcycle")
                    .foregroundStyle(Theme.Colors.primary)
            }
        }
        .frame(width: 52, height: 38)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.controlInner))
        .accessibilityHidden(true)
    }
}

/// Bottom of the iPad sidebar: sync state (or what is happening right now)
/// and the settings button.
struct SidebarStatusBar: View {
    @ObservedObject var viewModel: MotorcycleDetailViewModel
    @EnvironmentObject private var engine: SyncEngine
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            if StatusAccessoryBar.isActive(engine: engine, viewModel: viewModel) {
                StatusAccessoryBar(viewModel: viewModel)
            } else {
                Circle().fill(.green).frame(width: 8, height: 8).accessibilityHidden(true)
                Text(syncedText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            Button("Einstellungen", systemImage: "gearshape", action: openSettings)
                .labelStyle(.iconOnly)
                .frame(width: 44, height: 44)
                .glassEffect(.regular, in: Circle())
                .accessibilityIdentifier("sidebar.settings")
        }
        .padding(.horizontal, Theme.Spacing.s)
    }

    private var syncedText: String {
        guard let date = engine.lastSyncDate else { return "Synchronisiert" }
        let relative = date.formatted(.relative(presentation: .named).locale(Formatters.displayLocale))
        return "Synchronisiert · \(relative)"
    }
}
