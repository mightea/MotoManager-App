import Testing
import Foundation
import SwiftUI
@testable import MotoManager

// MARK: - Note markup (shared fixture with the webapp)

/// The fixture is the contract between this parser and the webapp's
/// `app/utils/formatted-text.ts`; both copies must stay identical.
struct NoteMarkupTests {

    private struct Fixture: Decodable {
        struct Case: Decodable {
            let name: String
            let markup: String
            let spans: [[String?]]
            let canonical: String?
        }
        let cases: [Case]
    }

    private static func loadCases() throws -> [Fixture.Case] {
        let bundled = Bundle(for: FixtureToken.self).url(forResource: "formatted-text", withExtension: "json")
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/formatted-text.json")
        let data = try Data(contentsOf: bundled ?? source)
        return try JSONDecoder().decode(Fixture.self, from: data).cases
    }

    private static func spans(_ rows: [[String?]]) -> [NoteMarkup.Span] {
        rows.map { row in
            let flags = row[1] ?? ""
            return NoteMarkup.Span(
                text: row[0] ?? "",
                bold: flags.contains("b"),
                italic: flags.contains("i"),
                color: row[2].flatMap(NoteMarkup.BrandColor.init(rawValue:))
            )
        }
    }

    @Test func parsesEveryFixtureCase() throws {
        for c in try Self.loadCases() {
            #expect(NoteMarkup.parse(c.markup) == Self.spans(c.spans), "\(c.name)")
        }
    }

    @Test func serializesCanonically() throws {
        for c in try Self.loadCases() {
            #expect(NoteMarkup.serialize(Self.spans(c.spans)) == (c.canonical ?? c.markup), "\(c.name)")
        }
    }

    @Test func roundTripsThroughMarkup() throws {
        for c in try Self.loadCases() {
            let expected = Self.spans(c.spans)
            #expect(NoteMarkup.parse(NoteMarkup.serialize(expected)) == expected, "\(c.name)")
        }
    }

    @Test func roundTripsThroughAttributedString() throws {
        for c in try Self.loadCases() {
            let expected = Self.spans(c.spans)
            let back = NoteMarkup.spans(from: NoteMarkup.attributedString(expected))
            #expect(NoteMarkup.serialize(back) == NoteMarkup.serialize(expected), "\(c.name)")
        }
    }

    @Test func storageFormTrimsLikeTheServer() {
        // Outer whitespace is trimmed across spans (the server trims the plain
        // text), inner whitespace stays, and the markup still strips to it.
        var text = AttributedString("  ")
        var bold = AttributedString("Achtung ")
        bold.inlinePresentationIntent = .stronglyEmphasized
        text += bold
        text += AttributedString("kalt  \n")
        let stored = NoteMarkup.storageForm(text)
        #expect(stored.description == "Achtung kalt")
        #expect(NoteMarkup.resolve(description: stored.description, markup: stored.markup) == [
            NoteMarkup.Span(text: "Achtung ", bold: true),
            NoteMarkup.Span(text: "kalt"),
        ])

        let plain = NoteMarkup.storageForm(AttributedString(" nur Text "))
        #expect(plain.description == "nur Text")
        #expect(plain.markup == "")

        let blank = NoteMarkup.storageForm(AttributedString(" \n "))
        #expect(blank.description == "")
        #expect(blank.markup == "")
    }

    @Test func resolveHonoursMarkupOnlyWhileConsistent() {
        let ok = NoteMarkup.resolve(description: "Achtung: kalt", markup: "[red]**Achtung:**[/red] kalt")
        #expect(NoteMarkup.hasFormatting(ok))
        #expect(NoteMarkup.plainText(ok) == "Achtung: kalt")

        // An older build changed the plain text: formatting is dropped.
        let stale = NoteMarkup.resolve(description: "Achtung: kalt, 2x", markup: "[red]**Achtung:**[/red] kalt")
        #expect(stale == [NoteMarkup.Span(text: "Achtung: kalt, 2x")])

        #expect(NoteMarkup.resolve(description: nil, markup: nil).isEmpty)
        #expect(NoteMarkup.resolve(description: "", markup: "**x**").isEmpty)
    }

    @Test func attributedStringIgnoresForeignAttributes() {
        var text = AttributedString("x")
        text.underlineStyle = .single
        text.inlinePresentationIntent = [.stronglyEmphasized, .code]
        let spans = NoteMarkup.spans(from: text)
        #expect(spans == [NoteMarkup.Span(text: "x", bold: true)])
    }
}

private final class FixtureToken {}
