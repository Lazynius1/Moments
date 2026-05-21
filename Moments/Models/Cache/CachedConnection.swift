import Foundation
import SwiftData

@Model
final class CachedConnection {
    @Attribute(.unique) var id: String // composite key: userId_targetId_type
    var userId: String
    var targetId: String
    var type: String // "follower" or "following"
    var timestamp: Date
    
    init(userId: String, targetId: String, type: String, timestamp: Date = Date()) {
        self.id = "\(userId)_\(targetId)_\(type)"
        self.userId = userId
        self.targetId = targetId
        self.type = type
        self.timestamp = timestamp
    }
}
