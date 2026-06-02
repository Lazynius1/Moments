import Foundation
import Combine
import FirebaseFirestore
import SwiftData
import WidgetKit

typealias FeedStoryUserState = (userId: String, hasStory: Bool, hasUnseenStory: Bool, storyCount: Int, storyViewedStatus: [Bool], storyAudiences: [String?])

@MainActor
final class FeedStoryRingCoordinator: ObservableObject {
    @Published var storyUsers: [FeedStoryUserState] = []
    @Published var isLoadingStories = true

    /// Orden exacto del anillo del feed (tú + quienes tienen historia activa). Usar para swipe en el visor.
    var ringNavigationUserIds: [String] {
        storyUsers.filter(\.hasStory).map(\.userId)
    }

    private let privacyService = PrivacyService()
    private var cachedStories: [String: Bool] = [:]
    private var cachedUnseenStories: [String: Bool] = [:]
    private var cachedStoriesTimestamp = Date()
    private var widgetReloadWorkItem: DispatchWorkItem?

    func clearCacheIfNeeded() {
        let cacheAge = Date().timeIntervalSince(cachedStoriesTimestamp)
        if cacheAge > 600 {
            cachedStories.removeAll()
            cachedStoriesTimestamp = Date()
        }
    }

    func resetCache() {
        cachedStories.removeAll()
        cachedUnseenStories.removeAll()
        cachedStoriesTimestamp = Date()
    }

