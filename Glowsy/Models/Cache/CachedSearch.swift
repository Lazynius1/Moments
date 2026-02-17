import Foundation
import SwiftData

@Model
final class CachedSearch {
    @Attribute(.unique) var id: String // query_type_targetId
    var query: String
    var type: String // "user", "hashtag", "text"
    var targetId: String? // Optional user ID or other entity ID
    var timestamp: Date
    
    init(query: String, type: String, targetId: String? = nil, timestamp: Date = Date()) {
        let tId = targetId ?? "none"
        self.id = "\(query)_\(type)_\(tId)"
        self.query = query
        self.type = type
        self.targetId = targetId
        self.timestamp = timestamp
    }
}
