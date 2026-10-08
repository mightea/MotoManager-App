import SwiftUI

/// Brand colors for note formatting, mirroring the webapp's Dakar tokens
/// (`--color-brand-red`, `--color-workshop`, `--color-primary` and their
/// dark-mode "soft"/"light" variants). Nonisolated so the editor's formatting
/// constraints, which run off the main actor, can use them.
nonisolated enum NoteBrandPalette {
    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { trait in
            let hex = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }

    static let vermillion = adaptive(light: 0xFF4124, dark: 0xFF7B61)
    static let sand = adaptive(light: 0xE8A341, dark: 0xF2C277)
    static let ultramarine = adaptive(light: 0x1E5BFF, dark: 0x6485FF)

    /// Text color for a brand color; yellow is a marker highlight instead
    /// (Sand on white is far below readable contrast, the tint is not).
    static func foreground(_ color: NoteMarkup.BrandColor?) -> Color? {
        switch color {
        case .red: return vermillion
        case .blue: return ultramarine
        case .yellow, nil: return nil
        }
    }

    static func background(_ color: NoteMarkup.BrandColor?) -> Color? {
        color == .yellow ? sand.opacity(0.4) : nil
    }

    /// Paints foreground/background from the brand color marker so the string
    /// renders the same in `Text` as in the editor.
    static func styled(_ text: AttributedString) -> AttributedString {
        var out = text
        for run in text.runs {
            let color = run[NoteMarkup.BrandColorAttribute.self]
            out[run.range].foregroundColor = foreground(color)
            out[run.range].backgroundColor = background(color)
        }
        return out
    }

    /// Display form of a record's note (see `NoteMarkup.resolve`).
    static func display(description: String?, markup: String?) -> AttributedString {
        styled(NoteMarkup.attributedString(NoteMarkup.resolve(description: description, markup: markup)))
    }
}

// MARK: - Formatting definition

/// Restricts the rich `TextEditor` to exactly what the markup can carry: bold,
/// italic and one brand color. Everything else (fonts, sizes, underline,
/// pasted styling) is outside the scope and dropped by the editor.
nonisolated struct NoteFormattingDefinition: AttributedTextFormattingDefinition {
    struct Scope: AttributeScope {
        let inlinePresentationIntent: AttributeScopes.FoundationAttributes.InlinePresentationIntentAttribute
        let noteBrandColor: NoteMarkup.BrandColorAttribute
        let foregroundColor: AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute
        let backgroundColor: AttributeScopes.SwiftUIAttributes.BackgroundColorAttribute
    }

    var body: some AttributedTextFormattingDefinition<Scope> {
        NoteIntentConstraint()
        NoteForegroundConstraint()
        NoteBackgroundConstraint()
    }
}

/// Keeps only the bold/italic bits of the presentation intent.
nonisolated struct NoteIntentConstraint: AttributedTextValueConstraint {
    typealias Scope = NoteFormattingDefinition.Scope
    typealias AttributeKey = AttributeScopes.FoundationAttributes.InlinePresentationIntentAttribute

    func constrain(_ container: inout Attributes) {
        guard let intent = container.inlinePresentationIntent else { return }
        let kept = intent.intersection([.stronglyEmphasized, .emphasized])
        container.inlinePresentationIntent = kept.isEmpty ? nil : kept
    }
}

/// Foreground color is derived from the brand color marker, never set directly.
nonisolated struct NoteForegroundConstraint: AttributedTextValueConstraint {
    typealias Scope = NoteFormattingDefinition.Scope
    typealias AttributeKey = AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute

    func constrain(_ container: inout Attributes) {
        container.foregroundColor = NoteBrandPalette.foreground(container.noteBrandColor)
    }
}

nonisolated struct NoteBackgroundConstraint: AttributedTextValueConstraint {
    typealias Scope = NoteFormattingDefinition.Scope
    typealias AttributeKey = AttributeScopes.SwiftUIAttributes.BackgroundColorAttribute

    func constrain(_ container: inout Attributes) {
        container.backgroundColor = NoteBrandPalette.background(container.noteBrandColor)
    }
}

// MARK: - Editor

/// WYSIWYG editor for note markup: a rich `TextEditor` bound to an
/// `AttributedString` plus a toolbar for bold, italic and the three brand
/// colors. Convert with `NoteMarkup.spans(from:)` on save.
struct NoteEditor: View {
    @Binding var text: AttributedString
    @Binding var selection: AttributedTextSelection
    var prompt: String = "Optionale Details"

