import Foundation
import FirebaseAuth

extension Foundation.Notification.Name {
    static let chatDraftDidChange = Foundation.Notification.Name("ChatDraftDidChange")
    static let conversationVanishModeDidChange = Foundation.Notification.Name("ConversationVanishModeDidChange")
}

final class ChatDraftStore {
    static let shared = ChatDraftStore()

    private let defaults = UserDefaults.standard
    private let keyPrefix = "chatDraft"

    private init() {}

    func draft(for conversationId: String, userId: String? = Auth.auth().currentUser?.uid) -> String {
        guard let key = storageKey(conversationId: conversationId, userId: userId) else { return "" }
        return defaults.string(forKey: key) ?? ""
    }

    func setDraft(_ text: String, for conversationId: String, userId: String? = Auth.auth().currentUser?.uid) {
        guard let key = storageKey(conversationId: conversationId, userId: userId) else { return }
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let previous = defaults.string(forKey: key) ?? ""

        if normalized.isEmpty {
            defaults.removeObject(forKey: key)
        } else {
            defaults.set(text, forKey: key)
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
