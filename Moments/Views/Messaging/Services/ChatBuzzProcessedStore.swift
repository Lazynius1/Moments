import Foundation
import FirebaseAuth

/// Buzz events already replayed (shake/haptic) for a conversation — keyed by event id, not a global boolean.
enum ChatBuzzProcessedStore {
    static let replayWindow: TimeInterval = 300

    private static let keyPrefix = "chatBuzzProcessed"
    private static let defaults = UserDefaults.standard

    static func isProcessed(eventId: String, conversationId: String, userId: String? = Auth.auth().currentUser?.uid) -> Bool {
        guard let key = storageKey(conversationId: conversationId, userId: userId) else { return false }
        let ids = defaults.stringArray(forKey: key) ?? []
        return ids.contains(eventId)
    }

    static func markProcessed(eventId: String, conversationId: String, userId: String? = Auth.auth().currentUser?.uid) {
        guard let key = storageKey(conversationId: conversationId, userId: userId) else { return }
        var ids = defaults.stringArray(forKey: key) ?? []
        guard !ids.contains(eventId) else { return }
        ids.append(eventId)
        // Keep only recent entries to avoid unbounded growth.
        if ids.count > 40 {
            ids = Array(ids.suffix(40))
        }
        defaults.set(ids, forKey: key)
    }

    static func clear(conversationId: String, userId: String? = Auth.auth().currentUser?.uid) {
        guard let key = storageKey(conversationId: conversationId, userId: userId) else { return }
        defaults.removeObject(forKey: key)
    }

    private static func storageKey(conversationId: String, userId: String?) -> String? {
        let cleanConversationId = conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let userId, !userId.isEmpty, !cleanConversationId.isEmpty else { return nil }
        return "\(keyPrefix).\(userId).\(cleanConversationId)"
    }
}
