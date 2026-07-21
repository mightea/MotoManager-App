import Foundation
import SwiftData

/// Owns the app-wide SwiftData stack for the offline-first sync entities.
enum PersistenceController {
    static let recoveryMessageKey = "com.motomanager.persistenceRecoveryMessage"
    /// The model types that make up the local store.
    static let schema = Schema([
        SDMaintenanceRecord.self,
        SDTorqueSpec.self,
        SDIssue.self,
        SDMotorcycleDetail.self,
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
            // to work. Preserve the unreadable files, then rebuild the persistent
            // store from scratch. The
            // synced entities are server-backed, so a rebuild simply re-pulls them;
            // only un-synced local writes are lost — and those are already
            // unreadable in the corrupt store.
            AppLog.error("SwiftData store unreadable, rebuilding from scratch: \(error.localizedDescription)")
            quarantineDefaultStore()
            do {
                return try ModelContainer(for: schema, configurations: [config])
            } catch {
                // A fresh persistent store still failed — unrecoverable. Fail loudly
                // rather than degrade to a silent, data-losing in-memory store.
                fatalError("Unrecoverable SwiftData store failure: \(error)")
            }
        }
    }()

    /// Move the default store and its sidecars to a recovery directory before a
    /// fresh store is created. This preserves unsynced writes for support/manual
    /// recovery instead of destroying the only remaining copy.
    private static func quarantineDefaultStore() {
        let fm = FileManager.default
        guard let dir = try? fm.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: false
        ) else { return }
        let baseURL = dir.appending(path: "default.store")
        let recoveryDirectory = dir
            .appending(path: "MotoManagerRecovery", directoryHint: .isDirectory)
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let sources = [
            baseURL,
            URL(filePath: baseURL.path(percentEncoded: false) + "-wal"),
            URL(filePath: baseURL.path(percentEncoded: false) + "-shm")
        ].filter { fm.fileExists(atPath: $0.path(percentEncoded: false)) }

        guard !sources.isEmpty else { return }

        do {
            try fm.createDirectory(at: recoveryDirectory, withIntermediateDirectories: true)
            // Copy the complete store first. If any copy fails, every original
            // remains in place and the subsequent open fails loudly. Only once
            // the recovery set is complete do we remove the unreadable sources.
            for source in sources {
                try fm.copyItem(at: source, to: recoveryDirectory.appending(path: source.lastPathComponent))
            }
            for source in sources {
                try fm.removeItem(at: source)
            }
            UserDefaults.standard.set(
                "Die beschädigte Datenbank wurde gesichert. Nicht synchronisierte Änderungen könnten fehlen.",
                forKey: recoveryMessageKey
            )
            AppLog.error("Unreadable SwiftData store preserved at \(recoveryDirectory.path(percentEncoded: false))")
        } catch {
            // If removal partially failed, the complete recovery copy still
            // exists. The subsequent container open fails loudly when an
            // unreadable original remains.
            AppLog.error("Could not preserve unreadable SwiftData store: \(error.localizedDescription)")
        }
    }
}
