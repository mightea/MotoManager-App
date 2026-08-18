import AppIntents
import Combine
import SwiftUI

// MARK: - Quick-action router

/// Bridges App Intents to the UI. An intent stashes the requested action here;
/// `MainTabView` switches to the owning tab, and the tab view consumes the
/// action by presenting its sheet. The value stays pending until a view is
/// ready to consume it, so a cold launch (fleet still loading) works too.
final class QuickActionRouter: ObservableObject {
    static let shared = QuickActionRouter()

    enum QuickAction {
        case addFuel
        case scanPart
    }

    @Published var pending: QuickAction?

    private init() {}
}

// MARK: - Intents

/// Opens the app on the fuel tab with the new-fill sheet presented.
struct AddFuelIntent: AppIntent {
    static let title: LocalizedStringResource = "Tankung erfassen"
    static let description = IntentDescription("Öffnet MotoManager und startet eine neue Tankung.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        QuickActionRouter.shared.pending = .addFuel
        return .result()
    }
}

/// Opens the app on the parts tab with the QR label scanner presented.
struct ScanPartLabelIntent: AppIntent {
    static let title: LocalizedStringResource = "Etikett scannen"
    static let description = IntentDescription("Öffnet MotoManager und scannt ein Teile- oder Lagerort-Etikett.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        QuickActionRouter.shared.pending = .scanPart
        return .result()
    }
}

// MARK: - App Shortcuts

/// Surfaces the two highest-frequency actions in Spotlight, Siri and the
/// Shortcuts app without any user setup.
struct MotoManagerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddFuelIntent(),
            phrases: [
                "Tankung in \(.applicationName) erfassen",
                "Neue Tankung in \(.applicationName)",
                "In \(.applicationName) tanken",
                "Log fuel in \(.applicationName)"
            ],
            shortTitle: "Tankung erfassen",
            systemImageName: "fuelpump.fill"
        )
        AppShortcut(
            intent: ScanPartLabelIntent(),
            phrases: [
                "Etikett in \(.applicationName) scannen",
                "Teil in \(.applicationName) scannen",
                "Lagerort in \(.applicationName) scannen",
                "Scan part in \(.applicationName)"
            ],
            shortTitle: "Etikett scannen",
            systemImageName: "qrcode.viewfinder"
        )
    }
}
