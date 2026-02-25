import Foundation

struct StoryRingSnapshot: Sendable {
    let hasStory: Bool
    let hasUnseenStory: Bool
    let storyCount: Int
    let storyViewedStatus: [Bool]
    let storyAudiences: [String?]
}

actor StoryRingCacheService {
    static let shared = StoryRingCacheService()
    
    private struct Entry {
        let snapshot: StoryRingSnapshot
        let expiresAt: Date
    }
    
    private var storage: [String: Entry] = [:]
    
    private func key(viewerId: String, authorId: String) -> String {
        "\(viewerId)|\(authorId)"
    }
    
    func get(viewerId: String, authorId: String) -> StoryRingSnapshot? {
        let cacheKey = key(viewerId: viewerId, authorId: authorId)
        guard let entry = storage[cacheKey] else { return nil }
        if entry.expiresAt < Date() {
            storage.removeValue(forKey: cacheKey)
            return nil
        }
        return entry.snapshot
    }
    
    func set(viewerId: String, authorId: String, snapshot: StoryRingSnapshot, ttl: TimeInterval = 30) {
        let cacheKey = key(viewerId: viewerId, authorId: authorId)
        storage[cacheKey] = Entry(snapshot: snapshot, expiresAt: Date().addingTimeInterval(ttl))
    }
    
    func invalidate(viewerId: String, authorId: String) {
        let cacheKey = key(viewerId: viewerId, authorId: authorId)
        storage.removeValue(forKey: cacheKey)
    }
    
    func invalidateAuthor(authorId: String) {
        storage = storage.filter { !$0.key.hasSuffix("|\(authorId)") }
    }
    
    func clear() {
        storage.removeAll()
    }
}
