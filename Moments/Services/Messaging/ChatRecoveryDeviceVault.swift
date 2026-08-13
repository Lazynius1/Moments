import Foundation
import Security

/// Stores the chat recovery PIN in the OS keychain (iCloud Keychain when available)
/// so same-Apple-ID reinstalls can restore without typing the PIN.
enum ChatRecoveryDeviceVault {
    private static let service = "com.Momentsapp.chatRecovery.pin.v1"
    private static let accountPrefix = "chat_recovery_pin_v1_"

    static func savePIN(uid: String, pin: String) {
        let trimmed = pin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !uid.isEmpty, trimmed.count == 6, trimmed.allSatisfy(\.isNumber) else { return }
        guard let data = trimmed.data(using: .utf8) else { return }

        let account = accountPrefix + uid
        deleteExisting(account: account)

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecAttrSynchronizable as String: true
        ]

        var status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecSuccess { return }

        // Fallback: device-only if synchronizable add fails (e.g. no iCloud Keychain).
        query[kSecAttrSynchronizable as String] = false
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        status = SecItemAdd(query as CFDictionary, nil)
        _ = status
    }

    static func loadPIN(uid: String) -> String? {
        guard !uid.isEmpty else { return nil }
        let account = accountPrefix + uid

        if let pin = loadPIN(account: account, synchronizable: true) {
            return pin
        }
        return loadPIN(account: account, synchronizable: false)
    }

    static func clear(uid: String) {
        guard !uid.isEmpty else { return }
        deleteExisting(account: accountPrefix + uid)
    }

    enum PINSyncState {
        case none
        case deviceOnly
        case iCloud
    }

    static func pinSyncState(uid: String) -> PINSyncState {
        guard !uid.isEmpty else { return .none }
        let account = accountPrefix + uid
        if loadPIN(account: account, synchronizable: true) != nil {
            return .iCloud
        }
        if loadPIN(account: account, synchronizable: false) != nil {
            return .deviceOnly
        }
        return .none
    }

    static func hasSynchronizedPIN(uid: String) -> Bool {
        pinSyncState(uid: uid) == .iCloud
    }

    private static func loadPIN(account: String, synchronizable: Bool) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrSynchronizable as String: synchronizable
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        guard let pin = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = pin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 6, trimmed.allSatisfy(\.isNumber) else { return nil }
        return trimmed
    }

    private static func deleteExisting(account: String) {
        for synchronizable in [true, false] {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecAttrSynchronizable as String: synchronizable
            ]
            SecItemDelete(query as CFDictionary)
        }
    }
}
