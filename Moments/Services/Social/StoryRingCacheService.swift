import Foundation
import FirebaseFirestore

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

final class StoryRingResolverService {
    static let shared = StoryRingResolverService()

    private init() {}

    private let viewerLookupTimeout: TimeInterval = 5

    private static let emptySnapshot = StoryRingSnapshot(
        hasStory: false,
        hasUnseenStory: false,
        storyCount: 0,
        storyViewedStatus: [],
        storyAudiences: []
    )

    func resolve(
        viewerId: String,
        authorId: String,
        privacyService: PrivacyService,
        db: Firestore = Firestore.firestore(),
        useCache: Bool = true,
        completion: @escaping (StoryRingSnapshot) -> Void
    ) {
        guard !viewerId.isEmpty, !authorId.isEmpty else {
            DispatchQueue.main.async {
                completion(Self.emptySnapshot)
            }
            return
        }

        let fetch = { [weak self] in
            self?.fetchFromFirestore(
                viewerId: viewerId,
                authorId: authorId,
                privacyService: privacyService,
                db: db,
                completion: completion
            )
        }

        guard useCache else {
            fetch()
            return
        }

        Task {
            if let cached = await StoryRingCacheService.shared.get(viewerId: viewerId, authorId: authorId) {
                await MainActor.run {
                    completion(cached)
                }
                return
            }
            fetch()
        }
    }

    private func fetchFromFirestore(
        viewerId: String,
        authorId: String,
        privacyService: PrivacyService,
        db: Firestore,
        completion: @escaping (StoryRingSnapshot) -> Void
    ) {
        db.collection("users").document(authorId).collection("stories")
            .whereField("expirationDate", isGreaterThan: Date())
            .order(by: "timestamp", descending: false)
            .getDocuments { [weak self] snapshot, _ in
                guard let self else { return }
                guard let documents = snapshot?.documents, !documents.isEmpty else {
                    self.cacheAndComplete(
                        viewerId: viewerId,
                        authorId: authorId,
                        snapshot: Self.emptySnapshot,
                        completion: completion
                    )
                    return
                }

                let stories = documents.compactMap { try? $0.data(as: Story.self) }
                guard !stories.isEmpty else {
                    self.cacheAndComplete(
                        viewerId: viewerId,
                        authorId: authorId,
                        snapshot: Self.emptySnapshot,
                        completion: completion
                    )
                    return
                }

                self.evaluateStories(
                    stories,
                    viewerId: viewerId,
                    authorId: authorId,
                    privacyService: privacyService,
                    db: db
                ) { snapshot in
                    self.cacheAndComplete(
                        viewerId: viewerId,
                        authorId: authorId,
                        snapshot: snapshot,
                        completion: completion
                    )
                }
            }
    }

    private func evaluateStories(
        _ stories: [Story],
        viewerId: String,
        authorId: String,
        privacyService: PrivacyService,
        db: Firestore,
        completion: @escaping (StoryRingSnapshot) -> Void
    ) {
        StorySeenStateService.shared.fetchEffectiveLastSeen(
            viewerId: viewerId,
            authorId: authorId
        ) { effectiveLastSeenAt in
            let group = DispatchGroup()
            let syncQueue = DispatchQueue(label: "story.ring.visibility.\(authorId)")
            var visibleStories: [(story: Story, wasViewed: Bool)] = []
            var hasUnseenStory = false

            for story in stories {
                group.enter()
                let completionLock = NSLock()
                var didComplete = false

                func markCompleted() -> Bool {
                    completionLock.lock()
                    defer { completionLock.unlock() }
                    if didComplete { return false }
                    didComplete = true
                    return true
                }

                privacyService.canUserViewStoryEnhanced(story, viewerId: viewerId) { canView in
                    guard markCompleted() else { return }

                    guard canView else {
                        group.leave()
                        return
                    }

                    let supportsShortcut = StorySeenStateService.shared.supportsShortcut(forAudience: story.audience)
                    if supportsShortcut,
                       let effectiveLastSeenAt = effectiveLastSeenAt,
                       story.timestamp <= effectiveLastSeenAt {
                        syncQueue.async {
                            visibleStories.append((story: story, wasViewed: true))
                            group.leave()
                        }
                        return
                    }

                    if let storyId = story.id, !storyId.isEmpty {
                        db.collection("users").document(story.authorId)
                            .collection("stories").document(storyId)
                            .collection("viewers").document(viewerId)
                            .getDocument { viewerDoc, _ in
                                let wasViewed = viewerDoc?.exists == true
                                if wasViewed, supportsShortcut {
                                    StorySeenStateService.shared.markSeen(
                                        viewerId: viewerId,
                                        authorId: authorId,
                                        timestamp: story.timestamp,
                                        syncRemote: true
                                    )
                                }
                                syncQueue.async {
                                    visibleStories.append((story: story, wasViewed: wasViewed))
                                    if !wasViewed {
                                        hasUnseenStory = true
                                    }
                                    group.leave()
                                }
                            }
                    } else {
                        syncQueue.async {
                            let wasViewed = supportsShortcut &&
                                (effectiveLastSeenAt != nil) &&
                                (story.timestamp <= (effectiveLastSeenAt ?? .distantPast))
                            visibleStories.append((story: story, wasViewed: wasViewed))
                            if !wasViewed {
                                hasUnseenStory = true
                            }
                            group.leave()
                        }
                    }
                }

                DispatchQueue.global().asyncAfter(deadline: .now() + self.viewerLookupTimeout) {
                    if markCompleted() {
                        group.leave()
                    }
                }
            }

            group.notify(queue: .main) {
                let (sortedStories, unresolvedUnseen): ([(story: Story, wasViewed: Bool)], Bool) = syncQueue.sync {
                    let sorted = visibleStories.sorted { lhs, rhs in
                        lhs.story.timestamp < rhs.story.timestamp
                    }
                    return (sorted, hasUnseenStory)
                }

                let viewedStatus = sortedStories.map(\.wasViewed)
                let audiences = sortedStories.map { $0.story.audience }
                let hasStory = !sortedStories.isEmpty
                let unseen = hasStory ? (unresolvedUnseen || viewedStatus.contains(false)) : false

                completion(
                    StoryRingSnapshot(
                        hasStory: hasStory,
                        hasUnseenStory: unseen,
                        storyCount: sortedStories.count,
                        storyViewedStatus: viewedStatus,
                        storyAudiences: audiences
                    )
                )
            }
        }
    }

    private func cacheAndComplete(
        viewerId: String,
        authorId: String,
        snapshot: StoryRingSnapshot,
        completion: @escaping (StoryRingSnapshot) -> Void
    ) {
        Task {
            await StoryRingCacheService.shared.set(
                viewerId: viewerId,
                authorId: authorId,
                snapshot: snapshot
            )
        }
        DispatchQueue.main.async {
            completion(snapshot)
        }
    }

}
