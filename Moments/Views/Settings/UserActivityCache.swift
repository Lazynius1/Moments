import Foundation

struct CachedReactionPayload: Codable {
    let id: String
    let authorId: String
    let momentId: String
    let reactionType: String
    let reactedAt: Double
    let canView: Bool
    var momentImagePath: String?
    var momentVideoUrl: String?
    var momentThumbnailUrl: String?
    var momentContent: String?
    var momentUsername: String?
    var momentAuthorId: String?
    var momentAudience: String?
}

struct CachedCommentPayload: Codable {
    let id: String
    let authorId: String
    let momentId: String
    let commentId: String
    let commentText: String
    let commentedAt: Double
    let canView: Bool
    var momentImagePath: String?
    var momentVideoUrl: String?
    var momentThumbnailUrl: String?
    var momentContent: String?
    var momentUsername: String?
    var momentAuthorId: String?
    var momentAudience: String?
}

enum ActivityCache {
    private static func minimalMoment(from p: (imagePath: String?, videoUrl: String?, thumbnailUrl: String?, content: String?, username: String?, authorId: String?, id: String, audience: String?)) -> Moment {
        Moment(
            id: p.id,
            authorId: p.authorId ?? "",
            username: p.username ?? "",
            content: p.content ?? "",
            imagePath: p.imagePath,
            videoUrl: p.videoUrl,
            timestamp: Date(),
            reactions: [:],
            commentCount: 0,
            profileImagePath: nil,
            taggedUsers: nil,
            location: nil,
            audience: p.audience,
            mediaItems: nil,
            aspectRatio: nil,
            customListId: nil,
            thumbnailUrl: p.thumbnailUrl,
            videoDuration: nil,
            videoFileSize: nil,
            videoResolution: nil,
            disableComments: false,
            hideLikeCounts: false,
            allowSharing: true
        )
    }

    static func saveReactions(_ items: [ActivityReactionItem], userId: String) {
        let payloads = items.map { item -> CachedReactionPayload in
            CachedReactionPayload(
                id: item.id, authorId: item.authorId, momentId: item.momentId,
                reactionType: item.reactionType, reactedAt: item.reactedAt.timeIntervalSince1970,
                canView: item.canView,
                momentImagePath: item.moment?.imagePath,
                momentVideoUrl: item.moment?.videoUrl,
                momentThumbnailUrl: item.moment?.thumbnailUrl,
                momentContent: item.moment?.content,
                momentUsername: item.moment?.username,
                momentAuthorId: item.moment?.authorId,
                momentAudience: item.moment?.audience
            )
        }
        if let data = try? JSONEncoder().encode(payloads) {
            UserDefaults.standard.set(data, forKey: "activityCache_reactions_\(userId)")
        }
    }

    static func loadReactions(userId: String) -> [ActivityReactionItem] {
        guard let data = UserDefaults.standard.data(forKey: "activityCache_reactions_\(userId)"),
              let payloads = try? JSONDecoder().decode([CachedReactionPayload].self, from: data)
        else { return [] }
        return payloads.map { p in
            let moment = minimalMoment(from: (p.momentImagePath, p.momentVideoUrl, p.momentThumbnailUrl, p.momentContent, p.momentUsername, p.momentAuthorId, p.momentId, p.momentAudience))
            return ActivityReactionItem(
                id: p.id, authorId: p.authorId, momentId: p.momentId,
                reactionType: p.reactionType, reactedAt: Date(timeIntervalSince1970: p.reactedAt),
                moment: moment, canView: p.canView
            )
        }
    }

    static func saveComments(_ items: [ActivityCommentItem], userId: String) {
        let payloads = items.map { item -> CachedCommentPayload in
            CachedCommentPayload(
                id: item.id, authorId: item.authorId, momentId: item.momentId,
                commentId: item.commentId, commentText: item.commentText,
                commentedAt: item.commentedAt.timeIntervalSince1970, canView: item.canView,
                momentImagePath: item.moment?.imagePath,
                momentVideoUrl: item.moment?.videoUrl,
                momentThumbnailUrl: item.moment?.thumbnailUrl,
                momentContent: item.moment?.content,
                momentUsername: item.moment?.username,
                momentAuthorId: item.moment?.authorId,
                momentAudience: item.moment?.audience
            )
        }
        if let data = try? JSONEncoder().encode(payloads) {
            UserDefaults.standard.set(data, forKey: "activityCache_comments_\(userId)")
        }
    }

    static func loadComments(userId: String) -> [ActivityCommentItem] {
        guard let data = UserDefaults.standard.data(forKey: "activityCache_comments_\(userId)"),
              let payloads = try? JSONDecoder().decode([CachedCommentPayload].self, from: data)
        else { return [] }
        return payloads.map { p in
            let moment = minimalMoment(from: (p.momentImagePath, p.momentVideoUrl, p.momentThumbnailUrl, p.momentContent, p.momentUsername, p.momentAuthorId, p.momentId, p.momentAudience))
            return ActivityCommentItem(
                id: p.id, authorId: p.authorId, momentId: p.momentId,
                commentId: p.commentId, commentText: p.commentText,
                commentedAt: Date(timeIntervalSince1970: p.commentedAt),
                moment: moment, canView: p.canView
            )
        }
    }

    static func saveRecentlyDeletedCount(_ count: Int, userId: String) {
        UserDefaults.standard.set(max(0, count), forKey: "activityCache_recentlyDeletedCount_\(userId)")
    }

    static func loadRecentlyDeletedCount(userId: String) -> Int {
        UserDefaults.standard.integer(forKey: "activityCache_recentlyDeletedCount_\(userId)")
    }

    static func saveTagged(_ items: [ActivityReactionItem], userId: String) {
        let payloads = items.map { item -> CachedReactionPayload in
            CachedReactionPayload(
                id: item.id, authorId: item.authorId, momentId: item.momentId,
                reactionType: item.reactionType, reactedAt: item.reactedAt.timeIntervalSince1970,
                canView: item.canView,
                momentImagePath: item.moment?.imagePath,
                momentVideoUrl: item.moment?.videoUrl,
                momentThumbnailUrl: item.moment?.thumbnailUrl,
                momentContent: item.moment?.content,
                momentUsername: item.moment?.username,
                momentAuthorId: item.moment?.authorId,
                momentAudience: item.moment?.audience
            )
        }
        if let data = try? JSONEncoder().encode(payloads) {
            UserDefaults.standard.set(data, forKey: "activityCache_tags_\(userId)")
        }
    }

    static func loadTagged(userId: String) -> [ActivityReactionItem] {
        guard let data = UserDefaults.standard.data(forKey: "activityCache_tags_\(userId)"),
              let payloads = try? JSONDecoder().decode([CachedReactionPayload].self, from: data)
        else { return [] }
        return payloads.map { p in
            let moment = minimalMoment(from: (p.momentImagePath, p.momentVideoUrl, p.momentThumbnailUrl, p.momentContent, p.momentUsername, p.momentAuthorId, p.momentId, p.momentAudience))
            return ActivityReactionItem(
                id: p.id, authorId: p.authorId, momentId: p.momentId,
                reactionType: p.reactionType, reactedAt: Date(timeIntervalSince1970: p.reactedAt),
                moment: moment, canView: p.canView
            )
        }
    }

    static func saveStickerReplyCount(_ count: Int, userId: String) {
        UserDefaults.standard.set(max(0, count), forKey: "activityCache_stickerCount_\(userId)")
    }

    static func loadStickerReplyCount(userId: String) -> Int {
        UserDefaults.standard.integer(forKey: "activityCache_stickerCount_\(userId)")
    }
}
