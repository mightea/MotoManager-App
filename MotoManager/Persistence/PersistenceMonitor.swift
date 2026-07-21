import Combine
import Foundation
import SwiftData

struct PersistenceIssue: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

/// Central, user-visible reporting for local database failures. Local writes are
/// the source of truth for offline-first features, so a failed save must never be
/// presented as success or silently dismissed.
@MainActor
final class PersistenceMonitor: ObservableObject {
    static let shared = PersistenceMonitor()

    @Published var issue: PersistenceIssue?

    private init() {
        let key = PersistenceController.recoveryMessageKey
        if let recoveryMessage = UserDefaults.standard.string(forKey: key) {
            issue = PersistenceIssue(title: "Lokale Datenbank wiederhergestellt", message: recoveryMessage)
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    @discardableResult
    func save(_ context: ModelContext, operation: String) -> Bool {
        do {
            try context.save()
            return true
        } catch {
            context.rollback()
            AppLog.error("\(operation) failed: \(error.localizedDescription)")
            issue = PersistenceIssue(
                title: "Änderungen nicht gespeichert",
                message: "Deine Eingabe wurde nicht übernommen. Bitte versuche es erneut. (\(error.localizedDescription))"
            )
            return false
        }
    }

    func report(_ error: Error, operation: String) {
        AppLog.error("\(operation) failed: \(error.localizedDescription)")
        issue = PersistenceIssue(
            title: "Lokaler Speicherfehler",
            message: "\(operation) konnte nicht abgeschlossen werden. Bitte versuche es erneut."
        )
    }
}
