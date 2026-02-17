import Foundation
import SwiftData

@Model
final class CachedNotification {
    @Attribute(.unique) var id: String
    var type: String
    var senderId: String
    var senderUsername: String
    var timestamp: Date
    var isPending: Bool
    var momentId: String?
    var visitCount: Int?
    var storyId: String?
    var storyAuthorId: String?
    var reaction: String?
    var commentId: String?
    var echoId: String?
    var lastSyncedAt: Date
    
    init(id: String, type: String, senderId: String, senderUsername: String, timestamp: Date, isPending: Bool, momentId: String? = nil, visitCount: Int? = nil, storyId: String? = nil, storyAuthorId: String? = nil, reaction: String? = nil, commentId: String? = nil, echoId: String? = nil, lastSyncedAt: Date = Date()) {
        self.id = id
        self.type = type
        self.senderId = senderId
        self.senderUsername = senderUsername
        self.timestamp = timestamp
        self.isPending = isPending
        self.momentId = momentId
        self.visitCount = visitCount
        self.storyId = storyId
        self.storyAuthorId = storyAuthorId
        self.reaction = reaction
        self.commentId = commentId
        self.echoId = echoId
        self.lastSyncedAt = lastSyncedAt
    }
    
    static func from(_ notification: Notification) -> CachedNotification {
        return CachedNotification(
            id: notification.id ?? UUID().uuidString,
            type: notification.type.rawValue,
            senderId: notification.senderId,
            senderUsername: notification.senderUsername,
            timestamp: notification.timestamp,
            isPending: notification.isPending,
            momentId: notification.momentId,
            visitCount: notification.visitCount,
            storyId: notification.storyId,
            storyAuthorId: notification.storyAuthorId,
            reaction: notification.reaction,
            commentId: notification.commentId,
            echoId: notification.echoId
        )
    }
    
    func toNotification() -> Notification {
        return Notification(
            id: id,
            type: NotificationType(rawValue: type) ?? .newFollower,
            senderId: senderId,
            senderUsername: senderUsername,
            timestamp: timestamp,
            isPending: isPending,
            momentId: momentId,
            visitCount: visitCount,
            storyId: storyId,
            storyAuthorId: storyAuthorId,
            reaction: reaction,
            commentId: commentId,
            echoId: echoId
        )
    }
}
