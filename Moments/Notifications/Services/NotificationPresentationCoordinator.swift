import Foundation
import FirebaseAuth
import FirebaseFirestore

enum NotificationPresentationSource {
    case push
    case firestore
    case local
}

@MainActor
final class NotificationPresentationCoordinator {
    static let shared = NotificationPresentationCoordinator()

    private var recentDedupKeys: [String: Date] = [:]
    private let dedupWindow: TimeInterval = 5.0
    private let db = Firestore.firestore()

    private init() {}

    func present(from userInfo: [AnyHashable: Any], source: NotificationPresentationSource) {
        guard let notification = mapPushPayload(userInfo) else { return }
        present(notification, source: source, userInfo: userInfo)
    }

    func present(_ notification: Notification, source: NotificationPresentationSource, userInfo: [AnyHashable: Any]? = nil) {
        if notification.senderId == Auth.auth().currentUser?.uid { return }
        guard shouldShowBanner(for: notification) else { return }
        guard registerDedup(for: notification) else { return }

        applySideEffects(for: notification, userInfo: userInfo)

        Task { @MainActor in
            let resolved = await InAppNotificationPreviewResolver.resolve(notification, userInfo: userInfo)
            guard self.shouldShowBanner(for: resolved) else { return }
            InAppNotificationService.shared.display(resolved)
        }
    }

    static func isSilentPush(_ userInfo: [AnyHashable: Any]) -> Bool {
        Self.parseBool(userInfo["silent"])
    }

    // MARK: - Suppression

    private func shouldShowBanner(for notification: Notification) -> Bool {
        let chatTypes: Set<NotificationType> = [.message, .messageReaction, .chatBuzz]
        if chatTypes.contains(notification.type),
           let conversationId = notification.conversationId,
           !conversationId.isEmpty,
           let userId = Auth.auth().currentUser?.uid,
           ChatService.shared.isConversationArchived(conversationId, for: userId) {
            return false
        }
        guard chatTypes.contains(notification.type),
              let conversationId = notification.conversationId,
              !conversationId.isEmpty,
              conversationId == ChatSessionEngine.shared.activeConversationId else {
            return true
        }
        return false
    }

    // MARK: - Dedup

    private func registerDedup(for notification: Notification) -> Bool {
        let key = dedupKey(for: notification)
        let now = Date()
        recentDedupKeys = recentDedupKeys.filter { now.timeIntervalSince($0.value) < dedupWindow }

        if recentDedupKeys[key] != nil {
            return false
        }

        recentDedupKeys[key] = now
        return true
    }

    private func dedupKey(for notification: Notification) -> String {
        let bucket = Int(notification.timestamp.timeIntervalSince1970 / dedupWindow)
        switch notification.type {
        case .message:
            return "message|\(notification.conversationId ?? "")|\(notification.senderId)|\(bucket)"
        case .messageReaction:
            return "messageReaction|\(notification.conversationId ?? "")|\(notification.messageId ?? "")|\(notification.senderId)|\(bucket)"
        case .chatBuzz:
            return "chatBuzz|\(notification.conversationId ?? "")|\(notification.buzzEventId ?? notification.senderId)|\(bucket)"
        case .like, .reaction, .comment, .mention, .photoTag, .storyReaction:
            return "\(notification.type.rawValue)|\(notification.senderId)|\(notification.momentId ?? "")|\(notification.storyId ?? "")|\(notification.commentId ?? "")|\(bucket)"
        case .newFollower, .followRequest, .requestAccepted, .mutualConnection:
            return "\(notification.type.rawValue)|\(notification.senderId)|\(bucket)"
        case .storyChainContinued:
            return "\(notification.type.rawValue)|\(notification.senderId)|\(notification.chainId ?? "")|\(notification.chainPosition ?? 0)|\(bucket)"
        default:
            if let id = notification.id, !id.isEmpty {
                return "\(notification.type.rawValue)|\(id)"
            }
            return "\(notification.type.rawValue)|\(notification.senderId)|\(bucket)"
        }
    }

    // MARK: - Side effects

