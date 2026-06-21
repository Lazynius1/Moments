import SwiftUI
import FirebaseAuth
@preconcurrency import FirebaseFirestore
import SwiftData
import Observation

// MARK: - FeedViewModel CORREGIDO - Versión que funciona

@MainActor
@Observable
class FeedViewModel {
    var moments: [Moment] = []
    var isLoading: Bool = false
    var isLoadingMore: Bool = false
    var errorMessage: String?
    var userProfileImage: String?
    var connections: [Connection] = []
    var admirers: [Admirer] = []

    // Propiedades para el selector de feed
    var currentFeedType: FeedType = .following
    var forYouMoments: [Moment] = []
    var followingMoments: [Moment] = []
    var isPausedForUploads = false

    private let firestoreService = FirestoreService.shared
    private let privacyService = PrivacyService()
    private var lastDocument: DocumentSnapshot?
    private var userListener: ListenerRegistration?
    private var momentListeners: [String: ListenerRegistration] = [:]
    private var commentListeners: [String: ListenerRegistration] = [:]
    private let listenerVisibilityThreshold: CGFloat = 0.08
    private let listenerIndexBuffer = 5
    private var pendingUpdates: [String: DispatchWorkItem] = [:]
    private let updateDebounceTime: TimeInterval = 0.3
    private var lastUpdateHashes: [String: Int] = [:]
    private var mutedUserIdsCache: Set<String> = []
    private var mutedUserIdsCacheTimestamp: Date = .distantPast
    private let mutedUserIdsCacheTTL: TimeInterval = 20

    // 🚀 Backend feed pagination state (per feed type)
    private var backendCursors: [FeedType: FeedCursor?] = [:]
    private var feedLoadedFromBackend: [FeedType: Bool] = [.following: false, .forYou: false]
    private var backendReachedEnd: [FeedType: Bool] = [.following: false, .forYou: false]
    private var cachedFollowingIds: Set<String> = []
    private var forYouLegacyGlobalStreamCursor: ForYouDiscoveryService.GlobalStreamCursor?

    // ✅ NUEVO: Queue para sincronización segura de arrays
    private let momentsQueue = DispatchQueue(label: "moments.sync", attributes: .concurrent)

    @MainActor
    func refreshMoments(userId: String) async {
        lastDocument = nil
        backendCursors.removeAll()
        feedLoadedFromBackend = [.following: false, .forYou: false]
        backendReachedEnd = [.following: false, .forYou: false]
        forYouLegacyGlobalStreamCursor = nil
        mutedUserIdsCache.removeAll()
        mutedUserIdsCacheTimestamp = .distantPast
        clearListeners()


        fetchMoments(userId: userId, feedType: currentFeedType)

        // ✅ Esperar a que se complete la operación inicial
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 segundos
    }

    // MARK: - Caching Logic (Offline Support)

    private func getCacheKey(for type: FeedType) -> String {
        return "cached_feed_\(type == .following ? "following" : "foryou")"
    }

    private func saveFeedToCache(moments: [Moment], type: FeedType, sync: Bool = false) {
        if let data = try? JSONEncoder().encode(moments) {
            UserDefaults.standard.set(data, forKey: getCacheKey(for: type))
        }

        // ✅ SwiftData: Guardar en DB local para experiencia offline
        Task { @MainActor in
            LocalPersistenceService.shared.saveFeedMoments(moments, sync: sync)
        }
    }

    private func loadFeedFromCache(type: FeedType) -> [Moment] {
        if let data = UserDefaults.standard.data(forKey: getCacheKey(for: type)),
           let moments = try? JSONDecoder().decode([Moment].self, from: data) {
            return moments
        }

        // ✅ SwiftData: fallback legacy para usuarios que aún no tienen caché separada por feed
        return type == .following ? LocalPersistenceService.shared.loadFeedMoments() : []
    }

    private func resolveMutedUserIds(viewerId: String, forceRefresh: Bool = false, completion: @escaping (Set<String>) -> Void) {
        guard !viewerId.isEmpty else {
            completion([])
            return
        }

        let cacheAge = Date().timeIntervalSince(mutedUserIdsCacheTimestamp)
        if !forceRefresh, cacheAge < mutedUserIdsCacheTTL {
            completion(mutedUserIdsCache)
            return
        }

        firestoreService.fetchMutedUserIds(userId: viewerId) { [weak self] mutedIds in
            Task { @MainActor in
                self?.mutedUserIdsCache = mutedIds
                self?.mutedUserIdsCacheTimestamp = Date()
                completion(mutedIds)
            }
        }
    }

    private func resolveMutedUserIdsAsync(viewerId: String, forceRefresh: Bool = false) async -> Set<String> {
        await withCheckedContinuation { continuation in
            resolveMutedUserIds(viewerId: viewerId, forceRefresh: forceRefresh) { mutedIds in
                continuation.resume(returning: mutedIds)
            }
        }
    }

    // MARK: - Main Functions