    private var current: AttributeContainer { selection.typingAttributes(in: text) }
    private var isBold: Bool { current.inlinePresentationIntent?.contains(.stronglyEmphasized) ?? false }
    private var isItalic: Bool { current.inlinePresentationIntent?.contains(.emphasized) ?? false }
    private var currentColor: NoteMarkup.BrandColor? { current[NoteMarkup.BrandColorAttribute.self] }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                if text.characters.isEmpty {
                    formPrompt(prompt)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $text, selection: $selection)
                    .attributedTextFormattingDefinition(NoteFormattingDefinition())
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 72, maxHeight: 160)
                    .accessibilityLabel("Notizen")
            }

            HStack(spacing: 6) {
                toolbarButton("Fett", symbol: "bold", active: isBold) { toggleIntent(.stronglyEmphasized) }
                toolbarButton("Kursiv", symbol: "italic", active: isItalic) { toggleIntent(.emphasized) }
                Divider().frame(height: 16)
                ForEach(NoteMarkup.BrandColor.allCases, id: \.self) { color in
                    colorButton(color)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Formatierung")
        }
    }

    // MARK: Toolbar

    private func toolbarButton(_ label: String, symbol: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .scaledFont(13, weight: .semibold)
                .frame(width: 30, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.badge, style: .continuous)
                        .fill(active ? Theme.Colors.primary.opacity(0.16) : Color.primary.opacity(0.06))
                )
                .foregroundStyle(active ? Theme.Colors.primary : .primary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(active ? [.isSelected] : [])
    }

    private func colorButton(_ color: NoteMarkup.BrandColor) -> some View {
        let active = currentColor == color
        let label: String
        let swatch: Color
        switch color {
        case .red: label = "Rot"; swatch = NoteBrandPalette.vermillion
        case .yellow: label = "Gelb markieren"; swatch = NoteBrandPalette.sand
        case .blue: label = "Blau"; swatch = NoteBrandPalette.ultramarine
        }
        return Button { toggleColor(color) } label: {
            Group {
                if color == .yellow {
                    Image(systemName: "highlighter")
                        .scaledFont(13, weight: .semibold)
                        .foregroundStyle(swatch)
                } else {
                    Circle().fill(swatch).frame(width: 12, height: 12)
                }
            }
            .frame(width: 30, height: 28)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.badge, style: .continuous)
                    .fill(active ? swatch.opacity(0.22) : Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.badge, style: .continuous)
                    .strokeBorder(active ? swatch : .clear, lineWidth: 1.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(active ? [.isSelected] : [])
    }

    // MARK: Mutations

    /// Applies `mutate` to every run of the selection, or to the typing
    /// attributes when the selection is a bare insertion point.
    private func apply(_ mutate: (inout AttributeContainer) -> Void) {
        switch selection.indices(in: text) {
        case .insertionPoint(let index):
            var attributes = selection.typingAttributes(in: text)
            mutate(&attributes)
            selection = AttributedTextSelection(insertionPoint: index, typingAttributes: attributes)
        case .ranges(let ranges):
            text.transform(updating: &selection) { text in
                for range in ranges.ranges {
                    // Snapshot the run ranges first: only attributes change,
                    // so the indices stay valid while we mutate.
                    for runRange in text[range].runs.map(\.range) {
                        var attributes = AttributeContainer()
                        attributes.inlinePresentationIntent = text[runRange].inlinePresentationIntent
                        attributes[NoteMarkup.BrandColorAttribute.self] = text[runRange][NoteMarkup.BrandColorAttribute.self]
                        mutate(&attributes)
                        text[runRange].inlinePresentationIntent = attributes.inlinePresentationIntent
                        text[runRange][NoteMarkup.BrandColorAttribute.self] = attributes[NoteMarkup.BrandColorAttribute.self]
                    }
                }
            }
        }
    }

    private func toggleIntent(_ bit: InlinePresentationIntent) {
        let turnOn = !(current.inlinePresentationIntent?.contains(bit) ?? false)
        apply { attributes in
            var intent = attributes.inlinePresentationIntent ?? []
            if turnOn { intent.insert(bit) } else { intent.remove(bit) }
            attributes.inlinePresentationIntent = intent.isEmpty ? nil : intent
        }
    }

    private func toggleColor(_ color: NoteMarkup.BrandColor) {
        let next: NoteMarkup.BrandColor? = currentColor == color ? nil : color
        apply { $0[NoteMarkup.BrandColorAttribute.self] = next }
    }
}
