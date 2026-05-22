import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseCore

// MARK: - Activity Summary (counters + previews for the main screen)

struct ThumbInfo: Identifiable {
    let id: String           // thumbnail url (or videoUrl) used as id
    let url: String          // static thumbnail URL (image or video still)
    let videoUrl: String?    // set only for video moments without a static thumbnail
    let isProtected: Bool    // audience != "everyone" → ScreenshotProtectedView
    let canView: Bool        // false → blur + lock icon
}

struct ActivityCategorySummary {
    let count: Int
    let thumbnails: [ThumbInfo]
}

final class ActivityInteractionDetailViewModel: ObservableObject, @unchecked Sendable {
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var reactionItems: [ActivityReactionItem] = []
    @Published var commentItems: [ActivityCommentItem] = []
    @Published var events: [ActivityEventItem] = []
    @Published var deletedStoryItems: [ActivityDeletedStoryItem] = []
    @Published var moments: [Moment] = [] // ✅ NUEVO: Para Moments y Reels (estilo ProfileView)
    @Published var customListNamesById: [String: String] = [:] // ✅ NUEVO: Para resolver audiencias custom

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private let category: ActivityInteractionCategory
    private let recentlyDeletedKind: RecentlyDeletedContentKind
    private let db = Firestore.firestore()
    private var didLoadOnce = false
    private var reactionsNextCursor: BackendReactionsCursor?
    private var commentsNextCursor: BackendCommentsCursor?

    init(category: ActivityInteractionCategory, recentlyDeletedKind: RecentlyDeletedContentKind = .moments) {
        self.category = category
        self.recentlyDeletedKind = recentlyDeletedKind
    }

    func loadIfNeeded() {
        guard !didLoadOnce else { return }
        didLoadOnce = true
        reload()
    }

    func reload() {
        guard let userId = Auth.auth().currentUser?.uid else {
            errorMessage = NSLocalizedString("messaging.error.notAuthenticated", comment: "Not authenticated")
            return
        }

        isLoading = true
        errorMessage = nil

        switch category {
        case .reactions:
            loadReactions(for: userId)
        case .comments:
            loadComments(for: userId)
        case .tags:
            loadTags(for: userId)
        case .stickerReplies:
            loadStickerReplies(for: userId)
        case .archived:
            loadArchived(for: userId)
        case .storiesArchive:
            self.reactionItems = []
            self.commentItems = []
            self.events = []
            self.isLoading = false
        case .recentlyDeleted:
            loadRecentlyDeleted(for: userId)
        case .moments:
            fetchCustomAudienceListNames(userId: userId) { [weak self] in
                self?.loadMoments(for: userId)
            }
        case .reels:
            fetchCustomAudienceListNames(userId: userId) { [weak self] in
                self?.loadReels(for: userId)
            }
        case .echoes:
            loadEchoes(for: userId)
        case .followers:
            loadFollowers(for: userId)
        case .visits:
            loadVisits(for: userId)
        case .timeSpent, .searches, .accountHistory:
            self.isLoading = false
        }
    }