    func fetchMoments(userId: String, feedType: FeedType? = nil) {
        let targetFeedType = feedType ?? currentFeedType
        let cached = loadFeedFromCache(type: targetFeedType)

        // ✅ Actualizar en main thread
        DispatchQueue.main.async {
            self.currentFeedType = targetFeedType
            self.isLoading = true
            self.errorMessage = nil

            if !cached.isEmpty && self.moments.isEmpty {
                self.moments = cached
                VideoMomentsIndex.shared.rebuild(from: cached)

                if targetFeedType == .following {
                    self.followingMoments = cached
                } else {
                    self.forYouMoments = cached
                }

                self.isLoading = false

                VideoPreloader.shared.preloadAssets(
                    urls: VideoPlaybackSelector.shared.preloadURLStrings(from: cached)
                )
            }
        }

        guard NetworkMonitor.shared.isConnected else {
            DispatchQueue.main.async {
                if !cached.isEmpty {
                    self.moments = cached
                    VideoMomentsIndex.shared.rebuild(from: cached)

                    if targetFeedType == .following {
                        self.followingMoments = cached
                    } else {
                        self.forYouMoments = cached
                    }

                    VideoPreloader.shared.preloadAssets(
                        urls: VideoPlaybackSelector.shared.preloadURLStrings(from: cached)
                    )
                }
                self.isLoading = false
            }
            return
        }

        resolveMutedUserIds(viewerId: userId) { [weak self] mutedUserIds in
            DispatchQueue.main.async {
                guard let self = self else { return }
                // ✅ Reconciliar caché con usuarios silenciados cuando hay red.
                let visibleCached = cached.filter { !mutedUserIds.contains($0.authorId) }
                if !visibleCached.isEmpty {
                    self.moments = visibleCached
                    VideoMomentsIndex.shared.rebuild(from: visibleCached)

                    if targetFeedType == .following {
                        self.followingMoments = visibleCached
                    } else {
                        self.forYouMoments = visibleCached
                    }

                    VideoPreloader.shared.preloadAssets(
                        urls: VideoPlaybackSelector.shared.preloadURLStrings(from: visibleCached)
                    )
                }
            }
        }

        // Limpiar listeners anteriores
        clearListeners()

        switch targetFeedType {
        case .following:
            fetchFollowingMoments(userId: userId)
        case .forYou:
            fetchForYouMoments(userId: userId)
        }
    }



    func loadMoreMoments(userId: String) {
        guard !isLoadingMore else { return }
        isLoadingMore = true

        let feed = currentFeedType

        // 🚀 If initial load was from backend, keep using backend for pagination
        if feedLoadedFromBackend[feed] == true {
            // End of feed reached — nothing more to load
            if backendReachedEnd[feed] == true {
                isLoadingMore = false
                LogConfig.log("🚀 LoadMore: backend end-of-feed for \(feed)", category: "Feed")
                return
            }

            guard let cursor = backendCursors[feed] ?? nil else {
                // No cursor but not marked as end — treat as end
                backendReachedEnd[feed] = true
                isLoadingMore = false
                return
            }

            Task {
                let feedTypeStr = feed == .forYou ? "forYou" : "following"
                let mutedUserIds = await self.resolveMutedUserIdsAsync(viewerId: userId)
                if let result = await BackendFeedService.shared.fetchFeedPage(
                    feedType: feedTypeStr,
                    cursor: cursor,
                    limit: 20
                ) {
                    let newMoments = result.moments
                        .filter { $0.isArchived != true }
                        .filter { !mutedUserIds.contains($0.authorId) }

                    let tunedNew: [Moment]
                    if feed == .forYou {
                        tunedNew = self.applyForYouClientTuning(
                            moments: newMoments,
                            followingIds: self.cachedFollowingIds,
                            viewerId: userId,
                            preserveOrder: true
                        )
                    } else {
                        tunedNew = newMoments.sorted { $0.timestamp > $1.timestamp }
                    }

                    let existingIds = Set(self.moments.map { $0.id })
                    let uniqueNew = tunedNew.filter { !existingIds.contains($0.id) }

                    await MainActor.run {
                        if let nextCursor = result.nextCursor {
                            self.backendCursors[feed] = nextCursor
                        } else {
                            self.backendCursors[feed] = nil
                            self.backendReachedEnd[feed] = true
                        }

                        self.moments.append(contentsOf: uniqueNew)

                        if feed == .following {
                            self.followingMoments.append(contentsOf: uniqueNew)
                        } else {
                            self.forYouMoments.append(contentsOf: uniqueNew)
                        }

                        self.isLoadingMore = false
                        self.saveFeedToCache(moments: self.moments, type: feed, sync: false)

                        VideoPreloader.shared.preloadAssets(
                            urls: VideoPlaybackSelector.shared.preloadURLStrings(from: uniqueNew)
                        )
                    }
                    LogConfig.log("🚀 LoadMore from BACKEND (+\(uniqueNew.count) moments)", category: "Feed")
                    return
                }

                // Backend loadMore failed — fall through to legacy
                LogConfig.log("🔄 LoadMore: backend failed, falling back to legacy", category: "Feed")
                await MainActor.run {
                    self.feedLoadedFromBackend[feed] = false
                    self.loadMoreMomentsLegacy(userId: userId)
                }
            }
            return
        }

        // Legacy loadMore
        loadMoreMomentsLegacy(userId: userId)
    }

