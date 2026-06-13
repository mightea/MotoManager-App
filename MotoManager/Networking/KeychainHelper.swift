import Foundation
import Security

class KeychainHelper {
    static let shared = KeychainHelper()

    private init() {}

    /// Stores `data`, replacing any existing item for the same service/account.
    ///
    /// Items are written with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`:
    /// readable after the first unlock (so background work keeps working) but never
    /// migrated to a new device via encrypted backup/restore. Returns whether the
    /// write succeeded so callers can react to failures.
    @discardableResult
    func save(_ data: Data, service: String, account: String) -> Bool {
        let query: [String: Any] = [
            kSecValueData as String: data,
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        if status == errSecDuplicateItem {
            // Item already exists — update its value (and refresh accessibility).
            let matchQuery: [String: Any] = [
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecClass as String: kSecClassGenericPassword
            ]
            let attributesToUpdate: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ]

            let updateStatus = SecItemUpdate(matchQuery as CFDictionary, attributesToUpdate as CFDictionary)
            if updateStatus != errSecSuccess {
                AppLog.error("Keychain update failed (status \(updateStatus))")
                return false
            }
            return true
        }

        if status != errSecSuccess {
            AppLog.error("Keychain save failed (status \(status))")
            return false
        }
        return true
    }

    func read(service: String, account: String) -> Data? {
        let query: [String: Any] = [
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecClass as String: kSecClassGenericPassword,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status != errSecSuccess && status != errSecItemNotFound {
            AppLog.error("Keychain read failed (status \(status))")
        }

        return result as? Data
    }

    /// Removes the item. Returns whether the keychain no longer holds it
    /// (treats "not found" as success so logout is idempotent).
    @discardableResult
    func delete(service: String, account: String) -> Bool {
        let query: [String: Any] = [
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecClass as String: kSecClassGenericPassword
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            AppLog.error("Keychain delete failed (status \(status))")
            return false
        }
        return true
    }
}
