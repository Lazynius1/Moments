import Foundation
import SwiftData

// MARK: - ✅ SwiftData Model: Acción pendiente offline
// Representa una operación que debe ejecutarse cuando haya conexión.

@Model
final class CachedAction {
    @Attribute(.unique) var id: String
    var type: String          // "moment_upload", "story_upload", "message", "reaction"
    var status: String        // "pending", "executing", "failed"
    var payloadData: Data     // JSON encoded parameters
    var createdAt: Date
    var retryCount: Int
    var lastError: String?
    
    init(
        id: String = UUID().uuidString,
        type: String,
        status: String = "pending",
        payloadData: Data,
        createdAt: Date = Date(),
        retryCount: Int = 0,
        lastError: String? = nil
    ) {
        self.id = id
        self.type = type
        self.status = status
        self.payloadData = payloadData
        self.createdAt = createdAt
        self.retryCount = retryCount
        self.lastError = lastError
    }
}

// MARK: - Enums for type safety (Internal mapping)
extension CachedAction {
    enum ActionType: String, CaseIterable {
        case momentUpload = "moment_upload"
        case storyUpload = "story_upload"
        case message = "message"
        case reaction = "reaction"
        case comment = "comment"
        case deleteComment = "delete_comment"
        case follow = "follow"
        case save = "save"
        case block = "block"
        case updateProfile = "update_profile"
        case acceptFollowRequest = "accept_follow_request"
        case rejectFollowRequest = "reject_follow_request"
        case reportContent = "report_content"
        case markAsRead = "mark_as_read"
        case deleteMoment = "delete_moment"
    }
    
    enum ActionStatus: String, CaseIterable {
        case pending = "pending"
        case executing = "executing"
        case failed = "failed"
        case completed = "completed" // Usually deleted after completion, but kept for audit if needed
    }
}
