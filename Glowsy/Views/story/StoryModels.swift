import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import AVKit
import PhotosUI
import FirebaseStorage
import Kingfisher
import Photos
import MapKit
import AVFoundation
import SwiftData

// MARK: - StoryViewModel
@MainActor
class StoryViewModel: ObservableObject {
    @Published var stories: [String: [Story]] = [:]
    @Published var sortedStoryUserIds: [String] = [] // Mantiene el orden de afinidad
    @Published var hasActiveStory: Bool = false
    @Published var storyReactions: [String: [StoryReaction]] = [:] // storyId: reactions
    @Published var storyViewers: [String: [StoryViewer]] = [:] // storyId: viewers

    // ✅ PRELOADING: Cache para historias precargadas
    @Published var preloadedStories: [String: Story] = [:] // storyId: Story
    @Published var preloadedImages: [String: UIImage] = [:] // storyId: UIImage
    @Published var preloadedVideos: [String: AVPlayer] = [:] // storyId: AVPlayer

    private let firestoreService = FirestoreService()
    private let chatService = ChatService.shared
    private let privacyService = PrivacyService()
    private var isFirstFetch = true

    // ✅ PRELOADING: Configuración
    private let maxPreloadedStories = 3 // Máximo 3 historias precargadas


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

        firestoreService.db.collection("users").document(userId).collection("stories")
            .whereField("expirationDate", isGreaterThan: Date())
            .order(by: "timestamp", descending: false)
            .getDocuments { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self = self else { return }
                    if let error = error {
                        // Si falla Firestore y no hay caché, limpiar
                        if self.stories[userId] == nil {
                            self.stories = [:]
                        }
                        return
                    }
                    // ✅ CORREGIDO: Mantener el orden original de Firestore
                    var allStories: [Story] = []

                    // Primero, procesar todas las historias para obtener visibilidad
                    for doc in snapshot?.documents ?? [] {
                        let data = doc.data()
                        // Handle legacy fields for backwards compatibility
                        var mediaItem: MediaItem?
                        if let mediaItemData = data["mediaItem"] as? [String: Any],
                           let typeString = mediaItemData["type"] as? String,
                           let type = MediaItem.MediaType(rawValue: typeString),
                           let url = mediaItemData["url"] as? String {
                            mediaItem = MediaItem(type: type, url: url)
                        } else if let imagePath = data["imagePath"] as? String, !imagePath.isEmpty {
                            mediaItem = MediaItem(type: .image, url: imagePath)
                        } else if let videoUrl = data["videoUrl"] as? String, !videoUrl.isEmpty {
                            mediaItem = MediaItem(type: .video, url: videoUrl)
                        }
                        guard let mediaItem = mediaItem else {
                            continue
                        }
                        var updatedData = data
                        updatedData["mediaItem"] = ["type": mediaItem.type.rawValue, "url": mediaItem.url]
                        updatedData["id"] = doc.documentID
                        do {
                            let story = try Firestore.Decoder().decode(Story.self, from: updatedData)
                            allStories.append(story)
                        } catch {
                            continue
                        }
                    }

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
                case .failure(let error):
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
            firestoreService.db.collection("users").document(userId).collection("stories")
                .whereField("expirationDate", isGreaterThan: Date())
                .order(by: "timestamp", descending: false)
                .getDocuments { [weak self] snapshot, error in
                    Task { @MainActor in
                        guard let self = self else {
                            group.leave()
                            return
                        }

                        if let _ = error {
                            group.leave()
                            return
                        }

                        let userStories = snapshot?.documents.compactMap { doc -> Story? in
                            var data = doc.data()
                            // Handle legacy fields for backwards compatibility
                            var mediaItem: MediaItem?
                            if let mediaItemData = data["mediaItem"] as? [String: Any],
                               let typeString = mediaItemData["type"] as? String,
                               let type = MediaItem.MediaType(rawValue: typeString),
                               let url = mediaItemData["url"] as? String {
                                mediaItem = MediaItem(type: type, url: url)
                            } else if let imagePath = data["imagePath"] as? String, !imagePath.isEmpty {
                                mediaItem = MediaItem(type: .image, url: imagePath)
                            } else if let videoUrl = data["videoUrl"] as? String, !videoUrl.isEmpty {
                                mediaItem = MediaItem(type: .video, url: videoUrl)
                            }

                            guard let mediaItem = mediaItem else { return nil }

                            data["mediaItem"] = ["type": mediaItem.type.rawValue, "url": mediaItem.url]
                            data["id"] = doc.documentID // Ensure ID is set

                            do {
                                let story = try Firestore.Decoder().decode(Story.self, from: data)
                                // ✅ CORREGIDO: Por ahora retornar la historia sin verificación de privacidad
                                // La verificación se hará después de forma asíncrona
                                return story
                            } catch {
                                return nil
                            }
                        } ?? []

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
        firestoreService.db.collection("users").document(userId).collection("stories")
            .whereField("expirationDate", isGreaterThan: Date())
            .getDocuments { [weak self] snapshot, error in
                guard let self = self else { return }
                if let error = error {
                    self.hasActiveStory = false
                    return
                }
                let hasStories = !(snapshot?.isEmpty ?? true)
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

            // Fetch the story to include its media data
            firestoreService.db.collection("users").document(userId).collection("stories").document(storyId).getDocument { (snapshot: DocumentSnapshot?, error: Error?) in
                if let error = error {
                    completion(false)
                    return
                }

                guard let snapshot = snapshot, snapshot.exists else {
                    completion(false)
                    return
                }

                let storyData = snapshot.data() ?? [:]

                // Extract mediaUrl and type from mediaItem
                guard let mediaItem = storyData["mediaItem"] as? [String: Any],
                      let storyMediaUrl = mediaItem["url"] as? String,
                      let storyMediaType = mediaItem["type"] as? String else {
                    completion(false)
                    return
                }

                // Create story reply data
                let storyReplyData: [String: String] = [
                    "storyId": storyId,
                    "storyMediaUrl": storyMediaUrl,
                    "storyMediaType": storyMediaType
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
                    case .failure(let error):
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
        firestoreService.db.collection("users").document(userId).collection("stories").document(storyId).getDocument { [weak self] (snapshot: DocumentSnapshot?, error: Error?) in
            if let error = error {
                completion(false)
                return
            }

            guard let snapshot = snapshot, snapshot.exists else {
                completion(false)
                return
            }

            let storyData = snapshot.data() ?? [:]

            // Extract mediaUrl and type from mediaItem
            guard let mediaItem = storyData["mediaItem"] as? [String: Any],
                  let storyMediaUrl = mediaItem["url"] as? String,
                  let storyMediaType = mediaItem["type"] as? String else {
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
                                        "storyMediaUrl": storyMediaUrl,
                                        "storyMediaType": storyMediaType
                                    ]
                                ) { ephemeralResult in
                                    switch ephemeralResult {
                                    case .success(_):
                                        completion(true)
                                    case .failure(let error):
                                        completion(false)
                                    }
                                }
                            case .failure(let error):
                                completion(false)
                            }
                        }
                    }

                case .failure(let error):
                    completion(false)
                }
            }
        }
    }


    func fetchReactions(for userId: String, storyId: String) {
        firestoreService.db.collection("users").document(userId).collection("stories").document(storyId)
            .collection("reactions")
            .order(by: "timestamp", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                if let error = error {
                    return
                }

                let reactions = snapshot?.documents.compactMap { doc -> StoryReaction? in
                    let data = doc.data()
                    guard let userId = data["userId"] as? String,
                          let reaction = data["reaction"] as? String,
                          let timestamp = (data["timestamp"] as? Timestamp)?.dateValue() else {
                        return nil
                    }
                    return StoryReaction(id: doc.documentID, userId: userId, reaction: reaction, timestamp: timestamp)
                } ?? []

                DispatchQueue.main.async {
                    self?.storyReactions[storyId] = reactions
                }
            }
    }

    func fetchViewers(for userId: String, storyId: String, completion: @escaping ([StoryViewer]) -> Void) {
        firestoreService.db.collection("users").document(userId).collection("stories").document(storyId)
            .collection("viewers")
            .order(by: "timestamp", descending: true)
            .getDocuments { [weak self] snapshot, error in
                if let error = error {
                    completion([])
                    return
                }

                let viewers = snapshot?.documents.compactMap { doc -> StoryViewer? in
                    let data = doc.data()
                    guard let userId = data["userId"] as? String,
                          let timestamp = (data["timestamp"] as? Timestamp)?.dateValue() else {
                        return nil
                    }
                    let username = data["username"] as? String
                    let profileImagePath = data["profileImagePath"] as? String
                    return StoryViewer(
                        id: doc.documentID,
                        userId: userId,
                        username: username,
                        profileImagePath: profileImagePath,
                        timestamp: timestamp
                    )
                } ?? []

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
                let viewerData: [String: Any] = [
                    "userId": currentUserId,
                    "username": user.username,
                    "profileImagePath": user.profileImagePath ?? "",
                    "timestamp": Timestamp()
                ]

                self.firestoreService.db.collection("users").document(userId).collection("stories").document(storyId)
                    .collection("viewers").document(currentUserId).setData(viewerData) { error in
                        if let error = error {
                        } else {
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

        let storyRef = firestoreService.db.collection("users").document(userId).collection("stories").document(storyId)
        let recentlyDeletedRef = firestoreService.db.collection("users").document(userId).collection("recentlyDeleted").document(storyId)

        // Soft delete: Mover a la colección 'recentlyDeleted'
        storyRef.getDocument { [weak self] document, error in
            guard let self = self else { return }

            if let error = error {
                completion(error)
                return
            }

            guard let data = document?.data() else {
                completion(NSError(domain: "", code: -404, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("errors.storyNotFound", comment: "Story not found")]))
                return
            }

            var deletedData = data
            deletedData["deletedAt"] = FieldValue.serverTimestamp()
            deletedData["type"] = "story"

            // Guardar en recentlyDeleted
            recentlyDeletedRef.setData(deletedData) { error in
                if let error = error {
                    completion(error)
                    return
                }

                // Borrar de la colección original
                storyRef.delete { firestoreError in
                    if let firestoreError = firestoreError {
                        completion(firestoreError)
                    } else {
                        // ✅ SwiftData: Actualizar caché local
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
        }
    }

    func permanentlyDeleteStory(userId: String, storyId: String, completion: @escaping (Error?) -> Void) {
        let recentlyDeletedRef = firestoreService.db.collection("users").document(userId).collection("recentlyDeleted").document(storyId)

        recentlyDeletedRef.getDocument { [weak self] snapshot, error in
            if let error = error {
                completion(error)
                return
            }

            guard let self = self, let data = snapshot?.data() else {
                completion(NSError(domain: "", code: -404, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("errors.storyNotFound", comment: "Story not found")]))
                return
            }

            // Extraer mediaUrl para limpieza de Storage
            let mediaItemData = data["mediaItem"] as? [String: Any]
            let mediaUrl = mediaItemData?["url"] as? String

            recentlyDeletedRef.delete { error in
                if let error = error {
                    completion(error)
                    return
                }

                if let mediaUrl = mediaUrl {
                    self.deleteMediaFromStorage(mediaUrl: mediaUrl) { _ in }
                }

                completion(nil)
            }
        }
    }

    func restoreStory(userId: String, storyId: String, completion: @escaping (Error?) -> Void) {
        let storyRef = firestoreService.db.collection("users").document(userId).collection("stories").document(storyId)
        let recentlyDeletedRef = firestoreService.db.collection("users").document(userId).collection("recentlyDeleted").document(storyId)

        recentlyDeletedRef.getDocument { [weak self] snapshot, error in
            if let error = error {
                completion(error)
                return
            }

            guard let self = self, var data = snapshot?.data() else {
                completion(NSError(domain: "", code: -404, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("errors.documentNotFound", comment: "Document not found")]))
                return
            }

            // Limpiar metadatos de borrado
            data.removeValue(forKey: "deletedAt")
            data.removeValue(forKey: "type")

            // Restaurar a la colección original
            storyRef.setData(data) { error in
                if let error = error {
                    completion(error)
                    return
                }

                // Borrar de recentlyDeleted
                recentlyDeletedRef.delete { error in
                    if let error = error {
                        completion(error)
                    } else {
                        self.firestoreService.rebuildStorySummary(for: userId) { _ in }
                        self.checkActiveStories(userId: userId)
                        completion(nil)
                    }
                }
            }
        }
    }

    // ✅ FUNCIÓN: Eliminar media de Firebase Storage
    private func deleteMediaFromStorage(mediaUrl: String, completion: @escaping (Error?) -> Void) {
        guard let url = URL(string: mediaUrl) else {
            completion(
                NSError(
                    domain: "",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("stories.error.invalidMediaUrl", comment: "Invalid media URL")]
                )
            )
            return
        }

        // ✅ Extraer la ruta del storage desde la URL
        let storagePath = extractStoragePath(from: url)

        // ✅ Eliminar de Firebase Storage
        let storageRef = Storage.storage().reference().child(storagePath)
        storageRef.delete { error in
            if let error = error {
                completion(error)
            } else {
                completion(nil)
            }
        }
    }

    // ✅ FUNCIÓN: Extraer ruta de storage desde URL
    private func extractStoragePath(from url: URL) -> String {
        // ✅ Ejemplo: https://firebasestorage.googleapis.com/v0/b/glowsy-6a40e.appspot.com/o/videos%2Ffilename.mp4?alt=media&token=...
        // ✅ Extraer: videos/filename.mp4

        let path = url.path
        if path.contains("/o/") {
            let components = path.components(separatedBy: "/o/")
            if components.count > 1 {
                let encodedPath = components[1]
                return encodedPath.removingPercentEncoding ?? encodedPath
            }
        }

        // ✅ Fallback: usar el último componente de la URL
        return url.lastPathComponent
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

        // 1. Guardar la reacción en la historia
        let reactionData: [String: Any] = [
            "userId": currentUserId,
            "reaction": reaction,
            "timestamp": Timestamp()
        ]

        firestoreService.db.collection("users").document(userId).collection("stories").document(storyId)
            .collection("reactions").addDocument(data: reactionData) { [weak self] error in
                if let error = error {
                } else {
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

// MARK: - Story Models
struct StoryReaction: Identifiable {
    let id: String
    let userId: String
    let reaction: String
    let timestamp: Date
}

struct StoryViewer: Identifiable {
    let id: String
    let userId: String
    let username: String?
    let profileImagePath: String?
    let timestamp: Date
}

// MARK: - Glassmorphic Story Video Player
struct GlassmorphicStoryVideoPlayer: UIViewControllerRepresentable {
    let url: URL
    @Binding var isPlaying: Bool
    let isHorizontalVideo: Bool
    let videoGravity: AVLayerVideoGravity
    let shouldLoop: Bool
    let onProgressUpdate: (Double) -> Void
    let onVideoComplete: () -> Void

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()

        // ✅ AUDIO FIX: Activar sesión de audio para que suene aunque esté en silencio
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [])
        try? AVAudioSession.sharedInstance().setActive(true)

        // ✅ USAR VIDEOPRELOADER PARA INICIO INSTANTÁNEO
        let playerItem = VideoPreloader.shared.getPlayerItem(for: url.absoluteString)

        let player: AVPlayer
        if shouldLoop {
            let queuePlayer = AVQueuePlayer(items: [playerItem])
            context.coordinator.playerLooper = AVPlayerLooper(player: queuePlayer, templateItem: playerItem)
            player = queuePlayer
        } else {
            context.coordinator.playerLooper = nil
            player = AVPlayer(playerItem: playerItem)
        }

        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = videoGravity
        controller.view.backgroundColor = .clear
        context.coordinator.player = player
        context.coordinator.onProgressUpdate = onProgressUpdate
        context.coordinator.onVideoComplete = onVideoComplete
        context.coordinator.currentURL = url // ✅ Track initial URL

        // ✅ CONFIGURAR OBSERVERS PARA PROGRESO
        context.coordinator.setupObservers()

        // 🎯 CONFIGURAR GRAVITY SEGÚN ORIENTACIÓN
        context.coordinator.configureVideoGravity(for: controller)

        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        // ✅ CRITICAL FIX: Use Coordinator's tracked URL instead of asset URL to avoid infinite loops
        // caused by mismatch between remote URL (view) and local cache URL (AVPlayer asset).
        if context.coordinator.currentURL != url {
             // URL changed, recreate player

            // 1. CLEANUP OLD PLAYER
            context.coordinator.cleanupObservers()
            uiViewController.player?.pause()
            uiViewController.player?.isMuted = true

            // 2. CREATE NEW PLAYER
            let playerItem = VideoPreloader.shared.getPlayerItem(for: url.absoluteString)
            let newPlayer: AVPlayer
            if shouldLoop {
                let queuePlayer = AVQueuePlayer(items: [playerItem])
                context.coordinator.playerLooper = AVPlayerLooper(player: queuePlayer, templateItem: playerItem)
                newPlayer = queuePlayer
            } else {
                context.coordinator.playerLooper = nil
                newPlayer = AVPlayer(playerItem: playerItem)
            }

            uiViewController.player = newPlayer
            context.coordinator.player = newPlayer

            // 3. UPDATE COORDINATOR
            context.coordinator.currentURL = url
            context.coordinator.setupObservers()

            // 4. CONFIGURE GRAVITY
            context.coordinator.configureVideoGravity(for: uiViewController)
        }

        if uiViewController.videoGravity != videoGravity {
            uiViewController.videoGravity = videoGravity
        }

        // ✅ EVITAR LOOP: Verificar estado actual del player
        let playerIsPlaying = uiViewController.player?.rate != 0.0

        if isPlaying && !playerIsPlaying {
            // ✅ Solo reproducir si no está reproduciéndose
            if let player = uiViewController.player, player.currentItem != nil {
                player.isMuted = false // ✅ ASEGURAR SONIDO AL VOLVER
                player.play()
            }
        } else if !isPlaying && playerIsPlaying {
            // ✅ Solo pausar si está reproduciéndose
            uiViewController.player?.pause()
            uiViewController.player?.isMuted = true // ✅ SILENCIAR AL PAUSAR
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject {
        var parent: GlassmorphicStoryVideoPlayer
        var player: AVPlayer?
        var playerLooper: AVPlayerLooper?
        var timeObserver: Any?
        var onProgressUpdate: ((Double) -> Void)?
        var onVideoComplete: (() -> Void)?
        var currentURL: URL? // ✅ Track the intended URL

        var completionObserver: NSObjectProtocol? // ✅ Track observer for cleanup

        init(_ parent: GlassmorphicStoryVideoPlayer) {
            self.parent = parent
            self.currentURL = parent.url // Initialize with current URL
        }

        // 🎯 CONFIGURAR GRAVITY SEGÚN ORIENTACIÓN DEL VIDEO
        func configureVideoGravity(for controller: AVPlayerViewController) {
            controller.videoGravity = parent.videoGravity
        }

        func cleanupObservers() {
            if let observer = timeObserver {
                player?.removeTimeObserver(observer)
                timeObserver = nil
            }
            // ✅ LIMPIAR OBSERVER DE COMPLETACIÓN
            if let observer = completionObserver {
                NotificationCenter.default.removeObserver(observer)
                completionObserver = nil
            }
            // Fallback for selector-based observers if any
            NotificationCenter.default.removeObserver(self)
        }

        func setupObservers() {
            // ✅ RESET PROGRESO AL CONFIGURAR OBSERVERS
            onProgressUpdate?(0.0)

            // ✅ OBSERVER DE PROGRESO
            timeObserver = player?.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC)),
                queue: .main
            ) { [weak self] time in
                guard let self = self, let currentItem = self.player?.currentItem else { return }

                let duration = currentItem.duration
                if CMTIME_IS_VALID(duration) && !CMTIME_IS_INDEFINITE(duration) {
                    let durationSeconds = CMTimeGetSeconds(duration)
                    if durationSeconds > 0 {
                        let currentSeconds = CMTimeGetSeconds(time)
                        let progress = min(max(currentSeconds / durationSeconds, 0.0), 1.0)
                        self.onProgressUpdate?(progress)
                    }
                }
            }

            // ✅ OBSERVER DE COMPLETACIÓN: avanzar a la siguiente historia al terminar
            completionObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player?.currentItem,
                queue: .main
            ) { [weak self] _ in
                self?.onProgressUpdate?(0.0)
                if self?.parent.shouldLoop == true {
                    return
                }
                self?.onVideoComplete?()
            }
        }

        deinit {
            cleanupObservers() // ✅ Ensure observers are removed

            player?.pause()
            player?.isMuted = true
            player?.replaceCurrentItem(with: nil)
            playerLooper = nil
            player = nil

            // ✅ CLEANUP DE AUDIO SESSION
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}

// MARK: - Glassmorphic Story Viewer
struct GlassmorphicStoryViewer: View {
    let story: Story
    let storyCount: Int
    let storyIndex: Int
    let screenSize: CGSize
    let storyViewModel: StoryViewModel
    @Binding var showingReportSheet: Bool
    @Binding var showingBlockConfirmation: Bool
    let onReportStory: () -> Void
    let onBlockUser: () -> Void
    let onNext: () -> Void
    let onPrevious: () -> Void
    let onClose: () -> Void
    let onProfileTap: () -> Void

    @State private var progress: Double = 0.0
    @State private var imageTimer: Timer? = nil
    @State private var isPaused: Bool = false
    @State private var showMomentDetail: Bool = false
    @State private var targetMomentId: String? = nil
    @State private var targetMomentUserId: String? = nil
    @State private var currentStoryId: String? = nil
    @State private var messageText: String = ""
    @State private var showReactions: Bool = false
    @State private var showEphemeralPicker: Bool = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showQuickActions: Bool = false
    @State private var showViewers: Bool = false
    @State private var showBestFriendsOptOutConfirmation: Bool = false
    @State private var showUnfollowConfirmation: Bool = false
    @State private var showMuteConfirmation: Bool = false
    @State private var isMenuInteractionActive: Bool = false
    @State private var menuAutoResumeWorkItem: DispatchWorkItem? = nil
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging: Bool = false
    @State private var showSuccessMessage: Bool = false
    @State private var canContinueChain: Bool = false
    @State private var successMessageText: String = ""
    @FocusState private var isTextFieldFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var keyboardHeight: CGFloat = 0 // Track keyboard height
    @State private var isKeyboardVisible: Bool = false // Track keyboard state
    @State private var authorAllowsMessages: Bool = true
    @State private var authorAllowsReactions: Bool = true
    @State private var authorAllowsEphemeralPhotos: Bool = true
    @State private var storyStickers: [StickerItem] = [] // Cache de stickers
    @State private var showUserProfile = false
    @State private var selectedUserId: String = ""
    @State private var floatingHearts: [FloatingHeart] = [] // ✅ FLOATING HEARTS ANIMATION
    @State private var isUIHidden: Bool = false // ✅ IMMERSIVE MODE STATE
    @State private var gestureActionTriggered: Bool = false // ✅ UNIFIED GESTURE STATE
    @State private var isHoldingStory: Bool = false
    @State private var holdPauseWorkItem: DispatchWorkItem? = nil
    @State private var holdStartLocation: CGPoint? = nil
    @State private var suppressNavigationTapUntil: Date? = nil
    // ✅ SOLO ZOOM - Estados para pinch to zoom
    @State private var zoomScale: CGFloat = 1.0
    @State private var lastZoomScale: CGFloat = 1.0
    // 🔗 STORY CHAINS - Variables para cadenas de historias
    @State private var showChainView: Bool = false
    @State private var selectedChainId: String = ""
    @State private var selectedChainTitle: String = ""
    @State private var selectedChainStoryId: String = ""
    @State private var selectedChainStoryPosition: Int = 1
    @State private var chainStories: [Story] = [] // Todas las historias de la cadena
    @State private var currentChainIndex: Int = 0 // Índice actual en la cadena
    @State private var isLoadingChainStories: Bool = false

    private let defaultStoryDuration: Double = 10.0
    private let reactions: [String] = ["✌🏻", "🔥", "✅", "😊", "✨", "❤️", "💕", "😮", "😂", "😢", "🙏🏻", "⚡", "🧠", "🎨", "😌", "🎉"]

    private let firestoreService = FirestoreService()
    private let bestFriendsService = BestFriendsService()

    private var canOptOutFromAuthorBestFriends: Bool {
        guard story.authorId != Auth.auth().currentUser?.uid else { return false }
        let normalizedAudience = story.audience?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "") ?? ""
        return normalizedAudience == "bestfriends"
    }

    // ✅ FUNCIÓN HELPER: Detectar aspect ratio de un video (CORREGIDA)
    static func detectVideoAspectRatio(from url: URL) async -> String? {
        let asset = AVAsset(url: url)
        let tracks = try? await asset.loadTracks(withMediaType: .video)

        if let videoTrack = tracks?.first {
            let naturalSize = try? await videoTrack.load(.naturalSize)
            let preferredTransform = try? await videoTrack.load(.preferredTransform)

            if let size = naturalSize, let transform = preferredTransform {
                // ✅ CALCULAR DIMENSIONES REALES DESPUÉS DE TRANSFORM
                let transformedSize = size.applying(transform)
                let width = Int(abs(transformedSize.width))
                let height = Int(abs(transformedSize.height))
                let aspectRatio = "\(width):\(height)"


                return aspectRatio
            }
        }

        return nil
    }

    // ✅ FUNCIÓN HELPER: Detectar aspect ratio de una imagen
    static func detectImageAspectRatio(from url: URL) async -> String? {
        guard let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else {
            return nil
        }

        let width = Int(image.size.width)
        let height = Int(image.size.height)
        let aspectRatio = "\(width):\(height)"


        return aspectRatio
    }

    // ✅ FUNCIÓN HELPER: Determinar si un aspect ratio es horizontal
    static func isHorizontalAspectRatio(_ aspectRatio: String?) -> Bool {
        guard let aspectRatio = aspectRatio else {
            return false
        }

        let components = aspectRatio.split(separator: ":")
        if components.count == 2,
           let width = Int(components[0]),
           let height = Int(components[1]) {
            let isHorizontal = width > height
            return isHorizontal
        }

        return false
    }

    private func stickerContentRect(containerSize: CGSize) -> CGRect {
        let resolvedContainerSize = CGSize(
            width: max(containerSize.width, 1),
            height: max(containerSize.height, 1)
        )
        let mediaAspectRatio = Self.parseAspectRatio(story.aspectRatio)
            ?? (resolvedContainerSize.width / resolvedContainerSize.height)
        let contentMode = StoryMediaLayoutRules.presentationMode(
            for: mediaAspectRatio,
            canvasAspectRatio: resolvedContainerSize.width / max(resolvedContainerSize.height, 1)
        ).swiftUIContentMode

        return Self.contentRect(
            containerSize: resolvedContainerSize,
            mediaAspectRatio: mediaAspectRatio,
            contentMode: contentMode
        )
    }

    private static func parseAspectRatio(_ aspectRatio: String?) -> CGFloat? {
        guard let aspectRatio else { return nil }
        let components = aspectRatio.split(separator: ":")
        guard components.count == 2,
              let widthValue = Double(components[0]),
              let heightValue = Double(components[1]) else {
            return nil
        }

        let width = CGFloat(widthValue)
        let height = CGFloat(heightValue)
        guard
              width > 0,
              height > 0 else {
            return nil
        }
        return width / height
    }

    private static func contentRect(
        containerSize: CGSize,
        mediaAspectRatio: CGFloat,
        contentMode: SwiftUI.ContentMode
    ) -> CGRect {
        let containerWidth = max(containerSize.width, 1)
        let containerHeight = max(containerSize.height, 1)
        let containerAspectRatio = containerWidth / containerHeight

        let isFit = contentMode == .fit
        let mediaIsWider = mediaAspectRatio > containerAspectRatio

        let width: CGFloat
        let height: CGFloat

        if isFit {
            if mediaIsWider {
                width = containerWidth
                height = containerWidth / max(mediaAspectRatio, 0.0001)
            } else {
                height = containerHeight
                width = containerHeight * mediaAspectRatio
            }
        } else {
            if mediaIsWider {
                height = containerHeight
                width = containerHeight * mediaAspectRatio
            } else {
                width = containerWidth
                height = containerWidth / max(mediaAspectRatio, 0.0001)
            }
        }

        return CGRect(
            x: (containerWidth - width) / 2,
            y: (containerHeight - height) / 2,
            width: width,
            height: height
        )
    }

    private func stickerDisplayPosition(_ sticker: StickerItem, containerSize: CGSize) -> CGPoint {
        let contentRect = stickerContentRect(containerSize: containerSize)
        return CGPoint(
            x: contentRect.minX + (sticker.position.x * contentRect.width),
            y: contentRect.minY + (sticker.position.y * contentRect.height)
        )
    }

    private func stickerForDisplay(_ sticker: StickerItem, containerSize: CGSize) -> StickerItem {
        let contentRect = stickerContentRect(containerSize: containerSize)
        let scaleFactor = max(contentRect.width, 1) / 375.0
        var displaySticker = sticker
        displaySticker.scale = sticker.scale * scaleFactor
        return displaySticker
    }

    private enum StoryConfirmationKind {
        case unfollow
        case mute
        case leaveBestFriends
    }

    private var activeStoryConfirmation: StoryConfirmationKind? {
        if showUnfollowConfirmation { return .unfollow }
        if showMuteConfirmation { return .mute }
        if showBestFriendsOptOutConfirmation { return .leaveBestFriends }
        return nil
    }

    private func confirmationTitle(for kind: StoryConfirmationKind) -> String {
        switch kind {
        case .unfollow:
            let format = NSLocalizedString("storyContextMenu.unfollow.confirm.title", comment: "Unfollow confirmation title")
            return String(format: format, story.username)
        case .mute:
            let format = NSLocalizedString("storyContextMenu.mute.confirm.title", comment: "Mute confirmation title")
            return String(format: format, story.username)
        case .leaveBestFriends:
            let format = NSLocalizedString("bestFriends.optOut.confirm.title", comment: "Leave best friends title")
            return String(format: format, story.username)
        }
    }

    private func confirmationMessage(for kind: StoryConfirmationKind) -> String {
        switch kind {
        case .unfollow:
            return NSLocalizedString("storyContextMenu.unfollow.confirm.message", comment: "Unfollow confirmation message")
        case .mute:
            return NSLocalizedString("storyContextMenu.mute.confirm.message", comment: "Mute confirmation message")
        case .leaveBestFriends:
            return NSLocalizedString("bestFriends.optOut.confirm.message", comment: "Leave best friends message")
        }
    }

    private func confirmationConfirmTitle(for kind: StoryConfirmationKind) -> String {
        switch kind {
        case .unfollow:
            return NSLocalizedString("storyContextMenu.unfollow.confirm.action", comment: "Unfollow action")
        case .mute:
            return NSLocalizedString("storyContextMenu.mute.confirm.action", comment: "Mute action")
        case .leaveBestFriends:
            return NSLocalizedString("bestFriends.optOut.confirm.action", comment: "Leave best friends action")
        }
    }

    private func confirmationCancelTitle(for kind: StoryConfirmationKind) -> String {
        switch kind {
        case .unfollow:
            return NSLocalizedString("storyContextMenu.unfollow.confirm.cancel", comment: "Unfollow cancel")
        case .mute:
            return NSLocalizedString("storyContextMenu.mute.confirm.cancel", comment: "Mute cancel")
        case .leaveBestFriends:
            return NSLocalizedString("bestFriends.optOut.confirm.cancel", comment: "Leave best friends cancel")
        }
    }

    private var quickActionTextColor: Color {
        colorScheme == .dark ? .white : .black.opacity(0.88)
    }

    private var quickActionDividerColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.10)
    }

    private var quickActionBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.08)
    }

    private func clearAllStoryConfirmations() {
        showUnfollowConfirmation = false
        showMuteConfirmation = false
        showBestFriendsOptOutConfirmation = false
    }

    private func handleStoryConfirmation(_ kind: StoryConfirmationKind) {
        clearAllStoryConfirmations()
        switch kind {
        case .unfollow:
            unfollowStoryAuthor()
        case .mute:
            muteStoryAuthor()
        case .leaveBestFriends:
            optOutFromBestFriends()
        }
    }

    var body: some View {
        profileAndChainBoundView
    }

    @ViewBuilder
    private func geometryStackView(for geometry: GeometryProxy) -> some View {
        ZStack {
            // MARK: - 1. CONTENIDO MULTIMEDIA (Fijo en el centro - NUNCA SE MUEVE)
            contentView
                .frame(width: geometry.size.width, height: geometry.size.height)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)

            // MARK: - 2. STICKERS (Fijos en sus posiciones)
            if !storyStickers.isEmpty {
                ForEach(storyStickers, id: \.id) { sticker in
                StoryStickerView(
                    sticker: stickerForDisplay(sticker, containerSize: screenSize),
                    screenSize: geometry.size,
                    storyId: story.id ?? "",
                    userId: story.authorId,
                    onPauseStory: pauseStory,
                    onResumeStory: resumeStory
                )
                .id((story.id ?? "") + sticker.id) // ✅ Forzar nueva instancia al cambiar de historia
                .position(stickerDisplayPosition(sticker, containerSize: screenSize))
                }
            }

            // MARK: - 3. FLOATING HEARTS (Under UI, Over Content)
            FloatingHeartsView(hearts: floatingHearts)
                .allowsHitTesting(false)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)

            if !isUIHidden {
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.70),
                            Color.black.opacity(0.42),
                            Color.black.opacity(0.16),
                            Color.black.opacity(0.00)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: max(geometry.safeAreaInsets.top, 47) + 160)
                    .ignoresSafeArea(edges: .top)

                    Spacer()
                }
                .allowsHitTesting(false)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            }

            // MARK: - 4. UI SUPERIOR (Header + Progress) - FIJA ARRIBA, NUNCA SE MUEVE
            VStack(spacing: 0) {
                if !isUIHidden {
                    Color.clear.frame(height: max(geometry.safeAreaInsets.top, 47) + 8)

                    glassmorphicProgressBar
                        .padding(.horizontal, 12)
                        .padding(.top, 8)

                    glassmorphicHeader
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .zIndex(1)
                }

                Spacer()

                Color.clear.frame(height: 80)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)

            if showQuickActions {
                storyQuickActionsOverlay(topInset: max(geometry.safeAreaInsets.top, 47))
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .topTrailing)))
                    .zIndex(20)
            }

            // MARK: - 5. ÁREAS DE NAVEGACIÓN (Fijas)
            if !isKeyboardVisible {
                navigationTouchAreas
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    .allowsHitTesting(!isMenuInteractionActive)
            }

            // MARK: - 6. INPUT AREA - Se mueve manualmente con keyboardHeight
            VStack {
                Spacer()

                if !isUIHidden {
                    glassmorphicBottomArea
                        .padding(.horizontal, 16)
                        .padding(.bottom, isKeyboardVisible ? keyboardHeight + 10 : max(geometry.safeAreaInsets.bottom, 25))
                        .animation(.easeInOut(duration: 0.25), value: keyboardHeight)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)

            // MARK: - 7. Success message overlay
            if showSuccessMessage {
                GlassmorphicSuccessMessage(text: successMessageText)
                    .transition(.scale.combined(with: .opacity))
                    .zIndex(10)
            }

            if let confirmationKind = activeStoryConfirmation {
                GlassmorphicStoryConfirmationDialog(
                    title: confirmationTitle(for: confirmationKind),
                    message: confirmationMessage(for: confirmationKind),
                    confirmTitle: confirmationConfirmTitle(for: confirmationKind),
                    cancelTitle: confirmationCancelTitle(for: confirmationKind),
                    isDestructive: true,
                    onConfirm: {
                        handleStoryConfirmation(confirmationKind)
                    },
                    onCancel: {
                        clearAllStoryConfirmations()
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .zIndex(30)
            }
        }
        .sheet(isPresented: $showMomentDetail) {
            if let momentId = targetMomentId, let userId = targetMomentUserId {
                MomentDetailFromNotificationView(
                    momentId: momentId,
                    userId: userId,
                    isPresented: $showMomentDetail
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenMomentFromStory"))) { notification in
            if let userInfo = notification.userInfo,
               let momentId = userInfo["momentId"] as? String,
               let userId = userInfo["userId"] as? String {
                self.targetMomentId = momentId
                self.targetMomentUserId = userId
                self.showMomentDetail = true
                self.pauseStory()
            }
        }
        .onChange(of: showMomentDetail) { oldValue, newValue in
            if !newValue {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.resumeStory()
                }
            }
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
        .ignoresSafeArea(.all)
    }

    private var interactiveRootView: AnyView {
        let base = GeometryReader { geometry in
            geometryStackView(for: geometry)
        }
        .ignoresSafeArea(.all)
        .background(Color.black)
        .scaleEffect(zoomScale)

        if isMenuInteractionActive {
            return AnyView(base)
        }

        return AnyView(
            base
                .simultaneousGesture(holdToPauseGesture)
                .simultaneousGesture(unifiedDragGesture)
                .simultaneousGesture(pinchGesture)
                .simultaneousGesture(
                    TapGesture()
                        .onEnded { _ in
                            if isTextFieldFocused {
                                isTextFieldFocused = false
                            }
                        }
                )
        )
    }

    private var lifecycleBoundView: AnyView {
        AnyView(
            interactiveRootView
                .onAppear {
                    prepareAndStartStory()
                    setupKeyboardNotifications()
                    if storyStickers.isEmpty {
                        storyStickers = story.convertStickersToStickerItems()
                    }
                    preloadNextStory()
                    if let chainId = story.chainId {
                        checkCanContinueChain(chainId: chainId)
                    }
                    if story.chainId != nil {
                        loadChainStories()
                    }
                }
                .onChange(of: story.id) { newId in
                    if let chainId = story.chainId {
                        checkCanContinueChain(chainId: chainId)
                    }
                }
                .onDisappear {
                    stopAndCleanupStory()
                    removeKeyboardNotifications()
                    cleanupAudioSession()
                }
                .onChange(of: story.id) { oldStoryId, newStoryId in
                    if oldStoryId != newStoryId {
                        progress = 0.0
                        handleStoryChange()
                        storyStickers = story.convertStickersToStickerItems()
                    }
                }
                .onChange(of: storyIndex) { oldIndex, newIndex in
                    let newStickers = story.convertStickersToStickerItems()
                    storyStickers = newStickers
                }
        )
    }

    private var overlayBoundView: AnyView {
        AnyView(
            ZStack {
                lifecycleBoundView
                    .sheet(isPresented: $showViewers, onDismiss: {
                        resumeStory()
                    }) {
                        GlassmorphicViewersSheet(
                            story: story,
                            viewers: storyViewModel.storyViewers[story.id ?? ""] ?? [],
                            reactions: storyViewModel.storyReactions[story.id ?? ""] ?? []
                        )
                        .onAppear {
                            pauseStory()
                        }
                    }
                
                // ✅ CAPA DE REVEAL (Si existe el sticker de reveal)
                let hasReveal = storyStickers.contains { $0.type == .reveal }
                if hasReveal {
                    InteractiveRevealSticker(
                        storyId: story.id ?? "",
                        onPauseStory: { pauseStory() },
                        onResumeStory: { resumeStory() }
                    )
                    .ignoresSafeArea()
                }
            }
            .onChange(of: selectedPhoto) { newPhoto in
                handleEphemeralPhoto(newPhoto)
            }
            .onChange(of: showReactions) { isOpen in
                if isOpen {
                    pauseStory()
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        resumeStory()
                    }
                }
            }
            .onChange(of: showEphemeralPicker) { isOpen in
                if isOpen {
                    pauseStory()
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        resumeStory()
                    }
                }
            }
            .onChange(of: showingReportSheet) { oldValue, newValue in
                if newValue {
                    pauseStory()
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        resumeStory()
                    }
                }
            }
            .onChange(of: showViewers) { oldValue, newValue in
                if newValue {
                    pauseStory()
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        resumeStory()
                    }
                }
            }
            .onChange(of: showingBlockConfirmation) { oldValue, newValue in
                    if newValue {
                        pauseStory()
                    } else {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            resumeStory()
                        }
                    }
                }
                .onChange(of: showUnfollowConfirmation) { oldValue, newValue in
                    if newValue {
                        pauseStory()
                    } else {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            resumeStory()
                        }
                    }
                }
                .onChange(of: showMuteConfirmation) { oldValue, newValue in
                    if newValue {
                        pauseStory()
                    } else {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            resumeStory()
                        }
                    }
                }
                .onChange(of: showBestFriendsOptOutConfirmation) { oldValue, newValue in
                    if newValue {
                        pauseStory()
                    } else {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            resumeStory()
                        }
                    }
                }
        )
    }

    private var profileAndChainBoundView: AnyView {
        AnyView(
            overlayBoundView
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowUserProfileFromStory"))) { notification in
                    if let userId = notification.object as? String, !userId.isEmpty {
                        selectedUserId = userId
                        showUserProfile = true
                        pauseStory()
                    }
                }
                .sheet(isPresented: $showUserProfile, onDismiss: {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        resumeStory()
                    }
                }) {
                    if !selectedUserId.isEmpty {
                        UserProfileView(userId: selectedUserId)
                    }
                }
                .sheet(isPresented: $showChainView, onDismiss: {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        resumeStory()
                    }
                }) {
                    StoryChainView(
                        chainId: selectedChainId,
                        chainTitle: selectedChainTitle,
                        canContinueChain: canContinueChain,
                        initialStoryId: selectedChainStoryId.isEmpty ? nil : selectedChainStoryId,
                        initialChainPosition: selectedChainStoryPosition
                    )
                    .background(Color.clear)
                }
                .onChange(of: showChainView) { isOpen in
                    if isOpen {
                        pauseStory()
                    }
                }
                .onChange(of: showUserProfile) { oldValue, newValue in
                    if !newValue && oldValue {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            resumeStory()
                        }
                    }
                }
        )
    }

    // MARK: - Glassmorphic Components

    private var glassmorphicProgressBar: some View {
        HStack(spacing: 4) {
            ForEach(0..<storyCount, id: \.self) { index in
                GlassmorphicProgressBar(
                    progress: getProgressForSegment(index: index),
                    isActive: index == storyIndex,
                    audience: audienceForSegment(index: index)
                )
            }
        }
    }

    private func audienceForSegment(index: Int) -> String? {
        guard let storiesForAuthor = storyViewModel.stories[story.authorId],
              storiesForAuthor.indices.contains(index) else {
            return nil
        }
        return storiesForAuthor[index].audience
    }

    private var glassmorphicHeader: some View {
        HStack(spacing: 12) {
            Button(action: onProfileTap) {
                HStack(spacing: 10) {
                    ZStack {
                        if let profileImagePath = story.profileImagePath {
                            KFImage(URL(string: profileImagePath))
                                .resizable()
                                .scaledToFill()
                                .frame(width: 38, height: 38)
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(0.44), lineWidth: 1)
                                )
                                .shadow(color: Color.black.opacity(0.38), radius: 10, x: 0, y: 5)
                        } else {
                            Circle()
                                .fill(Color.black.opacity(0.16))
                                .frame(width: 38, height: 38)
                                .liquidGlass(in: Circle())

                            Image(systemName: "person.circle.fill")
                                .foregroundColor(.white.opacity(0.7))
                                .font(.system(size: 28))
                        }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(story.username)
                                .foregroundColor(.white)
                                .font(.custom("Poppins-SemiBold", size: 14))
                                .lineLimit(1)
                                .shadow(color: Color.black.opacity(0.60), radius: 5, x: 0, y: 2)

                            // ✅ INSIGNIA DE VERIFICADO
                            if story.authorId == Auth.auth().currentUser?.uid {
                                // Para el usuario actual, verificar si está verificado
                                CurrentUserVerifiedBadge(size: 12)
                            } else {
                                // Para otros usuarios, verificar si están verificados
                                VerifiedBadgeView(userId: story.authorId, size: 12)
                            }
                        }

                        Text(timeAgoString(from: story.timestamp))
                            .foregroundColor(.white.opacity(0.7))
                            .font(.custom("Poppins-Regular", size: 11))
                            .shadow(color: Color.black.opacity(0.55), radius: 4, x: 0, y: 2)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())

            Spacer()


            HStack(alignment: .top, spacing: 8) {
                Button(action: toggleQuickActions) {
                    Image(systemName: "ellipsis")
                        .foregroundColor(.white)
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.001))
                        .liquidGlass(in: Circle(), interactive: true)
                }
                .buttonStyle(PlainButtonStyle())

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .foregroundColor(.white)
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.001))
                        .liquidGlass(in: Circle(), interactive: true)
                }
            }
        }
    }

    private func storyQuickActionsOverlay(topInset: CGFloat) -> some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    dismissQuickActions()
                }

            storyQuickActionsDropdown
                .padding(.top, topInset + 74)
                .padding(.trailing, 16)
        }
    }

    private var storyQuickActionsDropdown: some View {
        VStack(spacing: 0) {
            if story.authorId == Auth.auth().currentUser?.uid {
                quickActionRow(
                    title: NSLocalizedString("storyContextMenu.viewActivity", comment: "View activity button")
                ) {
                    dismissQuickActions(resume: false)
                    fetchViewersAndShow()
                }

                quickActionDivider

                quickActionRow(
                    title: NSLocalizedString("storyContextMenu.save", comment: "Save story button")
                ) {
                    dismissQuickActions(resume: false)
                    saveStoryToDevice()
                }

                quickActionDivider

                quickActionRow(
                    title: NSLocalizedString("storyContextMenu.delete", comment: "Delete story button"),
                    isDestructive: true
                ) {
                    dismissQuickActions(resume: false)
                    deleteStory()
                }
            } else {
                quickActionRow(
                    title: NSLocalizedString("storyContextMenu.unfollow", comment: "Unfollow user button")
                ) {
                    dismissQuickActions(resume: false)
                    showUnfollowConfirmation = true
                }

                quickActionDivider

                quickActionRow(
                    title: NSLocalizedString("storyContextMenu.mute", comment: "Mute user button")
                ) {
                    dismissQuickActions(resume: false)
                    showMuteConfirmation = true
                }

                quickActionDivider

                quickActionRow(
                    title: NSLocalizedString("storyContextMenu.report", comment: "Report story button"),
                    isDestructive: true
                ) {
                    dismissQuickActions(resume: false)
                    onReportStory()
                }

                if canOptOutFromAuthorBestFriends {
                    quickActionDivider

                    quickActionRow(
                        title: NSLocalizedString("storyContextMenu.leaveBestFriends", comment: "Leave best friends")
                    ) {
                        dismissQuickActions(resume: false)
                        showBestFriendsOptOutConfirmation = true
                    }
                }
            }
        }
        .frame(minWidth: 200)
        .fixedSize(horizontal: true, vertical: false)
        .background(Color.white.opacity(0.001))
        .liquidGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(quickActionBorderColor, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.28), radius: 24, x: 0, y: 14)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onTapGesture {
        }
    }

    private var quickActionDivider: some View {
        Divider()
            .background(quickActionDividerColor)
    }

    private func quickActionRow(
        title: String,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        MenuActionRow(
            title: title,
            textColor: quickActionTextColor,
            isDestructive: isDestructive,
            action: action
        )
    }

    // MARK: - Menu Action Row (vertical list style)
    struct MenuActionRow: View {
        let title: String
        let textColor: Color
        var isDestructive: Bool = false
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                HStack {
                    Spacer(minLength: 0)
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(isDestructive ? .red : textColor)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 15)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
        }
    }


    // MARK: - Bottom Area
    private var glassmorphicBottomArea: some View {
        let hasChainOverlay = story.chainId != nil && story.chainTitle != nil && story.chainPosition != nil
        return VStack(spacing: 12) {
            // ✅ REACCIONES: Solo mostrar si el autor las permite
            if showReactions && authorAllowsReactions {
                VStack(spacing: 8) {
                    // Indicador de scroll
                    HStack {
                        Spacer()
                        Text(NSLocalizedString("storyContextMenu.scrollReactions", comment: "Scroll for more reactions"))
                            .font(.custom("Poppins-Regular", size: 10))
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(reactions, id: \.self) { reaction in
                                Button(action: {
                                    sendReaction(reaction)
                                }) {
                                    Text(reaction)
                                        .font(.system(size: 32))
                                        .frame(width: 52, height: 52)
                                        .background(Color.white.opacity(0.001))
                                        .liquidGlass(in: Circle(), interactive: true)
                                }
                                .scaleEffect(showReactions ? 1.0 : 0.5)
                                .animation(
                                    .spring(response: 0.3)
                                        .delay(Double(reactions.firstIndex(of: reaction) ?? 0) * 0.03),
                                    value: showReactions
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                    }
                    .frame(height: 70)
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .move(edge: .bottom).combined(with: .opacity)
                ))
            }

            // ✅ ÁREA DE INTERACCIÓN: Solo para historias de otros usuarios
            if story.authorId != Auth.auth().currentUser?.uid {

                // Si permite alguna interacción, mostrar controles
                if authorAllowsMessages || authorAllowsReactions || authorAllowsEphemeralPhotos {

                    HStack(spacing: 12) {
                        // ✅ ÁREA DE TEXTO/REACCIONES
                        HStack(spacing: 8) {
                            // Campo de texto solo si permite mensajes
                            if authorAllowsMessages {
                                TextField(storyMessagePlaceholder, text: $messageText, axis: .vertical)
                                    .foregroundColor(.white)
                                    .font(.custom("Poppins-Regular", size: 14))
                                    .padding(.leading, 4)
                                    .lineLimit(1...3)
                                    .focused($isTextFieldFocused)
                                    .submitLabel(.send)
                                    .onSubmit {
                                        if !messageText.isEmpty {
                                            sendMessage()
                                        }
                                    }
                                    .onChange(of: isTextFieldFocused) { focused in
                                        if focused {
                                            pauseStory()
                                        } else {
                                            resumeStory()
                                        }
                                    }
                            }

                            // ✅ BOTÓN REACCIONES: Siempre visible si permite reacciones
                            if authorAllowsReactions && (messageText.isEmpty || !authorAllowsMessages) {
                                Button(action: {
                                    withAnimation(.spring()) {
                                        showReactions.toggle()
                                    }
                                }) {
                                    Image(systemName: showReactions ? "face.smiling.fill" : "face.smiling")
                                        .foregroundColor(.white)
                                        .font(.system(size: 18))
                                }
                                .onChange(of: showReactions) { isOpen in
                                    if isOpen {
                                        pauseStory() // ✅ Pausar historia cuando se abren reacciones
                                    } else {
                                        // ✅ Reanudar historia cuando se cierran reacciones
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                            resumeStory()
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.001))
                        .liquidGlass(in: Capsule(), interactive: true)

                        // ✅ BOTÓN CÁMARA: Solo si permite fotos efímeras
                        if authorAllowsEphemeralPhotos {
                            Button(action: {
                                showEphemeralPicker = true
                            }) {
                                Image(systemName: "camera.fill")
                                    .foregroundColor(.white)
                                    .font(.system(size: 18))
                                    .frame(width: 44, height: 44)
                                    .background(Color.white.opacity(0.001))
                                    .liquidGlass(in: Circle(), interactive: true)
                            }
                            .photosPicker(isPresented: $showEphemeralPicker, selection: $selectedPhoto, matching: .images)
                            .onChange(of: showEphemeralPicker) { isOpen in
                                if isOpen {
                                    pauseStory() // ✅ Pausar historia cuando se abre selector de fotos
                                } else {
                                    // ✅ Reanudar historia cuando se cierra selector de fotos
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                        resumeStory()
                                    }
                                }
                            }
                        }

                        // ✅ BOTÓN ENVIAR: Solo si hay mensaje Y permite mensajes
                        if !messageText.isEmpty && authorAllowsMessages {
                            Button(action: sendMessage) {
                                Image(systemName: "paperplane.fill")
                                    .foregroundColor(.white)
                                    .font(.system(size: 18))
                                    .frame(width: 44, height: 44)
                                    .background(Color.white.opacity(0.001))
                                    .liquidGlass(in: Circle(), interactive: true)
                            }
                            .frame(width: 54, height: 54)
                            .contentShape(Rectangle())
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .animation(.easeInOut(duration: 0.3), value: keyboardHeight)

                } else {
                    // ✅ MENSAJE: Cuando no permite ninguna interacción
                    VStack(spacing: 8) {
                        Image(systemName: "eye.slash")
                            .font(.system(size: 20))
                            .foregroundColor(.white.opacity(0.6))

                        Text("stories.noInteractions")
                            .font(.custom("Poppins-Regular", size: 14))
                            .foregroundColor(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(
                        Color.white.opacity(0.001)
                            .liquidGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    )
                }
            }

            // 🔗 STORY CHAINS: Botones para cadenas de historias
            if let chainId = story.chainId, let chainTitle = story.chainTitle, let chainPosition = story.chainPosition {
                VStack(spacing: 8) {
                    // Banner de información de la cadena
                    HStack {
                        Spacer()

                        HStack {
                            Image(systemName: "link")
                                .foregroundColor(.blue)
                                .font(.caption)

                            Text(String(format: NSLocalizedString("storyChains.part", comment: "Part"), chainPosition, chainTitle))
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.001))
                        .liquidGlass(in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                        Spacer()
                    }

                    // Botones de acción
                    HStack(spacing: 12) {
                        // Botón para ver cadena completa
                        Button(action: {
                            showChainView(
                                chainId: chainId,
                                chainTitle: chainTitle,
                                initialStoryId: story.id,
                                initialChainPosition: chainPosition
                            )
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "list.bullet")
                                    .foregroundColor(.white)
                                    .font(.system(size: 14))

                                Text(NSLocalizedString("storyChains.viewChain", comment: "View Chain"))
                                    .font(.custom("Poppins-Medium", size: 14))
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.001))
                            .liquidGlass(in: Capsule(), interactive: true)
                        }

                        // Botón principal para continuar (solo si se puede)
                        if canContinueChain {

                            Button(action: {
                                continueStoryChain(chainId: chainId, chainTitle: chainTitle, chainPosition: chainPosition)
                            }) {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(.white)
                                    .font(.system(size: 16))

                                Text(NSLocalizedString("storyChains.continueStory", comment: "Continue Story"))
                                    .font(.custom("Poppins-Medium", size: 16))
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(0.001))
                            .liquidGlass(in: Capsule(), interactive: true)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 8)
                .padding(.vertical, 12)
                .background(
                    Color.white.opacity(0.001)
                        .liquidGlass(in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                )
                .offset(y: 10)
            }
        }
        .padding(.horizontal, 16)
        // ✅ Eliminar padding interno si el teclado está visible
        .padding(.bottom, isKeyboardVisible ? 0 : (hasChainOverlay ? 12 : 25))
    }

    private var contentView: some View {
        let resolvedScreenSize = CGSize(
            width: max(screenSize.width, 1),
            height: max(screenSize.height, 1)
        )
        let mediaAspectRatio = GlassmorphicStoryViewer.parseAspectRatio(story.aspectRatio)
            ?? (resolvedScreenSize.width / resolvedScreenSize.height)
        let presentationMode = StoryMediaLayoutRules.presentationMode(
            for: mediaAspectRatio,
            canvasAspectRatio: resolvedScreenSize.width / resolvedScreenSize.height
        )

        return ScreenshotProtectedView(isProtected: (story.audience?.lowercased() ?? "") != "everyone", fillsContainer: true) {
            ZStack {
                // ✅ CONTENIDO PRINCIPAL (imagen/video)
                Group {
                    if story.mediaItem.type == .video, let url = URL(string: story.mediaItem.url) {
                    GlassmorphicStoryVideoPlayer(
                        url: url,
                        isPlaying: Binding(
                            get: { !isPaused },
                            set: { isPaused = !$0 }
                        ),
                        isHorizontalVideo: GlassmorphicStoryViewer.isHorizontalAspectRatio(story.aspectRatio),
                        videoGravity: presentationMode.videoGravity,
                        shouldLoop: false,
                        onProgressUpdate: { newProgress in
                            // ✅ ACTUALIZAR PROGRESO DE LA HISTORIA (con verificación)
                            guard currentStoryId == story.id else { return }
                            progress = newProgress
                        },
                        onVideoComplete: {
                            // ✅ VIDEO TERMINÓ, IR A SIGUIENTE (solo si no está pausado)
                            if !isPaused {
                                onNext()
                            }
                        }
                    )
                    .frame(width: screenSize.width, height: screenSize.height)
                    .background(
                        Group {
                            if presentationMode == .fitWithBlur,
                               let backgroundFrameURL = story.backgroundFrameURL,
                               let url = URL(string: backgroundFrameURL) {
                                KFImage(url)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .blur(radius: 15) // ✅ BLUR SUTIL
                                    .scaleEffect(1.2) // ✅ ESCALADO PARA EVITAR BORDES
                                    .clipped()
                            } else {
                                // ✅ FALLBACK: Degradado elegante
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.black.opacity(0.85),
                                        Color.black.opacity(0.6),
                                        Color.black.opacity(0.4)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            }
                        }
                    )
                    .id(story.id) // ✅ FORZAR RECREACIÓN CUANDO CAMBIA LA HISTORIA
                } else if story.mediaItem.type == .image, let url = URL(string: story.mediaItem.url) {
                    KFImage(url)
                        .placeholder {
                            ZStack {
                                Color.black
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(1.2)
                            }
                        }
                        .resizable()
                        .aspectRatio(contentMode: presentationMode.swiftUIContentMode)
                        .frame(width: screenSize.width, height: screenSize.height)
                        .background(
                            // ✅ FONDO BLUR para imágenes (usando la misma imagen con blur)
                            KFImage(url)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .blur(radius: 20) // ✅ BLUR INTENSO para fondo
                                .scaleEffect(1.3) // ✅ ESCALADO PARA EVITAR BORDES
                                .clipped()
                        )
                        .clipped()
                } else {
                    ZStack {
                        Color.black
                        VStack(spacing: 12) {
                            Image(systemName: "photo.on.rectangle")
                                .font(.system(size: 40))
                                .foregroundColor(.white.opacity(0.6))
                            Text("stories.contentUnavailable")
                                .foregroundColor(.white.opacity(0.8))
                                .font(.custom("Poppins-Medium", size: 16))
                        }
                    }
                    .frame(width: screenSize.width, height: screenSize.height)
                }
            }
        }
        .clipped() // Ensure content doesn't overflow
        }
    }

    private var navigationTouchAreas: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: geometry.size.width * 0.15) // Reduced from 0.2 to 0.15
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !shouldSuppressNavigationTap else { return }
                        onPrevious()
                    }

                Spacer()

                Rectangle()
                    .fill(Color.clear)
                    .frame(width: geometry.size.width * 0.15) // Reduced from 0.2 to 0.15
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !shouldSuppressNavigationTap else { return }
                        onNext()
                    }
            }
            .frame(height: geometry.size.height * 0.5) // ✅ MUY REDUCIDO: Solo área central
            .offset(y: 150) // ✅ MUY AUMENTADO: Muy abajo para evitar completamente el header
        }
    }

    // MARK: - ✅ PRELOADING
    private func preloadNextStory() {
        // ✅ Obtener todas las historias del usuario actual
        let userId = story.authorId
        guard let allStories = storyViewModel.stories[userId],
              let currentStoryId = story.id else {
            return
        }

        // ✅ Precargar la siguiente historia
        storyViewModel.preloadNextStory(currentStoryId: currentStoryId, allStories: allStories)
    }

    // MARK: - Keyboard Handling
    private func setupKeyboardNotifications() {
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification,
            object: nil,
            queue: .main
        ) { notification in
            if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                withAnimation(.easeInOut(duration: 0.3)) {
                    keyboardHeight = keyboardFrame.height
                    isKeyboardVisible = true
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil,
            queue: .main
        ) { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                keyboardHeight = 0
                isKeyboardVisible = false
            }
        }
    }

    private func removeKeyboardNotifications() {
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)

        // Clear focus and resume story smoothly
        if isTextFieldFocused {
            isTextFieldFocused = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                resumeStory()
            }
        }
    }

    // MARK: - Gestures

    private var storyMessagePlaceholder: String {
        let format = NSLocalizedString("stories.sendMessagePlaceholder", comment: "Send story message placeholder")
        return String(format: format, story.username)
    }

    private func isProtectedGestureStart(_ location: CGPoint) -> Bool {
        let topProtectedHeight: CGFloat = 180
        let topRightProtectedX = screenSize.width - 120
        let bottomProtectedHeight = screenSize.height - 170

        if location.y < topProtectedHeight {
            return true
        }

        if location.y < 220 && location.x > topRightProtectedX {
            return true
        }

        if location.y > bottomProtectedHeight {
            return true
        }

        return false
    }

    private var holdToPauseGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard canStartHoldGesture(from: value.startLocation) else { return }

                if abs(value.translation.width) > 14 || abs(value.translation.height) > 14 {
                    cancelPendingHoldPause()
                    return
                }

                guard holdPauseWorkItem == nil, holdStartLocation == nil else { return }
                holdStartLocation = value.startLocation

                let workItem = DispatchWorkItem {
                    guard self.canStartHoldGesture(from: value.startLocation) else { return }
                    self.isHoldingStory = true
                    self.pauseStory()
                    withAnimation(.easeInOut(duration: 0.18)) {
                        self.isUIHidden = true
                    }
                }

                holdPauseWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: workItem)
            }
            .onEnded { _ in
                let shouldResume = isHoldingStory
                cancelPendingHoldPause()
                isHoldingStory = false

                if shouldResume {
                    suppressNavigationTapUntil = Date().addingTimeInterval(0.25)
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isUIHidden = false
                    }
                    resumeStory()
                }
            }
    }

    private func canStartHoldGesture(from location: CGPoint) -> Bool {
        guard !isMenuInteractionActive,
              !isKeyboardVisible,
              !isProtectedGestureStart(location),
              !showQuickActions,
              !showViewers,
              !showingReportSheet,
              !showingBlockConfirmation,
              !showUserProfile,
              !showChainView,
              !showReactions,
              !showEphemeralPicker,
              !showBestFriendsOptOutConfirmation,
              !showUnfollowConfirmation,
              !showMuteConfirmation else {
            return false
        }

        return true
    }

    private var shouldSuppressNavigationTap: Bool {
        guard let suppressNavigationTapUntil else { return false }
        return Date() < suppressNavigationTapUntil
    }

    private func cancelPendingHoldPause() {
        holdPauseWorkItem?.cancel()
        holdPauseWorkItem = nil
        holdStartLocation = nil
    }

    // ✅ UNIFIED GESTURE: Drag, Swipe Up/Down/Horizontal
    private var unifiedDragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard !isMenuInteractionActive else { return }

                if isProtectedGestureStart(value.startLocation) {
                    return
                }

                if !isPaused && !isHoldingStory {
                    pauseStory()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isUIHidden = true
                    }
                }

                // Si ya se disparó una acción (nav/reply), ignorar resto del drag
                if gestureActionTriggered { return }

                // SWIPE UP (Quick Reply)
                if value.translation.height < -60 && abs(value.translation.width) < 50 {
                    if authorAllowsMessages {
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                        withAnimation {
                            isTextFieldFocused = true
                            isUIHidden = false
                        }
                        gestureActionTriggered = true
                    }
                }

                // HORIZONTAL SWIPE (Navigation) - Solo si es cadena
                else if let chainId = story.chainId, !chainStories.isEmpty {
                    if value.translation.width > 60 {
                         goToPreviousChainPart()
                         gestureActionTriggered = true
                    } else if value.translation.width < -60 {
                         goToNextChainPart()
                         gestureActionTriggered = true
                    }
                }
            }
            .onEnded { value in
                guard !isMenuInteractionActive else { return }

                if isProtectedGestureStart(value.startLocation) {
                    return
                }

                isHoldingStory = false
                cancelPendingHoldPause()
                gestureActionTriggered = false

                // Restaurar UI
                if isUIHidden {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isUIHidden = false
                    }
                }

                if !isTextFieldFocused {
                    resumeStory()
                }
            }
    }

    // ✅ ZOOM: Gesto de pinch to zoom
    private var pinchGesture: some Gesture {
        MagnificationGesture()
            .onChanged { scale in
                let newScale = lastZoomScale * scale
                zoomScale = min(max(newScale, 1.0), 3.0) // Limitar zoom entre 1x y 3x
            }
            .onEnded { _ in
                lastZoomScale = zoomScale

                // Volver a escala normal si es muy pequeña
                if zoomScale < 1.2 {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        zoomScale = 1.0
                        lastZoomScale = 1.0
                    }
                }
            }
    }

    // MARK: - Actions

    // 🔗 STORY CHAINS: Navegar a la siguiente parte de la cadena
    private func goToNextChainPart() {
        guard currentChainIndex < chainStories.count - 1 else { return }

        let nextIndex = currentChainIndex + 1
        let nextStory = chainStories[nextIndex]

        // Actualizar el índice actual
        currentChainIndex = nextIndex

        // Notificar al padre para cambiar la historia
        NotificationCenter.default.post(
            name: NSNotification.Name("NavigateToChainStory"),
            object: nil,
            userInfo: [
                "storyId": nextStory.id ?? "",
                "chainIndex": nextIndex
            ]
        )
    }

    // 🔗 STORY CHAINS: Navegar a la parte anterior de la cadena
    private func goToPreviousChainPart() {
        guard currentChainIndex > 0 else { return }

        let previousIndex = currentChainIndex - 1
        let previousStory = chainStories[previousIndex]

        // Actualizar el índice actual
        currentChainIndex = previousIndex

        // Notificar al padre para cambiar la historia
        NotificationCenter.default.post(
            name: NSNotification.Name("NavigateToChainStory"),
            object: nil,
            userInfo: [
                "storyId": previousStory.id ?? "",
                "chainIndex": previousIndex
            ]
        )
    }

    // 🔗 STORY CHAINS: Cargar todas las historias de la cadena
    private func loadChainStories() {
        guard let chainId = story.chainId else { return }

        isLoadingChainStories = true

        Task {
            do {
                let storiesSnapshot = try await firestoreService.db
                    .collectionGroup("stories")
                    .whereField("chainId", isEqualTo: chainId)
                    .order(by: "chainPosition")
                    .getDocuments()

                let stories = storiesSnapshot.documents.compactMap { doc in
                    try? doc.data(as: Story.self)
                }

                await MainActor.run {
                    chainStories = stories

                    // Encontrar el índice de la historia actual
                    if let currentStoryId = story.id {
                        currentChainIndex = stories.firstIndex { $0.id == currentStoryId } ?? 0
                    }

                    isLoadingChainStories = false
                }
            } catch {
                await MainActor.run {
                    isLoadingChainStories = false
                }
            }
        }
    }

    private func sendMessage() {
        guard !messageText.isEmpty, let storyId = story.id else { return }

        let messageToSend = messageText
        messageText = "" // Clear immediately for better UX
        isTextFieldFocused = false // Dismiss keyboard

        storyViewModel.sendMessage(
            to: story.authorId,
            storyId: storyId,
            message: messageToSend
        ) { success in
            if success {
                showSuccessAnimation("Mensaje enviado")
            } else {
                // Restore message if failed
                messageText = messageToSend
            }
        }
    }

    private func sendReaction(_ reaction: String) {
        guard let storyId = story.id else { return }

        storyViewModel.sendReaction(
            to: story.authorId,
            storyId: storyId,
            reaction: reaction
        )

        withAnimation(.spring()) {
            showReactions = false
        }

        // ✅ TRIGGER FLOATING VISUAL FEEDBACK
        let randomX = CGFloat.random(in: 50...(screenSize.width - 50))
        let heart = FloatingHeart(emoji: reaction, startX: randomX)
        floatingHearts.append(heart)

        // Remove heart after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if !floatingHearts.isEmpty {
                floatingHearts.removeFirst()
            }
        }

        showSuccessAnimation(NSLocalizedString("stories.reactionSent", comment: "Reaction sent"))

        // ✅ Reanudar historia inmediatamente después de enviar reacción
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            resumeStory()
        }
    }

    private func handleEphemeralPhoto(_ photo: PhotosPickerItem?) {
        guard let photo = photo else { return }

        Task {
            do {
                guard let data = try await photo.loadTransferable(type: Data.self),
                      let uiImage = UIImage(data: data),
                      let storyId = story.id else {
                    return
                }

                storyViewModel.sendEphemeralMoment(
                    to: story.authorId,
                    storyId: storyId,
                    image: uiImage
                ) { success in
                    if success {
                        showSuccessAnimation("Momento enviado")
                        // ✅ Reanudar historia después de enviar foto efímera
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            resumeStory()
                        }
                    }
                }
            } catch {
                // ✅ Reanudar historia si hay error
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    resumeStory()
                }
            }
        }
    }

    private func deleteStory() {
        guard let storyId = story.id else { return }

        storyViewModel.deleteStory(userId: story.authorId, storyId: storyId) { error in
            if error == nil {
                // ✅ PASAR A LA SIGUIENTE HISTORIA en lugar de cerrar
                onNext()
            }
        }
        showQuickActions = false
    }

    private func fetchViewersAndShow() {
        guard let storyId = story.id else { return }

        storyViewModel.fetchViewers(for: story.authorId, storyId: storyId) { _ in
            showViewers = true
            showQuickActions = false
        }
    }

    private func saveStoryToDevice() {
        if let url = URL(string: story.mediaItem.url) {
            Task {
                do {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    if story.mediaItem.type == .image {
                        try await PHPhotoLibrary.shared().performChanges {
                            PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
                        }
                        showSuccessAnimation(NSLocalizedString("stories.savedImage", comment: "Image saved"))
                    } else if story.mediaItem.type == .video {
                        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("story_video.mp4")
                        try data.write(to: tempURL)
                        try await PHPhotoLibrary.shared().performChanges {
                            PHAssetCreationRequest.forAsset().addResource(with: .video, fileURL: tempURL, options: nil)
                        }
                        showSuccessAnimation(NSLocalizedString("stories.savedVideo", comment: "Video saved"))
                        try? FileManager.default.removeItem(at: tempURL)
                    }
                } catch {
                }
            }
        }
        showQuickActions = false
    }

    private func showSuccessAnimation(_ message: String) {
        successMessageText = message
        withAnimation(.spring()) {
            showSuccessMessage = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.spring()) {
                showSuccessMessage = false
            }
        }
    }

    private func pauseForMenuInteraction() {
        pauseStory()
        isMenuInteractionActive = true
        menuAutoResumeWorkItem?.cancel()

        let workItem = DispatchWorkItem {
            let isAnyOverlayVisible = self.showQuickActions
                || self.showViewers
                || self.showingReportSheet
                || self.showingBlockConfirmation
                || self.showUserProfile
                || self.showChainView
                || self.showReactions
                || self.showEphemeralPicker
                || self.showBestFriendsOptOutConfirmation
                || self.showUnfollowConfirmation
                || self.showMuteConfirmation

            self.isMenuInteractionActive = false
            if !isAnyOverlayVisible {
                self.resumeStory()
            }
            self.menuAutoResumeWorkItem = nil
        }

        menuAutoResumeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0, execute: workItem)
    }

    private func cancelMenuAutoResume() {
        menuAutoResumeWorkItem?.cancel()
        menuAutoResumeWorkItem = nil
        isMenuInteractionActive = false
    }

    private func toggleQuickActions() {
        if showQuickActions {
            dismissQuickActions()
        } else {
            pauseForMenuInteraction()
            withAnimation(.spring(response: 0.26, dampingFraction: 0.92)) {
                showQuickActions = true
            }
        }
    }

    private func dismissQuickActions(resume: Bool = true) {
        let shouldResume = resume
        withAnimation(.spring(response: 0.24, dampingFraction: 0.92)) {
            showQuickActions = false
        }
        cancelMenuAutoResume()

        guard shouldResume else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            self.resumeStory()
        }
    }

    private func optOutFromBestFriends() {
        pauseStory()
        bestFriendsService.optOutFromBestFriends(of: story.authorId) { error in
            DispatchQueue.main.async {
                if let error = error {
                    let fallback = NSLocalizedString("bestFriends.optOut.error", comment: "Could not leave best friends")
                    let message = error.localizedDescription.isEmpty ? fallback : error.localizedDescription
                    self.showSuccessAnimation(message)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.resumeStory()
                    }
                    return
                }

                self.showSuccessAnimation(NSLocalizedString("bestFriends.optOut.success", comment: "You left best friends"))
                if let currentUserId = Auth.auth().currentUser?.uid {
                    StorySeenStateService.shared.invalidate(
                        viewerId: currentUserId,
                        authorId: self.story.authorId
                    )
                }

                // Dar tiempo a leer el mensaje y mantener flujo natural de historias.
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    self.onNext()
                }
            }
        }
    }

    private func unfollowStoryAuthor() {
        guard let currentUserId = Auth.auth().currentUser?.uid, currentUserId != story.authorId else {
            return
        }

        pauseStory()
        firestoreService.unfollowUser(currentUserId: currentUserId, targetUserId: story.authorId) { error in
            DispatchQueue.main.async {
                if let error = error {
                    let fallback = NSLocalizedString("storyContextMenu.actionFailed", comment: "Generic story action failed")
                    let message = error.localizedDescription.isEmpty ? fallback : error.localizedDescription
                    self.showSuccessAnimation(message)
                } else {
                    self.showSuccessAnimation(NSLocalizedString("storyContextMenu.unfollow.success", comment: "Unfollow success message"))
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.resumeStory()
                }
            }
        }
    }

    private func muteStoryAuthor() {
        guard let currentUserId = Auth.auth().currentUser?.uid, currentUserId != story.authorId else {
            return
        }

        pauseStory()
        firestoreService.db
            .collection("users")
            .document(currentUserId)
            .updateData([
                "muteSettings.mutedUsers": FieldValue.arrayUnion([story.authorId])
            ]) { error in
                DispatchQueue.main.async {
                    if let error = error {
                        let fallback = NSLocalizedString("storyContextMenu.actionFailed", comment: "Generic story action failed")
                        let message = error.localizedDescription.isEmpty ? fallback : error.localizedDescription
                        self.showSuccessAnimation(message)
                    } else {
                        self.showSuccessAnimation(NSLocalizedString("storyContextMenu.mute.successWithHint", comment: "Mute success message with settings hint"))
                    }

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.resumeStory()
                    }
                }
            }
    }

    // MARK: - Story Playback

    private func prepareAndStartStory() {

        // ✅ SIMPLIFICADO: Solo reset de estado
        progress = 0.0
        isPaused = false
        currentStoryId = story.id

        loadAuthorInteractionSettings()

        // Mark story as viewed
        if let storyId = story.id {
            storyViewModel.markStoryAsViewed(
                userId: story.authorId,
                storyId: storyId,
                storyTimestamp: story.timestamp,
                audience: story.audience
            )
        }

        // ✅ SIMPLIFICADO: Solo timer para imágenes
        if story.mediaItem.type == .image {
            startImageTimer()
        }
    }

    private func stopAndCleanupStory() {

        // ✅ SIMPLIFICADO: Solo pausar y limpiar timer
        isPaused = true
        cancelMenuAutoResume()
        cancelPendingHoldPause()
        isHoldingStory = false
        progress = 0.0
        imageTimer?.invalidate()
        imageTimer = nil

        // ✅ CLEANUP DE AUDIO
        cleanupAudioSession()
    }

    // ✅ NUEVA FUNCIÓN: Limpiar sesión de audio
    private func cleanupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
        }
    }


    private func startImageTimer() {
        // ✅ NUNCA resetear progress - siempre continuar desde donde se pausó

        let duration = story.duration > 0 ? story.duration : defaultStoryDuration
        imageTimer?.invalidate()

        imageTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            // ✅ CRITICAL FIX: Doble verificación de pausa para evitar condiciones de carrera
            guard !self.isPaused else {
                return
            }

            self.progress += 0.05 / duration

            if self.progress >= 1.0 {
                self.progress = 1.0  // Cap at 100%
                self.imageTimer?.invalidate()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.onNext()
                }
            }
        }
    }

    // ✅ SIMPLIFICADO: Solo cambiar estado
    private func pauseStory() {
        isPaused = true
        // ✅ INVALIDAR TIMER para evitar bucle infinito
        imageTimer?.invalidate()
        imageTimer = nil
    }

    private func resumeStory() {
        // ✅ REFUERZO SEGURO: No reanudar si cualquier overlay está visible o si hay teclado/drag
        let isAnyOverlayVisible = showQuickActions || showViewers || showingReportSheet || showingBlockConfirmation || showUserProfile || showChainView || showReactions || showEphemeralPicker || showBestFriendsOptOutConfirmation || showUnfollowConfirmation || showMuteConfirmation

        guard !isKeyboardVisible && !isDragging && !isMenuInteractionActive && !isAnyOverlayVisible else {
            return
        }

        isPaused = false

        // ✅ SIEMPRE RECREAR TIMER para continuar desde el progreso actual
        if story.mediaItem.type == .image {
            startImageTimer()
        }
    }

    // MARK: - Helpers

    private func handleStoryChange() {

        // ✅ SIMPLIFICADO: Cleanup inmediato
        stopAndCleanupStory()

        // ✅ RESET PROGRESO INMEDIATAMENTE
        progress = 0.0
        currentStoryId = story.id


        // ✅ SIMPLIFICADO: Sin delay, transición inmediata
        prepareAndStartStory()
    }

    private func getProgressForSegment(index: Int) -> Double {
        if index < storyIndex {
            return 1.0  // Historias anteriores completadas
        } else if index == storyIndex {
            return progress  // Historia actual con progreso dinámico
        } else {
            return 0.0  // Historias futuras sin progreso
        }
    }

    private func timeAgoString(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.locale = Locale(identifier: "es")
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func loadAuthorInteractionSettings() {
        FirestoreService().db.collection("users").document(story.authorId).getDocument { document, error in
            DispatchQueue.main.async {
                if let document = document, document.exists,
                   let data = document.data(),
                   let visibilitySettings = data["contentVisibilitySettings"] as? [String: Any] {

                    self.authorAllowsMessages = visibilitySettings["allowStoryMessages"] as? Bool ?? true
                    self.authorAllowsReactions = visibilitySettings["allowStoryReactions"] as? Bool ?? true
                    self.authorAllowsEphemeralPhotos = visibilitySettings["allowStoryEphemeralPhotos"] as? Bool ?? true
                }
            }
        }
    }

    // 🔗 FUNCIÓN: Verificar si el usuario puede continuar la cadena
    private func checkCanContinueChain(chainId: String) {

        guard let currentUserId = Auth.auth().currentUser?.uid else {

            canContinueChain = false
            return
        }


        // 🔥 LÓGICA MEJORADA: 1. Intentar obtener configuración desde la colección global 'storyChains'
        let firestoreService = FirestoreService()
        firestoreService.db.collection("storyChains").document(chainId).getDocument { snapshot, error in
            if let document = snapshot, document.exists, let data = document.data() {

                self.processChainMetadata(data, currentUserId: currentUserId)
                return
            }

            // 2. FALLBACK: Si no existe el documento global, buscar la primera historia (legacy)

            self.fallbackToCheckFirstPart(chainId: chainId, currentUserId: currentUserId)
        }
    }

    // 🔗 AUXILIAR: Procesar metadata de la cadena (desde global o primera parte)
    private func processChainMetadata(_ data: [String: Any], currentUserId: String) {
        // El autor original de la cadena siempre puede continuarla
        let authorId = data["authorId"] as? String ?? ""
        if authorId == currentUserId {

            DispatchQueue.main.async {
                self.canContinueChain = true
            }
            return
        }

        // Verificar si se permite que otros continúen
        let allowOthersToContinue = data["allowOthersToContinue"] as? Bool ?? true


        if !allowOthersToContinue {

            DispatchQueue.main.async {
                self.canContinueChain = false
            }
            return
        }

        // Verificar audiencia de continuación
        let continuationAudience = data["continuationAudience"] as? String ?? "everyone"

        checkContinuationAudience(continuationAudience: continuationAudience, data: data, currentUserId: currentUserId)
    }

    // 🔗 FALLBACK: Buscar la primera parte de la cadena (lógica antigua)
    private func fallbackToCheckFirstPart(chainId: String, currentUserId: String) {
        let authorId = story.authorId
        let firestoreService = FirestoreService()

        firestoreService.db.collection("users").document(authorId).collection("stories")
            .whereField("chainId", isEqualTo: chainId)
            .whereField("chainPosition", isEqualTo: 1) // Primera parte
            .limit(to: 1)
            .getDocuments { snapshot, error in
                if let document = snapshot?.documents.first {
                    let data = document.data()

                    self.processChainMetadata(data, currentUserId: currentUserId)
                } else {

                    self.ultimateFallbackSearch(chainId: chainId, currentUserId: currentUserId)
                }
            }
    }

    // 🔗 ÚLTIMO RECURSO: Búsqueda global de la primera parte
    private func ultimateFallbackSearch(chainId: String, currentUserId: String) {
        let firestoreService = FirestoreService()
        firestoreService.db.collectionGroup("stories")
            .whereField("chainId", isEqualTo: chainId)
            .whereField("chainPosition", isEqualTo: 1)
            .limit(to: 1)
            .getDocuments { snapshot, error in
                guard let document = snapshot?.documents.first,
                      let data = document.data() as? [String: Any] else {

                    DispatchQueue.main.async {
                        self.canContinueChain = false
                    }
                    return
                }


                self.processChainMetadata(data, currentUserId: currentUserId)
            }
    }


    // 🔗 FUNCIÓN: Verificar audiencia de continuación
    private func checkContinuationAudience(continuationAudience: String, data: [String: Any], currentUserId: String) {
        let authorId = data["authorId"] as? String ?? ""


        switch continuationAudience {
        case "everyone":

            DispatchQueue.main.async {
                canContinueChain = true

            }

        case "connections":

            // Verificar conexión mutua usando PrivacyService
            let privacyService = PrivacyService()
            privacyService.checkMutualConnection(user1: currentUserId, user2: authorId) { isMutual in
                DispatchQueue.main.async {
                    canContinueChain = isMutual

                }
            }

        case "bestFriends":

            // Verificar si el autor tiene al usuario actual en sus mejores amigos
            let privacyService = PrivacyService()
            privacyService.checkIfBestFriend(userId: authorId, friendId: currentUserId) { isBestFriend in
                DispatchQueue.main.async {
                    canContinueChain = isBestFriend

                }
            }

        case "custom":

            // Verificar usuarios específicos
            let continuationCustomViewers = data["continuationCustomViewers"] as? [String] ?? []
            DispatchQueue.main.async {
                canContinueChain = continuationCustomViewers.contains(currentUserId)

            }

        case "customList":

            // Verificar lista personalizada
            let continuationCustomListId = data["continuationCustomListId"] as? String
            let authorId = data["authorId"] as? String ?? ""

            if let listId = continuationCustomListId {
                // Usar PrivacyService para obtener miembros de la lista
                let privacyService = PrivacyService()
                privacyService.getCustomListViewers(
                    listId: listId,
                    ownerId: authorId
                ) { members in
                    DispatchQueue.main.async {
                        canContinueChain = members.contains(currentUserId)

                    }
                }
            } else {

                DispatchQueue.main.async {
                    canContinueChain = false
                }
            }

        default:

            DispatchQueue.main.async {
                canContinueChain = false
            }
        }
    }

    // 🔗 FUNCIÓN: Continuar cadena de historias
    private func continueStoryChain(chainId: String, chainTitle: String, chainPosition: Int) {
        // Cerrar la vista actual
        dismiss()

        // Notificar al TabBarView para abrir CreatorView
        NotificationCenter.default.post(
            name: NSNotification.Name("OpenCreatorForChain"),
            object: nil,
            userInfo: [
                "chainId": chainId,
                "chainTitle": chainTitle,
                "chainPosition": chainPosition
            ]
        )
    }

    // 🔗 FUNCIÓN: Mostrar vista de cadena completa
    private func showChainView(chainId: String, chainTitle: String, initialStoryId: String? = nil, initialChainPosition: Int? = nil) {
        selectedChainId = chainId
        selectedChainTitle = chainTitle
        selectedChainStoryId = initialStoryId ?? ""
        selectedChainStoryPosition = initialChainPosition ?? 1
        showChainView = true
    }
}

