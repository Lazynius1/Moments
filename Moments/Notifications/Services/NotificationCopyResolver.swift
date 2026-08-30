import Foundation

struct NotificationBannerCopy {
    let title: String
    let body: String?
    let preview: String?
}

enum NotificationCopyResolver {
    static func resolve(_ notification: Notification) -> NotificationBannerCopy {
        if notification.senderId == "system_time_limit" {
            return NotificationBannerCopy(
                title: notification.senderUsername,
                body: notification.reaction,
                preview: nil
            )
        }

        if notification.type == .mediaModeration {
            return NotificationBannerCopy(
                title: notification.title ?? notification.senderUsername,
                body: notification.message ?? notification.reaction,
                preview: nil
            )
        }

        switch notification.type {
        case .message:
            return messageCopy(for: notification)
        case .messageReaction:
            return messageReactionCopy(for: notification)
        case .chatBuzz:
            return NotificationBannerCopy(
                title: notification.senderUsername,
                body: NSLocalizedString("notification.chatBuzz.single", comment: ""),
                preview: nil
            )
        case .gentleReminder:
            return gentleReminderCopy(for: notification)
        case .reaction:
            return momentReactionCopy(for: notification)
        case .storyReaction:
            return storyReactionCopy(for: notification)
        case .comment:
            return commentCopy(for: notification)
        case .newFollower:
            return followerCopy(for: notification, accepted: false)
        case .requestAccepted:
            return followerCopy(for: notification, accepted: true)
        case .followRequest:
            return followRequestCopy(for: notification)
        case .mention:
            return mentionCopy(for: notification)
        case .photoTag:
            return photoTagCopy(for: notification)
        case .storyChainContinued:
            return storyChainCopy(for: notification)
        case .mutualConnection:
            return mutualConnectionCopy(for: notification)
        case .dataExportReady:
            return NotificationBannerCopy(
                title: NSLocalizedString("notification.gentleReminder.title", comment: "Moments"),
                body: NSLocalizedString("notifications.message.dataExportReady", value: "Your data export is ready to download", comment: ""),
                preview: nil
            )
        case .echoSuggestion:
            return NotificationBannerCopy(
                title: notification.senderUsername,
                body: NSLocalizedString("banner.verb.echoSuggestion", value: "is near you! Create an Echo", comment: ""),
                preview: nil
            )
        default:
            return NotificationBannerCopy(
                title: notification.senderUsername,
                body: notification.message ?? notification.reaction,
                preview: nil
            )
        }
    }

    // MARK: - Chat

    private static func messageCopy(for notification: Notification) -> NotificationBannerCopy {
        let unreadCount = notification.reactionCount ?? 0
        let isPlural = unreadCount > 1

        if isPlural {
            return NotificationBannerCopy(
                title: notification.senderUsername,
                body: String(
                    format: NSLocalizedString("notification.message.multiple", comment: ""),
                    String(unreadCount)
                ),
                preview: nil
            )
        }

        if let decrypted = sanitizedPreviewLine(for: notification.reaction, messageType: notification.messageType) {
            return NotificationBannerCopy(
                title: notification.senderUsername,
                body: decrypted,
                preview: nil
            )
        }

        return NotificationBannerCopy(
            title: notification.senderUsername,
            body: NSLocalizedString(messageLocKey(for: notification.messageType), comment: ""),
            preview: nil
        )
    }

    private static func messageLocKey(for messageType: String?) -> String {
        switch messageType {
        case "text": return "notification.message.single.text"
        case "image": return "notification.message.single.photo"
        case "video": return "notification.message.single.video"
        case "audio": return "notification.message.single.audio"
        case "viewOnceImage", "viewOnceVideo", "ephemeral": return "notification.message.single.viewOnce"
        case "moment", "sharedMoment": return "notification.message.single.moment"
        case "storyMention": return "notification.message.single.storyMention"
        default: return "notification.message.single.default"
        }
    }

    private static func sanitizedPreviewLine(for preview: String?, messageType: String?) -> String? {
        guard let preview, !preview.isEmpty else { return nil }
        if let messageType, let type = MessageType(rawValue: messageType), type.isViewOnce {
            return nil
        }
        if neutralPreviewPrefixes.contains(where: { preview.hasPrefix($0) }) {
            return nil
        }
        if preview == MessageType.text.conversationPreview {
            return nil
        }
        if looksLikeEncryptedPayload(preview) {
            return nil
        }
        return ChatTextMarkup.plainText(from: preview, hidesSpoilers: true)
    }