    private func loadMoreMomentsLegacy(userId: String) {
        if currentFeedType == .following {
            firestoreService.fetchFollowing(userId: userId) { [weak self] result in
                switch result {
                case .success(let followingUsers):
                    let targetUserIds = followingUsers.map { $0.id }

                    if targetUserIds.isEmpty {
                        DispatchQueue.main.async {
                            self?.isLoadingMore = false
                        }
                        return
                    }

                    self?.fetchMoreMomentsFromUsers(userIds: targetUserIds, userId: userId, feedType: .following)
                case .failure(_):
                    DispatchQueue.main.async {
                        self?.isLoadingMore = false
                        self?.errorMessage = NSLocalizedString("feed.loading.moreContent", comment: "Error loading more content")
                    }
                }
            }
        } else if currentFeedType == .forYou {
            fetchMoreForYouMoments(userId: userId)
        }
    }

    func switchFeedType(to feedType: FeedType, userId: String) {
        currentFeedType = feedType
        clearListeners()

        switch feedType {
        case .following:
            if !followingMoments.isEmpty {
                moments = followingMoments
            } else {
                moments = []
                isLoading = true
                fetchMoments(userId: userId, feedType: feedType)
            }
        case .forYou:
            if !forYouMoments.isEmpty {
                moments = forYouMoments
            } else {
                moments = []
                isLoading = true
                fetchMoments(userId: userId, feedType: feedType)
            }
        }
    }

    // MARK: - Private Functions

    private func resolveFollowingIdsAsync(viewerId: String) async -> Set<String> {
        await withCheckedContinuation { continuation in
            firestoreService.fetchFollowing(userId: viewerId) { result in
                if case .success(let users) = result {
                    continuation.resume(returning: Set(users.map(\.id)))
                } else {
                    continuation.resume(returning: [])
                }
            }
        }
    }

    private func sortMomentsChronologically(_ moments: [Moment], limit: Int? = nil) -> [Moment] {
        let sorted = moments.sorted { $0.timestamp > $1.timestamp }
        if let limit {
            return Array(sorted.prefix(limit))
        }
        return sorted
    }

    /// Defensive Para Ti tuning: exclude followed authors; optional light local affinity when not preserving backend order.
    private func applyForYouClientTuning(
        moments: [Moment],
        followingIds: Set<String>,
        viewerId: String,
        preserveOrder: Bool
    ) -> [Moment] {
        let filtered = moments.filter { moment in
            moment.authorId != viewerId && !followingIds.contains(moment.authorId)
        }

        guard !preserveOrder, let container = AffinityTracker.shared.modelContainer else {
            return filtered
        }

        let context = SwiftData.ModelContext(container)
        let affinityScores = AffinityTracker.shared.getScores(for: filtered.map(\.authorId), in: context)

        let scored = filtered.map { moment -> (moment: Moment, score: Double) in
            let baseScore = moment.timestamp.timeIntervalSince1970
            let affinityScore = affinityScores[moment.authorId] ?? 0.0
            return (moment: moment, score: baseScore + (affinityScore * 500))
        }

        return scored.sorted { $0.score > $1.score }.map(\.moment)
    }

    private func fetchFollowingMoments(userId: String) {
        // 🚀 Backend-first: try Cloud Function, fallback to legacy
        Task {
            let mutedUserIds = await self.resolveMutedUserIdsAsync(viewerId: userId)
            self.cachedFollowingIds = await self.resolveFollowingIdsAsync(viewerId: userId)
            if let result = await BackendFeedService.shared.fetchFeedPage(feedType: "following", limit: 40) {
                let finalMoments = self.sortMomentsChronologically(
                    result.moments
                        .filter { $0.isArchived != true }
                        .filter { !mutedUserIds.contains($0.authorId) }
                )

                await MainActor.run {
                    self.isLoading = false
                    self.followingMoments = finalMoments
                    self.moments = finalMoments
                    VideoMomentsIndex.shared.rebuild(from: finalMoments)
                    self.feedLoadedFromBackend[.following] = true
                    if let nextCursor = result.nextCursor {
                        self.backendCursors[.following] = nextCursor
                        self.backendReachedEnd[.following] = false
                    } else {
                        self.backendCursors[.following] = nil
                        self.backendReachedEnd[.following] = true
                    }
                    self.saveFeedToCache(moments: finalMoments, type: .following, sync: true)

                    VideoPreloader.shared.preloadAssets(
                        urls: VideoPlaybackSelector.shared.preloadURLStrings(from: finalMoments)
                    )
                }
                LogConfig.log("🚀 Feed loaded from BACKEND (\(finalMoments.count) moments)", category: "Feed")
                return
            }

            // ❌ Backend failed or circuit open — use legacy
            LogConfig.log("🔄 Feed: fallback to LEGACY", category: "Feed")
            await MainActor.run {
                self.feedLoadedFromBackend[.following] = false
                self.backendCursors[.following] = nil
                self.backendReachedEnd[.following] = false
            }
            self.fetchFollowingMomentsLegacy(userId: userId)
        }
    }

