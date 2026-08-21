import Foundation
import Combine

/// Response of `GET /api/app-upgrade` — the admin-configured minimum build
/// numbers for this app. 0 disables the respective check.
struct AppUpgradeInfo: Codable {
    let softUpgradeBuild: Int
    let hardUpgradeBuild: Int
}

/// Where this build stands relative to the backend's upgrade requirements.
enum AppUpgradeStatus: Equatable {
    /// Build is current enough — nothing to do.
    case supported
    /// Build is at or below the soft requirement — remind the user to update.
    case updateRecommended
    /// Build is below the hard requirement — out of support; no further
    /// backend requests are allowed until the app is updated.
    case unsupported
}

/// Checks the backend's app-upgrade requirements after login and drives the
/// two consequences: an update-reminder toast (soft) and the full request
/// block plus blocking screen (hard).
@MainActor
final class AppUpgradeManager: ObservableObject {
    static let shared = AppUpgradeManager()

    /// Transient update reminder; auto-dismissed by the toast view.
    @Published var showUpdateToast = false
    /// Hard block: the app is out of support and must be updated.
    @Published var isBlocked = false

    private init() {}

    /// `CFBundleVersion` as an integer (CI sets it to run*10 + attempt + 900).
    static var currentBuild: Int {
        Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
    }

    /// Pure decision, kept separate for tests. The hard bound wins over the
    /// soft one; a build *equal* to the hard bound is still supported (the
    /// bound names the first supported build), while a build *equal* to the
    /// soft bound already gets the reminder.
    static func evaluate(build: Int, softUpgradeBuild: Int, hardUpgradeBuild: Int) -> AppUpgradeStatus {
        if build < hardUpgradeBuild {
            return .unsupported
        }
        if build <= softUpgradeBuild {
            return .updateRecommended
        }
        return .supported
    }

    /// Fetch the requirements and apply them. Fails open: when the check
    /// itself fails (offline, server error) the current state is kept, so a
    /// network hiccup never locks the user out.
    func check() async {
        guard let info = try? await NetworkManager.shared.fetchAppUpgradeInfo() else { return }

        let status = Self.evaluate(
            build: Self.currentBuild,
            softUpgradeBuild: info.softUpgradeBuild,
            hardUpgradeBuild: info.hardUpgradeBuild
        )
        isBlocked = status == .unsupported
        NetworkManager.shared.isUpdateBlocked = isBlocked
        showUpdateToast = status == .updateRecommended
        if status != .supported {
            AppLog.error("App upgrade check: build \(Self.currentBuild) is \(status == .unsupported ? "unsupported (hard \(info.hardUpgradeBuild))" : "below soft requirement \(info.softUpgradeBuild)")")
        }
    }
}
