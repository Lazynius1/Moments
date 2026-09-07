import Foundation
import FirebaseFirestore
import FirebaseAuth

/// The group namespace is allocated only by manageGroup. Direct IDs are unchanged.
/// This survives offline queues/cache restoration without relying on participant count.
enum GroupChatScope {
    static func isGroup(_ id: String?) -> Bool {
        guard let id, id.hasPrefix("group-") else { return false }
        return UUID(uuidString: String(id.dropFirst(6))) != nil
    }
    static func newId() -> String { "group-" + UUID().uuidString }
    static func reactions(_ id: String) -> String { isGroup(id) ? "groupMessageReactions" : "messageReactions" }
}

extension Firestore {
    func messagingThread(_ id: String) -> DocumentReference {
        collection(GroupChatScope.isGroup(id) ? "groupConversations" : "conversations").document(id)
    }
}

extension DocumentReference {
    var messagingMessages: CollectionReference {
        collection(parent.collectionID == "groupConversations" ? "groupMessages" : "messages")
    }
}

extension Conversation {
    var isGroup: Bool { GroupChatScope.isGroup(id) }
}

extension GroupChatScope {
    static func recipientMetadata(_ raw: [String: Any], conversationId: String) -> [String: Any] {
        guard isGroup(conversationId), let uid = Auth.auth().currentUser?.uid,
              raw["senderId"] as? String != uid,
              raw["isViewOnce"] as? Bool == true else { return raw }
        var data = raw
        var viewed = raw["viewedBy"] as? [String] ?? []
        let eligible = (raw["recipientIds"] as? [String] ?? []).contains(uid)
        if !eligible && !viewed.contains(uid) { viewed.append(uid) }
        data["viewedBy"] = viewed
        data["isViewed"] = viewed.contains(uid)
        return data
    }
}