    func prefetchTopStoryUsers(excluding currentUserId: String?, firestoreService: FirestoreService = .shared) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self else { return }
            let topStoryUsers = self.storyUsers.prefix(5)
            for user in topStoryUsers where user.hasStory && user.userId != currentUserId {
                firestoreService.prefetchStoriesForUser(userId: user.userId)
            }
        }
    }

    func loadStoryUsers(
        userId: String,
        allowInstantCache: Bool = true,
        firestoreService: FirestoreService
    ) async {
        isLoadingStories = true

        if allowInstantCache,
           let cachedTray = StoryTrayService.shared.cachedTray(for: userId) {
            applyStoryTrayResponse(cachedTray, currentUserId: userId)
            isLoadingStories = false
        }

        guard NetworkMonitor.shared.isConnected else {
            isLoadingStories = false
            return
        }

        if let trayResponse = await StoryTrayService.shared.fetchStoryTray() {
            applyStoryTrayResponse(trayResponse, currentUserId: userId)
            isLoadingStories = false
            return
        }

        LogConfig.log("⚡ StoryTray: fallback legacy ring loader", category: "BackendFeed")
        await withCheckedContinuation { continuation in
            firestoreService.fetchMutedUserIds(userId: userId) { [weak self] mutedUserIds in
                guard let self else {
                    continuation.resume()
                    return
                }

                firestoreService.fetchFollowing(userId: userId) { result in
                    switch result {
                    case .success(let followingUsers):
                        let followingIds = followingUsers.map { $0.id }.filter { !mutedUserIds.contains($0) }
                        var allUserIds = [userId]
                        allUserIds.append(contentsOf: followingIds)

                        let cacheAge = Date().timeIntervalSince(self.cachedStoriesTimestamp)
                        if allowInstantCache && cacheAge < 20 && !self.cachedStories.isEmpty {
                            var cachedEntries: [FeedStoryUserState] = []

                            let currentUserHasStory = self.cachedStories[userId] ?? false
                            let cachedOwnStories = currentUserHasStory ? LocalPersistenceService.shared.loadStories(userId: userId) : []
                            let ownStoryCount = cachedOwnStories.isEmpty ? (currentUserHasStory ? 1 : 0) : cachedOwnStories.count
                            let ownAudiences = cachedOwnStories.isEmpty ? (currentUserHasStory ? [nil] : []) : cachedOwnStories.map { $0.audience }
                            let ownViewedStatus = Array(repeating: true, count: ownStoryCount)
                            cachedEntries.append((
                                userId: userId,
                                hasStory: currentUserHasStory,
                                hasUnseenStory: false,
                                storyCount: ownStoryCount,
                                storyViewedStatus: ownViewedStatus,
                                storyAudiences: ownAudiences
                            ))

                            for followingId in followingIds {
                                if let hasStory = self.cachedStories[followingId], hasStory {
                                    let hasUnseenStory = self.cachedUnseenStories[followingId] ?? true
                                    let cachedStories = LocalPersistenceService.shared.loadStories(userId: followingId)
                                    let count = cachedStories.isEmpty ? 1 : cachedStories.count
                                    let audiences = cachedStories.isEmpty ? [nil] : cachedStories.map { $0.audience }
                                    let viewedStatus = Array(repeating: !hasUnseenStory, count: count)
                                    cachedEntries.append((
                                        userId: followingId,
                                        hasStory: true,
                                        hasUnseenStory: hasUnseenStory,
                                        storyCount: count,
                                        storyViewedStatus: viewedStatus,
                                        storyAudiences: audiences
                                    ))
                                }
                            }

                            let finalUsers = self.buildSortedStoryUsers(entries: cachedEntries, currentUserId: userId)
                            self.storyUsers = finalUsers

                            let newStoriesCount = finalUsers.filter { $0.hasUnseenStory }.count
                            let widgetDefaults = UserDefaults(suiteName: "group.com.glowsyapp")
                            widgetDefaults?.set(newStoriesCount, forKey: "widget_new_stories_count")
                            self.scheduleWidgetReload()

                            self.isLoadingStories = false
                            continuation.resume()
                            return
                        }

                        let finishLoad: ([FeedStoryUserState]) -> Void = { finalUsers in
                            DispatchQueue.main.async {
                                self.cachedStoriesTimestamp = Date()
                                self.storyUsers = finalUsers

                                let newStoriesCount = finalUsers.filter { $0.hasUnseenStory }.count
                                let widgetDefaults = UserDefaults(suiteName: "group.com.glowsyapp")
                                widgetDefaults?.set(newStoriesCount, forKey: "widget_new_stories_count")
                                self.scheduleWidgetReload()

                                self.isLoadingStories = false
                                continuation.resume()
                            }
                        }

                        firestoreService.fetchStorySummariesForUsers(userIds: allUserIds) { summaryResult in
                            let candidateUserIds: [String]
                            switch summaryResult {
                            case .success(let summaries):
                                candidateUserIds = allUserIds.filter {
                                    self.shouldFetchDetailedStories(
                                        for: $0,
                                        currentUserId: userId,
                                        summaries: summaries
                                    )
                                }
                            case .failure:
                                candidateUserIds = allUserIds
                            }

                            firestoreService.fetchActiveStoriesForUsers(userIds: candidateUserIds) { batchedResult in
                                switch batchedResult {
                                case .success(let storiesByUser):
                                    self.loadStoryUsersFromBatchedStories(
                                        allUserIds: allUserIds,
                                        currentUserId: userId,
                                        storiesByUser: storiesByUser,
                                        completion: finishLoad
                                    )
                                case .failure:
                                    self.loadStoryUsersLegacy(
                                        allUserIds: allUserIds,
                                        currentUserId: userId,
                                        firestoreService: firestoreService,
                                        completion: finishLoad
                                    )
                                }
                            }
                        }

                    case .failure:
                        self.checkUserStories(userId: userId, currentUserId: userId, firestoreService: firestoreService) { hasStory, hasUnseen, storyCount, viewedStatus, audiences in
                            DispatchQueue.main.async {
                                self.cachedStories[userId] = hasStory
                                self.cachedUnseenStories[userId] = hasUnseen

                                self.storyUsers = [(
                                    userId: userId,
                                    hasStory: hasStory,
                                    hasUnseenStory: false,
                                    storyCount: storyCount,
                                    storyViewedStatus: viewedStatus,
                                    storyAudiences: audiences
                                )]
                                self.isLoadingStories = false
                                continuation.resume()
                            }
                        }
                    }
                }
            }
        }
    }

    private func applyStoryTrayResponse(_ response: BackendStoryTrayResponse, currentUserId: String) {
        let entries: [FeedStoryUserState] = response.items.map { item -> FeedStoryUserState in
            let viewedStatus = item.segments.map(\.viewed)
            let audiences = item.segments.map(\.audience)
            let storyCount = max(item.storyCount, item.segments.count)
            return (
                userId: item.userId,
                hasStory: storyCount > 0,
                hasUnseenStory: item.userId == currentUserId ? false : item.hasUnseenStory,
                storyCount: storyCount,
                storyViewedStatus: viewedStatus,
                storyAudiences: audiences
            )
        }

        var finalUsers = entries
        if finalUsers.first?.userId != currentUserId {
            finalUsers.removeAll { $0.userId == currentUserId }
            finalUsers.insert(emptyCurrentUserEntry(currentUserId), at: 0)
        }

        storyUsers = finalUsers
        cachedStoriesTimestamp = Date()
        for entry in finalUsers {
            cachedStories[entry.userId] = entry.hasStory
            cachedUnseenStories[entry.userId] = entry.hasUnseenStory
            Task {
                await StoryRingCacheService.shared.set(
                    viewerId: currentUserId,
                    authorId: entry.userId,
                    snapshot: StoryRingSnapshot(
                        hasStory: entry.hasStory,
                        hasUnseenStory: entry.hasUnseenStory,
                        storyCount: entry.storyCount,
                        storyViewedStatus: entry.storyViewedStatus,
                        storyAudiences: entry.storyAudiences
                    )
                )
            }
        }

        updateStoryWidgetCount(from: finalUsers)
    }

    private func emptyCurrentUserEntry(_ userId: String) -> FeedStoryUserState {
        (
            userId: userId,
            hasStory: false,
            hasUnseenStory: false,
            storyCount: 0,
            storyViewedStatus: [],
            storyAudiences: []
        )
    }

    private func updateStoryWidgetCount(from users: [FeedStoryUserState]) {
        let newStoriesCount = users.filter { $0.hasUnseenStory }.count
        let widgetDefaults = UserDefaults(suiteName: "group.com.glowsyapp")
        widgetDefaults?.set(newStoriesCount, forKey: "widget_new_stories_count")
        scheduleWidgetReload()
    }

    private func loadCachedStoryUsers(userId: String) -> [FeedStoryUserState] {
        let cachedConnections = LocalPersistenceService.shared.loadConnections(userId: userId)
        let candidateIds = [userId] + cachedConnections.following.map { $0.id }
        var entries: [FeedStoryUserState] = []

        for candidateId in candidateIds {
            let stories = LocalPersistenceService.shared.loadStories(userId: candidateId)
            let hasStory = !stories.isEmpty

            if candidateId != userId && !hasStory {
                continue
            }

            entries.append((
                userId: candidateId,
                hasStory: hasStory,
                hasUnseenStory: candidateId == userId ? false : hasStory,
                storyCount: stories.count,
                storyViewedStatus: Array(repeating: candidateId == userId, count: stories.count),
                storyAudiences: stories.map { $0.audience }
            ))
        }

        return buildSortedStoryUsers(entries: entries, currentUserId: userId)
    }

    private func loadStoryUsersFromBatchedStories(
        allUserIds: [String],
        currentUserId: String,
        storiesByUser: [String: [Story]],
        completion: @escaping ([FeedStoryUserState]) -> Void
    ) {
        let group = DispatchGroup()
        let syncQueue = DispatchQueue(label: "story.users.batched.sync")
        var entriesByUser: [String: FeedStoryUserState] = [:]

        for userIdToCheck in allUserIds {
            let stories = storiesByUser[userIdToCheck] ?? []
            group.enter()
            evaluateVisibleStoriesForRing(userId: userIdToCheck, currentUserId: currentUserId, stories: stories) { hasStory, hasUnseen, storyCount, viewedStatus, audiences in
                syncQueue.async {
                    let entry: FeedStoryUserState = (
                        userId: userIdToCheck,
                        hasStory: hasStory,
                        hasUnseenStory: hasUnseen,
                        storyCount: storyCount,
                        storyViewedStatus: viewedStatus,
                        storyAudiences: audiences
                    )
                    entriesByUser[userIdToCheck] = entry
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) {
            let orderedEntries = syncQueue.sync {
                allUserIds.map { userId in
                    entriesByUser[userId] ?? (
                        userId: userId,
                        hasStory: false,
                        hasUnseenStory: false,
                        storyCount: 0,
                        storyViewedStatus: [],
                        storyAudiences: []
                    )
                }
            }
            for entry in orderedEntries {
                self.cachedStories[entry.userId] = entry.hasStory
                self.cachedUnseenStories[entry.userId] = entry.hasUnseenStory
            }
            completion(self.buildSortedStoryUsers(entries: orderedEntries, currentUserId: currentUserId))
        }
    }

    private func loadStoryUsersLegacy(
        allUserIds: [String],
        currentUserId: String,
        firestoreService: FirestoreService,
        completion: @escaping ([FeedStoryUserState]) -> Void
    ) {
        let group = DispatchGroup()
        let syncQueue = DispatchQueue(label: "story.users.legacy.sync")
        var entriesByUser: [String: FeedStoryUserState] = [:]

        for userIdToCheck in allUserIds {
            group.enter()
            checkUserStories(userId: userIdToCheck, currentUserId: currentUserId, firestoreService: firestoreService) { hasStory, hasUnseen, storyCount, viewedStatus, audiences in
                syncQueue.async {
                    let entry: FeedStoryUserState = (
                        userId: userIdToCheck,
                        hasStory: hasStory,
                        hasUnseenStory: hasUnseen,
                        storyCount: storyCount,
                        storyViewedStatus: viewedStatus,
                        storyAudiences: audiences
                    )
                    entriesByUser[userIdToCheck] = entry
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) {
            let orderedEntries = syncQueue.sync {
                allUserIds.map { userId in
                    entriesByUser[userId] ?? (
                        userId: userId,
                        hasStory: false,
                        hasUnseenStory: false,
                        storyCount: 0,
                        storyViewedStatus: [],
                        storyAudiences: []
                    )
                }
            }
            for entry in orderedEntries {
                self.cachedStories[entry.userId] = entry.hasStory
                self.cachedUnseenStories[entry.userId] = entry.hasUnseenStory
            }
            completion(self.buildSortedStoryUsers(entries: orderedEntries, currentUserId: currentUserId))
        }
    }

    private func buildSortedStoryUsers(entries: [FeedStoryUserState], currentUserId: String) -> [FeedStoryUserState] {
        let currentUserEntry = entries.first(where: { $0.userId == currentUserId }) ?? (
            userId: currentUserId,
            hasStory: false,
            hasUnseenStory: false,
            storyCount: 0,
            storyViewedStatus: [],
            storyAudiences: []
        )

        let normalizedCurrentUserEntry: FeedStoryUserState = (
            userId: currentUserEntry.userId,
            hasStory: currentUserEntry.hasStory,
            hasUnseenStory: false,
            storyCount: currentUserEntry.storyCount,
            storyViewedStatus: currentUserEntry.storyViewedStatus,
            storyAudiences: currentUserEntry.storyAudiences
        )

        var sortedOthers = entries.filter { $0.userId != currentUserId && $0.hasStory }

        let affinityManager = AffinityTracker.shared
        if let container = affinityManager.modelContainer {
            let context = SwiftData.ModelContext(container)
            let bestFriends = Set(UserDefaults.standard.stringArray(forKey: "bestFriends") ?? [])
            let mutuals = Set(UserDefaults.standard.stringArray(forKey: "mutuals") ?? [])
            let affinityScores = affinityManager.getScores(for: sortedOthers.map { $0.userId }, in: context)

            sortedOthers.sort { user1, user2 in
                if user1.hasUnseenStory && !user2.hasUnseenStory { return true }
                if user2.hasUnseenStory && !user1.hasUnseenStory { return false }

                var score1 = (affinityScores[user1.userId] ?? 0.0) * 1000
                var score2 = (affinityScores[user2.userId] ?? 0.0) * 1000

                if bestFriends.contains(user1.userId) {
                    score1 += 50000
                } else if mutuals.contains(user1.userId) {
                    score1 += 20000
                }

                if bestFriends.contains(user2.userId) {
                    score2 += 50000
                } else if mutuals.contains(user2.userId) {
                    score2 += 20000
                }

                return score1 > score2
            }
        } else {
            sortedOthers.sort { user1, user2 in
                if user1.hasUnseenStory && !user2.hasUnseenStory { return true }
                if user2.hasUnseenStory && !user1.hasUnseenStory { return false }
                return false
            }
        }

        var finalUsers: [FeedStoryUserState] = [normalizedCurrentUserEntry]
        finalUsers.append(contentsOf: sortedOthers)
        return finalUsers
    }

    private func shouldFetchDetailedStories(
        for authorId: String,
        currentUserId: String,
        summaries: [String: StoryAuthorSummary]
    ) -> Bool {
        if authorId == currentUserId {
            return true
        }
        guard let summary = summaries[authorId] else {
            return true
        }
        return !summary.shouldSkipDetailedFetch()
    }

    private func evaluateVisibleStoriesForRing(
        userId: String,
        currentUserId: String,
        stories: [Story],
        completion: @escaping (Bool, Bool, Int, [Bool], [String?]) -> Void
    ) {
        guard !stories.isEmpty else {
            completion(false, false, 0, [], [])
            return
        }

        StorySeenStateService.shared.fetchEffectiveLastSeen(
            viewerId: currentUserId,
            authorId: userId
        ) { effectiveLastSeenAt in
            let group = DispatchGroup()
            let syncQueue = DispatchQueue(label: "story.visibility.sync.\(userId)")
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

                self.privacyService.canUserViewStoryEnhanced(story, viewerId: currentUserId) { canView in
                    guard markCompleted() else { return }

                    if canView {
                        let supportsShortcut = StorySeenStateService.shared.supportsShortcut(forAudience: story.audience)
                        if supportsShortcut, let effectiveLastSeenAt = effectiveLastSeenAt, story.timestamp <= effectiveLastSeenAt {
                            syncQueue.async {
                                visibleStories.append((story: story, wasViewed: true))
                                group.leave()
                            }
                            return
                        }

                        if let storyId = story.id {
                            Firestore.firestore().collection("users").document(story.authorId)
                                .collection("stories").document(storyId)
                                .collection("viewers").document(currentUserId)
                                .getDocument { viewerDoc, _ in
                                    let wasViewed = viewerDoc?.exists == true
                                    if wasViewed, supportsShortcut {
                                        StorySeenStateService.shared.markSeen(
                                            viewerId: currentUserId,
                                            authorId: userId,
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
                                let wasViewed = supportsShortcut && (effectiveLastSeenAt != nil)
                                visibleStories.append((story: story, wasViewed: wasViewed))
                                if !wasViewed {
                                    hasUnseenStory = true
                                }
                                group.leave()
                            }
                        }
                    } else {
                        group.leave()
                    }
                }

                DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                    if markCompleted() {
                        group.leave()
                    }
                }
            }

            group.notify(queue: .main) {
                let (sortedStories, unseenStory): ([(story: Story, wasViewed: Bool)], Bool) = syncQueue.sync {
                    let sorted = visibleStories.sorted { story1, story2 in
                        story1.story.timestamp < story2.story.timestamp
                    }
                    return (sorted, hasUnseenStory)
                }

                let storyCount = sortedStories.count
                let viewedStatus = sortedStories.map { $0.wasViewed }
                let audiences = sortedStories.map { $0.story.audience }
                let hasStory = storyCount > 0

                Task {
                    await StoryRingCacheService.shared.set(
                        viewerId: currentUserId,
                        authorId: userId,
                        snapshot: StoryRingSnapshot(
                            hasStory: hasStory,
                            hasUnseenStory: unseenStory,
                            storyCount: storyCount,
                            storyViewedStatus: viewedStatus,
                            storyAudiences: audiences
                        )
                    )
                }

                completion(hasStory, unseenStory, storyCount, viewedStatus, audiences)
            }
        }
    }

    private func checkUserStories(
        userId: String,
        currentUserId: String,
        firestoreService: FirestoreService,
        completion: @escaping (Bool, Bool, Int, [Bool], [String?]) -> Void
    ) {
        firestoreService.db.collection("users").document(userId).collection("stories")
            .whereField("expirationDate", isGreaterThan: Date())
            .getDocuments { snapshot, _ in
                guard let documents = snapshot?.documents, !documents.isEmpty else {
                    completion(false, false, 0, [], [])
                    return
                }

                let stories = documents.compactMap { doc -> Story? in
                    try? doc.data(as: Story.self)
                }

                guard !stories.isEmpty else {
                    completion(false, false, 0, [], [])
                    return
                }

                Task { @MainActor in
                    self.evaluateVisibleStoriesForRing(
                        userId: userId,
                        currentUserId: currentUserId,
                        stories: stories,
                        completion: completion
                    )
                }
            }
    }

    private func scheduleWidgetReload(delay: TimeInterval = 2.0) {
        widgetReloadWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            WidgetCenter.shared.reloadTimelines(ofKind: "GlowsyWidgetExtension")
        }
        widgetReloadWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
}