// MARK: - Supporting Glassmorphic Views

struct GlassmorphicProgressBar: View {
    let progress: Double
    let isActive: Bool
    let audience: String?

    private var normalizedAudience: String {
        audience?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }

    private var progressGradient: LinearGradient {
        switch normalizedAudience {
        case "bestfriends", "best_friends", "best-friends":
            // Instagram-like Best Friends green
            return LinearGradient(
                colors: [Color(hex: "24C26A"), Color(hex: "5BE584")],
                startPoint: .leading,
                endPoint: .trailing
            )
        case "connections", "mutuals", "mutual":
            // Mutuals accent (different from default)
            return LinearGradient(
                colors: [Color(hex: "00B4D8"), Color(hex: "4CC9F0")],
                startPoint: .leading,
                endPoint: .trailing
            )
        default:
            return LinearGradient(
                colors: [Color.blue, Color.purple, Color.pink],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }

    private var shadowColor: Color {
        switch normalizedAudience {
        case "bestfriends", "best_friends", "best-friends":
            return Color(hex: "24C26A").opacity(0.65)
        case "connections", "mutuals", "mutual":
            return Color(hex: "00B4D8").opacity(0.55)
        default:
            return Color.purple.opacity(0.6)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                Rectangle()
                    .fill(Color.white.opacity(0.15))
                    .frame(height: 2.5)
                    .cornerRadius(1.25)

                // Progress with clamped value
                Rectangle()
                    .fill(progressGradient)
                    .frame(
                        width: geometry.size.width * min(max(progress, 0.0), 1.0),
                        height: 2.5
                    )
                    .cornerRadius(1.25)
                    .shadow(color: shadowColor, radius: 3, x: 0, y: 0)
                    .animation(
                        isActive ? .linear(duration: 0.1) : .none,
                        value: progress
                    )
            }
        }
        .frame(height: 2.5)
    }
}

struct GlassmorphicActionButton: View {
    let icon: String
    let title: String
    let subtitle: String?
    var isDestructive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundColor(isDestructive ? .red : .white)
                    .font(.system(size: 18))
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundColor(isDestructive ? .red : .white)
                        .font(.custom("Poppins-Medium", size: 14))

