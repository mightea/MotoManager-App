import Foundation

/// Per-record sync lifecycle for the offline-first store.
///
/// A record is `synced` once the server has acknowledged it. Local edits move it
/// to one of the `pending*` states; the `SyncEngine` drains those to the server
/// and returns the record to `synced`. `pendingDelete` is a local tombstone —
/// the row is hidden from the UI but kept until the server confirms the delete.
enum SyncState: String, Codable, Sendable, CaseIterable {
    case synced
    case pendingCreate
    case pendingUpdate
    case pendingDelete

    /// True when the record still owes the server a change.
    var isPending: Bool { self != .synced }
}
