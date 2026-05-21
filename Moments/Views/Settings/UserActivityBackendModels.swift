import Foundation

struct BackendReactionsCursor: Codable {
    let timestamp: Double
}

struct BackendReactionsItem: Codable {
    let moment: BackendMoment
    let reactionType: String
    let reactedAt: Double?
    let authorId: String?
    let momentId: String?
    let canView: Bool?
}

struct BackendReactionsResponse: Codable {
    let items: [BackendReactionsItem]
    let nextCursor: BackendReactionsCursor?
    let source: String
    let totalCandidates: Int
}

struct BackendCommentsCursor: Codable {
    let timestamp: Double
}

struct BackendCommentPayload: Codable {
    let id: String?
    let content: String?
    let timestamp: Double?
    let parentCommentId: String?
}

struct BackendCommentedItem: Codable {
    let moment: BackendMoment
    let comment: BackendCommentPayload?
    let commentedAt: Double?
    let authorId: String?
    let momentId: String?
    let commentId: String?
    let canView: Bool?
}

struct BackendCommentsResponse: Codable {
    let items: [BackendCommentedItem]
    let nextCursor: BackendCommentsCursor?
    let source: String
    let totalCandidates: Int
}

struct BackendTagsCursor: Codable {
    let timestamp: Double
}

struct BackendTaggedItem: Codable {
    let moment: BackendMoment
    let taggedAt: Double?
    let authorId: String?
    let momentId: String?
    let canView: Bool?
}

struct BackendTagsResponse: Codable {
    let items: [BackendTaggedItem]
    let nextCursor: BackendTagsCursor?
    let source: String
    let totalCandidates: Int
}

struct BackendStickerRepliesCursor: Codable {
    let timestamp: Double
}

struct BackendStickerReplyItem: Codable {
    let id: String
    let sourceId: String?
    let kind: String
    let authorId: String?
    let storyId: String?
    let targetUsername: String?
    let actorId: String?
    let actorUsername: String?
    let actorProfileImagePath: String?
    let timestamp: Double?
    let questionText: String?
    let responseText: String?
    let pollOption: Int?
    let pollOptionText: String?
}

struct BackendStickerRepliesResponse: Codable {
    let items: [BackendStickerReplyItem]
    let nextCursor: BackendStickerRepliesCursor?
    let source: String
    let totalCandidates: Int
}

struct DeleteCommentsTarget: Codable {
    let authorId: String
    let momentId: String
    let commentId: String
}

struct DeleteCommentsBatchResponse: Codable {
    let deleted: Int
    let skipped: Int
    let cascadedReplies: Int?
}

struct NotificationRecord {
    let id: String
    let type: String
    let senderUsername: String?
    let reaction: String?
    let timestamp: Date
}
