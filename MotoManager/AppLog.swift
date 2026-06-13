import Foundation
import os

/// Lightweight diagnostic logging.
///
/// Replaces the ad-hoc `print()` statements that previously dumped full
/// response bodies — including the login response containing the JWT — to the
/// console in every build. `AppLog` only emits in DEBUG builds and is intended
/// for low-cardinality status/count messages. **Never** pass response bodies,
/// tokens, or other secrets here; for any dynamic value prefer the `os.Logger`
/// `privacy: .private` redaction below.
enum AppLog {
    private static let logger = Logger(subsystem: "ltd.herrmann.MotoManager", category: "app")

    /// Log a non-sensitive diagnostic message (DEBUG builds only).
    static func debug(_ message: String) {
        #if DEBUG
        logger.debug("\(message, privacy: .public)")
        #endif
    }

    /// Log a non-fatal error. Safe in all builds; the message is treated as public,
    /// so keep it free of secrets.
    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}