    /// Legacy feed: fetch from Firestore + client-side privacy filter
    private func fetchFollowingMomentsLegacy(userId: String) {
        firestoreService.fetchFollowing(userId: userId) { [weak self] result in
            switch result {
            case .success(let followingUsers):
                let targetUserIds = followingUsers.map { $0.id }
                self?.cachedFollowingIds = Set(targetUserIds)

                if targetUserIds.isEmpty {
                    DispatchQueue.main.async {
                        self?.isLoading = false
                        self?.followingMoments = []
                        self?.moments = []
                    }
                } else {
                    self?.fetchMomentsFromUsers(userIds: targetUserIds, userId: userId, feedType: .following)
                }

            case .failure(_):
                DispatchQueue.main.async {
                    self?.isLoading = false
                    self?.followingMoments = []
                    self?.moments = []
                    self?.errorMessage = NSLocalizedString("feed.loading.content", comment: "Error loading content")
                }
            }
        }
    }


    private func fetchForYouMoments(userId: String) {
        // 🚀 Backend-first: try Cloud Function, fallback to legacy
        Task {
            let mutedUserIds = await self.resolveMutedUserIdsAsync(viewerId: userId)
            self.cachedFollowingIds = await self.resolveFollowingIdsAsync(viewerId: userId)
            if let result = await BackendFeedService.shared.fetchFeedPage(feedType: "forYou", limit: 60) {
                let finalMoments = self.applyForYouClientTuning(
                    moments: result.moments
                        .filter { $0.isArchived != true }
                        .filter { !mutedUserIds.contains($0.authorId) },
                    followingIds: self.cachedFollowingIds,
                    viewerId: userId,
                    preserveOrder: true
                )

                await MainActor.run {
                    self.isLoading = false
                    self.forYouMoments = finalMoments
                    self.moments = finalMoments
                    VideoMomentsIndex.shared.rebuild(from: finalMoments)
                    self.feedLoadedFromBackend[.forYou] = true
                    if let nextCursor = result.nextCursor {
                        self.backendCursors[.forYou] = nextCursor
                        self.backendReachedEnd[.forYou] = false
                    } else {
                        self.backendCursors[.forYou] = nil
                        self.backendReachedEnd[.forYou] = true
                    }
                    self.saveFeedToCache(moments: finalMoments, type: .forYou, sync: true)

                    VideoPreloader.shared.preloadAssets(
                        urls: VideoPlaybackSelector.shared.preloadURLStrings(from: finalMoments)
                    )
                }
                LogConfig.log("🚀 ForYou feed loaded from BACKEND (\(finalMoments.count) moments)", category: "Feed")
                return
            }

            LogConfig.log("🔄 ForYou feed: fallback to LEGACY", category: "Feed")
            await MainActor.run {
                self.feedLoadedFromBackend[.forYou] = false
                self.backendCursors[.forYou] = nil
                self.backendReachedEnd[.forYou] = false
            }
            self.fetchForYouMomentsLegacy(userId: userId)
        }
    }

    /// Legacy forYou: discovery outside following graph
    private func fetchForYouMomentsLegacy(userId: String) {
        forYouLegacyGlobalStreamCursor = nil
        loadLegacyForYouPage(userId: userId, existingMomentIds: [], isInitialLoad: true) { [weak self] finalMoments in
            guard let self else { return }
            DispatchQueue.main.async {
                self.isLoading = false
                self.forYouMoments = finalMoments
                self.moments = finalMoments
                VideoMomentsIndex.shared.rebuild(from: finalMoments)
                self.saveFeedToCache(moments: finalMoments, type: .forYou, sync: true)
                VideoPreloader.shared.preloadAssets(
                    urls: VideoPlaybackSelector.shared.preloadURLStrings(from: finalMoments)
                )
            }
        } onFailure: { [weak self] error in
            DispatchQueue.main.async {
                self?.isLoading = false
                self?.errorMessage = error.localizedDescription
            }
        }
    }

