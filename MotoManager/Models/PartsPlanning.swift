import Combine
import Foundation

// MARK: - "Bald gebraucht"

/// Why a part will be needed soon.
enum PartNeedReason: Equatable {
    case issue(title: String)
    case interval(label: String, due: Date)
}

struct PartNeed: Equatable {
    let partId: UUID
    let reason: PartNeedReason
}

/// Infers which stocked parts a bike will need soon, from its open issues
/// and its service intervals coming due: the part↔defect links (server-backed,
/// see `IssuePartLinkStore`) plus matching on names. Pure, so it can be tested.
enum PartNeeds {
    struct Part { let id: UUID; let name: String; let fitsBike: Bool }
    struct Issue { let id: UUID; let title: String; let text: String }
    struct Interval { let key: String; let label: String; let due: Date; let isDue: Bool }

    /// Words in part names that belong to an interval.
    static func keywords(forInterval key: String) -> [String] {
        switch key {
        case "fluid-engineoil": ["ölfilter", "oelfilter", "motoröl", "motorenöl"]
        case "fluid-gearboxoil": ["getriebeöl"]
        case "fluid-finaldriveoil", "fluid-finaldrivegearboxoil": ["kardanöl", "hinterachsöl", "endantriebsöl"]
        case "fluid-forkoil": ["gabelöl"]
        case "fluid-brakefluid": ["bremsflüssigkeit"]
        case "fluid-coolant": ["kühlmittel", "kühlflüssigkeit"]
        case "battery": ["batterie"]
        case "tire-front", "tire-rear": ["reifen"]
        case "chain": ["kette", "kettenspray", "kettenfett"]
        default: []
        }
    }

    /// Generic words an issue text shares with many part names.
    private static let stopwords: Set<String> = [
        "prüfen", "bestellen", "ersetzen", "wechseln", "tauschen", "defekt", "standzeit", "manchmal",
        "leicht", "kaputt", "undicht", "bitte", "wieder", "immer", "vorne", "hinten", "links", "rechts",
        "flackert", "tropft", "schwergängig", "kontrollieren", "massekontakt"
    ]

    /// Lower-cased words of at least five letters, without stopwords.
    static func tokens(_ text: String) -> Set<String> {
        Set(text.lowercased()
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { $0.count >= 5 && !stopwords.contains($0) })
    }

    /// Needs, one per part (an issue beats an interval), issues first, then
    /// by due date. Intervals count when due or within `horizon` months.
    static func needs(parts: [Part], issues: [Issue], intervals: [Interval],
                      links: [UUID: Set<UUID>] = [:], now: Date = Date(), horizon: Int = 12) -> [PartNeed] {
        var result: [UUID: PartNeed] = [:]
        let byId = Dictionary(parts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        for issue in issues {
            for partId in links[issue.id] ?? [] where byId[partId] != nil && result[partId] == nil {
                result[partId] = PartNeed(partId: partId, reason: .issue(title: issue.title))
            }
            let words = tokens(issue.title + " " + issue.text)
            guard !words.isEmpty else { continue }
            for part in parts where part.fitsBike && result[part.id] == nil {
                let name = part.name.lowercased()
                if words.contains(where: { name.contains($0) }) {
                    result[part.id] = PartNeed(partId: part.id, reason: .issue(title: issue.title))
                }
            }
        }

        let limit = Calendar.current.date(byAdding: .month, value: horizon, to: now) ?? now
        for interval in intervals.sorted(by: { $0.due < $1.due }) where interval.isDue || interval.due <= limit {
            let words = keywords(forInterval: interval.key)
            guard !words.isEmpty else { continue }
            for part in parts where part.fitsBike && result[part.id] == nil {
                let name = part.name.lowercased()
                if words.contains(where: { name.contains($0) }) {
                    result[part.id] = PartNeed(partId: part.id, reason: .interval(label: interval.label, due: interval.due))
                }
            }
        }

        return result.values.sorted { lhs, rhs in
            switch (lhs.reason, rhs.reason) {
            case (.issue, .interval): return true
            case (.interval, .issue): return false
            case let (.interval(_, a), .interval(_, b)): return a < b
            case let (.issue(a), .issue(b)): return a < b
            }
        }
    }
}

// MARK: - Einkaufsliste

/// One line of the shopping list.
struct ShoppingItem: Equatable, Identifiable {
    enum Group: Int, Comparable {
        case issue, low, manual
        static func < (lhs: Group, rhs: Group) -> Bool { lhs.rawValue < rhs.rawValue }