    func removeReactions(withIds ids: Set<String>) async -> Result<Void, Error> {
        guard !ids.isEmpty else { return .success(()) }
        guard let currentUserId = Auth.auth().currentUser?.uid, !currentUserId.isEmpty else {
            return .failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("messaging.error.notAuthenticated", comment: "Not authenticated")]))
        }

        let targets = reactionItems.filter { ids.contains($0.id) }
        guard !targets.isEmpty else { return .success(()) }

        let batch = db.batch()
        for item in targets {
            let ref = db.collection("users")
                .document(item.authorId)
                .collection("moments")
                .document(item.momentId)
                .collection("reactions")
                .document(currentUserId)
            batch.deleteDocument(ref)
        }

        do {
            try await batch.commit()

            await MainActor.run {
                self.reactionItems.removeAll { ids.contains($0.id) }
            }
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    func removeComments(withIds ids: Set<String>) async -> Result<Void, Error> {
        guard !ids.isEmpty else { return .success(()) }
        guard Auth.auth().currentUser?.uid != nil else {
            return .failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("messaging.error.notAuthenticated", comment: "Not authenticated")]))
        }

        let targets = commentItems.filter { ids.contains($0.id) }
        guard !targets.isEmpty else { return .success(()) }

        do {
            try await deleteCommentsBatch(targets)
            await MainActor.run {
                self.commentItems.removeAll { ids.contains($0.id) }
            }
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    func removeTags(withIds ids: Set<String>) async -> Result<Void, Error> {
        guard !ids.isEmpty else { return .success(()) }
        guard let currentUser = Auth.auth().currentUser else {
            return .failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("messaging.error.notAuthenticated", comment: "Not authenticated")]))
        }

        let targets = reactionItems
            .filter { ids.contains($0.id) }
            .map { ["authorId": $0.authorId, "momentId": $0.momentId] }
        guard !targets.isEmpty else { return .success(()) }

        do {
            let idToken = try await currentUser.getIDToken()
            guard let projectId = FirebaseApp.app()?.options.projectID, !projectId.isEmpty else {
                return .failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing Firebase project ID"]))
            }

            guard let url = URL(string: "https://europe-southwest1-\(projectId).cloudfunctions.net/removeMyTagsBatch") else {
                return .failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid backend URL"]))
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 20
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["moments": targets])

            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid backend response"]))
            }
            guard http.statusCode == 200 else {
                return .failure(NSError(domain: "", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Backend error \(http.statusCode)"]))
            }

            await MainActor.run {
                self.reactionItems.removeAll { ids.contains($0.id) }
            }
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    func removeStickerReplies(withIds ids: Set<String>) async -> Result<Void, Error> {
        guard !ids.isEmpty else { return .success(()) }
        guard let currentUserId = Auth.auth().currentUser?.uid, !currentUserId.isEmpty else {
            return .failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("messaging.error.notAuthenticated", comment: "Not authenticated")]))
        }

        let targets = events.filter { ids.contains($0.id) }
        guard !targets.isEmpty else { return .success(()) }

        let payload = targets.compactMap { item -> [String: String]? in
            guard let kind = item.kind, !kind.isEmpty,
                  let authorId = item.targetAuthorId, !authorId.isEmpty,
                  let storyId = item.storyId, !storyId.isEmpty else {
                return nil
            }
            var map: [String: String] = [
                "kind": kind,
                "authorId": authorId,
                "storyId": storyId
            ]
            if let sourceId = item.sourceId, !sourceId.isEmpty {
                map["sourceId"] = sourceId
            }
            return map
        }

        guard !payload.isEmpty else { return .success(()) }

        do {
            guard let currentUser = Auth.auth().currentUser else {
                return .failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("messaging.error.notAuthenticated", comment: "Not authenticated")]))
            }
            let idToken = try await currentUser.getIDToken()
            guard let projectId = FirebaseApp.app()?.options.projectID, !projectId.isEmpty else {
                return .failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing Firebase project ID"]))
            }
            guard let url = URL(string: "https://europe-southwest1-\(projectId).cloudfunctions.net/removeMyStickerRepliesBatch") else {
                return .failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid backend URL"]))
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 20
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["replies": payload])

            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid backend response"]))
            }
            guard http.statusCode == 200 else {
                return .failure(NSError(domain: "", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Backend error \(http.statusCode)"]))
            }

            await MainActor.run {
                self.events.removeAll { ids.contains($0.id) }
            }
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    func restoreSelection(withIds ids: Set<String>) async -> Result<Void, Error> {
        guard !ids.isEmpty else { return .success(()) }
        guard let userId = Auth.auth().currentUser?.uid else {
            return .failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("messaging.error.notAuthenticated", comment: "Not authenticated")]))
        }

        do {
            if category == .recentlyDeleted && recentlyDeletedKind == .stories {
                let storyRepository = StoryRepository(firestoreService: FirestoreService.shared)
                for id in ids {
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                        storyRepository.restoreStory(userId: userId, storyId: id) { error in
                            if let error {
                                continuation.resume(throwing: error)
                            } else {
                                continuation.resume()
                            }
                        }
                    }
                }
            } else {
                for id in ids {
                    try await FirestoreService.shared.restoreMoment(momentId: id, userId: userId)
                }
            }
            await MainActor.run {
                self.reactionItems.removeAll { ids.contains($0.id) }
                self.deletedStoryItems.removeAll { ids.contains($0.id) }
                ActivityCache.saveRecentlyDeletedCount(self.reactionItems.count + self.deletedStoryItems.count, userId: userId)
            }
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    func permanentlyDeleteSelection(withIds ids: Set<String>) async -> Result<Void, Error> {
        guard !ids.isEmpty else { return .success(()) }
        guard let userId = Auth.auth().currentUser?.uid else {
            return .failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("messaging.error.notAuthenticated", comment: "Not authenticated")]))
        }

        do {
            try await FirestoreService.shared.permanentlyDeleteRecentlyDeleted(ids: Array(ids))
            await MainActor.run {
                self.reactionItems.removeAll { ids.contains($0.id) }
                self.deletedStoryItems.removeAll { ids.contains($0.id) }
                if category == .recentlyDeleted {
                    ActivityCache.saveRecentlyDeletedCount(self.reactionItems.count + self.deletedStoryItems.count, userId: userId)
                }
            }
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    func unarchiveSelection(withIds ids: Set<String>) async -> Result<Void, Error> {
        guard !ids.isEmpty else { return .success(()) }
        guard let userId = Auth.auth().currentUser?.uid else {
            return .failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("messaging.error.notAuthenticated", comment: "Not authenticated")]))
        }

        do {
            for id in ids {
                try await FirestoreService.shared.unarchiveMoment(momentId: id, userId: userId)
            }
            await MainActor.run {
                self.reactionItems.removeAll { ids.contains($0.id) }
            }
            return .success(())
        } catch {
            return .failure(error)
        }
    }


    private func loadReactions(for userId: String) {
        Task { [weak self] in
            guard let self = self else { return }

            do {
                let page = try await self.fetchReactedMomentsPage(limit: 36, cursor: nil)
                let sorted = page.items.sorted { $0.reactedAt > $1.reactedAt }
                ActivityCache.saveReactions(sorted, userId: userId)
                DispatchQueue.main.async {
                    self.reactionItems = sorted
                    self.reactionsNextCursor = page.nextCursor
                    self.commentItems = []
                    self.events = []
                    self.isLoading = false
                }
            } catch {
                let cached = ActivityCache.loadReactions(userId: userId).filter { $0.moment?.isArchived != true }
                DispatchQueue.main.async {
                    if !cached.isEmpty {
                        self.reactionItems = cached
                        self.commentItems = []
                        self.events = []
                        self.isLoading = false
                    } else {
                        self.isLoading = false
                        self.errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }

    private func loadComments(for userId: String) {
        Task { [weak self] in
            guard let self = self else { return }

            do {
                let page = try await self.fetchCommentedMomentsPage(limit: 36, cursor: nil)
                let sorted = page.items.sorted { $0.commentedAt > $1.commentedAt }
                ActivityCache.saveComments(sorted, userId: userId)
                DispatchQueue.main.async {
                    self.commentItems = sorted
                    self.commentsNextCursor = page.nextCursor
                    self.reactionItems = []
                    self.events = []
                    self.isLoading = false
                }
            } catch {
                let cached = ActivityCache.loadComments(userId: userId).filter { $0.moment?.isArchived != true }
                DispatchQueue.main.async {
                    if !cached.isEmpty {
                        self.commentItems = cached
                        self.reactionItems = []
                        self.events = []
                        self.isLoading = false
                    } else {
                        self.isLoading = false
                        self.errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }

    private func loadTags(for userId: String) {
        Task { [weak self] in
            guard let self = self else { return }
            do {
                let page = try await self.fetchTaggedMomentsPage(limit: 60, cursor: nil)
                let mapped: [ActivityReactionItem] = page.items.compactMap { item in
                    let moment = item.moment.toMoment()
                    guard moment.isArchived != true else { return nil }
                    let timestamp = item.taggedAt.map { Date(timeIntervalSince1970: $0 / 1000) } ?? moment.timestamp
                    let authorId = item.authorId ?? moment.authorId
                    guard let momentId = item.momentId ?? moment.id,
                          !authorId.isEmpty, !momentId.isEmpty else { return nil }
                    return ActivityReactionItem(
                        id: "\(authorId)_\(momentId)",
                        authorId: authorId,
                        momentId: momentId,
                        reactionType: "tagged",
                        reactedAt: timestamp,
                        moment: moment,
                        canView: true
                    )
                }
                DispatchQueue.main.async {
                    let sorted = mapped.sorted { $0.reactedAt > $1.reactedAt }
                    if let uid = FirebaseAuth.Auth.auth().currentUser?.uid {
                        ActivityCache.saveTagged(sorted, userId: uid)
                    }
                    self.reactionItems = sorted
                    self.commentItems = []
                    self.events = []
                    self.isLoading = false
                }
            } catch {
                self.loadTagsLegacy(for: userId)
            }
        }
    }

    private func loadTagsLegacy(for userId: String) {
        db.collectionGroup("moments")
            .whereField("taggedUsers", arrayContains: userId)
            .getDocuments { [weak self] snapshot, error in
                guard let self = self else { return }
                if let _ = error {
                    DispatchQueue.main.async {
                        self.reactionItems = []
                        self.commentItems = []
                        self.events = []
                        self.isLoading = false
                    }
                    return
                }

                let mapped: [ActivityReactionItem] = snapshot?.documents.compactMap { doc in
                    guard let moment = try? doc.data(as: Moment.self) else { return nil }
                    guard moment.isArchived != true else { return nil }
                    let authorId = moment.authorId
                    guard let momentId = moment.id, !authorId.isEmpty, !momentId.isEmpty else { return nil }
                    return ActivityReactionItem(
                        id: "\(authorId)_\(momentId)",
                        authorId: authorId,
                        momentId: momentId,
                        reactionType: "tagged",
                        reactedAt: moment.timestamp,
                        moment: moment,
                        canView: true
                    )
                } ?? []

                DispatchQueue.main.async {
                    let sorted = mapped.sorted { $0.reactedAt > $1.reactedAt }
                    if let uid = FirebaseAuth.Auth.auth().currentUser?.uid {
                        ActivityCache.saveTagged(sorted, userId: uid)
                    }
                    self.reactionItems = sorted
                    self.commentItems = []
                    self.events = []
                    self.isLoading = false
                }
        }
    }

    private func loadRecentlyDeleted(for userId: String) {
        Task { [weak self] in
            guard let self = self else { return }
            do {
                let snapshot = try await db.collection("users").document(userId).collection("recentlyDeleted")
                    .order(by: "deletedAt", descending: true)
                    .limit(to: 50)
                    .getDocuments()

                let momentItems: [ActivityReactionItem] = snapshot.documents.compactMap { doc in
                    let data = doc.data()
                    let type = (data["type"] as? String)?.lowercased() ?? "moment"
                    guard type != "story" else { return nil }
                    let timestamp = (data["deletedAt"] as? Timestamp)?.dateValue() ?? Date()

                    guard let moment = try? doc.data(as: Moment.self) else { return nil }
                    return ActivityReactionItem(
                        id: doc.documentID,
                        authorId: userId,
                        momentId: doc.documentID,
                        reactionType: "deleted_moment",
                        reactedAt: timestamp,
                        moment: moment,
                        canView: true
                    )
                }

                let storyItems: [ActivityDeletedStoryItem] = snapshot.documents.compactMap { doc in
                    let data = doc.data()
                    let type = (data["type"] as? String)?.lowercased() ?? ""
                    guard type == "story" else { return nil }
                    let timestamp = (data["deletedAt"] as? Timestamp)?.dateValue() ?? Date()
                    guard let story = try? doc.data(as: Story.self) else { return nil }
                    return ActivityDeletedStoryItem(id: doc.documentID, story: story, deletedAt: timestamp)
                }

                DispatchQueue.main.async {
                    self.reactionItems = self.recentlyDeletedKind == .moments ? momentItems : []
                    self.deletedStoryItems = self.recentlyDeletedKind == .stories ? storyItems : []
                    self.commentItems = []
                    self.events = []
                    self.isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func loadArchived(for userId: String) {
        FirestoreService.shared.fetchArchivedMoments(userId: userId) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let moments):
                let mapped: [ActivityReactionItem] = moments.compactMap { moment in
                    guard let id = moment.id else { return nil }
                    return ActivityReactionItem(
                        id: id,
                        authorId: moment.authorId,
                        momentId: id,
                        reactionType: "archived",
                        reactedAt: moment.archivedAt ?? moment.timestamp,
                        moment: moment,
                        canView: true
                    )
                }
                DispatchQueue.main.async {
                    self.reactionItems = mapped
                    self.commentItems = []
                    self.events = []
                    self.isLoading = false
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    self.isLoading = false
                    if self.moments.isEmpty {
                        self.errorMessage = error.localizedDescription
                    } else {
                        self.errorMessage = nil
                    }
                }
            }
        }
    }

    private func fetchCustomAudienceListNames(userId: String, completion: (() -> Void)? = nil) {
        FirestoreService.shared.fetchCustomLists(for: userId) { [weak self] result in
            guard let self = self else {
                completion?()
                return
            }
            guard case .success(let lists) = result else {
                completion?()
                return
            }

            let map = lists.reduce(into: [String: String]()) { partialResult, list in
                guard let id = list.id else { return }
                partialResult[id] = list.name
            }

            DispatchQueue.main.async {
                self.customListNamesById = map
                completion?()
            }
        }
    }

    private func loadMoments(for userId: String) {
        // 1. Load from local cache for immediate UI
        Task { @MainActor in
            let cached = LocalPersistenceService.shared.loadProfileMoments(userId: userId)
            let filtered = cached.filter { moment in
                let isArchived = moment.isArchived ?? false
                let isReel = moment.isReelCandidate
                return !isArchived && !isReel
            }

            await MainActor.run {
                if !filtered.isEmpty {
                    self.moments = filtered
                    self.isLoading = false
                }
            }
        }

        // 2. Fetch from Firestore
        FirestoreService.shared.fetchMoments(for: userId) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let moments):
                Task { @MainActor in
                    LocalPersistenceService.shared.saveProfileMoments(moments, userId: userId, sync: true)
                }

                let filtered = moments.filter { moment in
                    let isArchived = moment.isArchived ?? false
                    let isReel = moment.isReelCandidate
                    return !isArchived && !isReel
                }

                DispatchQueue.main.async {
                    self.moments = filtered
                    self.reactionItems = []
                    self.commentItems = []
                    self.events = []
                    self.isLoading = false
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    self.isLoading = false
                    if self.moments.isEmpty {
                        self.errorMessage = error.localizedDescription
                    } else {
                        self.errorMessage = nil
                    }
                }
            }
        }
    }

    private func loadReels(for userId: String) {
        // 1. Load from local cache
        Task { @MainActor in
            let cached = LocalPersistenceService.shared.loadProfileMoments(userId: userId)
            let filtered = cached.filter { moment in
                let isArchived = moment.isArchived ?? false
                let isReel = moment.isReelCandidate
                return !isArchived && isReel
            }

            await MainActor.run {
                if !filtered.isEmpty {
                    self.moments = filtered
                    self.isLoading = false
                }
            }
        }

        // 2. Fetch from Firestore
        FirestoreService.shared.fetchMoments(for: userId) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let moments):
                Task { @MainActor in
                    LocalPersistenceService.shared.saveProfileMoments(moments, userId: userId, sync: true)
                }

                let filtered = moments.filter { moment in
                    let isArchived = moment.isArchived ?? false
                    let isReel = moment.isReelCandidate
                    return !isArchived && isReel
                }

                DispatchQueue.main.async {
                    self.moments = filtered
                    self.reactionItems = []
                    self.commentItems = []
                    self.events = []
                    self.isLoading = false
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func mapMomentsToReactionItems(_ moments: [Moment], type: String) -> [ActivityReactionItem] {
        moments.compactMap { moment in
            guard let id = moment.id else { return nil }
            return ActivityReactionItem(
                id: id,
                authorId: moment.authorId,
                momentId: id,
                reactionType: type,
                reactedAt: moment.timestamp,
                moment: moment,
                canView: true
            )
        }
    }

    private func loadEchoes(for userId: String) {
        _ = EchoService.shared.fetchEchoHistory(userId: userId) { [weak self] echoes in
            guard let self = self else { return }

            let mapped: [ActivityEventItem] = echoes.compactMap { (echo: Echo) -> ActivityEventItem? in
                guard let id = echo.id else { return nil }

                let participantsCount = echo.participants.count
                let locationName = echo.locationName ?? NSLocalizedString("echo.unknownLocation", comment: "Unknown location")
                let title = locationName

                let thumbnailUrl = echo.moments.last?.thumbnailUrl ?? echo.moments.last?.mediaUrl

                return ActivityEventItem(
                    id: id,
                    title: title,
                    subtitle: "",
                    timestamp: echo.createdAt,
                    icon: "waveform.and.mic",
                    kind: "echo",
                    sourceId: id,
                    thumbnailUrl: thumbnailUrl,
                    echoStatusRaw: echo.status.rawValue,
                    echoParticipantsCount: participantsCount,
                    echoExpiresAt: echo.expiresAt
                )
            }.sorted { $0.timestamp > $1.timestamp }

            DispatchQueue.main.async {
                self.events = mapped
                self.isLoading = false
            }
        }
    }

    private func loadFollowers(for userId: String) {
        Task {
            do {
                let items = try await FirestoreService.shared.fetchFollowersWithTimestamps(userId: userId)
                let mapped: [ActivityEventItem] = items.map { item in
                    let dateString = self.dateFormatter.string(from: item.timestamp)
                    let subtitle = String(format: NSLocalizedString("userActivity.event.follow.subtitle", comment: ""), dateString)

                    return ActivityEventItem(
                        id: item.user.id,
                        title: item.user.username,
                        subtitle: subtitle,
                        timestamp: item.timestamp,
                        icon: "person.badge.plus",
                        actorId: item.user.id,
                        actorUsername: item.user.username,
                        actorProfileImagePath: item.user.profileImagePath,
                        actionText: NSLocalizedString("userActivity.event.action.viewProfile", comment: "View profile"),
                        kind: "follower"
                    )
                }

                await MainActor.run {
                    self.events = mapped
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    print("Error loading followers for activity: \(error)")
                }
            }
        }
    }

    private func loadVisits(for userId: String) {
        Task {
            do {
                let items = try await FirestoreService.shared.fetchVisitsWithUsers(userId: userId)
                // Deduplicate visits by user, keeping the latest one
                var latestVisits: [String: ActivityEventItem] = [:]

                for item in items {
                    let actorId = item.user.id
                    let dateString = self.dateFormatter.string(from: item.visit.timestamp)
                    let subtitle = String(format: NSLocalizedString("userActivity.event.visit.subtitle", comment: ""), dateString)

                    let event = ActivityEventItem(
                        id: item.visit.id ?? UUID().uuidString,
                        title: item.user.username,
                        subtitle: subtitle,
                        timestamp: item.visit.timestamp,
                        icon: "eye",
                        actorId: actorId,
                        actorUsername: item.user.username,
                        actorProfileImagePath: item.user.profileImagePath,
                        actionText: NSLocalizedString("userActivity.event.action.viewProfile", comment: "View profile"),
                        kind: "visit"
                    )

                    if let existing = latestVisits[actorId] {
                        if event.timestamp > existing.timestamp {
                            latestVisits[actorId] = event
                        }
                    } else {
                        latestVisits[actorId] = event
                    }
                }

                let sortedEvents = latestVisits.values.sorted { $0.timestamp > $1.timestamp }

                await MainActor.run {
                    self.events = sortedEvents
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    print("Error loading visits for activity: \(error)")
                }
            }
        }
    }

    private func loadStickerReplies(for _: String) {
        Task {
            do {
                let page = try await self.fetchStickerRepliesPage(limit: 80, cursor: nil)
                let mapped: [ActivityEventItem] = page.items.compactMap { item in
                    let timestamp = item.timestamp.map { Date(timeIntervalSince1970: $0 / 1000) } ?? Date()
                    let kind = item.kind.lowercased()
                    let actorName = (item.actorUsername ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let displayName = actorName.isEmpty
                        ? NSLocalizedString("userActivity.simple.stickers.actorFallback", comment: "Sticker actor fallback")
                        : actorName

                    if kind == "poll" {
                        let optionText = (item.pollOptionText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        let optionFallback: String
                        if let option = item.pollOption {
                            optionFallback = String(
                                format: NSLocalizedString("userActivity.simple.stickers.poll.optionFallback", comment: "Poll option fallback"),
                                option + 1
                            )
                        } else {
                            optionFallback = ""
                        }
                        let resolvedOptionText = optionText.isEmpty ? optionFallback : optionText
                        let subtitle = resolvedOptionText.isEmpty
                            ? NSLocalizedString("userActivity.simple.stickers.poll.subtitleFallback", comment: "Poll response fallback")
                            : String(format: NSLocalizedString("userActivity.simple.stickers.poll.subtitle", comment: "Poll response subtitle"), resolvedOptionText)
                        return ActivityEventItem(
                            id: "event_poll_\(item.id)",
                            title: displayName,
                            subtitle: subtitle,
                            timestamp: timestamp,
                            icon: "checkmark.circle.fill",
                            actorId: item.actorId,
                            actorUsername: item.actorUsername,
                            actorProfileImagePath: item.actorProfileImagePath,
                            actionText: NSLocalizedString("userActivity.simple.stickers.poll.action", comment: "Poll response action"),
                            kind: "poll",
                            targetAuthorId: item.authorId,
                            targetUsername: item.targetUsername,
                            storyId: item.storyId,
                            sourceId: item.sourceId,
                            contextText: String(
                                format: NSLocalizedString("userActivity.simple.stickers.poll.context", comment: "Poll context"),
                                (item.targetUsername ?? "").isEmpty
                                    ? NSLocalizedString("onlineStatus.unknown", comment: "Unknown")
                                    : (item.targetUsername ?? "")
                            )
                        )
                    }

                    if kind == "question" {
                        let questionText = (item.questionText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        let responseText = (item.responseText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        let subtitle: String
                        if !responseText.isEmpty {
                            subtitle = responseText
                        } else if !questionText.isEmpty {
                            subtitle = questionText
                        } else {
                            subtitle = NSLocalizedString("userActivity.simple.stickers.question.subtitleFallback", comment: "Question response fallback")
                        }
                        return ActivityEventItem(
                            id: "event_question_\(item.id)",
                            title: displayName,
                            subtitle: subtitle,
                            timestamp: timestamp,
                            icon: "questionmark.bubble.fill",
                            actorId: item.actorId,
                            actorUsername: item.actorUsername,
                            actorProfileImagePath: item.actorProfileImagePath,
                            actionText: NSLocalizedString("userActivity.simple.stickers.question.action", comment: "Question response action"),
                            kind: "question",
                            targetAuthorId: item.authorId,
                            targetUsername: item.targetUsername,
                            storyId: item.storyId,
                            sourceId: item.sourceId,
                            contextText: String(
                                format: NSLocalizedString("userActivity.simple.stickers.question.context", comment: "Question context"),
                                (item.targetUsername ?? "").isEmpty
                                    ? NSLocalizedString("onlineStatus.unknown", comment: "Unknown")
                                    : (item.targetUsername ?? "")
                            )
                        )
                    }

                    return nil
                }

                DispatchQueue.main.async {
                    let sorted = mapped.sorted { $0.timestamp > $1.timestamp }
                    if let uid = FirebaseAuth.Auth.auth().currentUser?.uid {
                        ActivityCache.saveStickerReplyCount(sorted.count, userId: uid)
                    }
                    self.events = sorted
                    self.reactionItems = []
                    self.commentItems = []
                    self.isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    if let uid = FirebaseAuth.Auth.auth().currentUser?.uid {
                        ActivityCache.saveStickerReplyCount(0, userId: uid)
                    }
                    self.events = []
                    self.reactionItems = []
                    self.commentItems = []
                    self.isLoading = false
                    self.errorMessage = NSLocalizedString("userActivity.simple.empty.stickers", comment: "No sticker replies")
                }
            }
        }
    }

    private func fetchReactedMomentsPage(limit: Int, cursor: BackendReactionsCursor?) async throws -> (items: [ActivityReactionItem], nextCursor: BackendReactionsCursor?) {
        guard let currentUser = Auth.auth().currentUser else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("messaging.error.notAuthenticated", comment: "Not authenticated")])
        }

        let idToken = try await currentUser.getIDToken()
        guard let projectId = FirebaseApp.app()?.options.projectID, !projectId.isEmpty else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing Firebase project ID"])
        }

        guard let url = URL(string: "https://europe-southwest1-\(projectId).cloudfunctions.net/getReactedMomentsPage") else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid backend URL"])
        }

        var payload: [String: Any] = ["limit": limit]
        if let cursor = cursor {
            payload["cursor"] = ["timestamp": cursor.timestamp]
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid backend response"])
        }
        guard http.statusCode == 200 else {
            throw NSError(domain: "", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Backend error \(http.statusCode)"])
        }

        let decoded = try JSONDecoder().decode(BackendReactionsResponse.self, from: data)
        let mapped: [ActivityReactionItem] = decoded.items.compactMap { item in
            let moment = item.moment.toMoment()
            guard moment.isArchived != true else { return nil }
            let resolvedAuthorId = item.authorId ?? moment.authorId
            let resolvedMomentId = item.momentId ?? moment.id
            guard let resolvedMomentId, !resolvedMomentId.isEmpty else { return nil }

            let reactedAtDate = item.reactedAt.map { Date(timeIntervalSince1970: $0 / 1000) } ?? moment.timestamp

            return ActivityReactionItem(
                id: "\(resolvedAuthorId)_\(resolvedMomentId)",
                authorId: resolvedAuthorId,
                momentId: resolvedMomentId,
                reactionType: item.reactionType,
                reactedAt: reactedAtDate,
                moment: moment,
                canView: item.canView ?? true
            )
        }

        return (mapped, decoded.nextCursor)
    }

    private func fetchCommentedMomentsPage(limit: Int, cursor: BackendCommentsCursor?) async throws -> (items: [ActivityCommentItem], nextCursor: BackendCommentsCursor?) {
        guard let currentUser = Auth.auth().currentUser else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("messaging.error.notAuthenticated", comment: "Not authenticated")])
        }

        let idToken = try await currentUser.getIDToken()
        guard let projectId = FirebaseApp.app()?.options.projectID, !projectId.isEmpty else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing Firebase project ID"])
        }

        guard let url = URL(string: "https://europe-southwest1-\(projectId).cloudfunctions.net/getCommentedMomentsPage") else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid backend URL"])
        }

        var payload: [String: Any] = ["limit": limit]
        if let cursor = cursor {
            payload["cursor"] = ["timestamp": cursor.timestamp]
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid backend response"])
        }
        guard http.statusCode == 200 else {
            throw NSError(domain: "", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Backend error \(http.statusCode)"])
        }

        let decoded = try JSONDecoder().decode(BackendCommentsResponse.self, from: data)
        let mapped: [ActivityCommentItem] = decoded.items.compactMap { item in
            let moment = item.moment.toMoment()
            guard moment.isArchived != true else { return nil }
            let resolvedAuthorId = item.authorId ?? moment.authorId
            let resolvedMomentId = item.momentId ?? moment.id
            let resolvedCommentId = item.commentId ?? item.comment?.id
            guard let resolvedMomentId, !resolvedMomentId.isEmpty,
                  let resolvedCommentId, !resolvedCommentId.isEmpty else { return nil }

            let commentText = item.comment?.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let commentedAtDate = item.commentedAt.map { Date(timeIntervalSince1970: $0 / 1000) }
                ?? item.comment?.timestamp.map { Date(timeIntervalSince1970: $0 / 1000) }
                ?? moment.timestamp

            return ActivityCommentItem(
                id: "\(resolvedAuthorId)_\(resolvedMomentId)_\(resolvedCommentId)",
                authorId: resolvedAuthorId,
                momentId: resolvedMomentId,
                commentId: resolvedCommentId,
                commentText: commentText,
                commentedAt: commentedAtDate,
                moment: moment,
                canView: item.canView ?? true
            )
        }

        return (mapped, decoded.nextCursor)
    }

    private func fetchTaggedMomentsPage(limit: Int, cursor: BackendTagsCursor?) async throws -> (items: [BackendTaggedItem], nextCursor: BackendTagsCursor?) {
        guard let currentUser = Auth.auth().currentUser else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("messaging.error.notAuthenticated", comment: "Not authenticated")])
        }

        let idToken = try await currentUser.getIDToken()
        guard let projectId = FirebaseApp.app()?.options.projectID, !projectId.isEmpty else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing Firebase project ID"])
        }

        guard let url = URL(string: "https://europe-southwest1-\(projectId).cloudfunctions.net/getTaggedMomentsPage") else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid backend URL"])
        }

        var payload: [String: Any] = ["limit": limit]
        if let cursor = cursor {
            payload["cursor"] = ["timestamp": cursor.timestamp]
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid backend response"])
        }
        guard http.statusCode == 200 else {
            throw NSError(domain: "", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Backend error \(http.statusCode)"])
        }

        let decoded = try JSONDecoder().decode(BackendTagsResponse.self, from: data)
        return (decoded.items, decoded.nextCursor)
    }

    private func fetchStickerRepliesPage(limit: Int, cursor: BackendStickerRepliesCursor?) async throws -> (items: [BackendStickerReplyItem], nextCursor: BackendStickerRepliesCursor?) {
        guard let currentUser = Auth.auth().currentUser else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("messaging.error.notAuthenticated", comment: "Not authenticated")])
        }

        let idToken = try await currentUser.getIDToken()
        guard let projectId = FirebaseApp.app()?.options.projectID, !projectId.isEmpty else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing Firebase project ID"])
        }

        guard let url = URL(string: "https://europe-southwest1-\(projectId).cloudfunctions.net/getStickerRepliesPage") else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid backend URL"])
        }

        var payload: [String: Any] = ["limit": limit]
        if let cursor = cursor {
            payload["cursor"] = ["timestamp": cursor.timestamp]
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid backend response"])
        }
        guard http.statusCode == 200 else {
            throw NSError(domain: "", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Backend error \(http.statusCode)"])
        }

        let decoded = try JSONDecoder().decode(BackendStickerRepliesResponse.self, from: data)
        return (decoded.items, decoded.nextCursor)
    }

    private func deleteCommentsBatch(_ items: [ActivityCommentItem]) async throws {
        guard let currentUser = Auth.auth().currentUser else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("messaging.error.notAuthenticated", comment: "Not authenticated")])
        }

        let idToken = try await currentUser.getIDToken()
        guard let projectId = FirebaseApp.app()?.options.projectID, !projectId.isEmpty else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing Firebase project ID"])
        }

        guard let url = URL(string: "https://europe-southwest1-\(projectId).cloudfunctions.net/deleteMyCommentsBatch") else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid backend URL"])
        }

        let payloadItems = items.map { item in
            DeleteCommentsTarget(authorId: item.authorId, momentId: item.momentId, commentId: item.commentId)
        }
        let payload: [String: Any] = [
            "comments": payloadItems.map { ["authorId": $0.authorId, "momentId": $0.momentId, "commentId": $0.commentId] }
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid backend response"])
        }
        guard http.statusCode == 200 else {
            throw NSError(domain: "", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Backend error \(http.statusCode)"])
        }

        _ = try? JSONDecoder().decode(DeleteCommentsBatchResponse.self, from: data)
    }

    private func fetchNotifications(userId: String, completion: @escaping ([NotificationRecord]) -> Void) {
        db.collection("users")
            .document(userId)
            .collection("notifications")
            .order(by: "timestamp", descending: true)
            .limit(to: 300)
            .getDocuments { snapshot, _ in
                let records = snapshot?.documents.compactMap { doc -> NotificationRecord? in
                    let data = doc.data()
                    guard let type = data["type"] as? String,
                          let timestamp = (data["timestamp"] as? Timestamp)?.dateValue() else {
                        return nil
                    }

                    return NotificationRecord(
                        id: doc.documentID,
                        type: type,
                        senderUsername: data["senderUsername"] as? String,
                        reaction: data["reaction"] as? String,
                        timestamp: timestamp
                    )
                } ?? []

                completion(records)
            }
    }

}