                    if let subtitle = subtitle {
                        Text(subtitle)
                            .foregroundColor(Color.white.opacity(0.7))
                            .font(.custom("Poppins-Regular", size: 11))
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .storyGlassmorphic()
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

struct GlassmorphicSuccessMessage: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(Color(hex: "007AFF"))
                .font(.system(size: 20))

            Text(text)
                .foregroundColor(.white)
                .font(.custom("Poppins-Medium", size: 14))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .storyGlassmorphic()
        .clipShape(Capsule())
    }
}

struct GlassmorphicStoryConfirmationDialog: View {
    let title: String
    let message: String
    let confirmTitle: String
    let cancelTitle: String
    var isDestructive: Bool = false
    let onConfirm: () -> Void
    let onCancel: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : .black.opacity(0.88)
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.82) : .black.opacity(0.62)
    }

    private var scrimColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.45) : Color.black.opacity(0.20)
    }

    var body: some View {
        ZStack {
            scrimColor
                .ignoresSafeArea()
                .onTapGesture {
                    onCancel()
                }

            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    Text(title)
                        .foregroundColor(primaryTextColor)
                        .font(.custom("Poppins-SemiBold", size: 18))
                        .multilineTextAlignment(.center)

                    Text(message)
                        .foregroundColor(secondaryTextColor)
                        .font(.custom("Poppins-Regular", size: 14))
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 10) {
                    Button(action: onCancel) {
                        Text(cancelTitle)
                            .font(.custom("Poppins-Medium", size: 14))
                            .foregroundColor(primaryTextColor)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(Color.white.opacity(0.001))
                            .liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(PlainButtonStyle())

                    Button(action: onConfirm) {
                        Text(confirmTitle)
                            .font(.custom("Poppins-SemiBold", size: 14))
                            .foregroundColor(isDestructive ? .red : primaryTextColor)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(Color.white.opacity(0.001))
                            .liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(20)
            .frame(maxWidth: 360)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .liquidGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            )
            .padding(.horizontal, 24)
        }
    }
}

