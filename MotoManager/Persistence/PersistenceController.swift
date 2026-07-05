import Foundation
import SwiftData

/// Owns the app-wide SwiftData stack for the offline-first sync entities.
enum PersistenceController {
    /// The model types that make up the local store.
    static let schema = Schema([
        SDMaintenanceRecord.self,
        SDTorqueSpec.self,
        SDIssue.self,
        SDPart.self,
        SDPartStock.self,
        SDPartConsumption.self,
        SDStorageLocation.self,
    ])

    static let shared: ModelContainer = {
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // The on-disk store is unreadable (e.g. an unmigratable schema change).
            // Do NOT silently fall back to an in-memory store: that makes every
            // launch ephemeral and quietly discards offline writes while pretending
            // to work. Instead rebuild the persistent store from scratch. The
            // synced entities are server-backed, so a rebuild simply re-pulls them;
            // only un-synced local writes are lost — and those are already
            // unreadable in the corrupt store.
            AppLog.error("SwiftData store unreadable, rebuilding from scratch: \(error.localizedDescription)")
            destroyDefaultStore()
            do {
                return try ModelContainer(for: schema, configurations: [config])
            } catch {
                // A fresh persistent store still failed — unrecoverable. Fail loudly
                // rather than degrade to a silent, data-losing in-memory store.
                fatalError("Unrecoverable SwiftData store failure: \(error)")
            }
        }
    }()

    /// Delete the default on-disk store and its `-wal`/`-shm` sidecar files so a
    /// fresh, still-persistent store can be created.
    private static func destroyDefaultStore() {
        let fm = FileManager.default
        guard let dir = try? fm.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: false
        ) else { return }
        let base = dir.appending(path: "default.store").path(percentEncoded: false)
        for path in [base, base + "-wal", base + "-shm"] {
            try? fm.removeItem(atPath: path)
        }
    }
}
