import Foundation
import Combine

/// User-level settings (service-interval rules) shared by every bike's
/// workspace. Cached on disk so the intervals card uses the user's own rules
/// offline; falls back to the webapp defaults before the first fetch.
@MainActor
final class UserSettingsStore: ObservableObject {
    static let shared = UserSettingsStore()

    @Published private(set) var settings: UserSettings
    /// False until the server copy has been fetched (or restored from cache)
    /// in this session.
    @Published private(set) var hasLoaded = false

    private init() {
        if let cached = CacheStore.shared.load(UserSettings.self, key: CacheKey.userSettings) {
            settings = cached
            hasLoaded = true
        } else {
            settings = .defaults
        }
    }

    /// Fetches the server copy; a failure keeps whatever is already loaded
    /// (cache or defaults) — the intervals card must not go blank offline.
    func refresh() async {
        do {
            let fresh = try await NetworkManager.shared.fetchUserSettings()
            apply(fresh)
        } catch {
            AppLog.debug("User settings refresh failed: \(error.localizedDescription)")
        }
    }

    /// Saves to the server and applies the confirmed copy. Online-only: the
    /// settings are not part of the offline sync protocol.
    func update(_ settings: UserSettings) async throws {
        let saved = try await NetworkManager.shared.updateUserSettings(settings)
        apply(saved)
    }

    private func apply(_ settings: UserSettings) {
        self.settings = settings
        hasLoaded = true
        CacheStore.shared.save(settings, key: CacheKey.userSettings)
    }

    /// Logout: drop the previous account's rules so the next login starts
    /// from the defaults until its own settings arrive.
    func clear() {
        settings = .defaults
        hasLoaded = false
        CacheStore.shared.remove(key: CacheKey.userSettings)
    }
}
