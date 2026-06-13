import SwiftUI

/// Actions for chrome elements (gear button, garage switcher) that live deep
/// in the view tree. Wired at the MainTabView level so individual screens do
/// not need to prop-drill closures.
struct ChromeActions {
    var openGarage: () -> Void = {}
    var openSettings: () -> Void = {}
}

private struct ChromeActionsKey: EnvironmentKey {
    static let defaultValue = ChromeActions()
}

extension EnvironmentValues {
    var chromeActions: ChromeActions {
        get { self[ChromeActionsKey.self] }
        set { self[ChromeActionsKey.self] = newValue }
    }
}
