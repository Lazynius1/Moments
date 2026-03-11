import Foundation
import FirebaseFirestore

// MARK: - Outbox Payloads for Offline Sync

/// Payload for persisting a reaction toggle action
struct ReactionPayload: Codable {
    let momentId: String
    let reaction: String
    let authorId: String // Moment author ID
    let userId: String   // Current user ID
}

struct SavePayload: Codable {
    let userId: String
    let momentId: String
}

struct CommentPayload: Codable {
    let momentId: String
    let authorId: String  // Moment author ID (recipient)
    let senderId: String  // Comment author ID (sender)
    let content: String
    let parentCommentId: String?
    let commentId: String? // ✅ Added for offline matching
}

/// Payload for persisting a comment deletion action
struct DeleteCommentPayload: Codable {
    let momentId: String
    let commentId: String
    let userId: String     // Moment owner ID
    let authorId: String   // Comment author ID
}

/// Payload for persisting a direct message action
struct MessagePayload: Codable {
    let message: EnhancedMessage
    let useServerTimestamp: Bool
}

/// Payload for persisting follow/unfollow actions
struct FollowActionPayload: Codable {
    let followerId: String
    let followedId: String
    let followedUsername: String
    let isFollow: Bool // true for follow, false for unfollow
}

/// Payload for persisting block/unblock actions
struct BlockActionPayload: Codable {
    let currentUserId: String
    let targetUserId: String
    let isBlock: Bool // true for block, false for unblock
}

/// Payload for persisting follow request actions
struct FollowRequestActionPayload: Codable {
    let notificationId: String
    let senderId: String
    let recipientId: String
    let isAccept: Bool // true for accept, false for reject
}

/// Payload for persisting report actions
struct ReportActionPayload: Codable {
    let reporterId: String
    let reportedUserId: String
    let reportedContentType: String
    let reportedContentId: String
    let category: String
    let description: String
    let priority: String
}

/// Payload for persisting mark as read actions
struct MarkAsReadPayload: Codable {
    let notificationId: String
    let userId: String
}

/// Payload for persisting moment deletion
struct DeleteMomentPayload: Codable {
    let momentId: String
    let userId: String
    let imagePath: String?
    let videoUrl: String?
}

/// Payload for persisting profile updates
struct ProfileUpdatePayload: Codable {
    let userId: String
    let bio: String?
    let oldBio: String?
    let websiteUrl: String?
    let oldWebsiteUrl: String?
    let interests: [String]?
    let profileImageLocalPath: String? // Path to local image file to upload
    let isImageUpdate: Bool
}
