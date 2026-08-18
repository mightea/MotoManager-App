import SwiftUI

/// Single field row used by the fuel-entry sheet — mirrors
/// `FuelEntrySheet.jsx::FieldRow` lines 384–440.
///
/// Renders: eyebrow + optional icon + optional "Berechnet" chip, then a
/// big tabular number + unit, then an optional hint. Active state
/// (matches the focused field) paints a primary-tinted background and ring.
///
/// The visible value uses Text() so we can style the digits like the
/// design while the embedded TextField (hidden behind it) drives the
/// system .decimalPad keyboard.
struct GlassFieldRow: View {
    let eyebrow: String
    let unit: String
    let value: String
    var hint: String? = nil
    var icon: String? = nil
    var size: Size = .big
    var derived: Bool = false
    var accent: Bool = false
    var isActive: Bool
    var onTap: () -> Void

    enum Size {
        case big, compact

        var valueSize: CGFloat {
            switch self {
            case .big: return 28
            case .compact: return 19
            }
        }

        var paddingH: CGFloat {
            switch self {
            case .big: return 14
            case .compact: return 12
            }
        }

        var paddingV: CGFloat {
            switch self {
            case .big: return 12
            case .compact: return 10
            }
        }

        var unitSize: CGFloat {
            switch self {
            case .big: return 11
            case .compact: return 10
            }
        }
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 3) {
                eyebrowRow

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    valueText
                    Text(unit)
                        .scaledFont(size.unitSize, weight: .semibold)
                        .foregroundStyle(.secondary)
                }

                if let hint, !hint.isEmpty {
                    Text(hint)
                        .scaledFont(10, weight: .medium)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, size.paddingH)
            .padding(.vertical, size.paddingV)
            .glassEffect(
                isActive ? .regular.tint(Theme.Colors.primary.opacity(0.5)) : .regular,
                in: RoundedRectangle(cornerRadius: Theme.Radius.field)
            )
            .overlay(border)
            .overlay(focusRing)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(eyebrow), \(value.isEmpty ? "leer" : value) \(unit)")
    }

    private var eyebrowRow: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .scaledFont(10, weight: .semibold)
                    .foregroundStyle(isActive ? AnyShapeStyle(Theme.Colors.primary) : AnyShapeStyle(.secondary))
            }
            Text(eyebrow)
                .scaledFont(9, weight: .heavy)
                .tracking(1.4)
                .foregroundStyle(isActive ? AnyShapeStyle(Theme.Colors.primary) : AnyShapeStyle(.secondary))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if derived {
                Spacer(minLength: 4)
                Text("BERECHNET")
                    .scaledFont(8, weight: .heavy)
                    .tracking(0.4)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.primary.opacity(0.12)))
            }
        }
    }

    private var valueText: some View {
        Text(value.isEmpty ? placeholder : value)
            .scaledFont(size.valueSize, weight: .bold)
            .monospacedDigit()
            .foregroundStyle(valueStyle)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }

    private var placeholder: String {
        switch size {
        case .big: return "0"
        case .compact: return "0.00"
        }
    }

    private var valueStyle: AnyShapeStyle {
        guard !value.isEmpty else { return AnyShapeStyle(.tertiary) }
        if accent { return AnyShapeStyle(Theme.Colors.primary) }
        return AnyShapeStyle(.primary)
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.field)
            .stroke(
                isActive
                    ? Theme.Colors.primary.opacity(0.5)
                    : Theme.Glass.border,
                lineWidth: isActive ? 1 : 0.5
            )
    }

    @ViewBuilder
    private var focusRing: some View {
        if isActive {
            RoundedRectangle(cornerRadius: Theme.Radius.field)
                .stroke(Theme.Colors.primary.opacity(0.12), lineWidth: 3)
                .padding(-1.5)
        }
    }
}
