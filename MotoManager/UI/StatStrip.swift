import SwiftUI

/// Reusable 3-tile glass stat strip used at the top of screen content.
/// Each tile has an eyebrow label, a main value, and an optional unit/sub line.
///
/// The tiles usually sit on the header photo. Ink is `onPhoto` (always white):
/// the photo underneath doesn't adapt to appearance, and the system glass
/// derives its look from the photo, not the color scheme. Legibility comes
/// from the header's photo scrim — the glass carries no extra tint of its own,
/// so it stays honest under the user's iOS 27 glass-intensity setting.
struct StatStrip: View {
    let tiles: [StatTile]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(_ tiles: [StatTile]) {
        self.tiles = tiles
    }

    var body: some View {
        // Group the tiles so adjacent glass surfaces blend/merge rather than
        // each drawing its own isolated effect.
        GlassEffectContainer(spacing: Theme.Spacing.s) {
            if dynamicTypeSize.isAccessibilitySize {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.s) {
                        ForEach(tiles) { tile in
                            tileView(tile)
                                .frame(width: 190)
                        }
                    }
                }
                .accessibilityHint("Weitere Kennzahlen horizontal verfügbar")
            } else {
                HStack(spacing: Theme.Spacing.s) {
                    ForEach(tiles) { tile in
                        tileView(tile)
                            .frame(maxWidth: .infinity)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func tileView(_ tile: StatTile) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(tile.eyebrow.uppercased())
                .scaledFont(9, weight: .heavy)
                .tracking(1.2)
                .foregroundStyle(Theme.Colors.onPhotoSecondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .minimumScaleFactor(0.75)

            Text(tile.value)
                .scaledFont(17, weight: .bold, design: .rounded)
                .foregroundStyle(tile.accent ?? Theme.Colors.onPhoto)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .minimumScaleFactor(0.7)

            if let unit = tile.unit, !unit.isEmpty {
                Text(unit)
                    .scaledFont(10, weight: .medium)
                    .foregroundStyle(Theme.Colors.onPhotoSecondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.Radius.chip))
    }
}

struct StatTile: Identifiable {
    let id = UUID()
    let eyebrow: String
    let value: String
    var unit: String? = nil
    var accent: Color? = nil
}
