import UIKit

/// Home-screen quick actions (long-press on the app icon). The items are
/// declared statically in `Supporting/Info.plist` so they exist before the
/// first launch; this maps their type identifiers onto the shared
/// `QuickActionRouter`, which App Shortcuts already use — one dispatch path
/// for both entry points.
enum HomeQuickAction: String {
    case addFuel = "ltd.herrmann.MotoManager.addFuel"
    case scanPart = "ltd.herrmann.MotoManager.scanPart"

    init?(_ item: UIApplicationShortcutItem) {
        self.init(rawValue: item.type)
    }

    func dispatch() {
        switch self {
        case .addFuel: QuickActionRouter.shared.pending = .addFuel
        case .scanPart: QuickActionRouter.shared.pending = .scanPart
        }
    }
}

/// Minimal delegate whose only job is installing `QuickActionSceneDelegate` —
/// the pure-SwiftUI lifecycle has no other hook for quick actions.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = QuickActionSceneDelegate.self
        return config
    }
}

final class QuickActionSceneDelegate: NSObject, UIWindowSceneDelegate {
    /// Cold launch from a quick action.
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        if let item = connectionOptions.shortcutItem {
            HomeQuickAction(item)?.dispatch()
        }
    }

    /// Quick action while the app is already running.
    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        if let action = HomeQuickAction(shortcutItem) {
            action.dispatch()
            completionHandler(true)
        } else {
            completionHandler(false)
        }
    }
}
