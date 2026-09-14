import Foundation
import FirebaseAuth

extension Foundation.Notification.Name {
    static let chatDraftDidChange = Foundation.Notification.Name("ChatDraftDidChange")
    static let conversationVanishModeDidChange = Foundation.Notification.Name("ConversationVanishModeDidChange")
    static let conversationMarkedReadLocally = Foundation.Notification.Name("ConversationMarkedReadLocally")
    static let messagingParticipantStateDidChange = Foundation.Notification.Name("MessagingParticipantStateDidChange")
}

final class ChatDraftStore {
    static let shared = ChatDraftStore()

    private let defaults = UserDefaults.standard
    private let keyPrefix = "chatDraft"
    private var memoryCache: [String: String] = [:]

    private init() {}

    func draft(for conversationId: String, userId: String? = Auth.auth().currentUser?.uid) -> String {
        guard let key = storageKey(conversationId: conversationId, userId: userId) else { return "" }
        if let cached = memoryCache[key] { return cached }
        let value = defaults.string(forKey: key) ?? ""
        memoryCache[key] = value
        return value
    }

    func setDraft(_ text: String, for conversationId: String, userId: String? = Auth.auth().currentUser?.uid) {
        guard let key = storageKey(conversationId: conversationId, userId: userId) else { return }
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let previous = defaults.string(forKey: key) ?? ""

        if normalized.isEmpty {
            defaults.removeObject(forKey: key)
            memoryCache[key] = ""
        } else {
            defaults.set(text, forKey: key)
            memoryCache[key] = text
        }

        guard previous != (defaults.string(forKey: key) ?? "") else { return }
        NotificationCenter.default.post(
            name: .chatDraftDidChange,
            object: nil,
            userInfo: ["conversationId": conversationId]
        )
    }

    func clearDraft(for conversationId: String, userId: String? = Auth.auth().currentUser?.uid) {
        setDraft("", for: conversationId, userId: userId)
    }

    private func storageKey(conversationId: String, userId: String?) -> String? {
        let cleanConversationId = conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let userId, !userId.isEmpty, !cleanConversationId.isEmpty else { return nil }
        return "\(keyPrefix).\(userId).\(cleanConversationId)"
    }
}
