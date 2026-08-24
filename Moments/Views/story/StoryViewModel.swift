import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import FirebaseStorage
import AVKit
import Kingfisher
import SwiftData

private enum StoryDeliveryError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        NSLocalizedString("stories.delivery.failed", comment: "Story interaction could not be delivered")
    }
}

// MARK: - StoryViewModel
@MainActor
class StoryViewModel: ObservableObject {
    @Published var stories: [String: [Story]] = [:]
    @Published var sortedStoryUserIds: [String] = [] // Mantiene el orden de afinidad
    /// Orden del ring del feed: tú primero, luego following (como en la barra horizontal).
    @Published var ringOrderedStoryUserIds: [String] = []
    private var lastFetchRingUserIds: [String] = []
    /// Orden fijado desde el anillo del feed; tiene prioridad sobre fetchFollowing.
    private var lockedRingNavigationOrder: [String] = []
    private var reactionListeners: [String: ListenerRegistration] = [:]

    func setRingNavigationOrder(_ userIds: [String]) {
        let order = userIds.filter { !$0.isEmpty }
        lockedRingNavigationOrder = order
        if !order.isEmpty {
            lastFetchRingUserIds = order
            ringOrderedStoryUserIds = order
        }
    }
    @Published var hasActiveStory: Bool = false
    @Published var storyReactions: [String: [StoryReaction]] = [:] // storyId: reactions
    @Published var storyViewers: [String: [StoryViewer]] = [:] // storyId: viewers

    private let firestoreService = FirestoreService()
    private let chatService = ChatService.shared
    private let messageRequestService = MessageRequestService()
    private let privacyService = PrivacyService()
    private let storyRepository = StoryRepository()
    private let playbackCoordinator = StoryPlaybackCoordinator()
    private var isFirstFetch = true

    deinit {
        for listener in reactionListeners.values {
            listener.remove()
        }
    }


    // MARK: - Obtener historias para un usuario específico
    func fetchStoriesForSpecificUser(userId: String, viewerId: String) {
        guard !userId.isEmpty else {
            self.stories = [:]
            return
        }
        guard !viewerId.isEmpty else {
            self.stories = [:]
            return
        }



        // Only own stories can be trusted from local cache before a fresh privacy check.
        if userId == viewerId {
            let cachedStories = LocalPersistenceService.shared.loadStories(userId: userId)
            if !cachedStories.isEmpty {
                self.stories[userId] = cachedStories
                self.hasActiveStory = true
            }
        }

        storyRepository.fetchActiveStories(for: userId) { [weak self] result in
                Task { @MainActor in
                    guard let self = self else { return }
                    if case .failure = result {
                        // Si falla Firestore y no hay caché, limpiar
                        if self.stories[userId] == nil {
                            self.stories = [:]
                        }
                        return
                    }

                    let allStories = (try? result.get()) ?? []

                    // Ahora verificar visibilidad manteniendo el orden
                    let group = DispatchGroup()
                    var storyVisibilityResults: [String: Bool] = [:]

                    for story in allStories {
                        group.enter()
                        self.privacyService.canUserViewStoryEnhanced(story, viewerId: viewerId) { canView in
                            if let storyId = story.id {
                                storyVisibilityResults[storyId] = canView
                            }
                            group.leave()
                        }
                    }
                    group.notify(queue: .main) {
                        Task { @MainActor in
                            // ✅ CORREGIDO: Construir array final manteniendo el orden original
                            let userStories = allStories.filter { story in
                                guard let storyId = story.id else { return false }
                                return storyVisibilityResults[storyId] == true
                            }

                            if userStories.isEmpty {
                                self.stories.removeValue(forKey: userId)
                                // ✅ SwiftData: Limpiar caché si ya no hay historias para este usuario
                                LocalPersistenceService.shared.deleteStories(for: userId)
                                return
                            }

                            self.stories = [userId: userStories]

                            // ✅ SwiftData: Actualizar caché local para este usuario
                            // Primero borramos lo anterior de este usuario para evitar "ghost stories"
                            LocalPersistenceService.shared.deleteStories(for: userId)
                            LocalPersistenceService.shared.saveStories(userStories)

                            // Fetch reactions and viewers for each story
                            for story in userStories {
                                if let storyId = story.id {
                                    self.fetchReactions(for: userId, storyId: storyId)
                                    self.fetchViewers(for: userId, storyId: storyId) { _ in }
                                }
                            }
                            self.prefetchImages()
                        }
                    }
                }
        }
    }