    private static func looksLikeEncryptedPayload(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 24 else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "+/=_-"))
        return trimmed.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private static let neutralPreviewPrefixes = ["💬", "📷", "🎥", "🎵", "🎞", "😊", "📍", "📎", "📸", "⏱"]

    private static func messageReactionCopy(for notification: Notification) -> NotificationBannerCopy {
        let emoji = notification.reaction ?? "❤️"
        let emojiList = notification.message ?? emoji
        let isPlural = notification.isReactionPlural == true || (notification.reactionCount ?? 0) > 1
        let quotedPreview = notification.title.map {
            ChatTextMarkup.plainText(from: $0, hidesSpoilers: true)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let body: String
        if isPlural {
            body = String(format: NSLocalizedString("notification.chatReaction.multiple", comment: ""), emojiList)
        } else if let quotedPreview, !quotedPreview.isEmpty {
            body = String(
                format: NSLocalizedString("notification.chatReaction.singleQuoted", comment: ""),
                emoji,
                quotedPreview
            )
        } else {
            body = String(format: NSLocalizedString("notification.chatReaction.single", comment: ""), emoji)
        }

        return NotificationBannerCopy(title: notification.senderUsername, body: body, preview: nil)
    }

    private static func gentleReminderCopy(for notification: Notification) -> NotificationBannerCopy {
        let variant = notification.reminderVariant ?? "neutral_day"
        let bodyKey = "notification.gentleReminder.body.\(variant)"
        let body = NSLocalizedString(bodyKey, comment: "")
        return NotificationBannerCopy(
            title: NSLocalizedString("notification.gentleReminder.title", comment: ""),
            body: body,
            preview: nil
        )
    }

    // MARK: - Social

    private static func momentReactionCopy(for notification: Notification) -> NotificationBannerCopy {
        let username = notification.senderUsername
        let reactionEmoji = reactionDisplayEmoji(for: notification.reaction)
        let count = notification.reactionCount ?? 1
        let isPlural = count > 1

        if isPlural {
            return NotificationBannerCopy(
                title: username,
                body: String(
                    format: NSLocalizedString("notification.momentReaction.multiple.title", comment: ""),
                    username,
                    String(count - 1)
                ),
                preview: nil
            )
        }

        return NotificationBannerCopy(
            title: username,
            body: String(
                format: NSLocalizedString("notification.momentReaction.single.title", comment: ""),
                username,
                reactionEmoji
            ),
            preview: nil
        )
    }

    private static func storyReactionCopy(for notification: Notification) -> NotificationBannerCopy {
        let username = notification.senderUsername
        let reactionEmoji = reactionDisplayEmoji(for: notification.reaction)
        let count = notification.reactionCount ?? 1
        let isPlural = count > 1

        if isPlural {
            return NotificationBannerCopy(
                title: username,
                body: String(
                    format: NSLocalizedString("notification.storyReaction.multiple.title", comment: ""),
                    username,
                    String(count - 1)
                ),
                preview: nil
            )
        }

        return NotificationBannerCopy(
            title: username,
            body: String(
                format: NSLocalizedString("notification.storyReaction.single.title", comment: ""),
                username,
                reactionEmoji
            ),
            preview: nil
        )
    }

    private static func commentCopy(for notification: Notification) -> NotificationBannerCopy {
        let username = notification.senderUsername
        let count = notification.reactionCount ?? 1
        if count > 1 {
            return NotificationBannerCopy(
                title: username,
                body: String(
                    format: NSLocalizedString("notification.comment.multiple.title", comment: ""),
                    username,
                    String(count - 1)
                ),
                preview: nil
            )
        }

        if let commentText = notification.reaction?.trimmingCharacters(in: .whitespacesAndNewlines), !commentText.isEmpty {
            return NotificationBannerCopy(title: username, body: commentText, preview: nil)
        }

        return NotificationBannerCopy(
            title: username,
            body: String(format: NSLocalizedString("notification.comment.single.title", comment: ""), username),
            preview: nil
        )
    }

    private static func followerCopy(for notification: Notification, accepted: Bool) -> NotificationBannerCopy {
        let username = notification.senderUsername
        let count = notification.reactionCount ?? 1
        if count > 1 {
            return NotificationBannerCopy(
                title: String(
                    format: NSLocalizedString("notification.follower.multiple.title", comment: ""),
                    username,
                    String(count - 1)
                ),
                body: String(
                    format: NSLocalizedString("notification.follower.multiple.body", comment: ""),
                    String(count)
                ),
                preview: nil
            )
        }

        if accepted {
            return NotificationBannerCopy(
                title: String(format: NSLocalizedString("notification.follower.acceptedRequest.single.title", comment: ""), username),
                body: NSLocalizedString("notification.follower.acceptedRequest.single.body", comment: ""),
                preview: nil
            )
        }

        return NotificationBannerCopy(
            title: String(format: NSLocalizedString("notification.follower.single.title", comment: ""), username),
            body: NSLocalizedString("notification.follower.single.body", comment: ""),
            preview: nil
        )
    }

    private static func followRequestCopy(for notification: Notification) -> NotificationBannerCopy {
        let username = notification.senderUsername
        let count = notification.reactionCount ?? 1
        if count > 1 {
            return NotificationBannerCopy(
                title: String(
                    format: NSLocalizedString("notification.followRequest.multiple.title", comment: ""),
                    username,
                    String(count - 1)
                ),
                body: String(
                    format: NSLocalizedString("notification.followRequest.multiple.body", comment: ""),
                    String(count)
                ),
                preview: nil
            )
        }

        return NotificationBannerCopy(
            title: String(format: NSLocalizedString("notification.followRequest.single.title", comment: ""), username),
            body: NSLocalizedString("notification.followRequest.single.body", comment: ""),
            preview: nil
        )
    }

    private static func mentionCopy(for notification: Notification) -> NotificationBannerCopy {
        let username = notification.senderUsername
        let contentTypeKey: String
        switch notification.mentionContext ?? (notification.storyId != nil ? "story" : "moment") {
        case "story":
            contentTypeKey = "notification.mention.contentType.story"
        case "comment":
            contentTypeKey = "notification.mention.contentType.moment"
        default:
            contentTypeKey = "notification.mention.contentType.moment"
        }
        let contentType = NSLocalizedString(contentTypeKey, comment: "")
        return NotificationBannerCopy(
            title: String(format: NSLocalizedString("notification.mention.title", comment: ""), username, contentType),
            body: NSLocalizedString("notification.mention.body", comment: ""),
            preview: nil
        )
    }

    private static func photoTagCopy(for notification: Notification) -> NotificationBannerCopy {
        let username = notification.senderUsername
        if let title = notification.reaction?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return NotificationBannerCopy(
                title: String(format: NSLocalizedString("notification.photoTag.withTitle.title", comment: ""), username, title),
                body: NSLocalizedString("notification.photoTag.body", comment: ""),
                preview: nil
            )
        }
        return NotificationBannerCopy(
            title: String(format: NSLocalizedString("notification.photoTag.title", comment: ""), username),
            body: NSLocalizedString("notification.photoTag.body", comment: ""),
            preview: nil
        )
    }

    private static func storyChainCopy(for notification: Notification) -> NotificationBannerCopy {
        if notification.chainRole == "creator" {
            let chainTitle = notification.chainTitle ?? NSLocalizedString("storyChains.chain", comment: "Chain")
            let totalParts = notification.totalParts.map(String.init) ?? "?"
            return NotificationBannerCopy(
                title: String(format: NSLocalizedString("notification.storyChain.creator.title", comment: ""), notification.senderUsername),
                body: String(format: NSLocalizedString("notification.storyChain.creator.body", comment: ""), chainTitle, totalParts),
                preview: nil
            )
        }

        let chainTitle = notification.chainTitle ?? NSLocalizedString("storyChains.chain", comment: "Chain")
        let totalParts = notification.totalParts.map(String.init) ?? "?"
        return NotificationBannerCopy(
            title: String(format: NSLocalizedString("notification.storyChain.participant.title", comment: ""), chainTitle),
            body: String(format: NSLocalizedString("notification.storyChain.participant.body", comment: ""), notification.senderUsername, totalParts),
            preview: nil
        )
    }

    private static func mutualConnectionCopy(for notification: Notification) -> NotificationBannerCopy {
        let username = notification.senderUsername
        let count = notification.reactionCount ?? 1
        if count > 1 {
            return NotificationBannerCopy(
                title: NSLocalizedString("notification.mutualConnection.multiple.title", comment: ""),
                body: String(
                    format: NSLocalizedString("notification.mutualConnection.multiple.body", comment: ""),
                    username,
                    String(count - 1)
                ),
                preview: nil
            )
        }

        return NotificationBannerCopy(
            title: NSLocalizedString("notification.mutualConnection.title", comment: ""),
            body: String(format: NSLocalizedString("notification.mutualConnection.body", comment: ""), username),
            preview: nil
        )
    }

    private static func reactionDisplayEmoji(for raw: String?) -> String {
        guard let raw else { return "✨" }
        if let type = ReactionType(rawValue: raw) {
            return type.icon
        }
        return raw
    }
}