struct GlassmorphicViewersSheet: View {
    let story: Story
    let viewers: [StoryViewer]
    let reactions: [StoryReaction]
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedTab = 0
    @State private var audienceUsers: [AppUser] = []
    @State private var audienceListName: String?
    @State private var isLoadingAudience = false
    @State private var didLoadAudience = false
    @State private var showAudienceList = false
    private let firestoreService = FirestoreService()

    private var normalizedAudience: String {
        story.audience?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? "everyone"
    }

    private var isEveryoneAudience: Bool {
        normalizedAudience == "everyone"
    }

    private var audienceTitle: String {
        switch normalizedAudience {
        case "connections", "mutuals", "mutual":
            return NSLocalizedString("audience.type.connections", comment: "Mutuals")
        case "bestfriends", "best_friends", "best-friends":
            return NSLocalizedString("audience.type.bestFriends", comment: "Best friends")
        case "customlist":
            return audienceListName ?? NSLocalizedString("audience.type.customList", comment: "Custom list")
        case "custom":
            return NSLocalizedString("audience.type.custom", comment: "Custom")
        case "onlyme", "only_me", "only-me":
            return NSLocalizedString("audience.type.onlyMe", comment: "Only me")
        default:
            return NSLocalizedString("audience.type.everyone", comment: "Everyone")
        }
    }

