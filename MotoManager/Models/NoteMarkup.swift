import Foundation

/// Inline formatting for free-text notes (currently torque spec descriptions).
///
/// The wire format is a tiny markup stored next to the plain text:
///
///     **bold**   *italic*   [red]…[/red]   [yellow]…[/yellow]   [blue]…[/blue]
///     \*  \[  \\   literal characters
///
/// The webapp (`app/utils/formatted-text.ts`) implements the same rules; the
/// shared fixture `MotoManagerTests/Fixtures/formatted-text.json` must pass on
/// both sides:
///
/// - Unmatched or unknown delimiters render literally, so legacy text such as
///   "M8*1.25" is unaffected.
/// - Styles may overlap; the result is a flat list of spans, never a tree.
/// - Serialization is canonical: adjacent identical spans merge, styles are
///   emitted as transitions (closing italic → bold → color, opening color →
///   bold → italic) and literal `*`, `[`, `\` are escaped. Round-tripping
///   through either editor therefore yields byte-identical markup.
///
/// The plain `description` is what older app builds read and write; the markup
/// is only honoured while stripping it reproduces that plain text (see
/// `resolve(description:markup:)`). Newlines are ordinary characters.
nonisolated enum NoteMarkup {

    enum BrandColor: String, Codable, CaseIterable, Sendable, Hashable {
        case red, yellow, blue
    }

    struct Span: Equatable, Sendable {
        var text: String
        var bold: Bool = false
        var italic: Bool = false
        var color: BrandColor? = nil

        var sameStyle: (Span) -> Bool {
            { $0.bold == bold && $0.italic == italic && $0.color == color }
        }
    }

    // MARK: Parsing

    private enum Token: Equatable {
        case text(String)
        case bold
        case italic
        case open(BrandColor)
        case close(BrandColor)

        var literal: String {
            switch self {
            case .text(let s): return s
            case .bold: return "**"
            case .italic: return "*"
            case .open(let c): return "[\(c.rawValue)]"
            case .close(let c): return "[/\(c.rawValue)]"
            }
        }
    }

    private static func tokenize(_ input: String) -> [Token] {
        var tokens: [Token] = []
        var text = ""
        func flush() {
            if !text.isEmpty { tokens.append(.text(text)); text = "" }
        }
        let chars = Array(input)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if ch == "\\", i + 1 < chars.count {
                text.append(chars[i + 1])
                i += 2
                continue
            }
            if ch == "*" {
                flush()
                if i + 1 < chars.count, chars[i + 1] == "*" {
                    tokens.append(.bold)
                    i += 2
                } else {
                    tokens.append(.italic)
                    i += 1
                }
                continue
            }
            if ch == "[", let (token, length) = tag(at: i, in: chars) {
                flush()
                tokens.append(token)
                i += length
                continue
            }
            text.append(ch)
            i += 1
        }
        flush()
        return tokens
    }

    /// `[red]` / `[/red]` at `start`, or nil when it is not a known tag.
    private static func tag(at start: Int, in chars: [Character]) -> (Token, Int)? {
        var i = start + 1
        var closing = false
        if i < chars.count, chars[i] == "/" { closing = true; i += 1 }
        var name = ""
        while i < chars.count, chars[i].isLetter, chars[i].isLowercase {
            name.append(chars[i]); i += 1
        }
        guard i < chars.count, chars[i] == "]", let color = BrandColor(rawValue: name) else { return nil }
        return (closing ? .close(color) : .open(color), i - start + 1)
    }

    /// Parse markup into flat spans. Never fails; garbage renders as text.
    static func parse(_ markup: String) -> [Span] {
        let tokens = tokenize(markup)
        var spans: [Span] = []
        var bold = false
        var italic = false
        var colors: [BrandColor] = []

        func push(_ text: String) {
            guard !text.isEmpty else { return }
            let span = Span(text: text, bold: bold, italic: italic, color: colors.last)
            if let last = spans.last, last.sameStyle(span) {
                spans[spans.count - 1].text += text
            } else {
                spans.append(span)
            }
        }
        func hasLater(_ index: Int, _ predicate: (Token) -> Bool) -> Bool {
            tokens[(index + 1)...].contains(where: predicate)
        }

        for (index, token) in tokens.enumerated() {
            switch token {
            case .text(let s):
                push(s)
            case .bold:
                if bold { bold = false }
                else if hasLater(index, { $0 == .bold }) { bold = true }
                else { push(token.literal) }
            case .italic:
                if italic { italic = false }
                else if hasLater(index, { $0 == .italic }) { italic = true }
                else { push(token.literal) }
            case .open(let color):
                if hasLater(index, { $0 == .close(color) }) { colors.append(color) }
                else { push(token.literal) }
            case .close(let color):
                if let at = colors.lastIndex(of: color) { colors.remove(at: at) }
                else { push(token.literal) }
            }
        }
        return spans
    }

    // MARK: Serialization

    private static func escape(_ text: String) -> String {
        var out = ""
        for ch in text {
            if ch == "\\" || ch == "*" || ch == "[" { out.append("\\") }
            out.append(ch)
        }
        return out
    }

    /// Drops empty spans and merges adjacent spans with identical style.
    static func normalize(_ spans: [Span]) -> [Span] {
        var out: [Span] = []
        for span in spans where !span.text.isEmpty {
            if let last = out.last, last.sameStyle(span) {
                out[out.count - 1].text += span.text
            } else {
                out.append(span)
            }
        }
        return out
    }

    /// Canonical markup for a span list; "" for an empty list.
    static func serialize(_ spans: [Span]) -> String {
        var out = ""
        var bold = false
        var italic = false
        var color: BrandColor? = nil

        func transition(to next: Span) {
            if italic, !next.italic { out += "*" }
            if bold, !next.bold { out += "**" }
            if let c = color, c != next.color { out += "[/\(c.rawValue)]" }
            if let c = next.color, c != color { out += "[\(c.rawValue)]" }
            if !bold, next.bold { out += "**" }
            if !italic, next.italic { out += "*" }
            bold = next.bold; italic = next.italic; color = next.color
        }

        for span in normalize(spans) {
            transition(to: span)
            out += escape(span.text)
        }
        transition(to: Span(text: ""))
        return out
    }

    static func plainText(_ spans: [Span]) -> String {
        spans.map(\.text).joined()
    }

    static func hasFormatting(_ spans: [Span]) -> Bool {
        spans.contains { $0.bold || $0.italic || $0.color != nil }
    }

    /// Strip leading/trailing whitespace the way the server trims plain text,
    /// so the stored markup still strips to the stored description. Emptied
    /// spans are dropped; inner whitespace is untouched.
    static func trim(_ spans: [Span]) -> [Span] {
        var out = spans
        while let first = out.first {
            let text = String(first.text.drop(while: \.isWhitespace))
            if text.isEmpty { out.removeFirst(); continue }
            out[0].text = text
            break
        }
        while let last = out.last {
            var text = last.text
            while let c = text.last, c.isWhitespace { text.removeLast() }
            if text.isEmpty { out.removeLast(); continue }
            out[out.count - 1].text = text
            break
        }
        return out
    }

    /// What an edited note persists as: the plain `description` (compatibility
    /// surface older builds read) and its markup twin, "" when unformatted or
    /// blank. Both are "" for an empty note.
    static func storageForm(_ text: AttributedString) -> (description: String, markup: String) {
        let spans = trim(spans(from: text))
        let plain = plainText(spans)
        if plain.isEmpty { return ("", "") }
        return (plain, hasFormatting(spans) ? serialize(spans) : "")
    }

    /// Spans to display for a record: the markup when it is consistent with the
    /// plain description (an older build may have edited the text since), else
    /// the plain text as a single unstyled span.
    static func resolve(description: String?, markup: String?) -> [Span] {
        let plain = description ?? ""
        if let markup, !markup.isEmpty {
            let spans = parse(markup)
            if plainText(spans) == plain { return spans }
        }
        return plain.isEmpty ? [] : [Span(text: plain)]
    }

    // MARK: AttributedString bridge

    /// Marker attribute for the brand color; the editor's formatting definition
    /// derives the visible foreground/background colors from it, and the
    /// serializer reads it back.
    struct BrandColorAttribute: CodableAttributedStringKey {
        typealias Value = BrandColor
        static let name = "ltd.herrmann.MotoManager.noteBrandColor"
    }

    static func intent(for span: Span) -> InlinePresentationIntent? {
        var intent: InlinePresentationIntent = []
        if span.bold { intent.insert(.stronglyEmphasized) }
        if span.italic { intent.insert(.emphasized) }
        return intent.isEmpty ? nil : intent
    }

    /// Attributed form carrying only the semantic attributes (presentation
    /// intent + brand color marker). Colors are painted by the caller.
    static func attributedString(_ spans: [Span]) -> AttributedString {
        var out = AttributedString()
        for span in spans {
            var piece = AttributedString(span.text)
            piece.inlinePresentationIntent = intent(for: span)
            piece[BrandColorAttribute.self] = span.color
            out += piece
        }
        return out
    }

    /// Reads spans back from an attributed string produced by `attributedString`
    /// or edited in `NoteEditor`. Any other attribute is ignored.
    static func spans(from text: AttributedString) -> [Span] {
        var spans: [Span] = []
        for run in text.runs {
            let intent = run.inlinePresentationIntent ?? []
            spans.append(Span(
                text: String(text[run.range].characters),
                bold: intent.contains(.stronglyEmphasized),
                italic: intent.contains(.emphasized),
                color: run[BrandColorAttribute.self]
            ))
        }
        return normalize(spans)
    }
}

extension AttributeScopes {
    struct NoteAttributes: AttributeScope {
        let noteBrandColor: NoteMarkup.BrandColorAttribute
    }
    var note: NoteAttributes.Type { NoteAttributes.self }
}

extension AttributeDynamicLookup {
    subscript<T: AttributedStringKey>(dynamicMember keyPath: KeyPath<AttributeScopes.NoteAttributes, T>) -> T {
        self[T.self]
    }
}