    private var authorReelTasks: [String: Task<Void, Never>] = [:]

    /// Carga el reel de un autor (backend con privacidad) sin vaciar el resto del diccionario.
    func loadAuthorReelIfNeeded(authorId: String, viewerId: String) {
        guard !authorId.isEmpty, !viewerId.isEmpty else { return }
        if let existing = stories[authorId], !existing.isEmpty { return }
        if authorReelTasks[authorId] != nil { return }

        if authorId == viewerId {
            let cachedStories = LocalPersistenceService.shared.loadStories(userId: authorId)
            if !cachedStories.isEmpty {
                stories[authorId] = cachedStories
            }
        }

        authorReelTasks[authorId] = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.authorReelTasks.removeValue(forKey: authorId) }

            if let bundle = await StoryTrayService.shared.fetchAuthorStoryBundle(authorId: authorId) {
                let visible = bundle.stories.compactMap { StoryRepository.decodeBackendStory($0) }
                LogConfig.log(
                    "📖 StoryBundle render: author=\(authorId), decoded=\(visible.count)/\(bundle.stories.count), source=backend",
                    category: "BackendFeed"
                )
                if !visible.isEmpty {
                    self.applyLoadedStories(visible, userId: authorId, viewerId: viewerId)
                    return
                }
            }

