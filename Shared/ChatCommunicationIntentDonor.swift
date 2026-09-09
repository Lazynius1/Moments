import Foundation
import Intents
import UIKit
import UserNotifications

/// Identificadores compartidos entre la app y la Notification Service Extension para
/// la respuesta rápida (quick reply) desde la notificación de mensaje.
enum ChatNotificationReply {
    /// Categoría aplicada a las notificaciones de mensaje de chat.
    static let categoryIdentifier = "MOMENTS_MESSAGE_REPLY"
    /// Acción de texto (campo de respuesta inline al hacer long-press).
    static let actionIdentifier = "MOMENTS_REPLY_ACTION"

    /// Categoría con el campo de respuesta inline. Se registra al lanzar la app.
    static func makeCategory() -> UNNotificationCategory {
        let replyAction = UNTextInputNotificationAction(
            identifier: actionIdentifier,
            title: NSLocalizedString("notification.action.reply", comment: "Reply"),
            options: [],
            textInputButtonTitle: NSLocalizedString("notification.action.send", comment: "Send"),
            textInputPlaceholder: NSLocalizedString("notification.action.placeholder", comment: "Message")
        )

        return UNNotificationCategory(
            identifier: categoryIdentifier,
            actions: [replyAction],
            intentIdentifiers: ["INSendMessageIntent"],
            options: []
        )
    }
}

