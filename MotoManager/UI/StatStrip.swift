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
    /// Whether the strip sits on the header photo (always-white ink) or on the
    /// page background (adaptive ink). At accessibility text sizes the strip
    /// moves off the photo, where white-only ink would vanish in light mode.
    let onPhoto: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(_ tiles: [StatTile], onPhoto: Bool = true) {
        self.tiles = tiles
        self.onPhoto = onPhoto
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

    /// Muted ink for eyebrow/unit lines, per surface.
    private var secondaryInk: AnyShapeStyle {
        onPhoto ? AnyShapeStyle(Theme.Colors.onPhotoSecondary) : AnyShapeStyle(.secondary)
    }

    private func valueInk(_ tile: StatTile) -> AnyShapeStyle {
        if let accent = tile.accent { return AnyShapeStyle(accent) }
        return onPhoto ? AnyShapeStyle(Theme.Colors.onPhoto) : AnyShapeStyle(.primary)
    }

    private func tileView(_ tile: StatTile) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(tile.eyebrow.uppercased())
                .scaledFont(9, weight: .heavy)
                .tracking(1.2)
                .foregroundStyle(secondaryInk)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .minimumScaleFactor(0.75)

            Text(tile.value)
                .scaledFont(17, weight: .bold, design: .rounded)
                .foregroundStyle(valueInk(tile))
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .minimumScaleFactor(0.7)

            if let unit = tile.unit, !unit.isEmpty {
                Text(unit)
                    .scaledFont(10, weight: .medium)
                    .foregroundStyle(secondaryInk)
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