    private var audienceIcon: String {
        switch normalizedAudience {
        case "connections", "mutuals", "mutual":
            return "person.2.fill"
        case "bestfriends", "best_friends", "best-friends":
            return "heart.fill"
        case "customlist":
            return "list.bullet.rectangle"
        case "custom":
            return "person.crop.circle.badge.plus"
        case "onlyme", "only_me", "only-me":
            return "lock.fill"
        default:
            return "globe.americas.fill"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            storyActivityHeader
                .padding(.horizontal, 22)
                .padding(.top, 12)

            audienceSection
                .padding(.horizontal, 22)
                .padding(.top, 18)

            GlassmorphicTabSelector(
                    tabs: [
                        String(format: NSLocalizedString("stories.activity.viewersTab", comment: ""), viewers.count),
                        String(format: NSLocalizedString("stories.activity.reactionsTab", comment: ""), reactions.count)
                    ],
                    selectedIndex: $selectedTab
                )
                .padding(.horizontal, 22)
                .padding(.top, 14)

            TabView(selection: $selectedTab) {
                ZStack {
                    if viewers.isEmpty {
                        GlassmorphicEmptyState(
                            icon: "eye.slash",
                            message: NSLocalizedString("stories.activity.noViewers", comment: "No viewers yet")
                        )
                        .frame(maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(viewers) { viewer in
                                    GlassmorphicViewerRow(viewer: viewer)
                                }
                            }
                            .padding(.horizontal, 22)
                            .padding(.top, 18)
                            .padding(.bottom, 28)
                        }
                    }
                }
                .tag(0)

                ZStack {
                    if reactions.isEmpty {
                        GlassmorphicEmptyState(
                            icon: "heart.slash",
                            message: NSLocalizedString("stories.activity.noReactions", comment: "No reactions yet")
                        )
                        .frame(maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(reactions) { reaction in
                                    GlassmorphicReactionRow(reaction: reaction)
                                }
                            }
                            .padding(.horizontal, 22)
                            .padding(.top, 18)
                            .padding(.bottom, 28)
                        }
                    }
                }
                .tag(1)
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
        }
        .background(Color.clear.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            guard !didLoadAudience else { return }
            didLoadAudience = true
            loadAudienceMembers()
        }
        .sheet(isPresented: $showAudienceList) {
            GlassmorphicAudienceMembersSheet(
                title: audienceTitle,
                users: audienceUsers
            )
        }
    }

    private var storyActivityHeader: some View {
        ZStack(alignment: .top) {
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(activityPrimaryText)
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.001))
                        .liquidGlass(in: Circle(), interactive: true)
                }
                .buttonStyle(.plain)

                Spacer()
            }

            VStack(spacing: 2) {
                Text(NSLocalizedString("stories.activity.title", comment: "Activity Title"))
                    .font(.custom("Poppins-SemiBold", size: 18))
                    .foregroundColor(activityPrimaryText)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 2)
        }
    }

    private var activityPrimaryText: Color {
        colorScheme == .dark ? .white : .black.opacity(0.88)
    }

    private var activitySecondaryText: Color {
        colorScheme == .dark ? .white.opacity(0.62) : .black.opacity(0.54)
    }

    private var audienceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isLoadingAudience {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(activitySecondaryText)
                    Text(NSLocalizedString("stories.activity.audienceLoading", comment: "Loading audience"))
                        .font(.custom("Poppins-Regular", size: 13))
                        .foregroundColor(activitySecondaryText)
                }
            } else if isEveryoneAudience {
                Text(NSLocalizedString("audience.description.everyone", comment: "Everyone audience description"))
                    .font(.custom("Poppins-Regular", size: 13))
                    .foregroundColor(activitySecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else if canOpenAudienceList {
                Button {
                    showAudienceList = true
                } label: {
                    audienceSummaryRow(showsChevron: true)
                }
                .buttonStyle(.plain)
            } else {
                audienceSummaryRow(showsChevron: false)
            }
        }
    }

    private var canOpenAudienceList: Bool {
        !isEveryoneAudience && !audienceUsers.isEmpty
    }

    private func audienceSummaryRow(showsChevron: Bool) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(activityPrimaryText.opacity(colorScheme == .dark ? 0.08 : 0.06))

                Image(systemName: audienceIcon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(activityPrimaryText.opacity(0.82))
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(audienceTitle)
                    .font(.custom("Poppins-Medium", size: 13))
                    .foregroundColor(activityPrimaryText)
                    .lineLimit(1)

                Text(audienceSummarySubtitle)
                    .font(.custom("Poppins-Regular", size: 11))
                    .foregroundColor(activitySecondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(activitySecondaryText)
            }
        }
        .contentShape(Rectangle())
    }

    private var audienceSummarySubtitle: String {
        if audienceUsers.isEmpty {
            return NSLocalizedString("stories.activity.audienceNoMembers", comment: "No users in this audience")
        }

        return String(format: NSLocalizedString("stories.activity.audienceMembersCount", comment: "Members count"), audienceUsers.count)
    }

    private func loadAudienceMembers() {
        isLoadingAudience = true
        audienceUsers = []
        audienceListName = nil

        switch normalizedAudience {
        case "connections", "mutuals", "mutual":
            firestoreService.fetchMutualConnections(userId: story.authorId) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let users):
                        self.audienceUsers = users.sorted { $0.username.lowercased() < $1.username.lowercased() }
                    case .failure:
                        self.audienceUsers = []
                    }
                    self.isLoadingAudience = false
                }
            }

        case "bestfriends", "best_friends", "best-friends":
            firestoreService.fetchUser(userId: story.authorId) { result in
                switch result {
                case .success(let user):
                    self.fetchAudienceUsersByIds(user.bestFriends)
                case .failure:
                    DispatchQueue.main.async {
                        self.audienceUsers = []
                        self.isLoadingAudience = false
                    }
                }
            }

        case "customlist":
            guard let listId = story.customListId, !listId.isEmpty else {
                isLoadingAudience = false
                return
            }

            firestoreService.fetchCustomListDetails(listId: listId, ownerId: story.authorId) { result in
                switch result {
                case .success(let list):
                    DispatchQueue.main.async {
                        self.audienceListName = list.name
                    }
                    self.fetchAudienceUsersByIds(list.members)
                case .failure:
                    DispatchQueue.main.async {
                        self.audienceUsers = []
                        self.isLoadingAudience = false
                    }
                }
            }

        case "custom":
            Firestore.firestore()
                .collection("users")
                .document(story.authorId)
                .getDocument { document, _ in
                    let visibilitySettings = document?.data()?["contentVisibilitySettings"] as? [String: Any]
                    let customUsers = visibilitySettings?["storyCustomUsers"] as? [String]
                        ?? visibilitySettings?["customStoryViewers"] as? [String]
                        ?? []
                    self.fetchAudienceUsersByIds(customUsers)
                }

        case "onlyme", "only_me", "only-me":
            fetchAudienceUsersByIds([story.authorId])

        default:
            isLoadingAudience = false
        }
    }

    private func fetchAudienceUsersByIds(_ userIds: [String]) {
        var seen = Set<String>()
        let uniqueIds = userIds.filter { id in
            guard !id.isEmpty else { return false }
            if seen.contains(id) { return false }
            seen.insert(id)
            return true
        }
        guard !uniqueIds.isEmpty else {
            DispatchQueue.main.async {
                self.audienceUsers = []
                self.isLoadingAudience = false
            }
            return
        }

        let chunks: [[String]] = stride(from: 0, to: uniqueIds.count, by: 10).map {
            Array(uniqueIds[$0..<min($0 + 10, uniqueIds.count)])
        }

        let group = DispatchGroup()
        let collectQueue = DispatchQueue(label: "story.audience.collect")
        var mergedUsers: [AppUser] = []

        for chunk in chunks {
            group.enter()
            firestoreService.fetchUsers(userIds: chunk) { result in
                defer { group.leave() }
                if case .success(let users) = result {
                    collectQueue.sync {
                        mergedUsers.append(contentsOf: users)
                    }
                }
            }
        }

        group.notify(queue: .main) {
            let order = Dictionary(uniqueIds.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
            self.audienceUsers = mergedUsers.sorted { lhs, rhs in
                (order[lhs.id] ?? Int.max) < (order[rhs.id] ?? Int.max)
            }
            self.isLoadingAudience = false
        }
    }
}

private struct GlassmorphicAudienceMembersSheet: View {
    let title: String
    let users: [AppUser]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : .black.opacity(0.88)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(primaryTextColor)
                            .frame(width: 40, height: 40)
                            .background(Color.white.opacity(0.001))
                            .liquidGlass(in: Circle(), interactive: true)
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }

                Text(title)
                    .font(.custom("Poppins-SemiBold", size: 18))
                    .foregroundColor(primaryTextColor)
                    .lineLimit(1)
                    .padding(.horizontal, 56)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 22)
            .padding(.top, 12)

            if users.isEmpty {
                GlassmorphicEmptyState(
                    icon: "person.2.slash",
                    message: NSLocalizedString("stories.activity.audienceNoMembers", comment: "No users in this audience")
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(users) { user in
                            GlassmorphicAudienceMemberRow(user: user)
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 22)
                    .padding(.bottom, 28)
                }
            }
        }
        .background(Color.clear.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct GlassmorphicAudienceMemberRow: View {
    let user: AppUser
    @Environment(\.colorScheme) private var colorScheme

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.92) : .black.opacity(0.86)
    }

    var body: some View {
        HStack(spacing: 12) {
            if let profileImagePath = user.profileImagePath,
               let url = URL(string: profileImagePath) {
                KFImage(url)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 42, height: 42)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(primaryTextColor.opacity(0.10))
                    .frame(width: 42, height: 42)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 16))
                            .foregroundColor(primaryTextColor.opacity(0.7))
                    )
            }

            HStack(spacing: 4) {
                Text(user.username)
                    .font(.custom("Poppins-SemiBold", size: 15))
                    .foregroundColor(primaryTextColor)
                    .lineLimit(1)

                if user.isVerified {
                    VerifiedBadgeView(userId: user.id, size: 12)
                }
            }

            Spacer()
        }
        .padding(.vertical, 8)
    }
}

struct GlassmorphicTabSelector: View {
    let tabs: [String]
    @Binding var selectedIndex: Int
    @Environment(\.colorScheme) private var colorScheme

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : .black.opacity(0.88)
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.52) : .black.opacity(0.46)
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<tabs.count, id: \.self) { index in
                tabButton(for: index)
            }
        }
    }

    private func tabButton(for index: Int) -> some View {
        let isSelected = selectedIndex == index

        return Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedIndex = index
            }
        }) {
            Text(tabs[index])
                .font(.custom("Poppins-SemiBold", size: 14))
                .foregroundColor(isSelected ? primaryTextColor : secondaryTextColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) {
                    Capsule()
                        .fill(isSelected ? primaryTextColor.opacity(0.86) : .clear)
                        .frame(width: 28, height: 2)
                }
                .opacity(isSelected ? 1 : 0.72)
        }
        .buttonStyle(.plain)
    }
}

struct GlassmorphicViewerRow: View {
    let viewer: StoryViewer
    @Environment(\.colorScheme) private var colorScheme

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : .black.opacity(0.88)
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.65) : .black.opacity(0.52)
    }

    var body: some View {
        HStack(spacing: 16) {
            // Profile image
            if let profileImagePath = viewer.profileImagePath,
               let url = URL(string: profileImagePath) {
                KFImage(url)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 48, height: 48)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 1))
            } else {
                ZStack {
                    Circle()
                        .fill(primaryTextColor.opacity(0.10))
                    Image(systemName: "person.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                        .foregroundColor(secondaryTextColor)
                }
                .frame(width: 48, height: 48)
            }

            // User info
            VStack(alignment: .leading, spacing: 4) {
                Text(viewer.username ?? "Usuario")
                    .font(.custom("Poppins-SemiBold", size: 15))
                    .foregroundColor(primaryTextColor)

                Text(timeAgo(from: viewer.timestamp))
                    .font(.custom("Poppins-Regular", size: 13))
                    .foregroundColor(secondaryTextColor)
            }

            Spacer()
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Divider()
                .background(secondaryTextColor.opacity(colorScheme == .dark ? 0.18 : 0.12))
        }
    }

    private func timeAgo(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.locale = Locale(identifier: "es")
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct GlassmorphicReactionRow: View {
    let reaction: StoryReaction
    @State private var username: String = "Usuario"
    @State private var profileImagePath: String?
    @Environment(\.colorScheme) private var colorScheme

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : .black.opacity(0.88)
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.65) : .black.opacity(0.52)
    }

    var body: some View {
        HStack(spacing: 16) {
            // Profile image
            if let profileImagePath = profileImagePath,
               let url = URL(string: profileImagePath) {
                KFImage(url)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 48, height: 48)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 1))
            } else {
                ZStack {
                    Circle()
                        .fill(primaryTextColor.opacity(0.10))
                    Image(systemName: "person.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                        .foregroundColor(secondaryTextColor)
                }
                .frame(width: 48, height: 48)
            }

            // User info
            VStack(alignment: .leading, spacing: 4) {
                Text(username)
                    .font(.custom("Poppins-SemiBold", size: 15))
                    .foregroundColor(primaryTextColor)

                Text(timeAgo(from: reaction.timestamp))
                    .font(.custom("Poppins-Regular", size: 13))
                    .foregroundColor(secondaryTextColor)
            }

            Spacer()

            // Reaction
            Text(reaction.reaction)
                .font(.system(size: 32))
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Divider()
                .background(secondaryTextColor.opacity(colorScheme == .dark ? 0.18 : 0.12))
        }
        .onAppear {
            fetchUserInfo()
        }
    }

    private func fetchUserInfo() {
        FirestoreService().fetchUserProfile(userId: reaction.userId) { result in
            switch result {
            case .success(let user):
                self.username = user.username
                self.profileImagePath = user.profileImagePath
            case .failure(_):
                self.username = "Usuario"
            }
        }
    }

    private func timeAgo(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.locale = Locale(identifier: "es")
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct GlassmorphicEmptyState: View {
    let icon: String
    let message: String
    let showCloseButton: Bool
    let onClose: (() -> Void)?
    @Environment(\.colorScheme) private var colorScheme

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : .black.opacity(0.84)
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.62) : .black.opacity(0.48)
    }

    init(icon: String, message: String, showCloseButton: Bool = false, onClose: (() -> Void)? = nil) {
        self.icon = icon
        self.message = message
        self.showCloseButton = showCloseButton
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(secondaryTextColor)

            Text(message)
                .foregroundColor(secondaryTextColor)
                .font(.custom("Poppins-Medium", size: 14))
                .multilineTextAlignment(.center)

            if showCloseButton, let onClose = onClose {
                Button(action: onClose) {
                    Text(NSLocalizedString("stories.close", comment: "Close"))
                        .font(.custom("Poppins-Medium", size: 14))
                        .foregroundColor(primaryTextColor)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.001))
                        .liquidGlass(in: Capsule(), interactive: true)
                }
            }
        }
        .padding()
        .padding(.horizontal, 40)
    }
}

// MARK: - Story Ring Component
struct StoryRing: View {
    let hasStory: Bool
    let hasUnseenStory: Bool
    let size: CGFloat

    var body: some View {
        Circle()
            .stroke(
                LinearGradient(
                    gradient: Gradient(colors: gradientColors),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: hasStory ? 2.5 : 0
            )
            .frame(width: size, height: size)
            .opacity(hasStory ? 1.0 : 0.3)
    }

    private var gradientColors: [Color] {
        if hasUnseenStory {
            return [.pink, .orange, .yellow]
        } else if hasStory {
            return [.gray.opacity(0.5), .gray.opacity(0.7)]
        }
        return [.clear]
    }
}

// MARK: - Story Reply Message Bubble
// MARK: - Story Reply Message Bubble (Componente Principal)
struct StoryReplyMessageBubble: View {
    let message: EnhancedMessage
    let isCurrentUser: Bool
    @State private var showEphemeralContent: Bool = false

    var body: some View {
        VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 8) {
            // Story preview section - always shown for story replies
            if let storyReplyData = message.storyReplyData {
                StoryReplyPreview(
                    storyReplyData: storyReplyData,
                    isCurrentUser: isCurrentUser
                )
            }

            // Content section - different based on message type
            if message.type == .ephemeral {
                // Verificar si el mensaje está marcado como eliminado O si ha expirado
                if message.isDeleted || !isEphemeralValid() {
                    // Mostrar placeholder de expirado
                    ExpiredEphemeralPlaceholder()
                } else {
                    // Ephemeral photo/video reply
                    EphemeralStoryReplyContent(
                        message: message,
                        isCurrentUser: isCurrentUser,
                        showContent: $showEphemeralContent
                    )
                }
            } else {
                // Regular text reply
                StoryTextReplyContent(
                    message: message,
                    isCurrentUser: isCurrentUser
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: isCurrentUser ? .trailing : .leading)
        .onAppear {
            // Verificar si necesita limpieza
            checkAndTriggerCleanupIfNeeded()
        }
    }

    private func isEphemeralValid() -> Bool {
        guard let expirationDate = message.expirationDate else { return true }
        return Date() < expirationDate
    }

    private func checkAndTriggerCleanupIfNeeded() {
        // Si el mensaje ha expirado pero no está marcado como eliminado, triggear limpieza
        if message.type == .ephemeral && !isEphemeralValid() && !message.isDeleted {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                ChatService().cleanupExpiredEphemeralMessages()
            }
        }
    }
}

// MARK: - Story Text Reply Content
struct StoryTextReplyContent: View {
    let message: EnhancedMessage
    let isCurrentUser: Bool

    var body: some View {
        if let content = message.content {
            // Remove the "💬 " prefix if it exists
            let cleanContent = content.hasPrefix("💬 ") ? String(content.dropFirst(2)) : content

            Text(cleanContent)
                .font(.custom("Poppins-Regular", size: 15))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .foregroundColor(.white)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(isCurrentUser ? Color(hex: "007AFF").opacity(0.8) : Color.white.opacity(0.15))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                        )
                )
        }
    }
}

// MARK: - Placeholder para mensajes expirados
struct ExpiredEphemeralPlaceholder: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "camera.circle")
                .font(.system(size: 30))
                .foregroundColor(.white.opacity(0.4))

                            Text("stories.ephemeral.expired")
                .font(.custom("Poppins-Regular", size: 14))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)

                            Text("stories.ephemeral.unavailable")
                .font(.custom("Poppins-Regular", size: 11))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 250, minHeight: 100)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Story Reply Preview
struct StoryReplyPreview: View {
    let storyReplyData: [String: String]
    let isCurrentUser: Bool

