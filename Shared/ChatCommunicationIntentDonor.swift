import Foundation
import Intents
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

enum ChatCommunicationIntentDonor {
    static func makeIncomingIntent(
        conversationId: String,
        messageId: String,
        senderId: String,
        senderUsername: String,
        senderProfileImageURL: URL?,
        messagePreview: String?
    ) -> INSendMessageIntent {
        let senderImage = senderProfileImageURL.flatMap { INImage(url: $0) }

        let sender = INPerson(
            personHandle: INPersonHandle(value: senderId, type: .unknown),
            nameComponents: nil,
            displayName: senderUsername,
            image: senderImage,
            contactIdentifier: nil,
            customIdentifier: senderId
        )

        let intent = INSendMessageIntent(
            recipients: nil,
            outgoingMessageType: .outgoingMessageText,
            content: messagePreview,
            speakableGroupName: nil,
            conversationIdentifier: conversationId,
            serviceName: "Moments",
            sender: sender,
            attachments: nil
        )

        if let senderImage {
            intent.setImage(senderImage, forParameterNamed: \INSendMessageIntent.sender)
        }

        return intent
    }

    static func donateIncomingMessage(
        conversationId: String,
        messageId: String,
        senderId: String,
        senderUsername: String,
        senderProfileImageURL: URL?,
        messagePreview: String?
    ) {
        let intent = makeIncomingIntent(
            conversationId: conversationId,
            messageId: messageId,
            senderId: senderId,
            senderUsername: senderUsername,
            senderProfileImageURL: senderProfileImageURL,
            messagePreview: messagePreview
        )

        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = INInteractionDirection.incoming
        interaction.identifier = messageId
        interaction.donate { _ in }
    }

    /// Convierte la notificación en communication notification (avatar + reply long-press).
    @discardableResult
    static func applyCommunicationIntent(
        to content: UNMutableNotificationContent,
        conversationId: String,
        messageId: String,
        senderId: String,
        senderUsername: String,
        senderProfileImageURL: URL?,
        messagePreview: String?
    ) -> UNNotificationContent {
        let intent = makeIncomingIntent(
            conversationId: conversationId,
            messageId: messageId,
            senderId: senderId,
            senderUsername: senderUsername,
            senderProfileImageURL: senderProfileImageURL,
            messagePreview: messagePreview
        )

        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = INInteractionDirection.incoming
        interaction.identifier = messageId
        interaction.donate(completion: nil)

        // Garantizar la categoría de respuesta aunque la conversión a communication
        // notification falle (fallback devuelve `content`).
        content.categoryIdentifier = ChatNotificationReply.categoryIdentifier

        do {
            let updated = try content.updating(from: intent)
            guard let mutable = updated.mutableCopy() as? UNMutableNotificationContent else {
                return content
            }
            mutable.userInfo = content.userInfo
            if mutable.threadIdentifier.isEmpty {
                mutable.threadIdentifier = "conversation_\(conversationId)"
            }
            mutable.categoryIdentifier = ChatNotificationReply.categoryIdentifier
            return mutable
        } catch {
            return content
        }
    }
}
