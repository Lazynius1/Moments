import Foundation

struct ActivityReactionItem: Identifiable {
    let id: String
    let authorId: String
    let momentId: String
    let reactionType: String
    let reactedAt: Date
    let moment: Moment?
    let canView: Bool
}

struct ActivityDeletedStoryItem: Identifiable {
    let id: String
    let story: Story
    let deletedAt: Date
}

struct ActivityCommentItem: Identifiable {
    let id: String
    let authorId: String
    let momentId: String
    let commentId: String
    let commentText: String
    let commentedAt: Date
    let moment: Moment?
    let canView: Bool
}

struct ActivityEventItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let timestamp: Date
    let icon: String
    let actorId: String?
    let actorUsername: String?
    let actorProfileImagePath: String?
    let actionText: String?
    let kind: String?
    let targetAuthorId: String?
    let targetUsername: String?
    let storyId: String?
    let sourceId: String?
    let contextText: String?
    let thumbnailUrl: String?
    let echoStatusRaw: String?
    let echoParticipantsCount: Int?
    let echoExpiresAt: Date?

    init(
        id: String,
        title: String,
        subtitle: String,
        timestamp: Date,
        icon: String,
        actorId: String? = nil,
        actorUsername: String? = nil,
        actorProfileImagePath: String? = nil,
        actionText: String? = nil,
        kind: String? = nil,
        targetAuthorId: String? = nil,
        targetUsername: String? = nil,
        storyId: String? = nil,
        sourceId: String? = nil,
        contextText: String? = nil,
        thumbnailUrl: String? = nil,
        echoStatusRaw: String? = nil,
        echoParticipantsCount: Int? = nil,
        echoExpiresAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.timestamp = timestamp
        self.icon = icon
        self.actorId = actorId
        self.actorUsername = actorUsername
        self.actorProfileImagePath = actorProfileImagePath
        self.actionText = actionText
        self.kind = kind
        self.targetAuthorId = targetAuthorId
        self.targetUsername = targetUsername
        self.storyId = storyId
        self.sourceId = sourceId
        self.contextText = contextText
        self.thumbnailUrl = thumbnailUrl
        self.echoStatusRaw = echoStatusRaw
        self.echoParticipantsCount = echoParticipantsCount
        self.echoExpiresAt = echoExpiresAt
    }
}
