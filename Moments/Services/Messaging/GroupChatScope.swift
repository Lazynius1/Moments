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

extension Query {
    func applyingHistoryCutoff(_ cutoff: MessageHistoryCutoff?) -> Query {
        guard let cutoff else { return self }
        let timestamp = Timestamp(date: cutoff.date)
        if cutoff.inclusive {
            return whereField("timestamp", isGreaterThanOrEqualTo: timestamp)
        }
        return whereField("timestamp", isGreaterThan: timestamp)
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

extension GroupChatScope {
    static func noticeText(_ content: String) -> String? {
        guard let bytes = content.data(using: .utf8),
              let data = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any],
              let kind = data["groupNotice"] as? String, ["joined", "left", "removed", "dissolved"].contains(kind),
              let name = data["name"] as? String else { return nil }
        return String(format: NSLocalizedString("groups.notice." + kind, comment: "Group membership event"), name)
    }

    static func typingSubtitle(userIds: Set<String>, names: [String: String]) -> String {
        let resolved = userIds.compactMap { id -> String? in
            let name = names[id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return name.isEmpty ? nil : name
        }
        switch resolved.count {
        case 0:
            return NSLocalizedString("chat.typing", comment: "")
        case 1:
            return String(format: NSLocalizedString("groups.typing.one", comment: ""), resolved[0])
        case 2:
            return String(format: NSLocalizedString("groups.typing.two", comment: ""), resolved[0], resolved[1])
        default:
            return String(
                format: NSLocalizedString("groups.typing.more", comment: ""),
                resolved[0],
                resolved.count - 1
            )
        }
    }

    static func detectMentionToken(in text: String) -> MentionDraftToken? {
        if let token = MentionParsing.detectActiveToken(in: text) { return token }
        guard !text.isEmpty else { return nil }
        let tokenStart = text.lastIndex(where: { $0.isWhitespace }).map { text.index(after: $0) } ?? text.startIndex
        let tokenRange = tokenStart..<text.endIndex
        guard String(text[tokenRange]) == "@" else { return nil }
        return MentionDraftToken(query: "", fullRange: tokenRange)
    }

    static func mentionedMemberIds(in text: String, members: [(id: String, name: String)], senderId: String) -> [String] {
        let usernames = MentionParsing.extractUsernames(from: text)
        guard !usernames.isEmpty else { return [] }
        return members.compactMap { member in
            guard member.id != senderId else { return nil }
            return usernames.contains(where: { $0.caseInsensitiveCompare(member.name) == .orderedSame }) ? member.id : nil
        }
    }
}