    var body: some View {
        HStack(spacing: 10) {
            // Story thumbnail
            if let storyMediaUrl = storyReplyData["storyMediaUrl"],
               let url = URL(string: storyMediaUrl) {
                ZStack {
                    KFImage(url)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    // Video play icon overlay if it's a video
                    if storyReplyData["storyMediaType"] == "video" {
                        Image(systemName: "play.circle.fill")
                            .foregroundColor(.white)
                            .font(.system(size: 16))
                            .background(
                                Circle()
                                    .fill(Color.black.opacity(0.5))
                                    .frame(width: 20, height: 20)
                            )
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [.pink, .orange, .yellow]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                )
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(.white.opacity(0.6))
                            .font(.system(size: 16))
                    )
            }

            // Story reply text with better styling
            VStack(alignment: .leading, spacing: 3) {
                Text(isCurrentUser ? NSLocalizedString("stories.replied", comment: "You replied to their story") : NSLocalizedString("stories.repliedTo", comment: "Replied to your story"))
                    .font(.custom("Poppins-SemiBold", size: 13))
                    .foregroundColor(.white.opacity(0.9))

                // Show story type with icon
                if let storyMediaType = storyReplyData["storyMediaType"] {
                    HStack(spacing: 4) {
                        Image(systemName: storyMediaType == "video" ? "play.rectangle.fill" : "photo.fill")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "007AFF"))

                        Text(storyMediaType == "video" ? NSLocalizedString("stories.video", comment: "Video") : NSLocalizedString("stories.photo", comment: "Photo"))
                            .font(.custom("Poppins-Regular", size: 11))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.black.opacity(0.4),
                            Color.black.opacity(0.2)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.25), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Fixed Ephemeral Story Reply Content
struct EphemeralStoryReplyContent: View {
    let message: EnhancedMessage
    let isCurrentUser: Bool
    @Binding var showContent: Bool
    @State private var hasBeenViewed: Bool = false

    var body: some View {
        ZStack {
            if !showContent && !hasBeenViewed && isEphemeralValid() {
                // Tap to view state
                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [.purple, .pink, .orange]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 60, height: 60)

                        Image(systemName: "camera.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                    }

                    VStack(spacing: 4) {
                        Text("stories.tapToView")
                            .font(.custom("Poppins-SemiBold", size: 14))
                            .foregroundColor(.white)

                        Text("stories.ephemeral.title")
                            .font(.custom("Poppins-Regular", size: 12))
                            .foregroundColor(.white.opacity(0.8))

                        // Expiration indicator with better styling
                        if let expirationDate = message.expirationDate {
                            let timeLeft = expirationDate.timeIntervalSince(Date())
                            if timeLeft > 0 {
                                HStack(spacing: 4) {
                                    Image(systemName: "clock")
                                        .font(.system(size: 10))
                                        .foregroundColor(.white.opacity(0.6))

                                    Text(String(format: NSLocalizedString("stories.expiresIn", comment: "Expires in"), formatTimeLeft(timeLeft)))
                                        .font(.custom("Poppins-Regular", size: 10))
                                        .foregroundColor(.white.opacity(0.6))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(Color.black.opacity(0.3))
                                )
                            }
                        }
                    }
                }
                .frame(maxWidth: 280, minHeight: 140)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.purple.opacity(0.15),
                                    Color.pink.opacity(0.15),
                                    Color.orange.opacity(0.1)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(
                                    LinearGradient(
                                        gradient: Gradient(colors: [.purple.opacity(0.5), .pink.opacity(0.5)]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                )
                .onTapGesture {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        showContent = true
                        hasBeenViewed = true
                        // Don't mark as "viewed" in Firebase since it can be viewed multiple times
                    }
                }
            } else if (showContent || hasBeenViewed) && isEphemeralValid() {
                // Show content - can be viewed multiple times during 24h period
                if let mediaUrl = message.mediaUrl, let url = URL(string: mediaUrl) {
                    ClickableEphemeralImageContent(
                        imageUrl: url,
                        expirationDate: message.expirationDate,
                        canViewMultipleTimes: true
                    )
                }
            } else {
                // Expired
                ExpiredEphemeralPlaceholder()
            }
        }
        .onAppear {
            hasBeenViewed = message.isViewed
        }
    }

    private func isEphemeralValid() -> Bool {
        guard let expirationDate = message.expirationDate else { return true }
        return Date() < expirationDate
    }

    private func formatTimeLeft(_ timeInterval: TimeInterval) -> String {
        let hours = Int(timeInterval) / 3600
        let minutes = Int(timeInterval) % 3600 / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

// MARK: - Clickable Ephemeral Image Content (for story replies)
struct ClickableEphemeralImageContent: View {
    let imageUrl: URL
    let expirationDate: Date?
    let canViewMultipleTimes: Bool
    @State private var showFullScreen = false

    var body: some View {
        KFImage(imageUrl)
            .resizable()
            .scaledToFill()
            .frame(maxWidth: 250, maxHeight: 300)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                // Show expiration info in corner
                VStack {
                    HStack {
                        Spacer()
                        if let expirationDate = expirationDate {
                            let timeLeft = expirationDate.timeIntervalSince(Date())
                            if timeLeft > 0 {
                                Text(formatTimeLeft(timeLeft))
                                    .font(.custom("Poppins-Regular", size: 10))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule()
                                            .fill(Color.black.opacity(0.6))
                                    )
                                    .padding(8)
                            }
                        }
                    }
                    Spacer()

                    // Add click indicator
                    HStack {
                        Spacer()
                        VStack {
                            Spacer()
                            HStack(spacing: 4) {
                                Image(systemName: "eye")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.8))
                                Text("stories.tapToViewComplete")
                                    .font(.custom("Poppins-Regular", size: 11))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(Color.black.opacity(0.6))
                            )
                            .padding(8)
                        }
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 5)
            .onTapGesture {
                showFullScreen = true
            }
            .fullScreenCover(isPresented: $showFullScreen) {
                FullScreenEphemeralImageView(
                    imageUrl: imageUrl,
                    expirationDate: expirationDate
                )
            }
    }

    private func formatTimeLeft(_ timeInterval: TimeInterval) -> String {
        let hours = Int(timeInterval) / 3600
        let minutes = Int(timeInterval) % 3600 / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

// MARK: - Full Screen Ephemeral Image
struct FullScreenEphemeralImageView: View {
    let imageUrl: URL
    let expirationDate: Date?
    @Environment(\.dismiss) var dismiss
    @State private var timeLeft: TimeInterval = 0
    @State private var timer: Timer?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            KFImage(imageUrl)
                .resizable()
                .scaledToFit()

            VStack {
                HStack {
                    Button("common.close") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                    .font(.custom("Poppins-Medium", size: 16))

                    Spacer()

                    if timeLeft > 0 {
                        Text(String(format: NSLocalizedString("stories.expiresIn", comment: "Expires in"), formatTimeLeft(timeLeft)))
                            .font(.custom("Poppins-Regular", size: 14))
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(Color.black.opacity(0.5))
                            )
                    }
                }
                .padding()

                Spacer()
            }
        }
        .onAppear {
            startTimer()
        }
        .onDisappear {
            timer?.invalidate()
        }
    }

    private func startTimer() {
        guard let expirationDate = expirationDate else { return }

        timeLeft = expirationDate.timeIntervalSince(Date())

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            timeLeft = max(0, expirationDate.timeIntervalSince(Date()))
            if timeLeft <= 0 {
                timer?.invalidate()
                dismiss()
            }
        }
    }

    private func formatTimeLeft(_ timeInterval: TimeInterval) -> String {
        let hours = Int(timeInterval) / 3600
        let minutes = Int(timeInterval) % 3600 / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

// MARK: - Glassmorphic Extensions
extension View {
    func glassmorphic() -> some View {
        self
            .background(
                Color.clear.liquidGlass(in: Rectangle())
            )
            .overlay(
                RoundedRectangle(cornerRadius: 0)
                    .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
            )
    }

    func storyGlassmorphic() -> some View {
        self
            .background(
                Color.clear.liquidGlass(in: Rectangle())
            )
            .overlay(
                RoundedRectangle(cornerRadius: 0)
                    .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
            )
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
        firestoreService.db.collection("users").document(userId).collection("stories")
            .whereField("expirationDate", isGreaterThan: Date())
            .order(by: "timestamp", descending: false)
            .getDocuments { [weak self] snapshot, error in
                guard let self = self else { return }

                if let error = error {
                    DispatchQueue.main.async {
                        self.stories = [:]
                    }
                    return
                }

                let userStories = snapshot?.documents.compactMap { doc -> Story? in
                    var data = doc.data()

                    // Handle legacy fields (misma lógica que fetchStories normal)
                    var mediaItem: MediaItem?
                    if let mediaItemData = data["mediaItem"] as? [String: Any],
                       let typeString = mediaItemData["type"] as? String,
                       let type = MediaItem.MediaType(rawValue: typeString),
                       let url = mediaItemData["url"] as? String {
                        mediaItem = MediaItem(type: type, url: url)
                    } else if let imagePath = data["imagePath"] as? String, !imagePath.isEmpty {
                        mediaItem = MediaItem(type: .image, url: imagePath)
                    } else if let videoUrl = data["videoUrl"] as? String, !videoUrl.isEmpty {
                        mediaItem = MediaItem(type: .video, url: videoUrl)
                    }

                    guard let mediaItem = mediaItem else { return nil }

                    data["mediaItem"] = ["type": mediaItem.type.rawValue, "url": mediaItem.url]
                    data["id"] = doc.documentID

                    return try? Firestore.Decoder().decode(Story.self, from: data)
                } ?? []


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

// MARK: - Verified Badge View
struct VerifiedBadgeView: View {
    let userId: String
    let size: CGFloat
    @State private var isVerified: Bool = false
    @State private var isLoading: Bool = true

    var body: some View {
        Group {
            if isLoading {
                // Placeholder mientras carga
                Color.clear
                    .frame(width: size, height: size)
            } else if isVerified {
                VerifiedBadge(size: size)
            } else {
                // No mostrar nada si no está verificado
                Color.clear
                    .frame(width: size, height: size)
            }
        }
        .onAppear {
            checkVerificationStatus()
        }
    }

    private func checkVerificationStatus() {
        Firestore.firestore().collection("users").document(userId)
            .getDocument { snapshot, error in
                DispatchQueue.main.async {
                    isLoading = false
                    if let data = snapshot?.data() {
                        isVerified = data["isVerified"] as? Bool ?? false
                    }
                }
            }
    }
}

// MARK: - Current User Verified Badge
struct CurrentUserVerifiedBadge: View {
    let size: CGFloat
    @State private var isVerified: Bool = false
    @State private var isLoading: Bool = true

    var body: some View {
        Group {
            if isLoading {
                // Placeholder mientras carga
                Color.clear
                    .frame(width: size, height: size)
            } else if isVerified {
                VerifiedBadge(size: size)
            } else {
                // No mostrar nada si no está verificado
                Color.clear
                    .frame(width: size, height: size)
            }
        }
        .onAppear {
            checkCurrentUserVerificationStatus()
        }
    }

    private func checkCurrentUserVerificationStatus() {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            isLoading = false
            return
        }

        Firestore.firestore().collection("users").document(currentUserId)
            .getDocument { snapshot, error in
                DispatchQueue.main.async {
                    isLoading = false
                    if let data = snapshot?.data() {
                        isVerified = data["isVerified"] as? Bool ?? false
                    }
                }
            }
    }
}

// MARK: - Interactive Poll Data
struct InteractivePollData {
    let pollData: [String]
    let storyId: String
    let stickerId: String
}

// MARK: - Interactive Poll Overlay
struct InteractivePollOverlay: View {
    let pollData: [String]
    let storyId: String
    let stickerId: String
    @Environment(\.dismiss) private var dismiss
    @State private var selectedOption: Int? = nil
    @State private var hasVoted = false
    @State private var voteCounts: [Int: Int] = [0: 0, 1: 0]
    @State private var totalVotes = 0

    var body: some View {
        ZStack {
            // Fondo semi-transparente
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture {
                    dismiss()
                }

            VStack(spacing: 20) {
                // Pregunta
                Text(pollData[0])
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)

                // Opciones interactivas
                VStack(spacing: 12) {
                    ForEach(0..<2, id: \.self) { index in
                        InteractivePollOption(
                            text: pollData[index + 1],
                            percentage: calculatePercentage(for: index),
                            isSelected: selectedOption == index,
                            hasVoted: hasVoted,
                            onTap: {
                                if !hasVoted {
                                    selectedOption = index
                                    submitVote()
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, 30)

                if hasVoted {
                    Text("poll.thanks")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.green)
                        .padding(.top, 10)
                }

                Text(String(format: NSLocalizedString("poll.votes", comment: "Votes count"), totalVotes))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(.vertical, 40)
        }
        .onAppear {
            loadVoteCounts()
        }
    }

    private func calculatePercentage(for option: Int) -> Double {
        guard totalVotes > 0 else { return 0 }
        return Double(voteCounts[option] ?? 0) / Double(totalVotes) * 100
    }

    private func submitVote() {
        guard let selectedOption = selectedOption,
              let currentUserId = Auth.auth().currentUser?.uid else { return }

        // Guardar voto en Firestore
        let voteData: [String: Any] = [
            "userId": currentUserId,
            "option": selectedOption,
            "timestamp": FieldValue.serverTimestamp()
        ]

        Firestore.firestore().collection("stories").document(storyId)
            .collection("pollVotes").document(currentUserId)
            .setData(voteData) { error in
                if error == nil {
                    DispatchQueue.main.async {
                        hasVoted = true
                        loadVoteCounts()
                    }
                }
            }
    }

    private func loadVoteCounts() {
        Firestore.firestore().collection("stories").document(storyId)
            .collection("pollVotes").getDocuments { snapshot, error in
                guard let documents = snapshot?.documents else { return }

                var counts: [Int: Int] = [0: 0, 1: 0]
                for doc in documents {
                    if let option = doc.data()["option"] as? Int {
                        counts[option, default: 0] += 1
                    }
                }

                DispatchQueue.main.async {
                    voteCounts = counts
                    totalVotes = counts.values.reduce(0, +)
                }
            }
    }
}

// MARK: - Interactive Poll Sticker (Estilo Nativo)
struct InteractivePollSticker: View {
    let pollData: [String]
    let storyId: String
    let userId: String
    @Binding var selectedOption: Int?
    @Binding var hasVoted: Bool
    @Binding var voteCounts: [Int: Int]
    @Binding var totalVotes: Int
    let onVote: (Int) -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text(pollData[0].count > 42 ? String(pollData[0].prefix(42)) + "..." : pollData[0])
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                .padding(.horizontal, 18)
                .padding(.top, 20)

            VStack(spacing: 8) {
                ForEach(0..<2, id: \.self) { index in
                    InteractivePollOptionButton(
                        text: pollData[index + 1].count > 26 ? String(pollData[index + 1].prefix(26)) + "..." : pollData[index + 1],
                        percentage: calculatePercentage(for: index),
                        isSelected: selectedOption == index,
                        hasVoted: hasVoted,
                        onTap: {
                            if !hasVoted {
                                selectedOption = index
                                onVote(index)
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 16)
        }
        .background(
            Color.clear.liquidGlass(in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        )
        .onAppear {
            loadVoteCounts()
        }
    }

    private func calculatePercentage(for option: Int) -> Double {
        guard totalVotes > 0 else { return 0 }
        return Double(voteCounts[option] ?? 0) / Double(totalVotes) * 100
    }

    private func loadVoteCounts() {
        // ✅ Cargar votos reales desde Firestore
        guard !storyId.isEmpty else { return }

        // Usar el userId real del story
        Firestore.firestore().collection("users").document(userId)
            .collection("stories").document(storyId)
            .collection("pollVotes").getDocuments { snapshot, error in
                guard let documents = snapshot?.documents else {
                    return
                }

                var counts: [Int: Int] = [0: 0, 1: 0]
                for doc in documents {
                    if doc.documentID != "metadata", // Excluir metadata
                       let option = doc.data()["option"] as? Int {
                        counts[option, default: 0] += 1
                    }
                }

                DispatchQueue.main.async {
                    voteCounts = counts
                    totalVotes = counts.values.reduce(0, +)
                }
            }

        guard let currentUserId = Auth.auth().currentUser?.uid else { return }

        Firestore.firestore().collection("users").document(userId)
            .collection("stories").document(storyId)
            .collection("pollVotes").document(currentUserId)
            .getDocument { snapshot, error in
                guard let data = snapshot?.data(),
                      let option = data["option"] as? Int else { return }

                DispatchQueue.main.async {
                    selectedOption = option
                    hasVoted = true
                }
            }
    }
}

// MARK: - Interactive Poll Option Button
struct InteractivePollOptionButton: View {
    let text: String
    let percentage: Double
    let isSelected: Bool
    let hasVoted: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(isSelected ? Color.white : Color.white.opacity(0.1))

                    if hasVoted {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(isSelected ? Color.white : Color.white.opacity(0.35))
                            .frame(width: proxy.size.width * (percentage / 100))
                            .animation(.easeInOut(duration: 0.5), value: percentage)
                    }

                    HStack(spacing: 10) {
                        Text(text)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(isSelected ? .black : .white)
                            .shadow(color: isSelected ? .clear : .black.opacity(0.15), radius: 2)
                            .lineLimit(1)

                        Spacer(minLength: 0)

                        if hasVoted {
                            Text("\(Int(percentage))%")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(isSelected ? .black : .white)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: 52)
        .disabled(hasVoted)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isSelected)
    }
}

// MARK: - Interactive Poll Option
struct InteractivePollOption: View {
    let text: String
    let percentage: Double
    let isSelected: Bool
    let hasVoted: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .leading) {
                // Barra de progreso
                Rectangle()
                    .fill(Color.white.opacity(0.2))
                    .frame(height: 50)
                    .overlay(
                        Rectangle()
                            .fill(isSelected ? Color.blue : Color.white.opacity(0.3))
                            .frame(width: UIScreen.main.bounds.width * 0.7 * (percentage / 100))
                            .animation(.easeInOut(duration: 0.5), value: percentage)
                        , alignment: .leading
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 25))

                // Texto y porcentaje
                HStack {
                    Text(text)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)

                    Spacer()

                    if hasVoted {
                        Text("\(Int(percentage))%")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .disabled(hasVoted)
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
    }
}

// MARK: - Poll Vote View
struct PollVoteView: View {
    let pollData: [String]
    let storyId: String
    @Environment(\.dismiss) private var dismiss
    @State private var selectedOption: Int? = nil
    @State private var hasVoted = false
    @State private var voteCounts: [Int: Int] = [0: 0, 1: 0] // option index: count

    var body: some View {
        ZStack {
            // Fondo con blur
            Color.black.opacity(0.8)
                .ignoresSafeArea()

            VStack(spacing: 25) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.white)

                    Text("poll.vote")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                }

                // Pregunta
                Text(pollData[0])
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)

                // Opciones
                VStack(spacing: 15) {
                    ForEach(0..<2, id: \.self) { index in
                        Button(action: {
                            selectedOption = index
                            submitVote()
                        }) {
                            HStack {
                                Text(pollData[index + 1])
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white)

                                Spacer()

                                if hasVoted {
                                    Text("\(voteCounts[index] ?? 0)")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.white.opacity(0.8))
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(selectedOption == index ? Color.blue : Color.white.opacity(0.2))
                            )
                        }
                        .disabled(hasVoted)
                    }
                }
                .padding(.horizontal, 20)

                if hasVoted {
                    Text("poll.thanks")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.green)
                }

                // Botón cerrar
                Button("common.close") {
                    dismiss()
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 30)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.2))
                )
            }
            .padding(30)
        }
        .onAppear {
            loadVoteCounts()
        }
    }

    private func submitVote() {
        guard let selectedOption = selectedOption,
              let currentUserId = Auth.auth().currentUser?.uid else { return }

        // Guardar voto en Firestore
        let voteData: [String: Any] = [
            "userId": currentUserId,
            "option": selectedOption,
            "timestamp": FieldValue.serverTimestamp()
        ]

        Firestore.firestore().collection("stories").document(storyId)
            .collection("pollVotes").document(currentUserId)
            .setData(voteData) { error in
                if error == nil {
                    DispatchQueue.main.async {
                        hasVoted = true
                        loadVoteCounts()
                    }
                }
            }
    }

    private func loadVoteCounts() {
        Firestore.firestore().collection("stories").document(storyId)
            .collection("pollVotes").getDocuments { snapshot, error in
                guard let documents = snapshot?.documents else { return }

                var counts: [Int: Int] = [0: 0, 1: 0]
                for doc in documents {
                    if let option = doc.data()["option"] as? Int {
                        counts[option, default: 0] += 1
                    }
                }

                DispatchQueue.main.async {
                    voteCounts = counts
                }
            }
    }
}

private struct InteractiveEmojiSliderSticker: View {
    let prompt: String
    let emoji: String
    let storyId: String
    let userId: String
    let stickerId: String

    @State private var dragValue: Double?
    @State private var submittedValue: Double?
    @State private var averageValue: Double = 0.5
    @State private var totalVotes: Int = 0

    private var currentUserId: String? {
        Auth.auth().currentUser?.uid
    }

    private var isAuthor: Bool {
        currentUserId == userId
    }

    private var displayValue: Double {
        if let dragValue {
            return dragValue
        }
        if let submittedValue {
            return submittedValue
        }
        if isAuthor, totalVotes > 0 {
            return averageValue
        }
        return 0.5
    }

    private var canVote: Bool {
        !isAuthor && submittedValue == nil && currentUserId != nil && !storyId.isEmpty
    }