            LogConfig.log(
                "⚡ StoryBundle render: author=\(authorId), source=legacy",
                category: "BackendFeed"
            )
            self.mergeStoriesForUserLegacy(userId: authorId, viewerId: viewerId)
        }
    }

    /// Compat: nombre anterior usado por el deck al hacer prefetch.
    func mergeStoriesForUserIfNeeded(userId: String, viewerId: String) {
        loadAuthorReelIfNeeded(authorId: userId, viewerId: viewerId)
    }

    private func applyLoadedStories(_ userStories: [Story], userId: String, viewerId: String) {
        stories[userId] = userStories
        if userId == viewerId {
            LocalPersistenceService.shared.deleteStories(for: userId)
            LocalPersistenceService.shared.saveStories(userStories)
        }
        for story in userStories {
            if let storyId = story.id {
                fetchReactions(for: userId, storyId: storyId)
                fetchViewers(for: userId, storyId: storyId) { _ in }
            }
        }
        prefetchImages()
    }

    private func mergeStoriesForUserLegacy(userId: String, viewerId: String) {
        if let existing = stories[userId], !existing.isEmpty { return }

        storyRepository.fetchActiveStories(for: userId) { [weak self] result in
            Task { @MainActor in
                guard let self, case .success(let allStories) = result, !allStories.isEmpty else { return }

                let group = DispatchGroup()
                var visibility: [String: Bool] = [:]

                for story in allStories {
                    guard let storyId = story.id else { continue }
                    group.enter()
                    self.privacyService.canUserViewStoryEnhanced(story, viewerId: viewerId) { canView in
                        visibility[storyId] = canView
                        group.leave()
                    }
                }

                group.notify(queue: .main) {
                    let visible = allStories.filter { story in
                        guard let storyId = story.id else { return false }
                        return visibility[storyId] == true
                    }
                    guard !visible.isEmpty else { return }
                    self.applyLoadedStories(visible, userId: userId, viewerId: viewerId)
                }
            }
        }
    }

    // MARK: - Obtener historias para usuarios (con conexiones opcionales)
    func fetchStories(for userId: String, includeConnections: Bool = false) {
        if includeConnections, !lockedRingNavigationOrder.isEmpty {
            let ringOrder = lockedRingNavigationOrder
            lastFetchRingUserIds = ringOrder
            ringOrderedStoryUserIds = ringOrder
            checkActiveStories(userId: userId)
            loadAuthorReelIfNeeded(authorId: userId, viewerId: userId)
            return
        }

        if includeConnections {
            // Usar fetchFollowing para obtener los usuarios seguidos
            firestoreService.fetchFollowing(userId: userId) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success(let followingUsers):
                    var followingIds = followingUsers.map { $0.id }
                    var ringOrder = [userId]
                    ringOrder.append(contentsOf: followingIds.filter { $0 != userId })
                    self.lastFetchRingUserIds = ringOrder
                    self.ringOrderedStoryUserIds = ringOrder

                    self.fetchStoriesForUsers(userIds: ringOrder, viewerId: userId)
                    self.checkActiveStories(userId: userId)
                case .failure:
                    self.lastFetchRingUserIds = [userId]
                    self.ringOrderedStoryUserIds = [userId]
                    self.fetchStoriesForUsers(userIds: [userId], viewerId: userId)
                    self.checkActiveStories(userId: userId)
                }
            }
        } else {
            fetchStoriesForUsers(userIds: [userId], viewerId: userId)
            checkActiveStories(userId: userId)
        }
    }

    // MARK: - Obtener historias para múltiples usuarios
    private func fetchStoriesForUsers(userIds: [String], viewerId: String) {
        let group = DispatchGroup()
        var allStories: [String: [Story]] = [:]

        for userId in userIds {
            group.enter()
            storyRepository.fetchActiveStories(for: userId) { [weak self] result in
                    Task { @MainActor in
                        guard let self = self else {
                            group.leave()
                            return
                        }

                        guard case .success(let userStories) = result else {
                            group.leave()
                            return
                        }

                        if !userStories.isEmpty {
                            allStories[userId] = userStories
                            // Fetch reactions and viewers for each story
                            for story in userStories {
                                if let storyId = story.id {
                                    self.fetchReactions(for: userId, storyId: storyId)
                                    self.fetchViewers(for: userId, storyId: storyId) { _ in }
                                }
                            }
                        }
                        group.leave()
                    }
            }
        }

        group.notify(queue: .main) {
            // ✅ NUEVO: Verificar privacidad de forma asíncrona después de cargar
            self.filterStoriesByPrivacy(allStories: allStories, viewerId: viewerId)
        }
    }

    // ✅ NUEVO: Filtrar historias por privacidad de forma asíncrona
    private func filterStoriesByPrivacy(allStories: [String: [Story]], viewerId: String) {
        let group = DispatchGroup()
        var filteredStories: [String: [Story]] = [:]

        for (userId, stories) in allStories {
            group.enter()
            var userFilteredStories: [Story] = []
            var processedCount = 0

            for story in stories {
                self.privacyService.canUserViewStoryEnhanced(story, viewerId: viewerId) { canView in
                    Task { @MainActor in
                        if canView {
                            userFilteredStories.append(story)
                        }

                        processedCount += 1

                        // Si procesamos todas las historias del usuario
                        if processedCount == stories.count {
                            if userFilteredStories.isEmpty {
                                filteredStories[userId] = []
                            } else {
                                filteredStories[userId] = userFilteredStories
                            }
                            group.leave()
                        }
                    }
                }
            }
        }

        group.notify(queue: .main) {
            Task { @MainActor in
                // ✅ EXPERIMENTAL AFFINITY SORTING FOR STORIES
                let affinityManager = AffinityTracker.shared
                var finalSortedStories: [String: [Story]] = [:]
                var finalSortedIds: [String] = []

                finalSortedStories = filteredStories

                if !self.lastFetchRingUserIds.isEmpty {
                    if !self.lockedRingNavigationOrder.isEmpty {
                        finalSortedIds = self.lockedRingNavigationOrder.filter { userId in
                            !(filteredStories[userId]?.isEmpty ?? true)
                        }
                    } else {
                        finalSortedIds = self.lastFetchRingUserIds.filter { userId in
                            !(filteredStories[userId]?.isEmpty ?? true)
                        }
                    }
                    self.ringOrderedStoryUserIds = finalSortedIds.isEmpty
                        ? self.lastFetchRingUserIds
                        : finalSortedIds
                } else if let container = affinityManager.modelContainer {
                    let context = SwiftData.ModelContext(container)
                    let bestFriends = Set(UserDefaults.standard.stringArray(forKey: "bestFriends") ?? [])
                    let mutuals = Set(UserDefaults.standard.stringArray(forKey: "mutuals") ?? [])
                    let storyUserIds = Array(filteredStories.keys)
                    let affinityScores = affinityManager.getScores(for: storyUserIds, in: context)

                    let userScores = filteredStories.keys.map { userId -> (userId: String, score: Double) in
                        var additionalScore = 0.0
                        let affinityScore = affinityScores[userId] ?? 0.0
                        additionalScore += (affinityScore * 1000)

                        let randomFactor = Double.random(in: 0...1000)
                        additionalScore += randomFactor

                        if bestFriends.contains(userId) {
                            additionalScore += 50000
                        } else if mutuals.contains(userId) {
                            additionalScore += 20000
                        }
                        return (userId: userId, score: additionalScore)
                    }

                    finalSortedIds = userScores.sorted { $0.score > $1.score }.map { $0.userId }
                } else {
                    finalSortedIds = Array(filteredStories.keys).shuffled()
                }

                self.stories = finalSortedStories
                self.sortedStoryUserIds = finalSortedIds

                // ✅ SwiftData: Guardar historias en caché local por cada usuario
                // Usar sync: true solo en la primera carga global para purgar inconsistencias
                if self.isFirstFetch {
                    LocalPersistenceService.shared.saveStories(filteredStories.flatMap { $0.value }, sync: true)
                    self.isFirstFetch = false
                } else {
                    for (_, uStories) in filteredStories {
                        LocalPersistenceService.shared.saveStories(uStories)
                    }
                }

                self.prefetchImages()
            }
        }
    }

    private func prefetchImages() {
        var urlsToPrefetch: [URL] = []

        for (_, userStories) in stories {
            for story in userStories {
                if story.mediaItem.type == .image, let url = URL(string: story.mediaItem.url) {
                    urlsToPrefetch.append(url)
                }
                if let profileImagePath = story.profileImagePath, let url = URL(string: profileImagePath) {
                    urlsToPrefetch.append(url)
                }
            }
        }

        let urlsToPrefetchLimited = Array(urlsToPrefetch.prefix(10))
        if !urlsToPrefetchLimited.isEmpty {
            ImagePrefetchManager.shared.prefetch(urls: urlsToPrefetchLimited)
        }
    }

    func checkActiveStories(userId: String) {
        storyRepository.hasActiveStories(userId: userId) { [weak self] hasStories in
                guard let self = self else { return }
                self.hasActiveStory = hasStories
        }
    }

    func sendMessage(
        to userId: String,
        storyId: String,
        message: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            completion(.failure(StoryDeliveryError.unavailable))
            return
        }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion(.failure(StoryDeliveryError.unavailable))
            return
        }
        let context = MessageRequestInteractionContext(
            kind: .storyMessage,
            storyId: storyId,
            storyOwnerId: userId
        )
        storyRepository.fetchStoryReplyData(userId: userId, storyId: storyId) { [weak self] storyReply in
            guard let self, let storyReply else {
                completion(.failure(StoryDeliveryError.unavailable))
                return
            }
            Task { @MainActor in
                do {
                    let route = try await self.messageRequestService.resolveRoute(to: userId, interaction: context)
                    switch route {
                    case .outgoingRequest:
                        _ = try await self.messageRequestService.appendRequestMessage(
                            to: userId,
                            text: "💬 \(trimmed)",
                            interaction: context
                        )
                        completion(.success(()))
                    case .conversation(let conversationId):
                        self.sendAcceptedStoryReply(
                            conversationId: conversationId,
                            senderId: currentUserId,
                            content: "💬 \(trimmed)",
                            storyReplyData: storyReply.payload,
                            completion: completion
                        )
                    case .conversationDraft(let threadId):
                        let conversationId = try await self.messageRequestService.activateConversationDraft(
                            to: userId,
                            threadId: threadId
                        )
                        self.sendAcceptedStoryReply(
                            conversationId: conversationId,
                            senderId: currentUserId,
                            content: "💬 \(trimmed)",
                            storyReplyData: storyReply.payload,
                            completion: completion
                        )
                    case .incomingRequest(let threadId, _):
                        let accepted = try await self.messageRequestService.acceptIncomingThread(threadId: threadId)
                        self.sendAcceptedStoryReply(
                            conversationId: accepted.conversationId,
                            senderId: currentUserId,
                            content: "💬 \(trimmed)",
                            storyReplyData: storyReply.payload,
                            completion: completion
                        )
                    }
                } catch {
                    completion(.failure(error))
                }
            }
        }
    }

    // MARK: - Vanish mode en respuestas de historia

    /// Caché por autor durante la sesión del viewer.
    private var vanishActiveWithAuthor: [String: Bool] = [:]

    /// Consulta de solo lectura: nunca crea conversación por mirar una historia.
    func fetchVanishState(withAuthor authorId: String, completion: @escaping (Bool) -> Void) {
        guard let currentUserId = Auth.auth().currentUser?.uid,
              !authorId.isEmpty,
              authorId != currentUserId else {
            completion(false)
            return
        }

        if let cached = vanishActiveWithAuthor[authorId] {
            completion(cached)
            return
        }

        firestoreService.db.collection("conversations")
            .whereField("participants", arrayContains: currentUserId)
            .getDocuments { [weak self] snapshot, _ in
                let conversation = snapshot?.documents.first { doc in
                    let participants = doc.data()["participants"] as? [String] ?? []
                    return participants.contains(authorId)
                }
                let vanishActive = conversation?.data()["vanishModeActive"] as? Bool ?? false
                DispatchQueue.main.async {
                    self?.vanishActiveWithAuthor[authorId] = vanishActive
                    completion(vanishActive)
                }
            }
    }


    func sendEphemeralMoment(
        to userId: String,
        storyId: String,
        image: UIImage,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            completion(.failure(StoryDeliveryError.unavailable))
            return
        }


        // Convert UIImage to Data
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            completion(.failure(StoryDeliveryError.unavailable))
            return
        }

        let context = MessageRequestInteractionContext(
            kind: .storyEphemeral,
            storyId: storyId,
            storyOwnerId: userId
        )
        storyRepository.fetchStoryReplyData(userId: userId, storyId: storyId) { [weak self] storyReply in
            guard let self, let storyReply else {
                completion(.failure(StoryDeliveryError.unavailable))
                return
            }
            Task { @MainActor in
                do {
                    let route = try await self.messageRequestService.resolveRoute(to: userId, interaction: context)
                    switch route {
                    case .outgoingRequest:
                        _ = try await self.messageRequestService.appendEphemeralMedia(
                            to: userId,
                            data: imageData,
                            mediaType: .image,
                            allowReplay: true,
                            interaction: context,
                            expiresAt: Date().addingTimeInterval(24 * 60 * 60)
                        )
                        completion(.success(()))
                    case .conversation(let conversationId):
                        self.sendAcceptedEphemeralStoryReply(
                            data: imageData,
                            conversationId: conversationId,
                            senderId: currentUserId,
                            storyReplyData: storyReply.payload,
                            completion: completion
                        )
                    case .conversationDraft(let threadId):
                        let conversationId = try await self.messageRequestService.activateConversationDraft(
                            to: userId,
                            threadId: threadId
                        )
                        self.sendAcceptedEphemeralStoryReply(
                            data: imageData,
                            conversationId: conversationId,
                            senderId: currentUserId,
                            storyReplyData: storyReply.payload,
                            completion: completion
                        )
                    case .incomingRequest(let threadId, _):
                        let accepted = try await self.messageRequestService.acceptIncomingThread(threadId: threadId)
                        self.sendAcceptedEphemeralStoryReply(
                            data: imageData,
                            conversationId: accepted.conversationId,
                            senderId: currentUserId,
                            storyReplyData: storyReply.payload,
                            completion: completion
                        )
                    }
                } catch {
                    completion(.failure(error))
                }
            }
        }
    }


    func fetchReactions(for userId: String, storyId: String) {
        reactionListeners[storyId]?.remove()
        reactionListeners[storyId] = storyRepository.observeReactions(userId: userId, storyId: storyId) { [weak self] reactions in
            DispatchQueue.main.async {
                self?.storyReactions[storyId] = reactions
            }
        }
    }

    func stopObservingReactions(storyId: String) {
        reactionListeners[storyId]?.remove()
        reactionListeners.removeValue(forKey: storyId)
    }

    func fetchViewers(for userId: String, storyId: String, completion: @escaping ([StoryViewer]) -> Void) {
        storyRepository.fetchViewers(userId: userId, storyId: storyId) { [weak self] viewers in
            DispatchQueue.main.async {
                self?.storyViewers[storyId] = viewers
            }
            completion(viewers)
        }
    }

    func markStoryAsViewed(
        userId: String,
        storyId: String,
        storyTimestamp: Date? = nil,
        audience: String? = nil
    ) {
        guard let currentUserId = Auth.auth().currentUser?.uid,
              currentUserId != userId else { return }

        let shouldSyncRemoteView = !IncognitoModeService.isActiveSnapshot

        // Sincroniza estado cross-device inmediatamente al abrir la story.
        StorySeenStateService.shared.markSeen(
            viewerId: currentUserId,
            authorId: userId,
            timestamp: storyTimestamp ?? Date(),
            syncRemote: shouldSyncRemoteView
        )

        guard shouldSyncRemoteView else { return }

        firestoreService.fetchUserProfile(userId: currentUserId) { result in
            switch result {
            case .success(let user):
                self.storyRepository.markStoryAsViewed(authorId: userId, storyId: storyId, viewer: user) { error in
                    if error == nil {
                        Task {
                            await StoryRingCacheService.shared.invalidate(viewerId: currentUserId, authorId: userId)
                        }
                    }
                }
            case .failure(_):
                break
            }
        }
    }

    func deleteStory(userId: String, storyId: String, completion: @escaping (Error?) -> Void) {
        guard let currentUserId = Auth.auth().currentUser?.uid, currentUserId == userId else {
            completion(
                NSError(
                    domain: "",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("stories.error.unauthorizedDelete", comment: "Not authorized to delete this story")]
                )
            )
            return
        }

        storyRepository.softDeleteStory(userId: userId, storyId: storyId) { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    completion(error)
                    return
                }

                if var userStories = self.stories[userId] {
                    userStories.removeAll { $0.id == storyId }
                    self.stories[userId] = userStories
                }

                LocalPersistenceService.shared.deleteStory(storyId: storyId)
                self.firestoreService.rebuildStorySummary(for: userId) { _ in }
                self.checkActiveStories(userId: userId)
                completion(nil)
            }
        }
    }

    func permanentlyDeleteStory(userId: String, storyId: String, completion: @escaping (Error?) -> Void) {
        storyRepository.permanentlyDeleteStory(userId: userId, storyId: storyId, completion: completion)
    }

    func restoreStory(userId: String, storyId: String, completion: @escaping (Error?) -> Void) {
        storyRepository.restoreStory(userId: userId, storyId: storyId) { [weak self] error in
            if let error {
                completion(error)
                return
            }

            self?.firestoreService.rebuildStorySummary(for: userId) { _ in }
            self?.checkActiveStories(userId: userId)
            completion(nil)
        }
    }

    func sendReaction(
        to userId: String,
        storyId: String,
        reaction: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            completion(.failure(StoryDeliveryError.unavailable))
            return
        }
        storyRepository.addReaction(
            userId: userId,
            storyId: storyId,
            currentUserId: currentUserId,
            reaction: reaction
        ) { [weak self] error in
            Task { @MainActor in
                if let error {
                    completion(.failure(error))
                    return
                }
                self?.completeStoryReaction(userId: userId, storyId: storyId)
                completion(.success(()))
            }
        }
    }

    private func sendAcceptedStoryReply(
        conversationId: String,
        senderId: String,
        content: String,
        storyReplyData: [String: String],
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        firestoreService.db.collection("conversations").document(conversationId).getDocument { [weak self] snapshot, _ in
            guard let self else {
                completion(.failure(StoryDeliveryError.unavailable))
                return
            }
            let vanishActive = snapshot?.data()?["vanishModeActive"] as? Bool ?? false
            self.chatService.sendStoryReplyMessage(
                conversationId: conversationId,
                senderId: senderId,
                content: content,
                storyReplyData: storyReplyData,
                isVanishModeMessage: vanishActive
            ) { result in
                completion(result.map { _ in () })
            }
        }
    }

    private func sendAcceptedEphemeralStoryReply(
        data: Data,
        conversationId: String,
        senderId: String,
        storyReplyData: [String: String],
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let messageId = UUID().uuidString
        chatService.uploadMedia(data: data, type: .ephemeral, conversationId: conversationId, messageId: messageId) { [weak self] result in
            guard let self else {
                completion(.failure(StoryDeliveryError.unavailable))
                return
            }
            guard case .success(let upload) = result else {
                if case .failure(let error) = result {
                    completion(.failure(error))
                } else {
                    completion(.failure(StoryDeliveryError.unavailable))
                }
                return
            }
            self.chatService.sendEphemeralMessage(
                conversationId: conversationId,
                senderId: senderId,
                content: NSLocalizedString("stories.ephemeral.replyContent", comment: ""),
                mediaUrl: upload.mediaUrl,
                mediaObjectPath: upload.mediaObjectPath,
                thumbnailUrl: upload.thumbnailUrl,
                thumbnailObjectPath: upload.thumbnailObjectPath,
                mediaEncryption: upload.mediaEncryption,
                thumbnailEncryption: upload.thumbnailEncryption,
                expirationHours: 24,
                storyReplyData: storyReplyData,
                messageId: messageId
            ) { result in
                completion(result.map { _ in () })
            }
        }
    }

    private func completeStoryReaction(userId: String, storyId: String) {
        fetchReactions(for: userId, storyId: storyId)
        AffinityTracker.shared.trackInteraction(type: .storyReaction, with: userId)
    }

}


