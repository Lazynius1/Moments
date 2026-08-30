import Foundation

enum ChatCommunicationNotificationService {
    static func donateFromPush(userInfo: [AnyHashable: Any], previewBody: String?) {
        let type = (userInfo["type"] as? String)?.lowercased()
        guard type == "message" || type == "new_message" else { return }
        guard let conversationId = userInfo["conversationId"] as? String,
              let messageId = userInfo["messageId"] as? String,
              let senderId = userInfo["senderId"] as? String else { return }

        let senderUsername = (userInfo["senderUsername"] as? String) ?? "Moments"
        let avatarURL = (userInfo["senderProfileImage"] as? String).flatMap { URL(string: $0) }
        let preview = previewBody.map {
            ChatTextMarkup.plainText(from: $0, hidesSpoilers: true)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        ChatCommunicationIntentDonor.donateIncomingMessage(
            conversationId: conversationId,
            messageId: messageId,
            senderId: senderId,
            senderUsername: senderUsername,
            senderProfileImageURL: avatarURL,
            messagePreview: preview?.isEmpty == false ? preview : nil
        )
    }
}
