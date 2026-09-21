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
