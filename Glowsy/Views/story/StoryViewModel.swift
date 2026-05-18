import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import FirebaseStorage
import AVKit
import Kingfisher
import SwiftData

// MARK: - StoryViewModel
@MainActor
class StoryViewModel: ObservableObject {
    @Published var stories: [String: [Story]] = [:]
    @Published var sortedStoryUserIds: [String] = [] // Mantiene el orden de afinidad
    @Published var hasActiveStory: Bool = false
    @Published var storyReactions: [String: [StoryReaction]] = [:] // storyId: reactions
    @Published var storyViewers: [String: [StoryViewer]] = [:] // storyId: viewers

    private let firestoreService = FirestoreService()
    private let chatService = ChatService.shared
    private let privacyService = PrivacyService()
    private let storyRepository = StoryRepository()
    private let playbackCoordinator = StoryPlaybackCoordinator()
    private var isFirstFetch = true


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



        // ✅ SwiftData: Cargar historias del caché local inmediatamente
        let cachedStories = LocalPersistenceService.shared.loadStories(userId: userId)
        if !cachedStories.isEmpty {
            self.stories[userId] = cachedStories
            self.hasActiveStory = true
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

    // MARK: - Obtener historias para usuarios (con conexiones opcionales)
    func fetchStories(for userId: String, includeConnections: Bool = false) {
        if includeConnections {
            // Usar fetchFollowing para obtener los usuarios seguidos
            firestoreService.fetchFollowing(userId: userId) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success(let followingUsers):
                    let connectionIds = followingUsers.map { $0.id }

                    self.fetchStoriesForUsers(userIds: connectionIds, viewerId: userId)
                    self.checkActiveStories(userId: userId)
                case .failure:
                    // Fallback: solo cargar tus historias
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

                if let container = affinityManager.modelContainer {
                    let context = SwiftData.ModelContext(container)
                    let bestFriends = Set(UserDefaults.standard.stringArray(forKey: "bestFriends") ?? [])
                    let mutuals = Set(UserDefaults.standard.stringArray(forKey: "mutuals") ?? [])
                    let storyUserIds = Array(filteredStories.keys)
                    let affinityScores = affinityManager.getScores(for: storyUserIds, in: context)

                    // Convert dictionary to array of tuples to sort users by affinity
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

                    // Sort the users based on score
                    finalSortedIds = userScores.sorted { $0.score > $1.score }.map { $0.userId }
                    finalSortedStories = filteredStories
                } else {
                    finalSortedStories = filteredStories
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

    // Updated sendMessage function in StoryViewModel
    func sendMessage(to userId: String, storyId: String, message: String, completion: @escaping (Bool) -> Void) {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            completion(false)
            return
        }


        // First, get or create conversation
        getOrCreateConversation(between: currentUserId, and: userId) { [weak self] conversationId, error in
            guard let self = self, let conversationId = conversationId, error == nil else {
                completion(false)
                return
            }

            storyRepository.fetchStoryReplyData(userId: userId, storyId: storyId) { storyReply in
                guard let storyReply else {
                    completion(false)
                    return
                }

                // Create story reply data
                let storyReplyData: [String: String] = [
                    "storyId": storyId,
                    "storyMediaUrl": storyReply.mediaUrl,
                    "storyMediaType": storyReply.mediaType
                ]

                // Send the message as regular text message with story reply data
                self.chatService.sendStoryReplyMessage(
                    conversationId: conversationId,
                    senderId: currentUserId,
                    content: "💬 \(message)",  // Keep the message content
                    storyReplyData: storyReplyData
                ) { result in
                    switch result {
                    case .success(_):
                        completion(true)
                    case .failure:
                        completion(false)
                    }
                }
            }
        }
    }


    func sendEphemeralMoment(to userId: String, storyId: String, image: UIImage, completion: @escaping (Bool) -> Void) {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            completion(false)
            return
        }


        // Convert UIImage to Data
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            completion(false)
            return
        }

        // Fetch the story to include its media
        storyRepository.fetchStoryReplyData(userId: userId, storyId: storyId) { [weak self] storyReply in
            guard let storyReply else {
                completion(false)
                return
            }

            // Check if user can send message
            self?.chatService.canSendMessage(from: currentUserId, to: userId) { [weak self] result in
                switch result {
                case .success(let canSend):
                    guard canSend else {
                        completion(false)
                        return
                    }

                    // Get or create conversation
                    self?.getOrCreateConversation(between: currentUserId, and: userId) { [weak self] conversationId, error in
                        guard let self = self, let conversationId = conversationId, error == nil else {
                            completion(false)
                            return
                        }

                        // Upload media and send ephemeral message
                        self.chatService.uploadMedia(data: imageData, type: .image, conversationId: conversationId) { result in
                            switch result {
                            case .success(let (mediaUrl, _)):
                                self.chatService.sendEphemeralMessage(
                                    conversationId: conversationId,
                                    senderId: currentUserId,
                                    content: NSLocalizedString("stories.ephemeral.replyContent", comment: "Ephemeral moment in reply to story"),
                                    mediaUrl: mediaUrl,
                                    expirationHours: 24,
                                    storyReplyData: [
                                        "storyId": storyId,
                                        "storyMediaUrl": storyReply.mediaUrl,
                                        "storyMediaType": storyReply.mediaType
                                    ]
                                ) { ephemeralResult in
                                    switch ephemeralResult {
                                    case .success(_):
                                        completion(true)
                                    case .failure:
                                        completion(false)
                                    }
                                }
                            case .failure:
                                completion(false)
                            }
                        }
                    }

                case .failure:
                    completion(false)
                }
            }
        }
    }


    func fetchReactions(for userId: String, storyId: String) {
        storyRepository.observeReactions(userId: userId, storyId: storyId) { [weak self] reactions in
            DispatchQueue.main.async {
                self?.storyReactions[storyId] = reactions
            }
        }
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

        // Sincroniza estado cross-device inmediatamente al abrir la story.
        StorySeenStateService.shared.markSeen(
            viewerId: currentUserId,
            authorId: userId,
            timestamp: storyTimestamp ?? Date(),
            syncRemote: true
        )

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

    // MARK: - Private Helpers

    private func getOrCreateConversation(between senderId: String, and receiverId: String, completion: @escaping (String?, Error?) -> Void) {

        // Validate inputs
        guard !senderId.isEmpty, !receiverId.isEmpty else {
            completion(nil, NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid user IDs"]))
            return
        }

        firestoreService.db.collection("conversations")
            .whereField("participants", arrayContains: senderId)
            .getDocuments { [weak self] snapshot, error in
                if let error = error {
                    completion(nil, error)
                    return
                }

                guard let documents = snapshot?.documents else {
                    self?.createNewConversation(between: senderId, and: receiverId, completion: completion)
                    return
                }


                // Find conversation with both participants
                let conversation = documents.first { doc in
                    let participants = doc.data()["participants"] as? [String] ?? []
                    return participants.contains(receiverId)
                }

                if let conversation = conversation {
                    let conversationId = conversation.documentID
                    completion(conversationId, nil)
                } else {
                    self?.createNewConversation(between: senderId, and: receiverId, completion: completion)
                }
            }
    }



    func sendReaction(to userId: String, storyId: String, reaction: String) {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }

        storyRepository.addReaction(userId: userId, storyId: storyId, currentUserId: currentUserId, reaction: reaction) { [weak self] error in
            if error == nil {
                // Update local reactions
                self?.fetchReactions(for: userId, storyId: storyId)

                // Track local affinity for story reaction (on successful write)
                Task { @MainActor in
                    AffinityTracker.shared.trackInteraction(type: .storyReaction, with: userId)
                }

                // 2. Notificación manejada por el servidor (onStoryReactionAdded)
            }
        }
    }

    // NUEVA función para enviar notificación de reacción
    private func sendStoryReactionNotification(to storyAuthorId: String, storyId: String, reaction: String, from senderId: String) {
        Task { @MainActor in
            NotificationService.shared.sendInteractionNotification(
                type: .storyReaction,
                to: storyAuthorId,
                storyId: storyId,
                reaction: reaction
            )
        }
    }

    private func createNewConversation(between senderId: String, and receiverId: String, completion: @escaping (String?, Error?) -> Void) {
        let participants = [senderId, receiverId]
        var readStatus: [String: Bool] = [:]
        participants.forEach { readStatus[$0] = ($0 == senderId) }

        // Fetch receiver's profile
        firestoreService.fetchUserProfile(userId: receiverId) { [weak self] result in
            switch result {
            case .success(let user):
                let conversationRef = self?.firestoreService.db.collection("conversations").document()
                let conversationId = conversationRef?.documentID ?? UUID().uuidString

                let conversationData: [String: Any] = [
                    "id": conversationId,
                    "participants": participants,
                    "lastMessage": "",
                    "timestamp": Timestamp(),
                    "readStatus": readStatus,
                    "otherParticipantId": receiverId,
                    "otherParticipantUsername": user.username,
                    "otherParticipantProfileImagePath": user.profileImagePath ?? ""
                ]

                conversationRef?.setData(conversationData) { error in
                    if let error = error {
                        completion(nil, error)
                    } else {
                        completion(conversationId, nil)
                    }
                }

            case .failure(let error):
                completion(nil, error)
            }
        }
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

    /// ✅ PRELOAD: Obtener video precargado
    func getPreloadedVideo(_ storyId: String) -> AVPlayer? {
        playbackCoordinator.getPreloadedVideo(storyId)
    }
}