extension StoryViewModel {

    /// Fetch stories específicamente para UserProfile con filtrado de privacidad
    func fetchStoriesForUserProfile(userId: String, viewerId: String) {

        guard !userId.isEmpty && !viewerId.isEmpty else {
            DispatchQueue.main.async {
                self.stories = [:]
            }
            return
        }

        // 1. Obtener historias sin filtrar (usando lógica existente)
        storyRepository.fetchActiveStories(for: userId) { [weak self] result in
                guard let self = self else { return }

                guard case .success(let userStories) = result else {
                    DispatchQueue.main.async {
                        self.stories = [:]
                    }
                    return
                }

                if userStories.isEmpty {
                    DispatchQueue.main.async {
                        self.stories = [:]
                    }
                    return
                }

                // 2. ✅ FILTRAR historias usando PrivacyService
                self.filterStoriesForUserProfile(stories: userStories, userId: userId, viewerId: viewerId)
        }
    }

    /// Función privada para filtrar historias de perfil
    private func filterStoriesForUserProfile(stories: [Story], userId: String, viewerId: String) {
        let group = DispatchGroup()
        var visibleStories: [Story] = []
        let syncQueue = DispatchQueue(label: "profile.stories.filter")
        // ✅ Usar la instancia existente de la clase en lugar de crear una nueva


        for story in stories {
            group.enter()
            self.privacyService.canUserViewStoryEnhanced(story, viewerId: viewerId) { canView in
                if canView {
                    syncQueue.async {
                        visibleStories.append(story)
                    }
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            // Mantener el orden original de las historias
            let orderedVisibleStories = stories.filter { story in
                visibleStories.contains { $0.id == story.id }
            }


            if !orderedVisibleStories.isEmpty {
                self.stories = [userId: orderedVisibleStories]

                // Fetch reactions and viewers como en fetchStories normal
                for story in orderedVisibleStories {
                    if let storyId = story.id {
                        self.fetchReactions(for: userId, storyId: storyId)
                        self.fetchViewers(for: userId, storyId: storyId) { _ in }
                    }
                }
            } else {
                self.stories = [:]
            }

            self.prefetchImages()
        }
    }
}


// MARK: - ✅ PRELOADING FUNCTIONS
extension StoryViewModel {

    /// ✅ PRELOAD: Precargar la siguiente historia
    func preloadNextStory(currentStoryId: String, allStories: [Story]) {
        playbackCoordinator.preloadNextStory(currentStoryId: currentStoryId, allStories: allStories)
    }

    /// ✅ PRELOAD: Precargar historia específica
    func preloadStory(_ story: Story) {
        playbackCoordinator.preloadStory(story)
    }

    /// ✅ PRELOAD: Limpiar cache completo
    func clearPreloadCache() {
        playbackCoordinator.clearPreloadCache()
    }

    /// ✅ PRELOAD: Obtener historia precargada
    func getPreloadedStory(_ storyId: String) -> Story? {
        playbackCoordinator.getPreloadedStory(storyId)
    }

    /// ✅ PRELOAD: Obtener imagen precargada
    func getPreloadedImage(_ storyId: String) -> UIImage? {
        playbackCoordinator.getPreloadedImage(storyId)
    }

}