    private func applySideEffects(for notification: Notification, userInfo: [AnyHashable: Any]?) {
        switch notification.type {
        case .message:
            if let conversationId = notification.conversationId,
               let messageId = notification.messageId {
                ChatService.shared.markMessageAsDeliveredFromNotification(
                    conversationId: conversationId,
                    messageId: messageId
                )

                if let userInfo {
                    Task { @MainActor in
                        await MessageIngestService.shared.ingest(userInfo: userInfo)
                    }
                } else {
                    Task { @MainActor in
                        await MessageIngestService.shared.ingest(
                            conversationId: conversationId,
                            messageId: messageId,
                            source: .push
                        )
                    }
                }
            }

        case .messageReaction:
            guard let conversationId = notification.conversationId,
                  let messageId = notification.messageId else { return }
            NotificationCenter.default.post(
                name: .chatMessageReactionHighlight,
                object: nil,
                userInfo: [
                    "conversationId": conversationId,
                    "messageId": messageId
                ]
            )

        case .chatBuzz:
            guard let conversationId = notification.conversationId else { return }
            ChatNavigationIntentStore.enqueueBuzz(
                conversationId: conversationId,
                buzzEventId: notification.buzzEventId
            )
            if conversationId == ChatSessionEngine.shared.activeConversationId {
                NotificationCenter.default.post(
                    name: .chatBuzzHighlight,
                    object: nil,
                    userInfo: [
                        "conversationId": conversationId,
                        "buzzEventId": notification.buzzEventId as Any
                    ]
                )
            }

        default:
            break
        }
    }

    // MARK: - Push mapping

    private func mapPushPayload(_ userInfo: [AnyHashable: Any]) -> Notification? {
        guard let rawType = userInfo["type"] as? String else { return nil }
        guard let notificationType = mapPushType(rawType) else { return nil }

        let senderId = firstString(in: userInfo, keys: ["senderId", "userId", "followerId"])
            ?? (notificationType == .gentleReminder ? "gentle_reminder" : "")
        let senderUsername = firstString(in: userInfo, keys: ["senderUsername", "username"]) ?? "Moments"
        let conversationId = firstString(in: userInfo, keys: ["conversationId", "targetId"])
        let messageId = firstString(in: userInfo, keys: ["messageId", "targetMessageId"])
        let messageType = firstString(in: userInfo, keys: ["messageType"])
        let buzzEventId = firstString(in: userInfo, keys: ["buzzEventId"])
        let reminderVariant = firstString(in: userInfo, keys: ["reminderVariant"])
        let reactionEmoji = firstString(in: userInfo, keys: ["reactionEmoji", "reactionType", "reaction"])
        let reactionEmojis = firstString(in: userInfo, keys: ["reactionEmojis"])
        let isReactionPlural = Self.parseBool(userInfo["isReactionPlural"])
        let reactionCount = intValue(in: userInfo, keys: ["reactionCount"])
        let momentId = firstString(in: userInfo, keys: ["momentId", "targetId"])
        let storyId = firstString(in: userInfo, keys: ["storyId"])
        let storyAuthorId = firstString(in: userInfo, keys: ["storyAuthorId", "storyOwnerId"])
        let echoId = firstString(in: userInfo, keys: ["echoId"])
        let chainId = firstString(in: userInfo, keys: ["chainId"])
        let chainTitle = firstString(in: userInfo, keys: ["chainTitle"])
        let chainPosition = intValue(in: userInfo, keys: ["chainPosition"])
        let totalParts = intValue(in: userInfo, keys: ["totalParts"])
        let chainRole = firstString(in: userInfo, keys: ["chainRole"])
        let mentionContext = firstString(in: userInfo, keys: ["mentionContext"])
        let targetAuthorId = firstString(in: userInfo, keys: ["targetAuthorId", "momentOwnerId"])
        let targetAuthorUsername = firstString(in: userInfo, keys: ["targetAuthorUsername"])
        let downloadURL = firstString(in: userInfo, keys: ["downloadURL"])
        let notificationId = firstString(in: userInfo, keys: ["notificationId", "gcm.message_id"])

        return Notification(
            id: notificationId ?? UUID().uuidString,
            type: notificationType,
            senderId: senderId.isEmpty ? "moments_system" : senderId,
            senderUsername: senderUsername,
            timestamp: Date(),
            isPending: true,
            title: nil,
            message: reactionEmojis,
            downloadURL: downloadURL,
            momentId: momentId,
            storyId: storyId,
            storyAuthorId: storyAuthorId,
            mentionContext: mentionContext,
            targetAuthorId: targetAuthorId,
            targetAuthorUsername: targetAuthorUsername,
            reaction: reactionEmoji,
            reactionCount: reactionCount,
            conversationId: conversationId,
            echoId: echoId,
            chainId: chainId,
            chainTitle: chainTitle,
            chainPosition: chainPosition,
            totalParts: totalParts,
            chainRole: chainRole,
            messageId: messageId,
            messageType: messageType,
            buzzEventId: buzzEventId,
            reminderVariant: reminderVariant,
            isReactionPlural: isReactionPlural
        )
    }