    private var displayAverage: Double? {
        if isAuthor {
            return nil
        }
        if submittedValue != nil, totalVotes > 0 {
            return averageValue
        }
        return nil
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            StickerEmojiSliderCardView(
                prompt: prompt,
                emoji: emoji,
                value: displayValue,
                averageValue: displayAverage
            )
        }
        .contentShape(Rectangle())
        .overlay {
            GeometryReader { geometry in
                let metrics = emojiSliderTrackMetrics(totalWidth: geometry.size.width)
                let trackFrame = emojiSliderTrackFrame(totalSize: geometry.size, showsPrompt: emojiSliderHasPrompt(prompt))
                
                // Hitbox expandida para que sea MUCHO más fácil de tocar
                let hitBox = CGRect(
                    x: trackFrame.minX - 40,
                    y: trackFrame.minY - 30,
                    width: trackFrame.width + 80,
                    height: trackFrame.height + 60
                )

                Color.clear
                    .contentShape(Rectangle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { gesture in
                                // Solo requiere estar dentro al iniciar, luego fluye
                                guard canVote, hitBox.contains(gesture.startLocation) else { return }
                                dragValue = normalizedValue(
                                    for: gesture.location.x,
                                    metrics: metrics
                                )
                            }
                            .onEnded { gesture in
                                guard canVote, hitBox.contains(gesture.startLocation) else {
                                    dragValue = nil
                                    return
                                }

                                let value = normalizedValue(
                                    for: gesture.location.x,
                                    metrics: metrics
                                )
                                dragValue = nil
                                submitVote(value)
                            }
                    )
            }
        }
        .onAppear {
            loadVoteState()
            loadVoteAggregate()
        }
    }

    private func normalizedValue(for locationX: CGFloat, metrics: (leading: CGFloat, width: CGFloat, thumbBaseSize: CGFloat, trackHeight: CGFloat)) -> Double {
        let minX = metrics.leading
        let maxX = metrics.leading + metrics.width
        let clampedX = min(max(locationX, minX), maxX)
        return Double((clampedX - minX) / max(metrics.width, 1))
    }

    private func sliderVotesCollection() -> CollectionReference {
        Firestore.firestore()
            .collection("users")
            .document(userId)
            .collection("stories")
            .document(storyId)
            .collection("emojiSliders")
            .document(stickerId)
            .collection("votes")
    }

    private func loadVoteState() {
        guard let currentUserId else { return }

        sliderVotesCollection()
            .document(currentUserId)
            .getDocument { snapshot, _ in
                guard let data = snapshot?.data() else { return }
                
                // Safely decode Double or Int
                let value: Double
                if let doubleVal = data["value"] as? Double {
                    value = doubleVal
                } else if let intVal = data["value"] as? Int {
                    value = Double(intVal)
                } else {
                    return
                }

                DispatchQueue.main.async {
                    submittedValue = value
                }
            }
    }

    private func loadVoteAggregate() {
        sliderVotesCollection()
            .getDocuments { snapshot, _ in
                let values = snapshot?.documents.compactMap { $0.data()["value"] as? Double } ?? []
                let total = values.count
                let average = total > 0 ? values.reduce(0, +) / Double(total) : 0.5

                DispatchQueue.main.async {
                    totalVotes = total
                    averageValue = average
                }
            }
    }

    private func submitVote(_ value: Double) {
        guard let currentUserId else { return }

        let voteRef = sliderVotesCollection().document(currentUserId)
        voteRef.getDocument { snapshot, _ in
            if let data = snapshot?.data() {
                let existingValue: Double?
                if let doubleVal = data["value"] as? Double {
                    existingValue = doubleVal
                } else if let intVal = data["value"] as? Int {
                    existingValue = Double(intVal)
                } else {
                    existingValue = nil
                }
                
                if let validExistingValue = existingValue {
                    DispatchQueue.main.async {
                        submittedValue = validExistingValue
                        loadVoteAggregate()
                    }
                    return
                }
            }

            voteRef.setData([
                "userId": currentUserId,
                "value": value,
                "timestamp": FieldValue.serverTimestamp()
            ]) { error in
                guard error == nil else { return }

                DispatchQueue.main.async {
                    submittedValue = value
                    loadVoteAggregate()
                }
            }
        }
    }
}

// MARK: - StoryStickerView para mostrar stickers en historias
struct StoryStickerView: View {
    let sticker: StickerItem
    let screenSize: CGSize
    let storyId: String
    let userId: String
    let onPauseStory: () -> Void
    let onResumeStory: () -> Void

    @State private var selectedPollOption: Int? = nil
    @State private var hasVoted = false
    @State private var voteCounts: [Int: Int] = [0: 0, 1: 0]
    @State private var totalVotes = 0

    var body: some View {
        // ✅ SOLUCIÓN DEFINITIVA: Solo una renderización
        if sticker.type == .shareMoment {
            // ✅ SHARE MOMENT UNIFICADO (FOTO Y VIDEO)
            // Renderizamos siempre el header y caption, independientemente de si es animado o no
            Button(action: {
                handleStickerTap()
            }) {
                ZStack {
                    // 1. Capa base: Imagen estática
                    Image(uiImage: sticker.image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: sticker.image.size.width * sticker.scale, height: sticker.image.size.height * sticker.scale)

                    // 2. Capa animada: Video (si existe)
                    if let videoURL = sticker.videoURL {
                         StickerVideoPlayer(url: videoURL)
                            .frame(width: sticker.image.size.width * sticker.scale, height: sticker.image.size.height * sticker.scale)
                            .allowsHitTesting(false)
                    }

                    // 3. OVERLAYS (Header + Caption) - SIEMPRE VISIBLES
                    ZStack(alignment: .top) {
                        Color.clear // Contenedor transparente para alinear

                        // Header Overlay (Username + Profile)
                        HStack(spacing: 10 * sticker.scale) {
                            // Profile Image
                            if let interactionData = sticker.interactionData,
                               let userId = interactionData.userId {
                                AsyncProfileImageView(userId: userId)
                                    .frame(width: 34 * sticker.scale, height: 34 * sticker.scale)
                                    .clipShape(Circle())
                                    .overlay(
                                        Circle()
                                            .stroke(
                                                LinearGradient(
                                                    colors: [.white.opacity(0.5), .clear],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                ),
                                                lineWidth: 1 * sticker.scale
                                            )
                                    )
                            } else {
                                Image(systemName: "person.circle.fill")
                                    .resizable()
                                    .frame(width: 34 * sticker.scale, height: 34 * sticker.scale)
                                    .foregroundColor(.white.opacity(0.5))
                            }

                            VStack(alignment: .leading, spacing: 0) {
                                Text(sticker.interactionData?.username ?? "User")
                                    .font(.custom("Poppins-Bold", size: 13 * sticker.scale))
                                    .foregroundColor(.white)
                                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                            }

                            Spacer()
                        }
                        .padding(.horizontal, 12 * sticker.scale)
                        .padding(.vertical, 10 * sticker.scale)
                        .background(
                            Rectangle()
                                .fill(.ultraThinMaterial)
                                .mask(
                                    LinearGradient(
                                        colors: [.black, .black, .clear],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        )

                        // Caption Overlay (Bottom)
                        if let caption = sticker.interactionData?.caption, !caption.isEmpty {
                            VStack {
                                Spacer()
                                Text(caption)
                                    .font(.custom("Poppins-Medium", size: 9 * sticker.scale))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8 * sticker.scale)
                                    .padding(.vertical, 4 * sticker.scale)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Capsule())
                                    .padding(.bottom, 10 * sticker.scale)
                            }
                        }

                        // Gallery Indicator Overlay (Top Right)
                        if (sticker.interactionData?.mediaCount ?? 0) > 1 {
                            VStack {
                                HStack {
                                    Spacer()
                                    Image(systemName: "square.on.square.fill")
                                        .font(.system(size: 11 * sticker.scale, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(6 * sticker.scale)
                                        .background(.ultraThinMaterial)
                                        .clipShape(RoundedRectangle(cornerRadius: 8 * sticker.scale))
                                        .padding(12 * sticker.scale)
                                        .padding(.top, 42 * sticker.scale) // Below header text
                                }
                                Spacer()
                            }
                        }
                    }
                }
                .frame(width: sticker.image.size.width * sticker.scale, height: sticker.image.size.height * sticker.scale)
                .clipShape(RoundedRectangle(cornerRadius: 28 * sticker.scale))
            }
            .buttonStyle(PlainButtonStyle())
            .rotationEffect(sticker.rotation)

        } else if sticker.isAnimated {
            Button(action: {
                handleStickerTap()
            }) {
                if let videoURL = sticker.videoURL {
                    ZStack {
                        Image(uiImage: sticker.image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: sticker.image.size.width * sticker.scale, height: sticker.image.size.height * sticker.scale)

                        ZStack(alignment: .top) {
                            StickerVideoPlayer(url: videoURL)
                                .frame(width: sticker.image.size.width * sticker.scale, height: sticker.image.size.height * sticker.scale)
                                .allowsHitTesting(false)

                            if let interactionData = sticker.interactionData, let username = interactionData.username {
                                HStack(spacing: 8 * sticker.scale) {
                                    Circle()
                                        .fill(.white.opacity(0.1))
                                        .frame(width: 24 * sticker.scale, height: 24 * sticker.scale)
                                        .overlay(Circle().stroke(.white.opacity(0.3), lineWidth: 0.5 * sticker.scale))

                                    Text(username)
                                        .font(.custom("Poppins-Bold", size: 10 * sticker.scale))
                                        .foregroundColor(.white)

                                    Spacer()
                                }
                                .padding(.horizontal, 10 * sticker.scale)
                                .padding(.vertical, 8 * sticker.scale)
                                .background(
                                    Rectangle()
                                        .fill(.ultraThinMaterial)
                                        .mask(
                                            LinearGradient(
                                                colors: [.black, .black, .clear],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                                )
                            }

                            if let caption = sticker.interactionData?.caption, !caption.isEmpty {
                                VStack {
                                    Spacer()
                                    Text(caption)
                                        .font(.custom("Poppins-Medium", size: 9 * sticker.scale))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 8 * sticker.scale)
                                        .padding(.vertical, 4 * sticker.scale)
                                        .background(.ultraThinMaterial)
                                        .clipShape(Capsule())
                                        .padding(.bottom, 10 * sticker.scale)
                                }
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 28 * sticker.scale))
                    .frame(width: sticker.image.size.width * sticker.scale, height: sticker.image.size.height * sticker.scale)
                } else if sticker.gifURL != nil {
                    AnimatedStickerView(
                        sticker: sticker,
                        size: CGSize(
                            width: sticker.image.size.width * sticker.scale,
                            height: sticker.image.size.height * sticker.scale
                        )
                    )
                    .frame(
                        width: sticker.image.size.width * sticker.scale,
                        height: sticker.image.size.height * sticker.scale
                    )
                }
            }
            .buttonStyle(PlainButtonStyle())
            .rotationEffect(sticker.rotation)
        } else if sticker.type == .poll, let pollData = sticker.interactionData?.pollData {
            // ✅ POLL INTERACTIVO: Diseño completo e interactivo
            InteractivePollSticker(
                pollData: pollData,
                storyId: storyId,
                userId: userId,
                selectedOption: $selectedPollOption,
                hasVoted: $hasVoted,
                voteCounts: $voteCounts,
                totalVotes: $totalVotes,
                onVote: { option in
                    handlePollVote(option: option, pollData: pollData)
                }
            )
            .frame(width: 300, height: 172)
            .scaleEffect(sticker.scale) // ✅ APLICAR ESCALA
            .rotationEffect(sticker.rotation)
        } else if sticker.type == .question, let questionText = sticker.interactionData?.questionText {
            // ✅ QUESTION INTERACTIVO: Diseño completo e interactivo
            InteractiveQuestionSticker(
                questionText: questionText,
                storyId: storyId,
                userId: userId,
                onPauseStory: onPauseStory,
                onResumeStory: onResumeStory
            )
            .frame(width: 300, height: 132)
            .scaleEffect(sticker.scale) // ✅ APLICAR ESCALA
            .rotationEffect(sticker.rotation)
        } else if sticker.type == .location, let locationName = sticker.interactionData?.location {
            // ✅ LOCATION INTERACTIVO: Diseño completo e interactivo
            InteractiveLocationSticker(
                locationName: locationName,
                coordinate: sticker.interactionData?.locationCoordinate,
                onPauseStory: onPauseStory,
                onResumeStory: onResumeStory
            )
            .scaleEffect(sticker.scale) // ✅ APLICAR ESCALA
            .rotationEffect(sticker.rotation)
        } else if sticker.type == .mention, let username = sticker.interactionData?.username {
            // ✅ MENTION INTERACTIVO: Diseño completo nativo
            InteractiveMentionSticker(
                username: username,
                onTap: {
                    handleStickerTap()
                }
            )
            .scaleEffect(sticker.scale)
            .rotationEffect(sticker.rotation)
        } else if sticker.type == .hashtag, let hashtag = sticker.interactionData?.hashtag {
            // ✅ HASHTAG INTERACTIVO: Diseño completo e interactivo
            InteractiveHashtagSticker(
                hashtag: hashtag,
                onPauseStory: onPauseStory,
                onResumeStory: onResumeStory
            )
            .scaleEffect(sticker.scale) // ✅ APLICAR ESCALA
            .rotationEffect(sticker.rotation)
        } else if sticker.type == .quiz, let question = sticker.interactionData?.quizQuestion, let options = sticker.interactionData?.quizOptions {
            InteractiveQuizSticker(
                storyId: storyId,
                userId: userId,
                stickerId: sticker.id,
                question: question,
                options: options,
                correctIndex: sticker.interactionData?.quizCorrectIndex ?? 0
            )
            .frame(width: 300) // ✅ CONSISTENCIA CON EL EDITOR
            .scaleEffect(sticker.scale)
            .rotationEffect(sticker.rotation)
        } else if sticker.type == .frame {
            InteractiveFrameSticker(
                image: sticker.image,
                onPauseStory: onPauseStory,
                onResumeStory: onResumeStory
            )
            .frame(width: 200, height: 240) // ✅ CONSISTENCIA CON EL EDITOR
            .scaleEffect(sticker.scale)
            .rotationEffect(sticker.rotation)
        } else if sticker.type == .reveal {
            EmptyView()
        } else if sticker.type == .link, let linkURL = sticker.interactionData?.linkURL {
            Button(action: {
                handleStickerTap()
            }) {
                StickerLinkCardView(
                    title: sticker.interactionData?.linkTitle ?? stickerHostLabel(from: linkURL)
                )
            }
            .buttonStyle(PlainButtonStyle())
            .scaleEffect(sticker.scale)
            .rotationEffect(sticker.rotation)
        } else if sticker.type == .countdown,
                  let countdownTitle = sticker.interactionData?.countdownTitle,
                  let targetAtMs = sticker.interactionData?.countdownTargetAtMs {
            StickerCountdownCardView(title: countdownTitle, targetAtMs: targetAtMs)
                .scaleEffect(sticker.scale)
                .rotationEffect(sticker.rotation)
        } else if sticker.type == .emojiSlider,
                  let sliderPrompt = sticker.interactionData?.sliderPrompt,
                  let sliderEmoji = sticker.interactionData?.sliderEmoji {
            InteractiveEmojiSliderSticker(
                prompt: sliderPrompt,
                emoji: sliderEmoji,
                storyId: storyId,
                userId: userId,
                stickerId: sticker.id
            )
            .frame(width: emojiSliderRenderingSize(prompt: sliderPrompt).width, height: emojiSliderRenderingSize(prompt: sliderPrompt).height)
            .scaleEffect(sticker.scale)
            .rotationEffect(sticker.rotation)
        } else if sticker.type == .weather, let weatherSymbol = sticker.interactionData?.weatherSymbol {
            // ✅ WEATHER ANIMADO: Diseño animado según clima
            AnimatedWeatherSticker(
                weatherSymbol: weatherSymbol,
                temperature: sticker.interactionData?.questionText ?? "🌤️"
            )
            .frame(width: 140, height: 50)
            .scaleEffect(sticker.scale) // ✅ APLICAR ESCALA
            .rotationEffect(sticker.rotation)
            .onAppear {

            }
        } else if sticker.type == .time {
            StickerTimeCardView(
                timeText: sticker.interactionData?.questionText ?? Date.now.formatted(date: .omitted, time: .shortened),
                dateText: sticker.interactionData?.caption ?? Date.now.formatted(date: .numeric, time: .omitted)
            )
            .frame(width: 164, height: 56)
            .scaleEffect(sticker.scale)
            .rotationEffect(sticker.rotation)

        } else {
            // Solo imagen estática
            // Solo imagen estática
            Button(action: {
                handleStickerTap()
            }) {
                Image(uiImage: sticker.image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: sticker.image.size.width * sticker.scale, height: sticker.image.size.height * sticker.scale)
                    .clipShape(RoundedRectangle(cornerRadius: 28 * sticker.scale))
            }
            .buttonStyle(PlainButtonStyle())
            .clipShape(RoundedRectangle(cornerRadius: 28 * sticker.scale))
            .rotationEffect(sticker.rotation)
        }
    }

    // ✅ MANEJAR TAP EN STICKERS
    private func handleStickerTap() {

        switch sticker.type {
        case .mention:
            if let interactionData = sticker.interactionData,
               let userId = interactionData.userId {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: NSNotification.Name("ShowUserProfileFromStory"), object: userId)
                }
            }

        case .poll:
            // ✅ ESTILO NATIVO: El poll es interactivo directamente, no necesita tap aquí
            break

        case .question:
            // ✅ ESTILO NATIVO: El question es interactivo directamente, no necesita tap aquí
            break

        case .hashtag:
            // ✅ ESTILO NATIVO: El hashtag es interactivo directamente, no necesita tap aquí
            break

        case .location:
            // ✅ ESTILO NATIVO: El location es interactivo directamente, no necesita tap aquí
            break

        case .link:
            if let rawURL = sticker.interactionData?.linkURL,
               let url = normalizedStickerURL(from: rawURL) {
                DispatchQueue.main.async {
                    UIApplication.shared.open(url)
                }
            }

        case .countdown:
            break

        case .emojiSlider:
            break

        case .shareMoment:
            if let interactionData = sticker.interactionData,
               let momentId = interactionData.momentId,
               let userId = interactionData.userId {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("OpenMomentFromStory"),
                        object: nil,
                        userInfo: ["momentId": momentId, "userId": userId]
                    )
                }
            }

        default:
            break
        }
    }

    // ✅ NUEVO: Manejar voto de poll directamente como Moments
    private func handlePollVote(option: Int, pollData: [String]) {
        // Guardar voto real en Firestore
        guard let currentUserId = Auth.auth().currentUser?.uid,
              !storyId.isEmpty else { return }

        // Verificar si ya votó
        Firestore.firestore().collection("users").document(userId)
            .collection("stories").document(storyId)
            .collection("pollVotes").document(currentUserId)
            .getDocument { snapshot, error in
                if let snapshot = snapshot, snapshot.exists {
                    if let option = snapshot.data()?["option"] as? Int {
                        DispatchQueue.main.async {
                            selectedPollOption = option
                            hasVoted = true
                        }
                    }
                    return
                }

                // Guardar voto
                let voteData: [String: Any] = [
                    "userId": currentUserId,
                    "option": option,
                    "timestamp": FieldValue.serverTimestamp()
                ]

                Firestore.firestore().collection("users").document(userId)
                    .collection("stories").document(storyId)
                    .collection("pollVotes").document(currentUserId)
                    .setData(voteData) { error in
                        if error == nil {
                            DispatchQueue.main.async {
                                hasVoted = true
                                // Actualizar votos localmente
                                voteCounts[option, default: 0] += 1
                                totalVotes += 1
                            }
                        } else {
                        }
                    }
            }
    }
}

// MARK: - ✅ STICKER INTERACTIVO DE QUESTIONS
struct InteractiveQuestionSticker: View {
    let questionText: String
    let storyId: String
    let userId: String
    let onPauseStory: () -> Void
    let onResumeStory: () -> Void

    @State private var showingResponseInput = false
    @State private var showingResponsesView = false
    @State private var responseText = ""
    @State private var responseCount = 0
    @State private var hasResponded = false
    @State private var isLoading = false
    @State private var isAuthor = false

    var body: some View {
        Button(action: {
            if isAuthor {
                // ✅ AUTOR: Ver respuestas
                showingResponsesView = true
            } else if !hasResponded {
                // ✅ ESPECTADOR: Responder
                showingResponseInput = true
            }
        }) {
            VStack(spacing: 14) {
                Text(questionText)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)

                Text(responseSubtitle)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.black.opacity(0.15))
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
            }
            .background(
                Color.clear.liquidGlass(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.15), radius: 16, x: 0, y: 8)
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showingResponseInput, onDismiss: {
            onResumeStory()
        }) {
            QuestionResponseInputView(
                questionText: questionText,
                storyId: storyId,
                userId: userId,
                onResponseSubmitted: { count in
                    responseCount = count
                    hasResponded = true
                    showingResponseInput = false
                    onResumeStory()
                }
            )
            .onAppear {
                onPauseStory()
            }
        }
        .sheet(isPresented: $showingResponsesView, onDismiss: {
            onResumeStory()
        }) {
            QuestionResponsesView(
                questionText: questionText,
                storyId: storyId,
                userId: userId
            )
            .onAppear {
                onPauseStory()
            }
        }
        .onAppear {
            loadResponseCount()
            checkIfUserHasResponded()
            checkIfUserIsAuthor()
        }
    }

    private var responseSubtitle: String {
        if isAuthor, responseCount > 0 {
            return String(format: NSLocalizedString("question.responses", comment: "Responses count"), responseCount)
        }

        if !isAuthor, hasResponded {
            return NSLocalizedString("question.alreadyAsked", comment: "Already asked")
        }

        return isAuthor
            ? NSLocalizedString("question.tapToSee", comment: "Tap to see questions")
            : NSLocalizedString("question.tapToAnswer", comment: "Tap to ask a question")
    }

    private func loadResponseCount() {
        let db = Firestore.firestore()
        db.collection("users").document(userId).collection("stories").document(storyId)
            .collection("questionResponses").getDocuments { snapshot, error in
                if let documents = snapshot?.documents {
                    DispatchQueue.main.async {
                        self.responseCount = documents.count
                    }
                }
            }
    }

    private func checkIfUserHasResponded() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }

        let db = Firestore.firestore()
        db.collection("users").document(userId).collection("stories").document(storyId)
            .collection("questionResponses").whereField("userId", isEqualTo: currentUserId)
            .getDocuments { snapshot, error in
                DispatchQueue.main.async {
                    self.hasResponded = !(snapshot?.documents.isEmpty ?? true)
                }
            }
    }

    private func checkIfUserIsAuthor() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        DispatchQueue.main.async {
            self.isAuthor = currentUserId == userId
        }
    }
}