    private func loadLegacyForYouPage(
        userId: String,
        existingMomentIds: Set<String>,
        isInitialLoad: Bool,
        onSuccess: @escaping ([Moment]) -> Void,
        onFailure: @escaping (Error) -> Void
    ) {
        firestoreService.fetchUserProfile(userId: userId) { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let user):
                let group = DispatchGroup()
                var followingIds = self.cachedFollowingIds
                var followerIds = Set<String>()

                if followingIds.isEmpty {
                    group.enter()
                    self.firestoreService.fetchFollowing(userId: userId) { followingResult in
                        if case .success(let followingUsers) = followingResult {
                            followingIds = Set(followingUsers.map(\.id))
                        }
                        group.leave()
                    }
                }

                group.enter()
                self.firestoreService.fetchFollowers(userId: userId) { followersResult in
                    if case .success(let followers) = followersResult {
                        followerIds = Set(followers.map(\.id))
                    }
                    group.leave()
                }

                group.notify(queue: .main) {
                    self.cachedFollowingIds = followingIds
                    let blockedUserIds = Set(user.blockedUsers)
                    let excludingAuthors = followingIds.union([userId]).union(blockedUserIds)
                    let streamCursor = isInitialLoad ? nil : self.forYouLegacyGlobalStreamCursor

                    ForYouDiscoveryService.loadDiscoveryAuthors(
                        viewerId: userId,
                        interests: user.interests,
                        followingIds: followingIds,
                        followerIds: followerIds,
                        blockedUserIds: blockedUserIds
                    ) { discovery in
                        let fetchGroup = DispatchGroup()
                        var authorMoments: [Moment] = []
                        var globalMoments: [Moment] = []

                        fetchGroup.enter()
                        self.firestoreService.fetchMomentsFromUsers(
                            userIds: discovery.authorIds,
                            perUserLimit: 8,
                            totalLimit: 120
                        ) { fetchResult in
                            if case .success(let moments) = fetchResult {
                                authorMoments = moments
                            }
                            fetchGroup.leave()
                        }

                        fetchGroup.enter()
                        ForYouDiscoveryService.fetchGlobalEveryoneMoments(
                            excludingAuthorIds: excludingAuthors,
                            excludingMomentIds: existingMomentIds,
                            globalStreamCursor: streamCursor
                        ) { moments, nextStreamCursor in
                            globalMoments = moments
                            self.forYouLegacyGlobalStreamCursor = nextStreamCursor ?? self.forYouLegacyGlobalStreamCursor
                            fetchGroup.leave()
                        }

                        fetchGroup.notify(queue: .main) {
                            var mergedById: [String: Moment] = [:]
                            for moment in authorMoments + globalMoments {
                                guard let momentId = moment.id else { continue }
                                guard !existingMomentIds.contains(momentId) else { continue }
                                mergedById[momentId] = moment
                            }

                            let merged = Array(mergedById.values)
                            self.filterMomentsForPrivacy(viewerId: userId, moments: merged) { visibleMoments in
                                let tuned = self.applyForYouClientTuning(
                                    moments: visibleMoments,
                                    followingIds: followingIds,
                                    viewerId: userId,
                                    preserveOrder: false
                                )
                                let finalMoments = isInitialLoad
                                    ? Array(tuned.prefix(60))
                                    : tuned
                                onSuccess(finalMoments)
                            }
                        }
                    }
                }

            case .failure(let error):
                onFailure(error)
            }
        }
    }

    private func fetchMomentsFromUsers(userIds: [String], userId: String, feedType: FeedType) {
        let limitPerUser = feedType == .forYou ? 8 : 12
        let totalLimit = feedType == .forYou ? 120 : 80

        firestoreService.fetchMomentsFromUsers(
            userIds: userIds,
            perUserLimit: limitPerUser,
            totalLimit: totalLimit
        ) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let fetchedMoments):
                let finalMoments: [Moment]
                switch feedType {
                case .following:
                    finalMoments = self.sortMomentsChronologically(fetchedMoments, limit: 40)
                case .forYou:
                    finalMoments = Array(self.applyForYouClientTuning(
                        moments: fetchedMoments,
                        followingIds: self.cachedFollowingIds,
                        viewerId: userId,
                        preserveOrder: false
                    ).prefix(60))
                }
            // Aplicar filtros de privacidad y actualizar UI
                self.filterMomentsForPrivacy(viewerId: userId, moments: finalMoments) { filteredMoments in
                DispatchQueue.main.async {
                        self.isLoading = false

                    switch feedType {
                    case .following:
                            self.followingMoments = filteredMoments
                    case .forYou:
                            self.forYouMoments = filteredMoments
                    }

                        self.moments = filteredMoments
                        VideoMomentsIndex.shared.rebuild(from: filteredMoments)

                    // ✅ OFFLINE: Guardar en caché para la próxima vez
                    // Como es el fetch inicial, usamos sync: true para limpiar momentos borrados
                        self.saveFeedToCache(moments: filteredMoments, type: feedType, sync: true)

                    // ✅ INSTANT PLAYBACK: Preload videos
                    VideoPreloader.shared.preloadAssets(
                        urls: VideoPlaybackSelector.shared.preloadURLStrings(from: filteredMoments)
                    )
                }
            }
            case .failure(let error):
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func fetchMoreMomentsFromUsers(userIds: [String], userId: String, feedType: FeedType) {
        let limitPerUser = feedType == .forYou ? 8 : 12
        let totalLimit = feedType == .forYou ? 120 : 80
        let existingMomentIds = Set(moments.compactMap { $0.id })

        firestoreService.fetchMomentsFromUsers(
            userIds: userIds,
            perUserLimit: limitPerUser,
            totalLimit: totalLimit
        ) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let fetchedMoments):
                let filteredNewMoments = fetchedMoments.filter { moment in
                    guard let momentId = moment.id else { return false }
                    return !existingMomentIds.contains(momentId)
                }
                let sortedNewMoments = filteredNewMoments.sorted { $0.timestamp > $1.timestamp }

                let finalSortedNewMoments: [Moment]
                switch feedType {
                case .following:
                    finalSortedNewMoments = sortedNewMoments
                case .forYou:
                    finalSortedNewMoments = self.applyForYouClientTuning(
                        moments: sortedNewMoments,
                        followingIds: self.cachedFollowingIds,
                        viewerId: userId,
                        preserveOrder: false
                    )
                }
                self.filterMomentsForPrivacy(viewerId: userId, moments: finalSortedNewMoments) { filteredMoments in
                DispatchQueue.main.async {
                        self.isLoadingMore = false

                    if feedType == .forYou {
                            self.forYouMoments.append(contentsOf: filteredMoments)
                            self.moments.append(contentsOf: filteredMoments)
                    } else {
                            self.followingMoments.append(contentsOf: filteredMoments)
                            self.moments.append(contentsOf: filteredMoments)
                    }

                    // ✅ INSTANT PLAYBACK: Preload videos
                    VideoPreloader.shared.preloadAssets(
                        urls: VideoPlaybackSelector.shared.preloadURLStrings(from: filteredMoments)
                    )
                }
            }
            case .failure:
                DispatchQueue.main.async {
                    self.isLoadingMore = false
                }
            }
        }
    }

    private func fetchMoreForYouMoments(userId: String) {
        let existingMomentIds = Set(moments.compactMap(\.id))
        loadLegacyForYouPage(
            userId: userId,
            existingMomentIds: existingMomentIds,
            isInitialLoad: false
        ) { [weak self] newMoments in
            guard let self else { return }
            DispatchQueue.main.async {
                self.isLoadingMore = false
                guard !newMoments.isEmpty else { return }
                self.forYouMoments.append(contentsOf: newMoments)
                self.moments.append(contentsOf: newMoments)
                self.saveFeedToCache(moments: self.forYouMoments, type: .forYou, sync: false)
                VideoPreloader.shared.preloadAssets(
                    urls: VideoPlaybackSelector.shared.preloadURLStrings(from: newMoments)
                )
            }
        } onFailure: { [weak self] _ in
            DispatchQueue.main.async {
                self?.isLoadingMore = false
            }
        }
    }

    // MARK: - Privacy Filter

    private func filterMomentsForPrivacy(viewerId: String, moments: [Moment], completion: @escaping ([Moment]) -> Void) {
         guard !viewerId.isEmpty, !moments.isEmpty else {
             completion([])
             return
         }

         let batchSize = 10
         var filteredMoments: [Moment] = []
         let cacheLock = NSLock()
         var decisionCache: [String: Bool] = [:]
         var inFlightDecisions: [String: [(Bool) -> Void]] = [:]

         func evaluateMomentAccess(_ moment: Moment, completion: @escaping (Bool) -> Void) {
             // Fast paths: no need to hit Firestore for these.
             if moment.authorId == viewerId {
                 completion(true)
                 return
             }

             let cacheKey = privacyDecisionCacheKey(for: moment, viewerId: viewerId)
 
              cacheLock.lock()
              if let cached = decisionCache[cacheKey] {
                  cacheLock.unlock()
                  completion(cached)
                  return
              }
 
              if inFlightDecisions[cacheKey] != nil {
                  inFlightDecisions[cacheKey]?.append(completion)
                  cacheLock.unlock()
                  return
              }
 
              inFlightDecisions[cacheKey] = [completion]
              cacheLock.unlock()
 
              let requestLock = NSLock()
              var didComplete = false
 
              func resolveRequest(_ canView: Bool) {
                  var callbacks: [(Bool) -> Void] = []
 
                  cacheLock.lock()
                  decisionCache[cacheKey] = canView
                  callbacks = inFlightDecisions[cacheKey] ?? []
                  inFlightDecisions[cacheKey] = nil
                  cacheLock.unlock()
 
                  callbacks.forEach { $0(canView) }
              }
 
              privacyService.canUserViewMomentEnhanced(moment, viewerId: viewerId) { canView in
                  requestLock.lock()
                  if didComplete {
                      requestLock.unlock()
                      return
                  }
                  didComplete = true
                  requestLock.unlock()
                  DispatchQueue.main.async {
                      resolveRequest(canView)
                  }
              }
 
              DispatchQueue.global().asyncAfter(deadline: .now() + 8) {
                  requestLock.lock()
                  if didComplete {
                      requestLock.unlock()
                      return
                  }
                  didComplete = true
                  requestLock.unlock()
                  DispatchQueue.main.async {
                      resolveRequest(false) // Fail closed on timeout.
                  }
              }
         }

         func processBatch(startIndex: Int) {
             let endIndex = min(startIndex + batchSize, moments.count)
             let batch = Array(moments[startIndex..<endIndex])

             let group = DispatchGroup()
             var visibleMomentIds = Set<String>()
             let syncQueue = DispatchQueue(label: "batch.results.sync")

             for moment in batch {
                 guard let momentId = moment.id, !momentId.isEmpty else { continue }

                 group.enter()

                  evaluateMomentAccess(moment) { canView in
                      if canView {
                          _ = syncQueue.sync {
                              visibleMomentIds.insert(momentId)
                          }
                      }
                      group.leave()
                  }
             }

             group.notify(queue: .main) {
                 let orderedBatchResults = batch.filter { moment in
                     guard let id = moment.id else { return false }
                     return visibleMomentIds.contains(id)
                 }
                 filteredMoments.append(contentsOf: orderedBatchResults)

                 if endIndex < moments.count {
                     processBatch(startIndex: endIndex)
                 } else {
                     completion(filteredMoments)
                 }
             }
         }

         processBatch(startIndex: 0)
     }

    private func privacyDecisionCacheKey(for moment: Moment, viewerId: String) -> String {
        let audience = moment.audience ?? "everyone"
        let base = "\(viewerId)|\(moment.authorId)|\(audience)"

        switch audience {
        case "custom":
            return "\(base)|moment:\(moment.id ?? "missing")"
        case "customList":
            if let customListId = moment.customListId, !customListId.isEmpty {
                return "\(base)|list:\(customListId)"
            }
            return "\(base)|moment:\(moment.id ?? "missing")"
        default:
            return base
        }
    }

    // MARK: - Listeners
    /// Limpia listeners y trabajo pendiente. Llamar desde `onDisappear` en vistas que crean un `FeedViewModel` efímero.
    func shutdown() {
        clearListeners()
        userListener?.remove()
        userListener = nil
    }

    private func clearListeners() {
        // Cancelar todos los updates pendientes
        self.pendingUpdates.values.forEach { $0.cancel() }
        self.pendingUpdates.removeAll()
        self.lastUpdateHashes.removeAll()

        // Remover listeners de forma segura
        self.momentListeners.values.forEach { $0.remove() }
        self.momentListeners.removeAll()
        self.commentListeners.values.forEach { $0.remove() }
        self.commentListeners.removeAll()
    }

    /// Mantiene listeners solo para momentos visibles en viewport (+ buffer de índices).
    func syncMomentListeners(visibilityByMomentId: [String: CGFloat]) {
        var eligibleIds = Set<String>()

        for (index, moment) in moments.enumerated() {
            guard let momentId = moment.id else { continue }
            let fraction = visibilityByMomentId[momentId] ?? 0
            guard fraction >= listenerVisibilityThreshold else { continue }

            let lowerBound = max(0, index - listenerIndexBuffer)
            let upperBound = min(moments.count - 1, index + listenerIndexBuffer)
            for bufferIndex in lowerBound...upperBound {
                if let bufferId = moments[bufferIndex].id {
                    eligibleIds.insert(bufferId)
                }
            }
        }

        for momentId in eligibleIds {
            guard let moment = moments.first(where: { $0.id == momentId }) else { continue }
            listenForCommentUpdates(momentId: momentId, authorId: moment.authorId)
        }

        let activeIds = Set(momentListeners.keys).union(Set(commentListeners.keys))
        for momentId in activeIds where !eligibleIds.contains(momentId) {
            removeMomentListeners(momentId: momentId)
        }
    }

    func listenForCommentUpdates(momentId: String, authorId: String) {
        if self.commentListeners[momentId] != nil || self.momentListeners[momentId] != nil {
            return
        }

        // ✅ VALIDAR: Solo crear listener si el usuario puede ver el momento
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }

        firestoreService.canViewContent(currentUserId: currentUserId, targetUserId: authorId) { [weak self] result in
            Task { @MainActor in
                guard let self = self else { return }
                switch result {
                case .success(let canView):
                    guard canView else { return } // No crear listener si no puede ver el momento

                    // ✅ Solo crear listener si tiene permisos
                    let commentListener = self.firestoreService.db.collection("users").document(authorId)
                        .collection("moments").document(momentId)
                        .collection("comments")
                        .addSnapshotListener { snapshot, error in
                            guard error == nil else { return }

                            Task { @MainActor in
                                NotificationCenter.default.post(
                                    name: NSNotification.Name("CommentAdded"),
                                    object: momentId
                                )
                            }
                        }

                    self.commentListeners[momentId] = commentListener

                case .failure(_):
                    return
                }
            }
        }

        if self.momentListeners[momentId] == nil {
            let momentListener = self.firestoreService.db.collection("users").document(authorId)
                .collection("moments").document(momentId)
                .addSnapshotListener { [weak self] document, error in
                    guard let self = self,
                          let document = document,
                          document.exists,
                          error == nil else {
                        return
                    }

                    Task { @MainActor in
                        // ✅ Pausa durante uploads para evitar conflictos
                        if self.isPausedForUploads {
                            return
                        }

                        do {
                            let documentID = document.documentID
                            guard !documentID.isEmpty else { return }

                            var updatedMoment = try document.data(as: Moment.self)
                            updatedMoment.id = documentID

                            // Si se archiva en tiempo real, retirarlo inmediatamente del feed.
                            if updatedMoment.isArchived == true {
                                self.moments.removeAll { $0.id == momentId }
                                self.followingMoments.removeAll { $0.id == momentId }
                                self.forYouMoments.removeAll { $0.id == momentId }
                                self.saveFeedToCache(moments: self.followingMoments, type: .following, sync: false)
                                self.saveFeedToCache(moments: self.forYouMoments, type: .forYou, sync: false)
                                return
                            }

                            // ✅ Solo actualizar si hay cambios significativos
                            guard self.shouldUpdateMoment(momentId: momentId, newMoment: updatedMoment) else {
                                return
                            }

                            // ✅ Debounce para agrupar múltiples updates
                            self.debouncedUpdateMoment(momentId: momentId, updatedMoment: updatedMoment)

                        } catch {
                        }
                    }
                }

            self.momentListeners[momentId] = momentListener
        }
    }

    private func shouldUpdateMoment(momentId: String, newMoment: Moment) -> Bool {
        // Buscar momento actual
        guard moments.first(where: { $0.id == momentId }) != nil else {
            return true // Es nuevo, siempre actualizar
        }

        // ✅ Generar hash de propiedades importantes para comparar
        let newHash = generateMomentHash(moment: newMoment)
        let currentHash = lastUpdateHashes[momentId] ?? 0

        // Solo actualizar si el hash cambió
        if newHash != currentHash {
            lastUpdateHashes[momentId] = newHash
            return true
        }

        return false
    }

    // ✅ Generar hash de propiedades importantes
    private func generateMomentHash(moment: Moment) -> Int {
        var hasher = Hasher()

        // ✅ Usar tu sistema de reactions en lugar de likes
        hasher.combine(moment.reactions.count) // Número total de reactions

        // ✅ Hash de cada tipo de reaction y su count
        for (reactionType, userIds) in moment.reactions.sorted(by: { $0.key < $1.key }) {
            hasher.combine(reactionType)
            hasher.combine(userIds.count) // Solo el count, no los IDs específicos
        }

        hasher.combine(moment.commentCount) // Tu campo commentCount
        hasher.combine(moment.content)
        hasher.combine(moment.timestamp.timeIntervalSince1970)

        // ✅ Incluir propiedades que podrían cambiar y afectar la UI
        hasher.combine(moment.imagePath)
        hasher.combine(moment.videoUrl)
        hasher.combine(moment.aspectRatio)
        hasher.combine(moment.hasHiddenLayers)
        hasher.combine(moment.hiddenLayerCount)

        return hasher.finalize()
    }

    // ✅ Update con debounce thread-safe
    private func debouncedUpdateMoment(momentId: String, updatedMoment: Moment) {
        // Cancelar update pendiente si existe
        self.pendingUpdates[momentId]?.cancel()

        // Crear nuevo update con delay
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            if let index = self.moments.firstIndex(where: { $0.id == momentId }) {
                self.moments[index] = updatedMoment

                // Actualizar caché correspondiente sin trigger adicional
                self.updateMomentInCache(momentId: momentId, updatedMoment: updatedMoment)
            }

            // Limpiar trabajo completado
            self.pendingUpdates.removeValue(forKey: momentId)
        }

        self.pendingUpdates[momentId] = workItem

        // Ejecutar después del debounce time
        DispatchQueue.main.asyncAfter(deadline: .now() + self.updateDebounceTime, execute: workItem)
    }

    // ✅ Actualizar caché sin trigger re-renders adicionales
    private func updateMomentInCache(momentId: String, updatedMoment: Moment) {
        if currentFeedType == .following {
            if let cacheIndex = followingMoments.firstIndex(where: { $0.id == momentId }) {
                followingMoments[cacheIndex] = updatedMoment
            }
        } else {
            if let cacheIndex = forYouMoments.firstIndex(where: { $0.id == momentId }) {
                forYouMoments[cacheIndex] = updatedMoment
            }
        }
    }

    // ✅ Pausar listeners durante uploads
    func pauseListenersForUpload() {
        isPausedForUploads = true

        // Auto-resume después de 10 segundos (safety)
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.resumeListenersAfterUpload()
        }
    }

    // ✅ Reanudar listeners después de upload
    func resumeListenersAfterUpload() {
        isPausedForUploads = false
    }

    // MARK: - User Data

    func fetchUserData(userId: String) {
        userListener?.remove()
        userListener = firestoreService.db.collection("users").document(userId)
            .addSnapshotListener { document, error in
                guard let data = document?.data(), error == nil else { return }

                DispatchQueue.main.async {
                    self.userProfileImage = data["profileImagePath"] as? String
                }
            }
    }

    func fetchConnections(userId: String) {
        firestoreService.fetchConnections(userId: userId) { _ in }
    }

    func removeCommentListener(momentId: String) {
        if let listener = self.commentListeners[momentId] {
            listener.remove()
            self.commentListeners.removeValue(forKey: momentId)
        }
    }

    func removeMomentListeners(momentId: String) {
        removeCommentListener(momentId: momentId)

        if let listener = momentListeners[momentId] {
            listener.remove()
            momentListeners.removeValue(forKey: momentId)
        }

        pendingUpdates[momentId]?.cancel()
        pendingUpdates.removeValue(forKey: momentId)
        lastUpdateHashes.removeValue(forKey: momentId)
    }

    func fetchAdmirers(userId: String) {
        firestoreService.fetchAdmirers(userId: userId) { result in
            if case .success(let admirers) = result {
                DispatchQueue.main.async {
                    self.admirers = admirers
                }
            }
        }
    }

    // MARK: - Stories (if needed)

    func filterStoriesForVisibility(viewerId: String, stories: [Story], completion: @escaping ([Story]) -> Void) {
        let group = DispatchGroup()
        var filteredStories: [Story] = []
        let syncQueue = DispatchQueue(label: "story.filter.sync")

        for story in stories {
            group.enter()

            privacyService.canUserViewStoryEnhanced(story, viewerId: viewerId) { canSee in
                if canSee {
                    syncQueue.async {
                        filteredStories.append(story)
                    }
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            let orderedFilteredStories = stories.filter { originalStory in
                filteredStories.contains { $0.id == originalStory.id }
            }
            completion(orderedFilteredStories)
        }
    }
}




// MARK: - Extensions

extension FeedViewModel {
    func resetFeedPreferences() {
        UserDefaults.standard.removeObject(forKey: "selectedFeedType")
    }

    func trackFeedUsage() {
        _ = UserDefaults.standard.selectedFeedType
    }
}
