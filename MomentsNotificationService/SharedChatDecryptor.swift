import Foundation
import CryptoKit
import Security

/// Lightweight, dependency-free decryptor used by the Notification Service Extension
/// to reveal chat message previews on-device (E2E), mirroring `EncryptionService`'s
/// AES-GCM combined-box format and shared Keychain storage.
///
/// It reads the conversation key from the shared Keychain access group
/// (`com.glowsyapp`, the default group both the app and this extension belong to),
/// using the exact same `service`/`account` naming as `EncryptionService`.
enum SharedChatDecryptor {

    /// Must match `EncryptionService.keyChainService`.
    private static let keyChainService = "com.Momentsapp.encryption.v2"

    /// Must match `EncryptionService.conversationKeysPrefix`.
    private static let conversationKeysPrefix = "conversation_key_v2_"

    struct MediaMetadata {
        let purpose: String
        let contentType: String
        let fileExtension: String
        let plaintextSize: Int64

        init?(map: [String: Any]) {
            guard
                let purpose = map["purpose"] as? String,
                let contentType = map["contentType"] as? String,
                let fileExtension = map["fileExtension"] as? String
            else {
                return nil
            }

            let plaintextSize: Int64
            if let size = map["plaintextSize"] as? Int64 {
                plaintextSize = size
            } else if let size = map["plaintextSize"] as? Int {
                plaintextSize = Int64(size)
            } else if let size = map["plaintextSize"] as? Double {
                plaintextSize = Int64(size)
            } else {
                return nil
            }

            self.purpose = purpose
            self.contentType = contentType
            self.fileExtension = fileExtension
            self.plaintextSize = plaintextSize
        }
    }

    /// Loads the per-conversation symmetric key from the shared Keychain.
    /// Returns `nil` if the key is unavailable (e.g. chat never opened on this
    /// device, or the device is locked and the item is not accessible).
    static func loadConversationKey(conversationId: String) -> SymmetricKey? {
        let account = conversationKeysPrefix + conversationId

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keyChainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let keyData = result as? Data else {
            return nil
        }

        return SymmetricKey(data: keyData)
    }

    /// Decrypts a base64-encoded AES-GCM combined box produced by
    /// `EncryptionService.encryptChatMessage`. Returns `nil` on any failure
    /// (missing key, malformed ciphertext, auth failure).
    static func decrypt(_ base64Content: String, conversationId: String) -> String? {
        let trimmed = base64Content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard let key = loadConversationKey(conversationId: conversationId) else {
            return nil
        }

        guard let combinedData = Data(base64Encoded: trimmed) else {
            return nil
        }

        do {
            let sealedBox = try AES.GCM.SealedBox(combined: combinedData)
            let decryptedData = try AES.GCM.open(sealedBox, using: key)
            return String(data: decryptedData, encoding: .utf8)
        } catch {
            return nil
        }
    }

    static func decryptMedia(
        _ encryptedData: Data,
        metadata: MediaMetadata,
        conversationId: String,
        messageId: String
    ) -> Data? {
        guard let conversationKey = loadConversationKey(conversationId: conversationId) else {
            return nil
        }

        let mediaKey = deriveChatMediaKey(
            from: conversationKey,
            conversationId: conversationId,
            messageId: messageId,
            purpose: metadata.purpose
        )
        let authenticatedData = Data(
            "moments.chat.media.aad.v1|\(conversationId)|\(messageId)|\(metadata.purpose)|\(metadata.contentType)".utf8
        )

        do {
            let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
            return try AES.GCM.open(sealedBox, using: mediaKey, authenticating: authenticatedData)
        } catch {
            return nil
        }
    }

    private static func deriveChatMediaKey(
        from conversationKey: SymmetricKey,
        conversationId: String,
        messageId: String,
        purpose: String
    ) -> SymmetricKey {
        let salt = Data("moments.chat.media.salt.v1".utf8)
        let info = Data("moments.chat.media.v1|\(conversationId)|\(messageId)|\(purpose)".utf8)
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: conversationKey,
            salt: salt,
            info: info,
            outputByteCount: 32
        )
    }
}
