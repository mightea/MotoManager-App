import Foundation
import Testing
@testable import MotoManager

@MainActor
struct DocumentTypeTests {
    private func document(_ id: Int, type: String?) -> Document {
        Document(id: id, title: "Doc \(id)", filePath: "/d/\(id).pdf", previewPath: nil, uploadedBy: nil, ownerId: 1,
                 isPrivate: false, createdAt: "2026-11-08", updatedAt: "2026-11-08", motorcycleIds: [1],
                 docType: type)
    }

    private func decode(_ json: String) throws -> Document {
        try JSONDecoder().decode(Document.self, from: Data(json.utf8))
    }

    private let base = """
        "id": 7, "title": "Schaltplan", "filePath": "/data/documents/a.pdf", "previewPath": null,
        "uploadedBy": "t", "ownerId": 1, "isPrivate": false, "createdAt": "2026-11-08",
        "updatedAt": "2026-11-08", "motorcycleIds": [1]
        """

    @Test func keysAndLabelsMatchTheApi() {
        #expect(DocumentType.allCases.map(\.key) == [
            "werkstatthandbuch", "reparaturanleitung", "schaltplan", "checkliste", "teilekatalog",
            "bedienungsanleitung", "fahrzeugausweis", "rechnung", "sonstiges",
        ])
        #expect(DocumentType.fahrzeugausweis.label == "Fahrzeugausweis")
        #expect(DocumentType.allCases.allSatisfy { !$0.systemImage.isEmpty })
    }

    @Test func decodesTheType() throws {
        let doc = try decode("{\(base), \"docType\": \"schaltplan\"}")
        #expect(doc.docType == "schaltplan")
        #expect(doc.documentType == .schaltplan)
    }

    @Test func missingOrNullTypeDecodesAsUnset() throws {
        // Older API responses and cached JSON have no docType key at all.
        #expect(try decode("{\(base)}").documentType == nil)
        #expect(try decode("{\(base), \"docType\": null}").documentType == nil)
    }

    @Test func unknownTypeCountsAsUnset() throws {
        let doc = try decode("{\(base), \"docType\": \"kochrezept\"}")
        #expect(doc.docType == "kochrezept")
        #expect(doc.documentType == nil)
        #expect(DocumentTypeFilter.untyped.matches(doc))
    }

    @Test func roundTripsThroughTheCache() throws {
        let original = document(1, type: "rechnung")
        let copy = try JSONDecoder().decode(Document.self, from: JSONEncoder().encode(original))
        #expect(copy.documentType == .rechnung)
    }

    @Test func formValueClearsWithEmptyString() {
        #expect(DocumentType.formValue(nil) == "")
        #expect(DocumentType.formValue(.checkliste) == "checkliste")
    }

    @Test func filterOptionsAreHiddenWithoutTypes() {
        #expect(DocumentTypeFilter.options(for: []).isEmpty)
        #expect(DocumentTypeFilter.options(for: [document(1, type: nil), document(2, type: "foo")]).isEmpty)
    }

    @Test func filterOptionsListPresentTypesInCanonicalOrderThenUntyped() {
        let docs = [document(1, type: "rechnung"), document(2, type: "schaltplan"),
                    document(3, type: nil), document(4, type: "rechnung")]
        #expect(DocumentTypeFilter.options(for: docs) == [.type(.schaltplan), .type(.rechnung), .untyped])
        // No "Ohne Typ" when every document has a type.
        #expect(DocumentTypeFilter.options(for: [document(1, type: "rechnung")]) == [.type(.rechnung)])
    }

    @Test func filterMatching() {
        let typed = document(1, type: "schaltplan")
        let untyped = document(2, type: nil)
        #expect(DocumentTypeFilter.all.matches(typed) && DocumentTypeFilter.all.matches(untyped))
        #expect(DocumentTypeFilter.type(.schaltplan).matches(typed))
        #expect(!DocumentTypeFilter.type(.schaltplan).matches(untyped))
        #expect(!DocumentTypeFilter.type(.rechnung).matches(typed))
        #expect(DocumentTypeFilter.untyped.matches(untyped) && !DocumentTypeFilter.untyped.matches(typed))
        #expect(DocumentTypeFilter.all.label == "Alle Typen" && DocumentTypeFilter.untyped.label == "Ohne Typ")
    }
}