    private func mapPushType(_ rawType: String) -> NotificationType? {
        switch rawType {
        case "new_message": return .message
        case "message_reaction": return .messageReaction
        case "chat_buzz": return .chatBuzz
        case "gentle_reminder": return .gentleReminder
        case "moment_reaction": return .reaction
        case "moment_comment": return .comment
        case "story_reaction": return .storyReaction
        case "story_chain_continued": return .storyChainContinued
        case "new_follower": return .newFollower
        case "follow_request": return .followRequest
        case "request_accepted": return .requestAccepted
        case "photo_tag": return .photoTag
        case "media_moderation": return .mediaModeration
        case "echo_suggestion": return .echoSuggestion
        case "data_export_ready": return .dataExportReady
        case "mutual_connection": return .mutualConnection
        case "mention": return .mention
        default:
            return NotificationType(rawValue: rawType)
        }
    }

    // MARK: - Fallback helpers

    func presentMessageReactionFallback(
        conversationId: String,
        messageId: String,
        senderId: String,
        senderUsername: String,
        emoji: String,
        messageType: String?
    ) {
        let notification = Notification(
            id: UUID().uuidString,
            type: .messageReaction,
            senderId: senderId,
            senderUsername: senderUsername,
            timestamp: Date(),
            isPending: true,
            reaction: emoji,
            conversationId: conversationId,
            messageId: messageId,
            messageType: messageType
        )
        present(notification, source: .firestore)
    }

    func presentChatBuzzFallback(
        conversationId: String,
        buzzEventId: String,
        senderId: String,
        senderUsername: String
    ) {
        ChatNavigationIntentStore.enqueueBuzz(conversationId: conversationId, buzzEventId: buzzEventId)
        let notification = Notification(
            id: UUID().uuidString,
            type: .chatBuzz,
            senderId: senderId,
            senderUsername: senderUsername,
            timestamp: Date(),
            isPending: true,
            conversationId: conversationId,
            buzzEventId: buzzEventId
        )
        present(notification, source: .firestore)
    }

    func fetchSenderUsername(userId: String) async -> String {
        do {
            let snapshot = try await db.collection("users").document(userId).getDocument()
            return snapshot.data()?["username"] as? String ?? "User"
        } catch {
            return "User"
        }
    }

    func isMessageAuthoredByCurrentUser(conversationId: String, messageId: String) async -> Bool {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return false }
        do {
            let snapshot = try await db.collection("conversations")
                .document(conversationId)
                .collection("messages")
                .document(messageId)
                .getDocument()
            return snapshot.data()?["senderId"] as? String == currentUserId
        } catch {
            return false
        }
    }

    // MARK: - Parsing

    private func firstString(in userInfo: [AnyHashable: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = userInfo[key] as? String,
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return nil
    }

    private func intValue(in userInfo: [AnyHashable: Any], keys: [String]) -> Int? {
        for key in keys {
            if let value = userInfo[key] as? Int { return value }
            if let value = userInfo[key] as? String, let intValue = Int(value) { return intValue }
        }
        return nil
    }

    private static func parseBool(_ value: Any?) -> Bool {
        if let boolValue = value as? Bool { return boolValue }
        if let stringValue = value as? String {
            let normalized = stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return normalized == "true" || normalized == "1"
        }
        if let intValue = value as? Int { return intValue != 0 }
        return false
    }
}