        var title: String {
            switch self {
            case .issue: "Für offene Mängel"
            case .low: "Knapp im Lager"
            case .manual: "Vorgemerkt"
            }
        }
    }

    let partId: UUID
    let name: String
    let group: Group
    let onHand: Int
    var quantity: Int
    let unitPrice: Double?

    var id: UUID { partId }
    var estimate: Double? { unitPrice.map { $0 * Double(quantity) } }
}

/// Builds the shopping list from stock levels, needs and the user's own
/// entries. Pure, so it can be tested.
enum ShoppingList {
    struct Part { let id: UUID; let name: String; let onHand: Int; let unitPrice: Double? }

    /// Parts at one piece or none, parts an open issue needs (unless enough
    /// are stocked) and manual entries. A part the user cleared stays off
    /// until its stock changes.
    static func items(parts: [Part], neededForIssue: Set<UUID>, manual: Set<UUID>,
                      dismissed: [UUID: Int], quantities: [UUID: Int]) -> [ShoppingItem] {
        parts.compactMap { part -> ShoppingItem? in
            let group: ShoppingItem.Group
            if neededForIssue.contains(part.id) && part.onHand <= 1 { group = .issue }
            else if part.onHand <= 1 { group = .low }
            else if manual.contains(part.id) { group = .manual }
            else { return nil }
            if !manual.contains(part.id), let cleared = dismissed[part.id], cleared == part.onHand { return nil }
            let suggested = max(1, 2 - part.onHand)
            return ShoppingItem(partId: part.id, name: part.name, group: group, onHand: part.onHand,
                                quantity: max(1, quantities[part.id] ?? suggested), unitPrice: part.unitPrice)
        }
        .sorted { ($0.group, $0.name) < ($1.group, $1.name) }
    }

    /// Plain text to share with a shop or a friend.
    static func text(_ items: [ShoppingItem]) -> String {
        var lines = ["Einkaufsliste"]
        for group in [ShoppingItem.Group.issue, .low, .manual] {
            let rows = items.filter { $0.group == group }
            guard !rows.isEmpty else { continue }
            lines.append("")
            lines.append(group.title + ":")
            lines += rows.map { "• \($0.quantity)× \($0.name)" }
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - On-device state

/// Shopping-list state, kept on this device (the server has no place for it
/// yet). Part↔defect links used to live here too; they moved to the server
/// (`IssuePartLinkStore`), and old snapshots still decode so they can be
/// handed over once.
@MainActor
final class PartsPlanningStore: ObservableObject {
    static let shared = PartsPlanningStore()

    @Published private(set) var manual: Set<UUID>
    @Published private(set) var dismissed: [UUID: Int]
    @Published private(set) var quantities: [UUID: Int]
    /// Links from before the move to the server, until taken.
    private var legacyLinks: [UUID: Set<UUID>]

    private let defaults: UserDefaults
    private static let key = "com.motomanager.partsPlanning"

    private struct Snapshot: Codable {
        var manual: Set<UUID> = []
        var dismissed: [UUID: Int] = [:]
        var quantities: [UUID: Int] = [:]
        /// Legacy: only read, never written once taken.
        var links: [UUID: Set<UUID>]?
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let snapshot = defaults.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) } ?? Snapshot()
        manual = snapshot.manual
        dismissed = snapshot.dismissed
        quantities = snapshot.quantities
        legacyLinks = snapshot.links ?? [:]
    }

    func addToList(_ partId: UUID) {
        manual.insert(partId)
        dismissed[partId] = nil
        persist()
    }

    /// Takes the part off the list until its stock changes.
    func clear(_ partId: UUID, onHand: Int) {
        manual.remove(partId)
        dismissed[partId] = onHand
        quantities[partId] = nil
        persist()
    }

    func setQuantity(_ quantity: Int, for partId: UUID) {
        quantities[partId] = max(1, quantity)
        persist()
    }

    /// Hands the pre-server links over (once) and drops them from the device.
    func takeLegacyLinks() -> [UUID: Set<UUID>] {
        let taken = legacyLinks
        guard !taken.isEmpty else { return [:] }
        legacyLinks = [:]
        persist()
        return taken
    }

    func clearAll() {
        manual = []; dismissed = [:]; quantities = [:]; legacyLinks = [:]
        persist()
    }

    private func persist() {
        let snapshot = Snapshot(manual: manual, dismissed: dismissed, quantities: quantities,
                                links: legacyLinks.isEmpty ? nil : legacyLinks)
        if let data = try? JSONEncoder().encode(snapshot) { defaults.set(data, forKey: Self.key) }
    }
}
