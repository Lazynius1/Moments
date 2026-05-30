import Foundation
import FirebaseFirestore

extension ChatService {
    func createBasicMessageData(from message: EnhancedMessage) -> [String: Any] {
        var data: [String: Any] = [
            "id": message.id,
            "conversationId": message.conversationId,
            "senderId": message.senderId,
            "type": message.type.rawValue,
            "timestamp": FieldValue.serverTimestamp(),
            "status": MessageStatus.sent.rawValue,
            "isRead": message.isRead,
            "isDeleted": message.isDeleted,
            "isViewed": message.isViewed
        ]

        if let mediaObjectPath = message.mediaObjectPath {
            data["mediaObjectPath"] = mediaObjectPath
        } else if let mediaUrl = message.mediaUrl {
            data["mediaUrl"] = mediaUrl
        }
        if let thumbnailObjectPath = message.thumbnailObjectPath {
            data["thumbnailObjectPath"] = thumbnailObjectPath
        } else if let thumbnailUrl = message.thumbnailUrl {
            data["thumbnailUrl"] = thumbnailUrl
        }
        if let mediaEncryption = message.mediaEncryption {
            data["mediaEncryption"] = mediaEncryption.firestoreData
        }
        if let thumbnailEncryption = message.thumbnailEncryption {
            data["thumbnailEncryption"] = thumbnailEncryption.firestoreData
        }
        if let fileSize = message.fileSize {
            data["fileSize"] = fileSize
        }

        return data
    }

    func buildEnhancedMessage(
        from data: [String: Any],
        docId: String,
        conversationId: String,
        decryptedContentOverride: String? = nil
    ) async -> EnhancedMessage {
        let id = data["id"] as? String ?? docId
        let senderId = data["senderId"] as? String ?? ""
        let typeString = data["type"] as? String ?? MessageType.text.rawValue
        let type = MessageType(rawValue: typeString) ?? .text

        let rawContent = data["content"] as? String
        let content: String?
        if let decryptedContentOverride {
            content = decryptedContentOverride
        } else if let rawContent {
            content = await decryptMessageContent(rawContent, for: conversationId)
        } else {
            content = rawContent
        }

        let mediaObjectPath = data["mediaObjectPath"] as? String
        let thumbnailObjectPath = data["thumbnailObjectPath"] as? String
        let mediaEncryption = (data["mediaEncryption"] as? [String: Any]).flatMap { EncryptedChatMediaMetadata(map: $0) }
        let thumbnailEncryption = (data["thumbnailEncryption"] as? [String: Any]).flatMap { EncryptedChatMediaMetadata(map: $0) }

        let resolvedMedia: CachedResolvedMedia
        if let mediaObjectPath, !mediaObjectPath.isEmpty, let mediaEncryption {
            resolvedMedia = await resolveEncryptedMediaForDisplay(
                messageId: id,
                conversationId: conversationId,
                mediaObjectPath: mediaObjectPath,
                mediaEncryption: mediaEncryption,
                thumbnailObjectPath: thumbnailObjectPath,
                thumbnailEncryption: thumbnailEncryption
            )
        } else {
            resolvedMedia = CachedResolvedMedia(
                mediaUrl: data["mediaUrl"] as? String,
                thumbnailUrl: data["thumbnailUrl"] as? String
            )
        }

        return EnhancedMessage(
            id: id,
            conversationId: conversationId,
            senderId: senderId,
            type: type,
            content: content,
            mediaUrl: resolvedMedia.mediaUrl,
            thumbnailUrl: resolvedMedia.thumbnailUrl,
            mediaObjectPath: mediaObjectPath,
            thumbnailObjectPath: thumbnailObjectPath,
            mediaEncryption: mediaEncryption,
            thumbnailEncryption: thumbnailEncryption,
            duration: data["duration"] as? Double,
            fileName: data["fileName"] as? String,
            fileSize: data["fileSize"] as? Int64,
            latitude: data["latitude"] as? Double,
            longitude: data["longitude"] as? Double,
            timestamp: (data["timestamp"] as? Timestamp)?.dateValue() ?? Date(),
            status: MessageStatus(rawValue: data["status"] as? String ?? MessageStatus.sent.rawValue) ?? .sent,
            isRead: data["isRead"] as? Bool ?? false,
            isDeleted: data["isDeleted"] as? Bool ?? false,
            deletedAt: (data["deletedAt"] as? Timestamp)?.dateValue(),
            editedAt: (data["editedAt"] as? Timestamp)?.dateValue(),
            reactions: data["reactions"] as? [String: [String]],
            replyTo: data["replyTo"] as? String,
            expirationDate: (data["expirationDate"] as? Timestamp)?.dateValue(),
            isViewed: data["isViewed"] as? Bool ?? false,
            storyReplyData: data["storyReplyData"] as? [String: String],
            sharedMomentData: data["sharedMomentData"] as? [String: String],
            sharedStoryData: data["sharedStoryData"] as? [String: String],
            mediaBatchId: data["mediaBatchId"] as? String,
            viewedBy: data["viewedBy"] as? [String]
        )
    }

    func resolveEncryptedMediaForMessage(_ message: EnhancedMessage) async -> (mediaUrl: String?, thumbnailUrl: String?)? {
        await encryptedMediaResolver.resolveForMessage(message)
    }

    func resolveEncryptedMediaForDisplay(
        messageId: String,
        conversationId: String,
        mediaObjectPath: String,
        mediaEncryption: EncryptedChatMediaMetadata,
        thumbnailObjectPath: String?,
        thumbnailEncryption: EncryptedChatMediaMetadata?
    ) async -> CachedResolvedMedia {
        await encryptedMediaResolver.resolveForDisplay(
            messageId: messageId,
            conversationId: conversationId,
            mediaObjectPath: mediaObjectPath,
            mediaEncryption: mediaEncryption,
            thumbnailObjectPath: thumbnailObjectPath,
            thumbnailEncryption: thumbnailEncryption
        )
    }
}