/// Hilo APNs / Notification Center: por conversación (1:1 o grupo), nunca por remitente.
enum ChatNotificationThread {
    static func conversationId(from userInfo: [AnyHashable: Any]) -> String? {
        let type = (userInfo["type"] as? String)?.lowercased()
        if type == "group_message" {
            let group = (userInfo["conversationId"] as? String) ?? (userInfo["groupId"] as? String)
            return group?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? (userInfo["groupId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }
        return (userInfo["conversationId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    static func isChatMessagePush(_ type: String?) -> Bool {
        switch type?.lowercased() {
        case "message", "new_message", "group_message": return true
        default: return false
        }
    }

    static func isGroupPush(_ userInfo: [AnyHashable: Any]) -> Bool {
        let type = (userInfo["type"] as? String)?.lowercased()
        if type == "group_message" { return true }
        if let cid = conversationId(from: userInfo), isGroupConversationId(cid) { return true }
        return false
    }

    /// Misma regla que GroupChatScope.isGroup, usable desde la NSE sin dependencias de app.
    static func isGroupConversationId(_ id: String) -> Bool {
        guard id.hasPrefix("group-") else { return false }
        return UUID(uuidString: String(id.dropFirst(6))) != nil
    }

    /// Nombre visible del grupo para Communication Notifications.
    /// Sin esto iOS trata el aviso como 1:1 con el remitente.
    static func resolvedGroupName(
        from userInfo: [AnyHashable: Any],
        contentTitle: String? = nil,
        senderUsername: String? = nil
    ) -> String? {
        guard isGroupPush(userInfo) else { return nil }
        let sender = senderUsername?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
            ?? (userInfo["senderUsername"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty
        if let name = (userInfo["groupName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            return name
        }
        let candidates: [String?] = [
            userInfo["title"] as? String,
            contentTitle,
        ]
        for raw in candidates {
            guard let name = raw?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else { continue }
            if let sender, name.caseInsensitiveCompare(sender) == .orderedSame { continue }
            return name
        }
        return localized("notification.group.untitled")
    }

    static func previewLabel(messageType: String?) -> String {
        let key: String
        switch messageType {
        case "image": key = "chat.preview.photo"
        case "video": key = "chat.preview.video"
        case "audio": key = "chat.preview.audio"
        case "gif": key = "chat.preview.gif"
        case "sticker": key = "chat.preview.sticker"
        case "location": key = "chat.preview.location"
        case "file": key = "chat.preview.file"
        case "viewOnceImage": key = "chat.preview.viewOncePhoto"
        case "viewOnceVideo": key = "chat.preview.viewOnceVideo"
        case "ephemeral": key = "chat.preview.ephemeral"
        case "moment", "sharedMoment": key = "chat.preview.sharedMoment"
        case "sharedStory", "storyMention": key = "chat.preview.sharedStory"
        case "sharedProfile": key = "chat.preview.sharedProfile"
        default: key = "notification.chatSummary.single"
        }
        return localized(key)
    }

    static func localized(_ key: String) -> String {
        let main = Bundle.main
        let hostURL = main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        let bundle = main.bundleURL.pathExtension == "appex" ? (Bundle(url: hostURL) ?? main) : main
        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    static func threadIdentifier(conversationId: String) -> String {
        "conversation_\(conversationId)"
    }

    static func clearDelivered(conversationId: String) {
        let center = UNUserNotificationCenter.current()
        center.getDeliveredNotifications { delivered in
            let ids = delivered.filter {
                self.conversationId(from: $0.request.content.userInfo) == conversationId
            }.map { $0.request.identifier }
            center.removeDeliveredNotifications(withIdentifiers: ids)
        }
    }

    static func shouldRecycle(conversationId: String, userInfo: [AnyHashable: Any]) -> Bool {
        !ChatPreviewPrivacy.shouldRevealPreview(
            for: conversationId,
            isVanishModeMessage: ChatPreviewPrivacy.isVanishModeMessage(in: userInfo)
        )
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

enum ChatCommunicationIntentDonor {
    static func makeIncomingIntent(
        conversationId: String,
        messageId: String,
        senderId: String,
        senderUsername: String,
        senderImage: INImage?,
        messagePreview: String?,
        groupName: String?,
        groupImage: INImage?,
        recipientCount: Int = 1,
        otherRecipientId: String? = nil,
        mentionsCurrentUser: Bool = false
    ) -> INSendMessageIntent {
        let sender = INPerson(
            personHandle: INPersonHandle(value: senderId, type: .unknown),
            nameComponents: nil,
            displayName: senderUsername,
            image: senderImage,
            contactIdentifier: nil,
            customIdentifier: senderId,
            isMe: false,
            suggestionType: .none
        )

        let trimmedGroup = groupName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let speakableGroup = (trimmedGroup?.isEmpty == false)
            ? INSpeakableString(spokenPhrase: trimmedGroup!)
            : nil

        let intent = INSendMessageIntent(
            recipients: speakableGroup == nil ? nil : otherRecipientId.map { id in
                [INPerson(personHandle: INPersonHandle(value: id, type: .unknown), nameComponents: nil,
                          displayName: nil, image: nil, contactIdentifier: nil, customIdentifier: id)]
            },
            outgoingMessageType: .outgoingMessageText,
            content: messagePreview,
            speakableGroupName: speakableGroup,
            conversationIdentifier: conversationId,
            serviceName: nil,
            sender: sender,
            attachments: nil
        )

        if speakableGroup != nil {
            let metadata = INSendMessageIntentDonationMetadata()
            // Incoming intents implicitly include the current user. Count only other recipients.
            metadata.recipientCount = max(0, recipientCount)
            metadata.mentionsCurrentUser = mentionsCurrentUser
            intent.donationMetadata = metadata
        }

        if let senderImage {
            intent.setImage(senderImage, forParameterNamed: \INSendMessageIntent.sender)
        }
        if speakableGroup != nil {
            let image = groupImage ?? UIImage(systemName: "person.3.fill")?
                .withTintColor(.systemGray, renderingMode: .alwaysOriginal).pngData().map { INImage(imageData: $0) }
            if let image { intent.setImage(image, forParameterNamed: \INSendMessageIntent.speakableGroupName) }
        }

        return intent
    }

    static func donateIncomingMessage(
        conversationId: String,
        messageId: String,
        senderId: String,
        senderUsername: String,
        senderProfileImageURL: URL?,
        messagePreview: String?,
        groupName: String? = nil,
        recipientCount: Int = 1,
        otherRecipientId: String? = nil,
        mentionsCurrentUser: Bool = false
    ) {
        let senderImage = senderProfileImageURL.flatMap { INImage(url: $0) }
        let intent = makeIncomingIntent(
            conversationId: conversationId,
            messageId: messageId,
            senderId: senderId,
            senderUsername: senderUsername,
            senderImage: senderImage,
            messagePreview: messagePreview,
            groupName: groupName,
            groupImage: nil,
            recipientCount: recipientCount,
            otherRecipientId: otherRecipientId,
            mentionsCurrentUser: mentionsCurrentUser
        )

        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = INInteractionDirection.incoming
        interaction.identifier = messageId
        interaction.donate { _ in }
    }

    static func donateAndApplyCommunicationIntent(
        to content: UNMutableNotificationContent,
        conversationId: String,
        messageId: String,
        senderId: String,
        senderUsername: String,
        senderImage: INImage?,
        messagePreview: String?,
        groupName: String?,
        groupImage: INImage?,
        recipientCount: Int,
        otherRecipientId: String?,
        mentionsCurrentUser: Bool,
        completion: @escaping (UNNotificationContent) -> Void
    ) {
        let intent = makeIncomingIntent(
            conversationId: conversationId, messageId: messageId, senderId: senderId,
            senderUsername: senderUsername, senderImage: senderImage, messagePreview: messagePreview,
            groupName: groupName, groupImage: groupImage, recipientCount: recipientCount,
            otherRecipientId: otherRecipientId, mentionsCurrentUser: mentionsCurrentUser
        )
        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = .incoming
        interaction.identifier = messageId
        interaction.donate { _ in
            DispatchQueue.main.async {
                completion(applyCommunicationIntent(
                    to: content, conversationId: conversationId, messageId: messageId, senderId: senderId,
                    senderUsername: senderUsername, senderImage: senderImage, messagePreview: messagePreview,
                    groupName: groupName, groupImage: groupImage, recipientCount: recipientCount,
                    otherRecipientId: otherRecipientId, mentionsCurrentUser: mentionsCurrentUser
                ))
            }
        }
    }

    /// Convierte la notificación en communication notification (avatar + reply).
    @discardableResult
    static func applyCommunicationIntent(
        to content: UNMutableNotificationContent,
        conversationId: String,
        messageId: String,
        senderId: String,
        senderUsername: String,
        senderImage: INImage?,
        messagePreview: String?,
        groupName: String?,
        groupImage: INImage?,
        recipientCount: Int = 1,
        otherRecipientId: String? = nil,
        mentionsCurrentUser: Bool = false
    ) -> UNNotificationContent {
        let intent = makeIncomingIntent(
            conversationId: conversationId,
            messageId: messageId,
            senderId: senderId,
            senderUsername: senderUsername,
            senderImage: senderImage,
            messagePreview: messagePreview,
            groupName: groupName,
            groupImage: groupImage,
            recipientCount: recipientCount,
            otherRecipientId: otherRecipientId,
            mentionsCurrentUser: mentionsCurrentUser
        )

        content.categoryIdentifier = ChatNotificationReply.categoryIdentifier
        let thread = ChatNotificationThread.threadIdentifier(conversationId: conversationId)
        content.threadIdentifier = thread

        if let groupName, !groupName.isEmpty {
            content.title = groupName
            content.subtitle = senderUsername
        }
        do {
            let updated = try content.updating(from: intent)
            guard let mutable = updated.mutableCopy() as? UNMutableNotificationContent else {
                return content
            }
            mutable.userInfo = content.userInfo
            mutable.threadIdentifier = thread
            mutable.categoryIdentifier = ChatNotificationReply.categoryIdentifier
            // Communication Notifications: sin título de grupo el sistema pinta 1:1.
            if let groupName = groupName?.trimmingCharacters(in: .whitespacesAndNewlines), !groupName.isEmpty {
                mutable.title = groupName
                if !senderUsername.isEmpty {
                    mutable.subtitle = senderUsername
                }
            }
            return mutable
        } catch {
            return content
        }
    }
}
