import Foundation
import FirebaseFirestore

@MainActor
enum InAppNotificationPreviewResolver {
    static func resolve(_ notification: Notification, userInfo: [AnyHashable: Any]?) async -> Notification {
        guard let conversationId = notification.conversationId, !conversationId.isEmpty else {
            return stripUnsafeTextPreview(from: notification)
        }

        let previewEnabled = UserDefaults(suiteName: "group.com.glowsyapp")?
            .object(forKey: "chat_show_message_preview_\(conversationId)") as? Bool ?? true

        switch notification.type {
        case .message:
            return await resolveMessagePreview(
                notification,
                conversationId: conversationId,
                userInfo: userInfo,
                previewEnabled: previewEnabled
            )
        case .messageReaction:
            return await resolveMessageReactionPreview(
                notification,
                conversationId: conversationId,
                userInfo: userInfo,
                previewEnabled: previewEnabled
            )
        default:
            return stripUnsafeTextPreview(from: notification)
        }
    }

    private static func resolveMessagePreview(
        _ notification: Notification,
        conversationId: String,
        userInfo: [AnyHashable: Any]?,
        previewEnabled: Bool
    ) async -> Notification {
        guard previewEnabled else {
            return notification.withBannerPreview(reaction: nil, title: notification.title)
        }

        guard notification.messageType == nil || notification.messageType == "text" else {
            return notification.withBannerPreview(reaction: nil, title: notification.title)
        }

        if let embedded = userInfo?["encryptedContent"] as? String,
           let decrypted = await decryptPreview(embedded, conversationId: conversationId) {
            return notification.withBannerPreview(reaction: truncated(decrypted, maxLength: 200), title: notification.title)
        }

        if let messageId = notification.messageId,
           let decrypted = await fetchAndDecryptMessage(messageId: messageId, conversationId: conversationId) {
            return notification.withBannerPreview(reaction: truncated(decrypted, maxLength: 200), title: notification.title)
        }

        if let reaction = notification.reaction,
           !reaction.isEmpty,
           !isNeutralPlaceholder(reaction),
           let decrypted = await decryptPreview(reaction, conversationId: conversationId) {
            return notification.withBannerPreview(reaction: truncated(decrypted, maxLength: 200), title: notification.title)
        }

        return notification.withBannerPreview(reaction: nil, title: notification.title)
    }

    private static func resolveMessageReactionPreview(
        _ notification: Notification,
        conversationId: String,
        userInfo: [AnyHashable: Any]?,
        previewEnabled: Bool
    ) async -> Notification {
        guard previewEnabled,
              notification.isReactionPlural != true,
              notification.messageType == nil || notification.messageType == "text" else {
            return notification.withBannerPreview(reaction: notification.reaction, title: nil)
        }

        if let embedded = userInfo?["encryptedContent"] as? String,
           let decrypted = await decryptPreview(embedded, conversationId: conversationId) {
            return notification.withBannerPreview(reaction: notification.reaction, title: truncated(decrypted, maxLength: 120))
        }

        if let messageId = notification.messageId,
           let decrypted = await fetchAndDecryptMessage(messageId: messageId, conversationId: conversationId) {
            return notification.withBannerPreview(reaction: notification.reaction, title: truncated(decrypted, maxLength: 120))
        }

        if let title = notification.title,
           !title.isEmpty,
           let decrypted = await decryptPreview(title, conversationId: conversationId) {
            return notification.withBannerPreview(reaction: notification.reaction, title: truncated(decrypted, maxLength: 120))
        }

        return notification.withBannerPreview(reaction: notification.reaction, title: nil)
    }

    private static func fetchAndDecryptMessage(messageId: String, conversationId: String) async -> String? {
        do {
            let snapshot = try await Firestore.firestore()
                .collection("conversations")
                .document(conversationId)
                .collection("messages")
                .document(messageId)
                .getDocument()

            guard let cipher = snapshot.data()?["content"] as? String, !cipher.isEmpty else {
                return nil
            }
            return await decryptPreview(cipher, conversationId: conversationId)
        } catch {
            return nil
        }
    }

    private static func decryptPreview(_ content: String, conversationId: String) async -> String? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if isNeutralPlaceholder(trimmed) {
            return nil
        }

        guard let decrypted = await EncryptionService.shared.decryptChatMessage(trimmed, for: conversationId) else {
            return nil
        }

        let cleaned = decrypted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned != trimmed else { return nil }
        return cleaned
    }

    private static func stripUnsafeTextPreview(from notification: Notification) -> Notification {
        switch notification.type {
        case .message:
            guard let reaction = notification.reaction,
                  !reaction.isEmpty,
                  !isNeutralPlaceholder(reaction),
                  !looksLikeEncryptedPayload(reaction) else {
                return notification
            }
            return notification.withBannerPreview(reaction: nil, title: notification.title)
        case .messageReaction:
            guard let title = notification.title,
                  !title.isEmpty,
                  looksLikeEncryptedPayload(title) else {
                return notification
            }
            return notification.withBannerPreview(reaction: notification.reaction, title: nil)
        default:
            return notification
        }
    }

    private static func isNeutralPlaceholder(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }

        let neutralPrefixes = ["💬", "📷", "🎥", "🎵", "🎞", "😊", "📍", "📎", "📸", "⏱"]
        if neutralPrefixes.contains(where: { trimmed.hasPrefix($0) }) {
            return true
        }

        return trimmed == MessageType.text.conversationPreview
    }

    private static func looksLikeEncryptedPayload(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 24 else { return false }

        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "+/=_-"))
        return trimmed.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private static func truncated(_ text: String, maxLength: Int) -> String {
        guard text.count > maxLength else { return text }
        return String(text.prefix(maxLength - 1)) + "…"
    }
}

private extension Notification {
    func withBannerPreview(reaction: String?, title: String?) -> Notification {
        Notification(
            id: id,
            type: type,
            senderId: senderId,
            senderUsername: senderUsername,
            timestamp: timestamp,
            isPending: isPending,
            title: title,
            message: message,
            downloadURL: downloadURL,
            momentId: momentId,
            visitCount: visitCount,
            storyId: storyId,
            storyAuthorId: storyAuthorId,
            storyPreviewUrl: storyPreviewUrl,
            mentionContext: mentionContext,
            targetAuthorId: targetAuthorId,
            targetAuthorUsername: targetAuthorUsername,
            reaction: reaction,
            reactionCount: reactionCount,
            commentId: commentId,
            conversationId: conversationId,
            echoId: echoId,
            moderationScope: moderationScope,
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
}
