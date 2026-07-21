import SwiftUI

/// Reusable 3-tile glass stat strip used at the top of screen content.
/// Each tile has an eyebrow label, a main value, and an optional unit/sub line.
struct StatStrip: View {
    let tiles: [StatTile]

    init(_ tiles: [StatTile]) {
        self.tiles = tiles
    }

    var body: some View {
        // Group the tiles so adjacent glass surfaces blend/merge rather than
        // each drawing its own isolated effect.
        GlassEffectContainer(spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.s) {
                ForEach(tiles) { tile in
                    tileView(tile)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func tileView(_ tile: StatTile) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(tile.eyebrow.uppercased())
                .scaledFont(9, weight: .heavy)
                .tracking(1.2)
                .foregroundColor(.white.opacity(0.55))
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(tile.value)
                .scaledFont(17, weight: .bold, design: .rounded)
                .foregroundColor(tile.accent ?? .white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if let unit = tile.unit, !unit.isEmpty {
                Text(unit)
                    .scaledFont(10, weight: .medium)
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct StatTile: Identifiable {
    let id = UUID()
    let eyebrow: String
    let value: String
    var unit: String? = nil
    var accent: Color? = nil
}
