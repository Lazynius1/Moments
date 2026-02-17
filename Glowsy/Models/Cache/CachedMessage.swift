import Foundation
import SwiftData

@Model
final class CachedMessage {
    @Attribute(.unique) var id: String
    var conversationId: String
    var senderId: String
    var typeString: String // Raw value of MessageType
    var content: String?
    var mediaUrl: String?
    var thumbnailUrl: String?
    var duration: Double?
    var fileName: String?
    var fileSize: Int64?
    var latitude: Double?
    var longitude: Double?
    var timestamp: Date
    var statusString: String // Raw value of MessageStatus
    var isRead: Bool
    var isDeleted: Bool
    var deletedAt: Date?
    var editedAt: Date?
    var reactionsData: Data? // [String: [String]] encoded
    var replyTo: String?
    var expirationDate: Date?
    var isViewed: Bool
    var storyReplyDataEncoded: Data? // [String: String] encoded
    var sharedMomentDataEncoded: Data? // [String: String] encoded
    var viewedBy: [String]?
    var lastSyncedAt: Date

    init(id: String,
         conversationId: String,
         senderId: String,
         typeString: String,
         content: String?,
         mediaUrl: String?,
         thumbnailUrl: String?,
         duration: Double?,
         fileName: String?,
         fileSize: Int64?,
         latitude: Double?,
         longitude: Double?,
         timestamp: Date,
         statusString: String,
         isRead: Bool,
         isDeleted: Bool,
         deletedAt: Date?,
         editedAt: Date?,
         reactionsData: Data?,
         replyTo: String?,
         expirationDate: Date?,
         isViewed: Bool,
         storyReplyDataEncoded: Data?,
         sharedMomentDataEncoded: Data?,
         viewedBy: [String]?,
         lastSyncedAt: Date = Date()) {
        self.id = id
        self.conversationId = conversationId
        self.senderId = senderId
        self.typeString = typeString
        self.content = content
        self.mediaUrl = mediaUrl
        self.thumbnailUrl = thumbnailUrl
        self.duration = duration
        self.fileName = fileName
        self.fileSize = fileSize
        self.latitude = latitude
        self.longitude = longitude
        self.timestamp = timestamp
        self.statusString = statusString
        self.isRead = isRead
        self.isDeleted = isDeleted
        self.deletedAt = deletedAt
        self.editedAt = editedAt
        self.reactionsData = reactionsData
        self.replyTo = replyTo
        self.expirationDate = expirationDate
        self.isViewed = isViewed
        self.storyReplyDataEncoded = storyReplyDataEncoded
        self.sharedMomentDataEncoded = sharedMomentDataEncoded
        self.viewedBy = viewedBy
        self.lastSyncedAt = lastSyncedAt
    }
}

extension CachedMessage {
    static func from(_ message: EnhancedMessage) -> CachedMessage {
        let encoder = JSONEncoder()
        let reactionsData = try? encoder.encode(message.reactions)
        let storyReplyDataEncoded = try? encoder.encode(message.storyReplyData)
        let sharedMomentDataEncoded = try? encoder.encode(message.sharedMomentData)
        
        return CachedMessage(
            id: message.id,
            conversationId: message.conversationId,
            senderId: message.senderId,
            typeString: message.type.rawValue,
            content: message.content,
            mediaUrl: message.mediaUrl,
            thumbnailUrl: message.thumbnailUrl,
            duration: message.duration,
            fileName: message.fileName,
            fileSize: message.fileSize,
            latitude: message.latitude,
            longitude: message.longitude,
            timestamp: message.timestamp,
            statusString: message.status.rawValue,
            isRead: message.isRead,
            isDeleted: message.isDeleted,
            deletedAt: message.deletedAt,
            editedAt: message.editedAt,
            reactionsData: reactionsData,
            replyTo: message.replyTo,
            expirationDate: message.expirationDate,
            isViewed: message.isViewed,
            storyReplyDataEncoded: storyReplyDataEncoded,
            sharedMomentDataEncoded: sharedMomentDataEncoded,
            viewedBy: message.viewedBy,
            lastSyncedAt: Date()
        )
    }
    
    func toEnhancedMessage() -> EnhancedMessage {
        let decoder = JSONDecoder()
        
        let type = MessageType(rawValue: typeString) ?? .text
        let status = MessageStatus(rawValue: statusString) ?? .sent
        
        let reactions: [String: [String]]? = {
            guard let data = reactionsData else { return nil }
            return try? decoder.decode([String: [String]].self, from: data)
        }()
        
        let storyReplyData: [String: String]? = {
            guard let data = storyReplyDataEncoded else { return nil }
            return try? decoder.decode([String: String].self, from: data)
        }()
        
        let sharedMomentData: [String: String]? = {
            guard let data = sharedMomentDataEncoded else { return nil }
            return try? decoder.decode([String: String].self, from: data)
        }()
        
        return EnhancedMessage(
            id: id,
            conversationId: conversationId,
            senderId: senderId,
            type: type,
            content: content,
            mediaUrl: mediaUrl,
            thumbnailUrl: thumbnailUrl,
            duration: duration,
            fileName: fileName,
            fileSize: fileSize,
            latitude: latitude,
            longitude: longitude,
            timestamp: timestamp,
            status: status,
            isRead: isRead,
            isDeleted: isDeleted,
            deletedAt: deletedAt,
            editedAt: editedAt,
            reactions: reactions,
            replyTo: replyTo,
            expirationDate: expirationDate,
            isViewed: isViewed,
            storyReplyData: storyReplyData,
            sharedMomentData: sharedMomentData,
            viewedBy: viewedBy
        )
    }
}