// MARK: - ✅ VISTA DE ENTRADA DE RESPUESTA
struct QuestionResponseInputView: View {
    let questionText: String
    let storyId: String
    let userId: String
    let onResponseSubmitted: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var responseText = ""
    @State private var isLoading = false
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 40, height: 40)
                        .background {
                            Color.clear
                                .liquidGlass(in: Circle(), interactive: true)
                        }
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 10)

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("question.answer.title")
                        .font(.custom("Poppins-SemiBold", size: 24))
                        .foregroundStyle(.primary)

                    Text("question.answer.subtitle")
                        .font(.custom("Poppins-Regular", size: 14))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)

                VStack(alignment: .leading, spacing: 10) {
                    Label("question.promptLabel", systemImage: "questionmark.bubble.fill")
                        .font(.custom("Poppins-SemiBold", size: 13))
                        .foregroundStyle(.secondary)

                    Text(questionText)
                        .font(.custom("Poppins-SemiBold", size: 17))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    Color.clear
                        .liquidGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .padding(.horizontal, 20)

                VStack(alignment: .leading, spacing: 10) {
                    Text("question.yourAnswer")
                        .font(.custom("Poppins-SemiBold", size: 13))
                        .foregroundStyle(.secondary)

                    TextField(NSLocalizedString("question.answerPlaceholder", comment: "Write your question"), text: $responseText, axis: .vertical)
                        .font(.custom("Poppins-Regular", size: 16))
                        .foregroundStyle(.primary)
                        .focused($isTextFieldFocused)
                        .lineLimit(3...6)
                        .disabled(isLoading)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    Color.clear
                        .liquidGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .padding(.horizontal, 20)

                Spacer(minLength: 0)

                Button(action: submitResponse) {
                    HStack(spacing: 10) {
                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.85)
                        }

                        Text("question.sendAnswer")
                            .font(.custom("Poppins-SemiBold", size: 16))
                    }
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background {
                        Color.clear
                            .liquidGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous), interactive: true)
                    }
                }
                .buttonStyle(.plain)
                .disabled(responseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear {
            isTextFieldFocused = true
        }
    }



    private func submitResponse() {
        guard let currentUserId = Auth.auth().currentUser?.uid,
              !responseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        isLoading = true

        let response = QuestionResponse(
            userId: currentUserId,
            response: responseText.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        let db = Firestore.firestore()
        db.collection("users").document(userId).collection("stories").document(storyId)
            .collection("questionResponses").document(response.id).setData([
                "userId": response.userId,
                "response": response.response,
                "timestamp": Timestamp(date: response.timestamp),
                "isAnonymous": response.isAnonymous
            ]) { error in
                DispatchQueue.main.async {
                    isLoading = false
                    if error == nil {
                        // Actualizar contador de respuestas
                        db.collection("users").document(userId).collection("stories").document(storyId)
                            .collection("questionResponses").getDocuments { snapshot, error in
                                let count = snapshot?.documents.count ?? 0
                                onResponseSubmitted(count)
                            }
                    } else {
                    }
                }
            }
    }
}

// MARK: - ✅ INTERACTIVE LOCATION STICKER
struct InteractiveLocationSticker: View {
    let locationName: String
    let coordinate: CLLocationCoordinate2D?
    let onPauseStory: () -> Void
    let onResumeStory: () -> Void
    @State private var showingLocationMap = false

    var body: some View {
        Button(action: {
            onPauseStory() // ✅ PAUSAR HISTORIA
            showingLocationMap = true
        }) {
            HStack(spacing: 8) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 16, weight: .bold))
                Text(locationName.uppercased())
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .tracking(0.5)
                    .lineLimit(1)
            }
            .foregroundColor(.white)
            .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(
                Color.clear.liquidGlass(in: Capsule(style: .continuous))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.4), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
        }
        .buttonStyle(PlainButtonStyle())
        .fullScreenCover(isPresented: $showingLocationMap) {
            LocationMapView(
                locationName: locationName,
                coordinate: coordinate,
                isPresented: $showingLocationMap
            )
        }
        .onChange(of: showingLocationMap) { isPresented in
            if !isPresented {
                onResumeStory() // ✅ REANUDAR HISTORIA CUANDO SE CIERRA
            }
        }
        .onAppear {
            if let coord = coordinate {
            } else {
            }
        }
    }
}

// MARK: - ✅ INTERACTIVE MENTION STICKER
struct InteractiveMentionSticker: View {
    let username: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 2) {
                Text("@")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .opacity(0.7)
                
                Text(username.uppercased())
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .tracking(0.5)
                    .foregroundColor(.white)
            }
            .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                Color.clear.liquidGlass(in: Capsule(style: .continuous))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.4), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - ✅ INTERACTIVE HASHTAG STICKER
struct InteractiveHashtagSticker: View {
    let hashtag: String
    let onPauseStory: () -> Void
    let onResumeStory: () -> Void
    @State private var showingHashtagExplore = false

    var body: some View {
        Button(action: {
            onPauseStory() // ✅ PAUSAR HISTORIA
            showingHashtagExplore = true
        }) {
            StickerHashtagCardView(hashtag: hashtag)
        }
        .buttonStyle(PlainButtonStyle())
        .fullScreenCover(isPresented: $showingHashtagExplore) {
            ExploreView(initialSearchQuery: "#\(hashtag)", isDismissable: true)
        }
        .onChange(of: showingHashtagExplore) { isPresented in
            if !isPresented {
                onResumeStory() // ✅ REANUDAR HISTORIA CUANDO SE CIERRA
            }
        }
        .onAppear {
        }
    }
}

// MARK: - ✅ STICKER DE CLIMA ANIMADO
struct AnimatedWeatherSticker: View {
    let weatherSymbol: String
    let temperature: String

    @State private var animationPhase: CGFloat = 0

    var body: some View {
        HStack(spacing: 8) {
            // ✅ TEMPERATURA
            Text(temperature)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.5), radius: 2, x: 1, y: 1)

            // ✅ SÍMBOLO ANIMADO
            ZStack {
                // Símbolo base
                Text(weatherSymbol)
                    .font(.system(size: 20))

                // Overlay de animación según el tipo
                weatherAnimationOverlay
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(weatherBackground)
        .onAppear {
            withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                animationPhase = 1
            }
        }
    }

    // MARK: - Animación específica según clima
    @ViewBuilder
    private var weatherAnimationOverlay: some View {
        switch weatherSymbol {
        case "☀️":
            SunAnimation(animationPhase: animationPhase)
        case "🌧️":
            RainAnimation(animationPhase: animationPhase)
        case "❄️":
            SnowAnimation(animationPhase: animationPhase)
        case "💨":
            WindAnimation(animationPhase: animationPhase)
        case "⛈️":
            ThunderAnimation(animationPhase: animationPhase)
        case "🌙":
            NightAnimation(animationPhase: animationPhase)
        default:
            EmptyView()
        }
    }

    // MARK: - Background del sticker
    private var weatherBackground: some View {
        RoundedRectangle(cornerRadius: 28)
            .fill(getWeatherGradientColors(for: weatherSymbol)[0].opacity(0.3))
            .overlay(
                RoundedRectangle(cornerRadius: 28)
                    .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
            )
    }

    // MARK: - Colores según clima
    private func getWeatherGradientColors(for symbol: String) -> [Color] {
        switch symbol {
        case "☀️": return [.orange, .yellow]
        case "🌤️", "⛅": return [.orange, .yellow]
        case "🌥️", "☁️": return [.gray, .blue]
        case "🌧️", "⛈️": return [.blue, .indigo]
        case "❄️", "🌨️": return [.cyan, .blue]
        case "🔥": return [.red, .orange]
        case "🥶": return [.cyan, .blue]
        case "💨": return [.white, .gray]
        case "🌙", "🌃": return [.indigo, .purple]
        case "🌅": return [.orange, .pink]
        case "🌄": return [.orange, .red]
        default: return [.orange, .yellow]
        }
    }
}

// MARK: - Animaciones individuales

struct SunAnimation: View {
    let animationPhase: CGFloat

    var body: some View {
        ForEach(0..<8, id: \.self) { index in
            SunRay(index: index, phase: animationPhase)
        }
    }
}

struct SunRay: View {
    let index: Int
    let phase: CGFloat

    var body: some View {
        Circle()
            .fill(Color.yellow.opacity(0.6))
            .frame(width: 4, height: 4)
            .offset(x: offsetX, y: offsetY)
            .scaleEffect(scaleValue)
            .opacity(opacityValue)
    }

    private var angle: Double {
        Double(index) * .pi / 4
    }

    private var radius: CGFloat {
        25
    }

    private var offsetX: CGFloat {
        cos(angle) * radius
    }

    private var offsetY: CGFloat {
        sin(angle) * radius
    }

    private var scaleValue: CGFloat {
        CGFloat(0.5 + 0.5 * sin(Double(phase) + Double(index) * 0.5))
    }

    private var opacityValue: Double {
        0.3 + 0.7 * sin(Double(phase) + Double(index) * 0.3)
    }
}

struct RainAnimation: View {
    let animationPhase: CGFloat

    var body: some View {
        ForEach(0..<6, id: \.self) { index in
            RainDrop(index: index, phase: animationPhase)
        }
    }
}

struct RainDrop: View {
    let index: Int
    let phase: CGFloat

    var body: some View {
        Circle()
            .fill(Color.blue.opacity(0.7))
            .frame(width: 3, height: 6)
            .offset(x: offsetX, y: offsetY)
            .opacity(opacityValue)
    }

    private var offsetX: CGFloat {
        CGFloat(index - 3) * 8
    }

    private var offsetY: CGFloat {
        -20 + (phase * 40).truncatingRemainder(dividingBy: 40)
    }

    private var opacityValue: Double {
        0.5 + 0.5 * sin(phase + Double(index) * 0.5)
    }
}

struct SnowAnimation: View {
    let animationPhase: CGFloat

    var body: some View {
        ForEach(0..<5, id: \.self) { index in
            SnowFlake(index: index, phase: animationPhase)
        }
    }
}

struct SnowFlake: View {
    let index: Int
    let phase: CGFloat

    var body: some View {
        Text("❄️")
            .font(.system(size: 8))
            .offset(x: offsetX, y: offsetY)
            .rotationEffect(.degrees(rotationAngle))
            .opacity(opacityValue)
    }

    private var offsetX: CGFloat {
        CGFloat(index - 2) * 12
    }

    private var offsetY: CGFloat {
        -15 + (phase * 30).truncatingRemainder(dividingBy: 30)
    }

    private var rotationAngle: Double {
        Double(phase * 360)
    }

    private var opacityValue: Double {
        0.6 + 0.4 * sin(phase + Double(index) * 0.7)
    }
}

struct WindAnimation: View {
    let animationPhase: CGFloat

    var body: some View {
        ForEach(0..<3, id: \.self) { index in
            WindParticle(index: index, phase: animationPhase)
        }
    }
}

struct WindParticle: View {
    let index: Int
    let phase: CGFloat

    var body: some View {
        Circle()
            .fill(Color.white.opacity(0.6))
            .frame(width: 6, height: 6)
            .offset(x: offsetX, y: offsetY)
            .opacity(opacityValue)
    }

    private var offsetX: CGFloat {
        (phase * 15).truncatingRemainder(dividingBy: 15) + CGFloat(index * 10)
    }

    private var offsetY: CGFloat {
        CGFloat(index - 1) * 5
    }

    private var opacityValue: Double {
        0.4 + 0.6 * sin(phase + Double(index) * 0.8)
    }
}

struct ThunderAnimation: View {
    let animationPhase: CGFloat

    var body: some View {
        ForEach(0..<2, id: \.self) { index in
            Lightning(index: index, phase: animationPhase)
        }
    }
}

struct Lightning: View {
    let index: Int
    let phase: CGFloat

    var body: some View {
        Image(systemName: "bolt.fill")
            .foregroundColor(.yellow)
            .font(.system(size: 12))
            .offset(x: offsetX, y: offsetY)
            .opacity(opacityValue)
    }

    private var offsetX: CGFloat {
        (CGFloat(index) - 0.5) * 20
    }

    private var offsetY: CGFloat {
        -8 + (phase * 15).truncatingRemainder(dividingBy: 15)
    }

    private var opacityValue: Double {
        0.3 + 0.7 * sin(Double(phase) * 2 + Double(index) * 1.0)
    }
}

struct NightAnimation: View {
    let animationPhase: CGFloat

    var body: some View {
        ForEach(0..<6, id: \.self) { index in
            Star(index: index, phase: animationPhase)
        }
    }
}

struct Star: View {
    let index: Int
    let phase: CGFloat

    var body: some View {
        Text("⭐")
            .font(.system(size: 6))
            .offset(x: offsetX, y: offsetY)
            .scaleEffect(scaleValue)
            .opacity(opacityValue)
    }

    private var angle: Double {
        Double(index) * .pi / 3
    }

    private var radius: CGFloat {
        20
    }

    private var offsetX: CGFloat {
        cos(angle) * radius
    }

    private var offsetY: CGFloat {
        sin(angle) * radius
    }

    private var scaleValue: CGFloat {
        0.3 + 0.7 * sin(phase + Double(index) * 0.8)
    }

    private var opacityValue: Double {
        0.4 + 0.6 * sin(phase + Double(index) * 0.6)
    }
}

// MARK: - ✅ PRELOADING FUNCTIONS
extension StoryViewModel {

    /// ✅ PRELOAD: Precargar la siguiente historia
    func preloadNextStory(currentStoryId: String, allStories: [Story]) {
        guard let currentIndex = allStories.firstIndex(where: { $0.id == currentStoryId }),
              currentIndex + 1 < allStories.count else {
            return
        }

        let nextStory = allStories[currentIndex + 1]
        preloadStory(nextStory)
    }

    /// ✅ PRELOAD: Precargar historia específica
    func preloadStory(_ story: Story) {
        guard let storyId = story.id else { return }

        // ✅ Evitar precargar si ya está en cache
        if preloadedStories[storyId] != nil {
            return
        }

        // ✅ Limpiar cache si está lleno
        if preloadedStories.count >= maxPreloadedStories {
            clearOldestPreloadedStory()
        }

        // ✅ Agregar a cache
        preloadedStories[storyId] = story

        // ✅ Precargar media según el tipo
        switch story.mediaItem.type {
        case .image:
            preloadImage(for: story)
        case .video:
            preloadVideo(for: story)
        }
    }

    /// ✅ PRELOAD: Precargar imagen
    private func preloadImage(for story: Story) {
        guard let storyId = story.id,
              let url = URL(string: story.mediaItem.url) else { return }

        // ✅ Usar Kingfisher para precargar
        KingfisherManager.shared.retrieveImage(with: url) { result in
            switch result {
            case .success(let imageResult):
                DispatchQueue.main.async {
                    self.preloadedImages[storyId] = imageResult.image
                }
            case .failure(_):
                break
            }
        }
    }

    /// ✅ PRELOAD: Precargar video
    private func preloadVideo(for story: Story) {
        guard let storyId = story.id,
              let url = URL(string: story.mediaItem.url) else { return }

        // ✅ Crear player y precargar
        let player = AVPlayer(url: url)
        player.isMuted = true // Silenciar para preload

        // ✅ Precargar buffer
        let playerItem = player.currentItem
        playerItem?.preferredForwardBufferDuration = 5.0 // 5 segundos de buffer

        DispatchQueue.main.async {
            self.preloadedVideos[storyId] = player
        }
    }

    /// ✅ PRELOAD: Limpiar historia más antigua del cache
    private func clearOldestPreloadedStory() {
        guard let oldestStoryId = preloadedStories.keys.first else { return }

        preloadedStories.removeValue(forKey: oldestStoryId)
        preloadedImages.removeValue(forKey: oldestStoryId)
        preloadedVideos.removeValue(forKey: oldestStoryId)
    }

    /// ✅ PRELOAD: Limpiar cache completo
    func clearPreloadCache() {
        preloadedStories.removeAll()
        preloadedImages.removeAll()
        preloadedVideos.removeAll()
    }

    /// ✅ PRELOAD: Obtener historia precargada
    func getPreloadedStory(_ storyId: String) -> Story? {
        return preloadedStories[storyId]
    }

    /// ✅ PRELOAD: Obtener imagen precargada
    func getPreloadedImage(_ storyId: String) -> UIImage? {
        return preloadedImages[storyId]
    }

    /// ✅ PRELOAD: Obtener video precargado
    func getPreloadedVideo(_ storyId: String) -> AVPlayer? {
        return preloadedVideos[storyId]
    }
}

// MARK: - Floating Hearts Animation Components

struct FloatingHeart: Identifiable, Equatable {
    let id = UUID()
    let emoji: String
    let startX: CGFloat
}

struct FloatingHeartsView: View {
    let hearts: [FloatingHeart]

    var body: some View {
        ZStack {
            ForEach(hearts) { heart in
                FloatingHeartToView(heart: heart)
            }
        }
    }
}

struct FloatingHeartToView: View {
    let heart: FloatingHeart
    @State private var offset: CGFloat = 0
    @State private var opacity: Double = 1
    @State private var scale: CGFloat = 0.5
    @State private var xOffset: CGFloat = 0

    var body: some View {
        Text(heart.emoji)
            .font(.system(size: 50))
            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
            .position(x: heart.startX + xOffset, y: UIScreen.main.bounds.height - 150)
            .offset(y: offset)
            .opacity(opacity)
            .scaleEffect(scale)
            .onAppear {
                // Randomize trajectory slightly
                let randomXPath = CGFloat.random(in: -30...30)

                withAnimation(.easeOut(duration: 2.0)) {
                    offset = -UIScreen.main.bounds.height * 0.7
                    opacity = 0
                    scale = 1.2
                    xOffset = randomXPath
                }
            }
    }
}

// MARK: - ✅ UIKit Wrapper to Disable Automatic Keyboard Avoidance
/// This wrapper prevents the automatic keyboard avoidance behavior that SwiftUI inherits from UIKit.
/// Use this when you need full control over keyboard positioning in fullScreenCover presentations.
struct KeyboardIgnoringContainer<Content: View>: UIViewControllerRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeUIViewController(context: Context) -> KeyboardIgnoringHostingController<Content> {
        let controller = KeyboardIgnoringHostingController(rootView: content)
        return controller
    }

    func updateUIViewController(_ uiViewController: KeyboardIgnoringHostingController<Content>, context: Context) {
        uiViewController.rootView = content
    }
}

/// Custom UIHostingController that prevents keyboard from pushing content up
class KeyboardIgnoringHostingController<Content: View>: UIHostingController<Content> {
    override func viewDidLoad() {
        super.viewDidLoad()
        // Disable automatic keyboard adjustment
        // This is done by not adjusting the safe area insets when keyboard appears
    }

    // Override to prevent keyboard from affecting layout
    override var additionalSafeAreaInsets: UIEdgeInsets {
        get { .zero }
        set { /* Ignore changes from keyboard */ }
    }
}

// MARK: - 🎥 NUEVO REPRODUCTOR DEDICADO PARA STICKERS
// Diseñado específicamente para el visor de historias, manejando el ciclo de vida y loop correctamente.
struct StickerVideoPlayer: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> StickerPlayerUIView {
        let view = StickerPlayerUIView(frame: .zero)
        return view
    }

    func updateUIView(_ uiView: StickerPlayerUIView, context: Context) {
        // Asegurar que se reproduzca al actualizar si la URL cambió o la vista se recargó
        uiView.play(url: url)
    }

    class StickerPlayerUIView: UIView {
        private let playerLayer = AVPlayerLayer()
        private var player: AVPlayer?
        private var playerItem: AVPlayerItem?
        private var loopObserver: NSObjectProtocol?

        override init(frame: CGRect) {
            super.init(frame: frame)
            setupLayer()
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        private func setupLayer() {
            playerLayer.videoGravity = .resizeAspectFill
            playerLayer.backgroundColor = UIColor.clear.cgColor // ✅ Transparente para ver la base estática
            layer.addSublayer(playerLayer)
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            playerLayer.frame = bounds
        }

        func play(url: URL) {
            // Evitar recrear si es la misma URL
            if let currentUrl = (player?.currentItem?.asset as? AVURLAsset)?.url, currentUrl == url {
                if player?.timeControlStatus != .playing {
                    player?.play()
                }
                return
            }

            // Limpiar observador anterior
            if let observer = loopObserver {
                NotificationCenter.default.removeObserver(observer)
            }

            let item = AVPlayerItem(url: url)
            playerItem = item

            let newPlayer = AVPlayer(playerItem: item)
            newPlayer.isMuted = true // ✅ Muteado por defecto para evitar conflictos de audio
            newPlayer.automaticallyWaitsToMinimizeStalling = false // Intentar reproducir ASAP

            player = newPlayer
            playerLayer.player = newPlayer

            newPlayer.play()

            // ✅ Loop Infinito Robust
            loopObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak newPlayer] _ in
                newPlayer?.seek(to: .zero)
                newPlayer?.play()
            }
        }

        deinit {
            if let observer = loopObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            player?.pause()
            player = nil
        }
    }
}
