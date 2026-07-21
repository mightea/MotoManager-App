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

        var valueFont: Font {
            switch self {
            case .big: return .system(size: 28, weight: .bold).monospacedDigit()
            case .compact: return .system(size: 19, weight: .bold).monospacedDigit()
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

        var unitFont: Font {
            switch self {
            case .big: return .system(size: 11, weight: .semibold)
            case .compact: return .system(size: 10, weight: .semibold)
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
                        .font(size.unitFont)
                        .foregroundColor(Theme.Glass.mutedText)
                }

                if let hint, !hint.isEmpty {
                    Text(hint)
                        .scaledFont(10, weight: .medium)
                        .foregroundColor(Theme.Glass.mutedText)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, size.paddingH)
            .padding(.vertical, size.paddingV)
            .glassEffect(
                isActive ? .regular.tint(Theme.Colors.primary.opacity(0.5)) : .regular,
                in: RoundedRectangle(cornerRadius: Theme.Glass.fieldRadius)
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
                    .foregroundColor(isActive ? Theme.Colors.primary : Theme.Glass.mutedText)
            }
            Text(eyebrow)
                .scaledFont(9, weight: .heavy)
                .tracking(1.4)
                .foregroundColor(isActive ? Theme.Colors.primary : Theme.Glass.mutedText)
            if derived {
                Spacer(minLength: 4)
                Text("BERECHNET")
                    .scaledFont(8, weight: .heavy)
                    .tracking(0.4)
                    .foregroundColor(Theme.Glass.mutedText)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
            }
        }
    }

    private var valueText: some View {
        Text(value.isEmpty ? placeholder : value)
            .font(size.valueFont)
            .foregroundColor(valueColor)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }

    private var placeholder: String {
        switch size {
        case .big: return "0"
        case .compact: return "0.00"
        }
    }

    private var valueColor: Color {
        guard !value.isEmpty else { return Color.white.opacity(0.3) }
        if accent { return Theme.Colors.primary }
        return .white
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: Theme.Glass.fieldRadius)
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
            RoundedRectangle(cornerRadius: Theme.Glass.fieldRadius)
                .stroke(Theme.Colors.primary.opacity(0.12), lineWidth: 3)
                .padding(-1.5)
        }
    }
}
