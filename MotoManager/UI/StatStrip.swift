import SwiftUI

/// Informational tiles use adaptive content surfaces. Large text reflows
/// vertically without shrinking labels or hiding tiles in a horizontal scroll.
struct StatStrip: View {
    let tiles: [StatTile]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(_ tiles: [StatTile]) { self.tiles = tiles }

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.m))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Theme.Spacing.s))
        layout {
            ForEach(tiles) { tile in
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(tile.eyebrow)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(tile.value)
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(tile.accent ?? .primary)
                    if let unit = tile.unit {
                        Text(unit).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(tile.accessibilityText)
            }
        }
        .padding(Theme.Spacing.m)
        .background(Theme.Colors.backgroundElevated, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
    }
}

/// The same figures as separate tiles, for wide overview panes: one row
/// when they fit, otherwise two per row — never a lone tile wrapping.
struct StatTileGrid: View {
    let tiles: [StatTile]

    init(_ tiles: [StatTile]) { self.tiles = tiles }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: Theme.Spacing.listSection) {
                ForEach(tiles) { tile($0).frame(minWidth: 128) }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.listSection), count: 2),
                      spacing: Theme.Spacing.listSection) {
                ForEach(tiles) { tile($0) }
            }
        }
    }

    private func tile(_ tile: StatTile) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(tile.eyebrow)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(tile.value)
                .font(.title2.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(tile.accent ?? .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let unit = tile.unit {
                Text(unit).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
        .padding(.horizontal, Theme.Spacing.m - 2)
        .padding(.vertical, Theme.Spacing.m - 4)
        .background(Theme.Colors.backgroundElevated, in: RoundedRectangle(cornerRadius: Theme.Radius.field))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tile.accessibilityText)
    }
}

struct StatTile: Identifiable {
    var id: String { eyebrow }
    let eyebrow: String
    let value: String
    var unit: String? = nil
    var accent: Color? = nil

    var accessibilityText: String {
        ["\(eyebrow): \(value)", unit].compactMap { $0 }.joined(separator: ", ")
    }
}
