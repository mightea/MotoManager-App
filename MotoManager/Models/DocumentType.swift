import Foundation

/// Document types — the API stores the key (`documents.docType`), the UI shows
/// the German label. Keep this the single place that maps one to the other
/// (mirrors the webapp's `app/utils/document-types.ts`).
enum DocumentType: String, CaseIterable, Identifiable, Hashable {
    case werkstatthandbuch
    case reparaturanleitung
    case schaltplan
    case checkliste
    case teilekatalog
    case bedienungsanleitung
    case fahrzeugausweis
    case rechnung
    case sonstiges

    var id: String { rawValue }

    /// The API key sent as the `docType` multipart field.
    var key: String { rawValue }

    var label: String {
        switch self {
        case .werkstatthandbuch: "Werkstatthandbuch"
        case .reparaturanleitung: "Reparaturanleitung"
        case .schaltplan: "Schaltplan"
        case .checkliste: "Checkliste"
        case .teilekatalog: "Teilekatalog"
        case .bedienungsanleitung: "Bedienungsanleitung"
        case .fahrzeugausweis: "Fahrzeugausweis"
        case .rechnung: "Rechnung"
        case .sonstiges: "Sonstiges"
        }
    }

    var systemImage: String {
        switch self {
        case .werkstatthandbuch: "book.closed"
        case .reparaturanleitung: "wrench.and.screwdriver"
        case .schaltplan: "bolt"
        case .checkliste: "checklist"
        case .teilekatalog: "shippingbox"
        case .bedienungsanleitung: "book"
        case .fahrzeugausweis: "person.text.rectangle"
        case .rechnung: "doc.text"
        case .sonstiges: "doc"
        }
    }

    /// The known type for an API key, or `nil` when unset. An older API sends
    /// no `docType` at all, and a key this client doesn't know counts as unset.
    init?(key: String?) {
        guard let key, let type = DocumentType(rawValue: key) else { return nil }
        self = type
    }

    /// The multipart value for a picked type: empty string clears it.
    static func formValue(_ type: DocumentType?) -> String { type?.key ?? "" }
}

extension Document {
    /// The document's known type, `nil` when unset or unknown to this client.
    var documentType: DocumentType? { DocumentType(key: docType) }
}

/// The library's type filter: everything, one type, or documents without one.
enum DocumentTypeFilter: Hashable {
    case all
    case type(DocumentType)
    case untyped

    var label: String {
        switch self {
        case .all: "Alle Typen"
        case .type(let type): type.label
        case .untyped: "Ohne Typ"
        }
    }

    func matches(_ document: Document) -> Bool {
        switch self {
        case .all: true
        case .type(let type): document.documentType == type
        case .untyped: document.documentType == nil
        }
    }

    /// Options besides "Alle Typen": the types present in `documents` (in
    /// canonical order), plus "Ohne Typ" when some have none. Empty when no
    /// document carries a type, so the filter can be hidden (e.g. older API).
    static func options(for documents: [Document]) -> [DocumentTypeFilter] {
        var present = Set<DocumentType>()
        var hasUntyped = false
        for document in documents {
            if let type = document.documentType { present.insert(type) } else { hasUntyped = true }
        }
        guard !present.isEmpty else { return [] }
        var options = DocumentType.allCases.filter(present.contains).map(DocumentTypeFilter.type)
        if hasUntyped { options.append(.untyped) }
        return options
    }
}
