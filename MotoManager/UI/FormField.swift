import SwiftUI

/// Eyebrow label above a form input or control group — the single caption
/// style of every form sheet.
struct FormLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .textCase(.uppercase)
            .scaledFont(10, weight: .heavy)
            .tracking(1.4)
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Placeholder text for inputs inside a `FormField`. The system renders
/// prompts in its placeholder grey regardless; readability comes from the
/// elevated field surface (`formFieldBox`).
func formPrompt(_ text: String) -> Text {
    Text(text)
}

/// Labeled input box used by every form sheet: eyebrow label, a filled
/// rounded box holding the input, an optional unit suffix and an optional
/// hint below.
struct FormField<Content: View>: View {
    static var paddingH: CGFloat { 14 }
    static var paddingV: CGFloat { 12 }

    let label: String
    var unit: String? = nil
    var hint: String? = nil
    @ViewBuilder var content: () -> Content

    init(
        _ label: String,
        unit: String? = nil,
        hint: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.label = label
        self.unit = unit
        self.hint = hint
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FormLabel(label)
            HStack(spacing: Theme.Spacing.s) {
                content()
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let unit {
                    Text(unit)
                        .scaledFont(12, weight: .semibold)
                        .foregroundStyle(.secondary)
                }
            }
            .formFieldBox()
            if let hint, !hint.isEmpty {
                Text(hint)
                    .scaledFont(11, weight: .medium)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension View {
    /// The filled rounded box behind a form input. Also used for rows that
    /// aren't a `FormField` (toggle rows, pickers) so they line up.
    func formFieldBox(tint: Color? = nil) -> some View {
        self
            .padding(.horizontal, FormField<EmptyView>.paddingH)
            .padding(.vertical, FormField<EmptyView>.paddingV)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.field)
                    // Elevated surface (white by day), not a translucent tint:
                    // the system placeholder grey needs that contrast.
                    .fill(tint.map { $0.opacity(0.16) } ?? Theme.Colors.backgroundElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.field)
                    .stroke(tint.map { $0.opacity(0.35) } ?? Theme.Glass.border, lineWidth: 0.5)
            )
    }
}

/// Native switch in a form box with a title and optional subtitle — the
/// single boolean control of the form sheets.
struct FormToggleRow: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool
    /// Highlights the row (e.g. orange for a warning flag) while on.
    var tint: Color? = nil

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .scaledFont(14, weight: .semibold)
                    .foregroundStyle(isOn && tint != nil ? AnyShapeStyle(tint!) : AnyShapeStyle(.primary))
                if let subtitle {
                    Text(subtitle)
                        .scaledFont(11)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tint(tint ?? Theme.Colors.primary)
        .formFieldBox(tint: isOn ? tint : nil)
    }
}
