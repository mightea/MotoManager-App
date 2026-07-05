import Foundation

// DTOs for the parts inventory (backend migration 012). `Part` carries the
// server-derived inventory meta (`onHand`, `stockCount`) and the fitment
// (`seriesIds`) embedded by the API; on-device the SwiftData models re-derive
// on-hand locally so offline writes stay consistent.

struct Part: Codable, Identifiable {
    let id: Int
    let userId: Int
    let partNumber: String
    let name: String
    let manufacturer: String
    let description: String?
    let isPublic: Bool
    /// Absolutized by NetworkManager (server sends "/images/<uuid>.jpg").
    var image: String?
    let createdAt: String
    let seriesIds: [Int]
    let onHand: Int
    let stockCount: Int
    // Sync metadata (server-provided; see backend migration 012).
    let clientId: String?
    let updatedAt: String?
    let deletedAt: String?
}

struct PartStock: Codable, Identifiable {
    let id: Int
    let partId: Int
    let quantity: Int
    let price: Double?
    let currency: String?
    let normalizedPrice: Double?
    let purchaseDate: String?
    let storageLocationId: Int?
    let notes: String?
    let createdAt: String
    // Sync metadata (server-provided; see backend migration 012).
    let clientId: String?
    let updatedAt: String?
    let deletedAt: String?
}

struct PartConsumption: Codable, Identifiable {
    let id: Int
    let partId: Int
    let maintenanceRecordId: Int?
    let quantity: Int
    let date: String
    let notes: String?
    let createdAt: String
    // Sync metadata (server-provided; see backend migration 012).
    let clientId: String?
    let updatedAt: String?
    let deletedAt: String?
}

struct StorageLocation: Codable, Identifiable {
    let id: Int
    let userId: Int
    let name: String
    let parentId: Int?
    let createdAt: String
    // Sync metadata (server-provided; see backend migration 012).
    let clientId: String?
    let updatedAt: String?
    let deletedAt: String?
}

/// Model-catalog node, hierarchical (realoem-style): Familie -> Serie ->
/// Modell, max depth 3. Global seed rows have `userId == nil`; custom entries
/// carry the creator's id. Fetched and cached like `Currency`.
struct ModelSeries: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let manufacturer: String
    let parentId: Int?
    let userId: Int?
    let createdAt: String

    /// "R 1150 GS" for BMW (the common case), "Yamaha XSR 700" otherwise.
    var displayName: String {
        manufacturer == "BMW" ? name : "\(manufacturer) \(name)"
    }
}

/// Tree helpers for the model catalog. All walks are depth-capped so
/// malformed data can never hang the UI.
enum ModelSeriesCatalog {
    static let maxWalk = 6
    static let levelLabels = ["Familie", "Serie", "Modell"]

    static func depth(of node: ModelSeries, in all: [ModelSeries]) -> Int {
        var depth = 0
        var current = node
        for _ in 0..<maxWalk {
            guard let parent = all.first(where: { $0.id == current.parentId }) else { break }
            depth += 1
            current = parent
        }
        return depth
    }

    static func levelLabel(forDepth depth: Int) -> String {
        levelLabels[min(depth, levelLabels.count - 1)]
    }

    /// "R-Modelle 2V › R 80 GS, R 100 GS, PD (90-95)"
    static func path(of node: ModelSeries, in all: [ModelSeries]) -> String {
        var names = [node.displayName]
        var current = node
        for _ in 0..<maxWalk {
            guard let parent = all.first(where: { $0.id == current.parentId }) else { break }
            names.insert(parent.displayName, at: 0)
            current = parent
        }
        return names.joined(separator: " › ")
    }

    /// Depth-first flattening: children grouped under parents, siblings
    /// sorted by name; orphans surface at root level.
    static func tree(_ all: [ModelSeries]) -> [(node: ModelSeries, depth: Int)] {
        let knownIds = Set(all.map(\.id))
        var childrenOf: [Int?: [ModelSeries]] = [:]
        for node in all {
            let key = node.parentId.flatMap { knownIds.contains($0) ? $0 : nil }
            childrenOf[key, default: []].append(node)
        }
        for key in childrenOf.keys {
            childrenOf[key]?.sort {
                ($0.manufacturer, $0.name) < ($1.manufacturer, $1.name)
            }
        }
        var result: [(node: ModelSeries, depth: Int)] = []
        func visit(_ parentId: Int?, _ depth: Int) {
            guard depth < maxWalk else { return }
            for node in childrenOf[parentId] ?? [] {
                result.append((node, depth))
                visit(node.id, depth + 1)
            }
        }
        visit(nil, 0)
        return result
    }

    /// Ancestors-or-self plus all descendants — the node set a link to
    /// `seriesId` is compatible with. Mirrors the backend's matching.
    static func compatibleIds(of seriesId: Int, in all: [ModelSeries]) -> Set<Int> {
        var matches: Set<Int> = [seriesId]
        var current = all.first(where: { $0.id == seriesId })
        for _ in 0..<maxWalk {
            guard let parentId = current?.parentId else { break }
            matches.insert(parentId)
            current = all.first(where: { $0.id == parentId })
        }
        var frontier: Set<Int> = [seriesId]
        for _ in 0..<maxWalk {
            let next = Set(
                all.filter { node in
                    guard let parentId = node.parentId else { return false }
                    return frontier.contains(parentId) && !matches.contains(node.id)
                }
                .map(\.id)
            )
            if next.isEmpty { break }
            matches.formUnion(next)
            frontier = next
        }
        return matches
    }

    /// Does a part (linked to `partSeriesIds`) fit a bike assigned to
    /// `bikeSeriesId`? Hierarchy-aware in both directions.
    static func matches(partSeriesIds: [Int], bikeSeriesId: Int, in all: [ModelSeries]) -> Bool {
        let compatible = compatibleIds(of: bikeSeriesId, in: all)
        return partSeriesIds.contains(where: compatible.contains)
    }
}

/// Another user's shared part as returned by `/api/parts/public`. The server
/// whitelists catalog data + availability; prices/locations never appear.
struct PublicPart: Codable, Identifiable {
    let id: Int
    let partNumber: String
    let name: String
    let manufacturer: String
    let description: String?
    /// Absolutized by NetworkManager (server sends "/images/<uuid>.jpg").
    var image: String?
    let seriesIds: [Int]
    let ownerName: String
    let hasStock: Bool
    let totalQuantity: Int
}
