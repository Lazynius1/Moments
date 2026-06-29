import Foundation
import Intents
import UserNotifications

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

        do {
            let updated = try content.updating(from: intent)
            guard let mutable = updated.mutableCopy() as? UNMutableNotificationContent else {
                return content
            }
            mutable.userInfo = content.userInfo
            if mutable.threadIdentifier.isEmpty {
                mutable.threadIdentifier = "conversation_\(conversationId)"
            }
            return mutable
        } catch {
            return content
        }
    }
}
