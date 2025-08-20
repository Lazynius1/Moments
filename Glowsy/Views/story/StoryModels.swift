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

// MARK: - StoryViewModel
class StoryViewModel: ObservableObject {
    @Published var stories: [String: [Story]] = [:]
    @Published var hasActiveStory: Bool = false
    @Published var storyReactions: [String: [StoryReaction]] = [:] // storyId: reactions
    @Published var storyViewers: [String: [StoryViewer]] = [:] // storyId: viewers
    
    // ✅ PRELOADING: Cache para historias precargadas
    @Published var preloadedStories: [String: Story] = [:] // storyId: Story
    @Published var preloadedImages: [String: UIImage] = [:] // storyId: UIImage
    @Published var preloadedVideos: [String: AVPlayer] = [:] // storyId: AVPlayer

    private let firestoreService = FirestoreService()
    private let chatService = ChatService()
    private let privacyService = PrivacyService()
    
    // ✅ PRELOADING: Configuración
    private let maxPreloadedStories = 3 // Máximo 3 historias precargadas
    
    // MARK: - Obtener historias para un usuario específico
    func fetchStoriesForSpecificUser(userId: String, viewerId: String) {
        guard !userId.isEmpty else {
            DispatchQueue.main.async {
                self.stories = [:]
            }
            return
        }
        guard !viewerId.isEmpty else {
            DispatchQueue.main.async {
                self.stories = [:]
            }
            return
        }
        

        
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
                    // ✅ CORREGIDO: Construir array final manteniendo el orden original
                    let userStories = allStories.filter { story in
                        guard let storyId = story.id else { return false }
                        return storyVisibilityResults[storyId] == true
                    }
                    
                    if userStories.isEmpty {
                        DispatchQueue.main.async {
                            self.stories = [:]
                        }
                        return
                    }
                    
                    DispatchQueue.main.async {
                        self.stories = [userId: userStories]
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
                    print("❌ Error al obtener usuarios seguidos: \(error.localizedDescription)")
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
                    guard let self = self else {
                        group.leave()
                        return
                    }
                    
                    if let error = error {
                        print("❌ Error fetching stories for \(userId): \(error.localizedDescription)")
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
                            print("❌ Error parseando historia: \(error)")
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
                    DispatchQueue.main.async {
                        if canView {
                            userFilteredStories.append(story)
                        }
                        
                        processedCount += 1
                        
                        // Si procesamos todas las historias del usuario
                        if processedCount == stories.count {
                            if !userFilteredStories.isEmpty {
                                filteredStories[userId] = userFilteredStories
                            }
                            group.leave()
                        }
                    }
                }
            }
        }
        
        group.notify(queue: .main) {
            self.stories = filteredStories
            self.prefetchImages()
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
            let prefetcher = ImagePrefetcher(urls: urlsToPrefetchLimited) { skippedResources, failedResources, completedResources in
                print("Precarga de imágenes completada: \(completedResources.count) imágenes")
            }
            prefetcher.start()
        }
    }

    func checkActiveStories(userId: String) {
        firestoreService.db.collection("users").document(userId).collection("stories")
            .whereField("expirationDate", isGreaterThan: Date())
            .getDocuments { [weak self] snapshot, error in
                guard let self = self else { return }
                if let error = error {
                    print("Error checking active stories: \(error.localizedDescription)")
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
        
        print("Sending story message to \(userId)")
        
        // First, get or create conversation
        getOrCreateConversation(between: currentUserId, and: userId) { [weak self] conversationId, error in
            guard let self = self, let conversationId = conversationId, error == nil else {
                print("Error getting conversation: \(error?.localizedDescription ?? "Unknown error")")
                completion(false)
                return
            }
            
            // Fetch the story to include its media data
            firestoreService.db.collection("users").document(userId).collection("stories").document(storyId).getDocument { (snapshot: DocumentSnapshot?, error: Error?) in
                if let error = error {
                    print("Error fetching story: \(error.localizedDescription)")
                    completion(false)
                    return
                }
                
                guard let snapshot = snapshot, snapshot.exists else {
                    print("Story document does not exist for storyId: \(storyId)")
                    completion(false)
                    return
                }
                
                let storyData = snapshot.data() ?? [:]
                print("Story data: \(storyData)")
                
                // Extract mediaUrl and type from mediaItem
                guard let mediaItem = storyData["mediaItem"] as? [String: Any],
                      let storyMediaUrl = mediaItem["url"] as? String,
                      let storyMediaType = mediaItem["type"] as? String else {
                    print("Missing mediaItem.url or mediaItem.type in story data for storyId: \(storyId)")
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
                        print("Story text reply sent successfully")
                        completion(true)
                    case .failure(let error):
                        print("Error sending story text reply: \(error.localizedDescription)")
                        completion(false)
                    }
                }
            }
        }
    }


    func sendEphemeralMoment(to userId: String, storyId: String, image: UIImage, completion: @escaping (Bool) -> Void) {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            print("No authenticated user")
            completion(false)
            return
        }
        
        print("Sending ephemeral moment to \(userId) for story \(storyId)")
        
        // Convert UIImage to Data
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            print("Failed to convert image to data")
            completion(false)
            return
        }
        
        // Fetch the story to include its media
        firestoreService.db.collection("users").document(userId).collection("stories").document(storyId).getDocument { [weak self] (snapshot: DocumentSnapshot?, error: Error?) in
            if let error = error {
                print("Error fetching story: \(error.localizedDescription)")
                completion(false)
                return
            }
            
            guard let snapshot = snapshot, snapshot.exists else {
                print("Story document does not exist for storyId: \(storyId)")
                completion(false)
                return
            }
            
            let storyData = snapshot.data() ?? [:]
            print("Story data: \(storyData)")
            
            // Extract mediaUrl and type from mediaItem
            guard let mediaItem = storyData["mediaItem"] as? [String: Any],
                  let storyMediaUrl = mediaItem["url"] as? String,
                  let storyMediaType = mediaItem["type"] as? String else {
                print("Missing mediaItem.url or mediaItem.type in story data for storyId: \(storyId)")
                completion(false)
                return
            }
            
            // Check if user can send message
            self?.chatService.canSendMessage(from: currentUserId, to: userId) { [weak self] result in
                switch result {
                case .success(let canSend):
                    guard canSend else {
                        print("Cannot send message to \(userId)")
                        completion(false)
                        return
                    }
                    
                    // Get or create conversation
                    self?.getOrCreateConversation(between: currentUserId, and: userId) { [weak self] conversationId, error in
                        guard let self = self, let conversationId = conversationId, error == nil else {
                            print("Error getting conversation: \(error?.localizedDescription ?? "Unknown error")")
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
                                    content: "📸 Momento efímero en respuesta a tu historia",
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
                                        print("Ephemeral moment sent successfully to conversation \(conversationId)")
                                        completion(true)
                                    case .failure(let error):
                                        print("Error sending ephemeral message: \(error.localizedDescription)")
                                        completion(false)
                                    }
                                }
                            case .failure(let error):
                                print("Error uploading ephemeral image: \(error.localizedDescription)")
                                completion(false)
                            }
                        }
                    }
                    
                case .failure(let error):
                    print("Error checking send permission: \(error.localizedDescription)")
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
                    print("Error fetching reactions: \(error.localizedDescription)")
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
                    print("Error fetching viewers: \(error.localizedDescription)")
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

    func markStoryAsViewed(userId: String, storyId: String) {
        guard let currentUserId = Auth.auth().currentUser?.uid,
              currentUserId != userId else { return }
        
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
                            print("Error marking story as viewed: \(error.localizedDescription)")
                        }
                    }
            case .failure(let error):
                print("Error fetching user profile: \(error.localizedDescription)")
            }
        }
    }

    func deleteStory(userId: String, storyId: String, completion: @escaping (Error?) -> Void) {
        guard let currentUserId = Auth.auth().currentUser?.uid, currentUserId == userId else {
            completion(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No autorizado para eliminar esta historia"]))
            return
        }
        
        // ✅ PRIMERO: Obtener la historia para extraer la URL del media
        firestoreService.db.collection("users").document(userId).collection("stories").document(storyId)
            .getDocument { [weak self] document, error in
                guard let self = self else { return }
                
                if let error = error {
                    completion(error)
                    return
                }
                
                guard let data = document?.data(),
                      let mediaItemData = data["mediaItem"] as? [String: Any],
                      let mediaUrl = mediaItemData["url"] as? String else {
                    completion(error)
                    return
                }
                
                // ✅ SEGUNDO: Eliminar el media de Firebase Storage
                self.deleteMediaFromStorage(mediaUrl: mediaUrl) { storageError in
                    if let storageError = storageError {
                        // Continuar aunque falle el borrado del media
                    }
                    
                    // ✅ TERCERO: Eliminar la historia de Firestore
                    self.firestoreService.db.collection("users").document(userId).collection("stories").document(storyId)
                        .delete { firestoreError in
                            if let firestoreError = firestoreError {
                                completion(firestoreError)
                            } else {
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
            completion(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "URL de media inválida"]))
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

    func shareStory(_ story: Story, completion: @escaping (Bool) -> Void) {
        guard let storyUrl = URL(string: story.mediaItem.url) else {
            completion(false)
            return
        }
        
        let activityController = UIActivityViewController(
            activityItems: [storyUrl, "Check out this story!"],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(activityController, animated: true) {
                completion(true)
            }
        } else {
            completion(false)
        }
    }

    // MARK: - Private Helpers
    
    private func getOrCreateConversation(between senderId: String, and receiverId: String, completion: @escaping (String?, Error?) -> Void) {
        print("Checking for conversation between \(senderId) and \(receiverId)")
        
        // Validate inputs
        guard !senderId.isEmpty, !receiverId.isEmpty else {
            print("Invalid senderId or receiverId")
            completion(nil, NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid user IDs"]))
            return
        }
        
        firestoreService.db.collection("conversations")
            .whereField("participants", arrayContains: senderId)
            .getDocuments { [weak self] snapshot, error in
                if let error = error {
                    print("Error searching conversation: \(error.localizedDescription)")
                    completion(nil, error)
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    print("No conversations found for \(senderId), creating new one")
                    self?.createNewConversation(between: senderId, and: receiverId, completion: completion)
                    return
                }
                
                print("Found \(documents.count) conversation documents")
                
                // Find conversation with both participants
                let conversation = documents.first { doc in
                    let participants = doc.data()["participants"] as? [String] ?? []
                    return participants.contains(receiverId)
                }
                
                if let conversation = conversation {
                    let conversationId = conversation.documentID
                    print("Found existing conversation: \(conversationId)")
                    completion(conversationId, nil)
                } else {
                    print("No matching conversation found, creating new one")
                    self?.createNewConversation(between: senderId, and: receiverId, completion: completion)
                }
            }
    }
    
    
    
    func sendReaction(to userId: String, storyId: String, reaction: String) {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        print("Sending reaction \(reaction) to story \(storyId)")
        
        // 1. Guardar la reacción en la historia
        let reactionData: [String: Any] = [
            "userId": currentUserId,
            "reaction": reaction,
            "timestamp": Timestamp()
        ]
        
        firestoreService.db.collection("users").document(userId).collection("stories").document(storyId)
            .collection("reactions").addDocument(data: reactionData) { [weak self] error in
                if let error = error {
                    print("Error sending reaction: \(error.localizedDescription)")
                } else {
                    // Update local reactions
                    self?.fetchReactions(for: userId, storyId: storyId)
                    
                    // 2. Enviar notificación si no es tu propia historia
                    if currentUserId != userId {
                        self?.sendStoryReactionNotification(
                            to: userId,
                            storyId: storyId,
                            reaction: reaction,
                            from: currentUserId
                        )
                    }
                }
            }
    }

    // NUEVA función para enviar notificación de reacción
    private func sendStoryReactionNotification(to storyAuthorId: String, storyId: String, reaction: String, from senderId: String) {
        // Fetch sender's profile
        firestoreService.fetchUserProfile(userId: senderId) { result in
            switch result {
            case .success(let user):
                let notification = Notification(
                    id: UUID().uuidString,
                    type: .storyReaction,
                    senderId: senderId,
                    senderUsername: user.username,
                    timestamp: Date(),
                    isPending: true,
                    momentId: nil,
                    visitCount: nil,
                    storyId: storyId,
                    storyAuthorId: storyAuthorId,
                    reaction: reaction
                )
                
                self.firestoreService.createNotification(notification: notification, for: storyAuthorId) { error in
                    if let error = error {
                        print("Error sending story reaction notification: \(error.localizedDescription)")
                    } else {
                        print("Story reaction notification sent successfully")
                    }
                }
                
            case .failure(let error):
                print("Error fetching sender profile for notification: \(error.localizedDescription)")
            }
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
                        print("Error creating conversation: \(error.localizedDescription)")
                        completion(nil, error)
                    } else {
                        print("Conversation created with ID: \(conversationId)")
                        completion(conversationId, nil)
                    }
                }
                
            case .failure(let error):
                print("Error fetching receiver profile: \(error.localizedDescription)")
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
    let onProgressUpdate: (Double) -> Void
    let onVideoComplete: () -> Void

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        let player = AVPlayer(url: url)
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspect // Inicial por defecto
        controller.view.backgroundColor = .clear
        context.coordinator.player = player
        context.coordinator.onProgressUpdate = onProgressUpdate
        context.coordinator.onVideoComplete = onVideoComplete
        
        // ✅ CONFIGURAR OBSERVERS PARA PROGRESO
        context.coordinator.setupObservers()
        
        // 🎯 CONFIGURAR GRAVITY SEGÚN ORIENTACIÓN
        context.coordinator.configureVideoGravity(for: controller)
        
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        // ✅ MEJORADO: Manejar cambios de URL
        if let currentURL = uiViewController.player?.currentItem?.asset as? AVURLAsset,
           currentURL.url != url {
            // URL cambió, recrear player
            print("🎬 [VIDEO] URL cambió, recreando player")
            
            // ✅ CLEANUP AUDIO DEL PLAYER ANTERIOR
            uiViewController.player?.pause()
            uiViewController.player?.isMuted = true
            
            let newPlayer = AVPlayer(url: url)
            uiViewController.player = newPlayer
            context.coordinator.player = newPlayer
            context.coordinator.setupObservers()
            
            // 🎯 RECONFIGURAR GRAVITY PARA NUEVO VIDEO
            context.coordinator.configureVideoGravity(for: uiViewController)
        }
        
        // ✅ EVITAR LOOP: Verificar estado actual del player
        let playerIsPlaying = uiViewController.player?.rate != 0.0
        
        if isPlaying && !playerIsPlaying {
            // ✅ Solo reproducir si no está reproduciéndose
            if let player = uiViewController.player, player.currentItem != nil {
                print("🎬 [VIDEO] Reproduciendo")
                player.play()
            }
        } else if !isPlaying && playerIsPlaying {
            // ✅ Solo pausar si está reproduciéndose
            print("🎬 [VIDEO] Pausando")
            uiViewController.player?.pause()
            uiViewController.player?.isMuted = true
        }
        
        // ✅ RESET PROGRESO CUANDO CAMBIA URL
        if let currentURL = uiViewController.player?.currentItem?.asset as? AVURLAsset,
           currentURL.url != url {
            context.coordinator.onProgressUpdate?(0.0)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject {
        var parent: GlassmorphicStoryVideoPlayer
        var player: AVPlayer?
        var timeObserver: Any?
        var onProgressUpdate: ((Double) -> Void)?
        var onVideoComplete: (() -> Void)?

        init(_ parent: GlassmorphicStoryVideoPlayer) {
            self.parent = parent
        }
        
        // 🎯 CONFIGURAR GRAVITY SEGÚN ORIENTACIÓN DEL VIDEO
        func configureVideoGravity(for controller: AVPlayerViewController) {
            // ✅ USAR EL PARÁMETRO isHorizontalVideo QUE YA TENEMOS
            if parent.isHorizontalVideo {
                // 📱 HORIZONTAL: Mostrar completo con barras
                controller.videoGravity = .resizeAspect
                print("🎬 [VIDEO] Gravity: .resizeAspect (horizontal - mostrar completo)")
            } else {
                // 📱 VERTICAL: Llenar pantalla (fullscreen)
                controller.videoGravity = .resizeAspectFill
                print("🎬 [VIDEO] Gravity: .resizeAspectFill (vertical - fullscreen)")
            }
        }
        
        func setupObservers() {
            // ✅ LIMPIAR OBSERVERS ANTERIORES
            if let observer = timeObserver {
                player?.removeTimeObserver(observer)
                timeObserver = nil
            }
            
            // ✅ RESET PROGRESO AL CONFIGURAR OBSERVERS
            onProgressUpdate?(0.0)
            
            // ✅ OBSERVER DE PROGRESO
            timeObserver = player?.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC)),
                queue: .main
            ) { time in
                guard let currentItem = self.player?.currentItem else { return }
                
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
            
            // ✅ OBSERVER DE COMPLETACIÓN
            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player?.currentItem,
                queue: .main
            ) { _ in
                self.onVideoComplete?()
            }
        }
        
        deinit {
            // ✅ CLEANUP COMPLETO
            print("🎬 [VIDEO] GlassmorphicStoryVideoPlayer deinit - limpiando")
            if let observer = timeObserver {
                player?.removeTimeObserver(observer)
            }
            NotificationCenter.default.removeObserver(self)
            player?.pause()
            player?.isMuted = true
            player?.replaceCurrentItem(with: nil)
            player = nil
            
            // ✅ CLEANUP DE AUDIO SESSION
            do {
                try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            } catch {
                print("⚠️ [AUDIO] Error limpiando sesión en deinit: \(error)")
            }
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
    @State private var currentStoryId: String? = nil
    @State private var messageText: String = ""
    @State private var showReactions: Bool = false
    @State private var showEphemeralPicker: Bool = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showQuickActions: Bool = false
    @State private var showViewers: Bool = false
    @State private var showShareSheet: Bool = false
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging: Bool = false
    @State private var showSuccessMessage: Bool = false
    @State private var successMessageText: String = ""
    @FocusState private var isTextFieldFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var keyboardHeight: CGFloat = 0 // Track keyboard height
    @State private var isKeyboardVisible: Bool = false // Track keyboard state
    @State private var authorAllowsMessages: Bool = true
    @State private var authorAllowsReactions: Bool = true
    @State private var authorAllowsEphemeralPhotos: Bool = true
    @State private var storyStickers: [StickerItem] = [] // Cache de stickers
    @State private var showUserProfile = false
    @State private var selectedUserId: String = ""
    // ✅ SOLO ZOOM - Estados para pinch to zoom
    @State private var zoomScale: CGFloat = 1.0
    @State private var lastZoomScale: CGFloat = 1.0

    private let defaultStoryDuration: Double = 10.0
    private let reactions: [String] = ["❤️", "😂", "😮", "😢", "😡", "👏"]

    private let firestoreService = FirestoreService()
    
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

    var body: some View {
        ZStack {
            // Media content in fullscreen
            contentView
                .ignoresSafeArea(.all) // Fullscreen, ignoring safe areas

            // Glassmorphic UI overlay
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    Color.clear.frame(height: 30)
                    
                    // ✅ CORREGIDO: Progress bars
                    glassmorphicProgressBar
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                    
                    glassmorphicHeader
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .zIndex(1)
                }
                
                Spacer()
                
                // Quick actions menu (not affected by keyboard)
                if showQuickActions {
                    modernActionMenu
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
                        .animation(.spring(response: 0.3), value: showQuickActions)
                }
                
                // Bottom interaction area (affected by keyboard)
                glassmorphicBottomArea
            }
            
            // Navigation touch areas (not affected by keyboard)
            if !isKeyboardVisible { // Hide navigation when keyboard is visible
                navigationTouchAreas
            }
            
            // Success message overlay
            if showSuccessMessage {
                GlassmorphicSuccessMessage(text: successMessageText)
                    .transition(.scale.combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .frame(width: screenSize.width, height: screenSize.height)
        .background(Color.black)
        .offset(y: dragOffset)
        .scaleEffect(zoomScale)
        .gesture(dragGesture)
        .gesture(pinchGesture)
        .gesture(longPressGesture)
        .onAppear {
            prepareAndStartStory()
            setupKeyboardNotifications() // Setup keyboard observers
            // ✅ CARGAR STICKERS UNA SOLA VEZ
            if storyStickers.isEmpty {
                storyStickers = story.convertStickersToStickerItems()
            }
            
            // ✅ PRELOAD: Precargar siguiente historia
            preloadNextStory()
        }
        .onDisappear {
            stopAndCleanupStory()
            removeKeyboardNotifications() // Cleanup observers
            // ✅ CLEANUP DE AUDIO AL CERRAR
            cleanupAudioSession()
        }
        .onChange(of: story.id) { oldStoryId, newStoryId in
            print("🔄 [STORY] story.id cambió: \(oldStoryId ?? "nil") → \(newStoryId ?? "nil")")
            if oldStoryId != newStoryId {
                print("🔄 [STORY] Ejecutando handleStoryChange")
                // ✅ RESET PROGRESO INMEDIATAMENTE
                progress = 0.0
                handleStoryChange()
                // ✅ CARGAR STICKERS DE LA NUEVA HISTORIA
                storyStickers = story.convertStickersToStickerItems()
            }
        }
        .onChange(of: storyIndex) { oldIndex, newIndex in
            // ✅ CARGAR STICKERS CUANDO CAMBIE EL ÍNDICE DE LA HISTORIA
            let newStickers = story.convertStickersToStickerItems()
            storyStickers = newStickers
        }
        .sheet(isPresented: $showViewers) {
            GlassmorphicViewersSheet(
                viewers: storyViewModel.storyViewers[story.id ?? ""] ?? [],
                reactions: storyViewModel.storyReactions[story.id ?? ""] ?? []
            )
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = URL(string: story.mediaItem.url) {
                ShareSheet(activityItems: [url, "Check out this story!"])
            }
        }
        .onChange(of: selectedPhoto) { newPhoto in
            handleEphemeralPhoto(newPhoto)
        }
        // ✅ AGREGAR AQUÍ: Nuevos onChange handlers para pausar historias
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
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowUserProfileFromStory"))) { notification in
            if let userId = notification.object as? String, !userId.isEmpty {
                selectedUserId = userId
                showUserProfile = true
                pauseStory() // ✅ Pausar la historia cuando se abre el perfil
            }
        }
        .sheet(isPresented: $showUserProfile, onDismiss: {
            // ✅ Reanudar la historia cuando se cierra el sheet
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                resumeStory()
            }
        }) {
            if !selectedUserId.isEmpty {
                UserProfileView(userId: selectedUserId)
            }
        }
        .onChange(of: showUserProfile) { oldValue, newValue in
            if !newValue && oldValue {
                // ✅ Reanudar la historia cuando se cierra el perfil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    resumeStory()
                }
            }
        }
    }
    
    // MARK: - Glassmorphic Components
    
    private var glassmorphicProgressBar: some View {
        HStack(spacing: 4) {
            ForEach(0..<storyCount, id: \.self) { index in
                GlassmorphicProgressBar(
                    progress: getProgressForSegment(index: index),
                    isActive: index == storyIndex
                )
            }
        }
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
                                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                )
                        } else {
                            Circle()
                                .fill(Color.white.opacity(0.1))
                                .frame(width: 38, height: 38)
                                .storyGlassmorphic()
                            
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
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            Spacer()
            
            
            HStack(spacing: 8) {
                Button(action: {
                    withAnimation(.spring(response: 0.3)) {
                        showQuickActions.toggle()
                        
                        // ✅ PAUSAR/REANUDAR según el estado del menú
                        if showQuickActions {
                            pauseStory()
                    
                        } else {
                            resumeStory()
                    
                        }
                    }
                }) {
                    Image(systemName: "ellipsis")
                        .foregroundColor(.white)
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 40, height: 40)
                        .storyGlassmorphic()
                        .clipShape(Circle())
                }
                
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .foregroundColor(.white)
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 40, height: 40)
                        .storyGlassmorphic()
                        .clipShape(Circle())
                }
            }
        }
    }
    
    // REEMPLAZO DIRECTO para tu glassmorphicQuickActions
    private var modernActionMenu: some View {
        VStack(spacing: 0) {
            // Handle indicator
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.white.opacity(0.6))
                .frame(width: 40, height: 5)
                .padding(.top, 12)
                .padding(.bottom, 20)
            
            // Título
            Text(story.authorId == Auth.auth().currentUser?.uid ? NSLocalizedString("storyContextMenu.myStory", comment: "My story title") : NSLocalizedString("storyContextMenu.options", comment: "Options title"))
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 1)
                .padding(.bottom, 20)
            
            if story.authorId == Auth.auth().currentUser?.uid {
                // ACCIONES DEL PROPIETARIO
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 20) {
                    ModernActionTile(
                        icon: "eye.fill",
                        title: NSLocalizedString("storyContextMenu.viewActivity", comment: "View activity button"),
                        subtitle: NSLocalizedString("storyContextMenu.viewActivity.subtitle", comment: "View activity subtitle"),
                        color: .blue
                    ) {
                        fetchViewersAndShow()
                    }
                    
                    ModernActionTile(
                        icon: "square.and.arrow.down",
                        title: NSLocalizedString("storyContextMenu.save", comment: "Save story button"),
                        subtitle: NSLocalizedString("storyContextMenu.save.subtitle", comment: "Save story subtitle"),
                        color: .green
                    ) {
                        saveStoryToDevice()
                        showQuickActions = false
                        // ✅ REANUDAR después de cerrar menú
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            resumeStory()
                        }
                    }
                    
                    ModernActionTile(
                        icon: "trash.fill",
                        title: NSLocalizedString("storyContextMenu.delete", comment: "Delete story button"),
                        subtitle: NSLocalizedString("storyContextMenu.delete.subtitle", comment: "Delete story subtitle"),
                        color: .red
                    ) {
                        deleteStory()
                        showQuickActions = false
                        // ✅ NO reanudar aquí porque se cierra la vista
                    }
                }
                
            } else {
                // ✅ ACCIONES PARA HISTORIAS DE OTROS
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 20) {
                    ModernActionTile(
                        icon: "square.and.arrow.up",
                        title: NSLocalizedString("storyContextMenu.share", comment: "Share story button"),
                        subtitle: NSLocalizedString("storyContextMenu.share.subtitle", comment: "Share story subtitle"),
                        color: .blue
                    ) {
                        showShareSheet = true
                        showQuickActions = false
                        // ✅ REANUDAR después de cerrar menú
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            resumeStory()
                        }
                    }
                    
                    ModernActionTile(
                        icon: "flag.fill",
                        title: NSLocalizedString("storyContextMenu.report", comment: "Report story button"),
                        subtitle: NSLocalizedString("storyContextMenu.report.subtitle", comment: "Report story subtitle"),
                        color: .orange
                    ) {
                        onReportStory()
                        showQuickActions = false
                        // ✅ NO reanudar aquí porque se abre otro sheet
                
                    }
                    
                    ModernActionTile(
                        icon: "person.slash",
                        title: NSLocalizedString("storyContextMenu.block", comment: "Block user button"),
                        subtitle: NSLocalizedString("storyContextMenu.block.subtitle", comment: "Block user subtitle"),
                        color: .red
                    ) {
                        onBlockUser()
                        showQuickActions = false
                        // ✅ NO reanudar aquí porque se abre confirmación
                
                    }
                }
            }
            
            Spacer().frame(height: 30)
        }
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.black.opacity(0.4))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
        .padding(.horizontal, 20)
        .onDisappear {
            // ✅ REANUDAR cuando el menú desaparece (si no hay otros overlays)
            if !showingReportSheet && !showingBlockConfirmation {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    resumeStory()
                }
            }
        }
    }

    // COMPONENTE: Tile del menú moderno con subtítulo
    struct ModernActionTile: View {
        let icon: String
        let title: String
        let subtitle: String
        let color: Color
        let action: () -> Void
        
        var body: some View {
            Button(action: action) {
                VStack(spacing: 8) {
                    // Ícono con fondo
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(color.opacity(0.15))
                            .frame(width: 60, height: 60)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(color.opacity(0.3), lineWidth: 1.5)
                            )
                        
                        Image(systemName: icon)
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(color)
                    }
                    
                    // Título principal
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .shadow(color: .black.opacity(0.6), radius: 1, x: 0, y: 1)
                    
                    // Subtítulo
                    Text(subtitle)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .shadow(color: .black.opacity(0.6), radius: 1, x: 0, y: 1)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    // MARK: - Bottom Area
    private var glassmorphicBottomArea: some View {
        VStack(spacing: 12) {
            // ✅ REACCIONES: Solo mostrar si el autor las permite
            if showReactions && authorAllowsReactions {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(reactions, id: \.self) { reaction in
                            Button(action: {
                                sendReaction(reaction)
                            }) {
                                Text(reaction)
                                    .font(.system(size: 35))
                                    .frame(width: 56, height: 56)
                                    .background(
                                        Color.black.opacity(0.5)
                                            .background(.ultraThinMaterial)
                                            .environment(\.colorScheme, .dark)
                                    )
                                    .clipShape(Circle())
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
                                    )
                            }
                            .scaleEffect(showReactions ? 1.0 : 0.5)
                            .animation(
                                .spring(response: 0.3)
                                    .delay(Double(reactions.firstIndex(of: reaction) ?? 0) * 0.05),
                                value: showReactions
                            )
                        }
                    }
                    .padding(.horizontal, 20)
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
                                TextField("Enviar mensaje...", text: $messageText, axis: .vertical)
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
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            Color.black.opacity(0.5)
                                .background(.ultraThinMaterial)
                                .environment(\.colorScheme, .dark)
                        )
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
                        )
                        .clipShape(Capsule())
                        
                        // ✅ BOTÓN CÁMARA: Solo si permite fotos efímeras
                        if authorAllowsEphemeralPhotos {
                            Button(action: {
                                showEphemeralPicker = true
                            }) {
                                Image(systemName: "camera.fill")
                                    .foregroundColor(.white)
                                    .font(.system(size: 18))
                                    .frame(width: 44, height: 44)
                                    .background(
                                        Color.black.opacity(0.5)
                                            .background(.ultraThinMaterial)
                                            .environment(\.colorScheme, .dark)
                                    )
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
                                    )
                                    .clipShape(Circle())
                            }
                            .photosPicker(isPresented: $showEphemeralPicker, selection: $selectedPhoto, matching: .images)
                        }
                        
                        // ✅ BOTÓN ENVIAR: Solo si hay mensaje Y permite mensajes
                        if !messageText.isEmpty && authorAllowsMessages {
                            Button(action: sendMessage) {
                                Image(systemName: "paperplane.fill")
                                    .foregroundColor(.white)
                                    .font(.system(size: 18))
                                    .frame(width: 44, height: 44)
                                    .background(Color(hex: "00A896"))
                                    .clipShape(Circle())
                            }
                            .frame(width: 54, height: 54)
                            .contentShape(Rectangle())
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .offset(y: isKeyboardVisible ? -max(keyboardHeight - 100, 0) : 0)
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
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.black.opacity(0.3))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                    )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, isKeyboardVisible ? 10 : 25)
    }
    
    private var contentView: some View {
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
                        onProgressUpdate: { newProgress in
                            // ✅ ACTUALIZAR PROGRESO DE LA HISTORIA (con verificación)
                            guard currentStoryId == story.id else { return }
                            progress = newProgress
                        },
                        onVideoComplete: {
                            // ✅ VIDEO TERMINÓ, IR A SIGUIENTE
                            onNext()
                        }
                    )
                    .aspectRatio(contentMode: {
                        let isHorizontal = GlassmorphicStoryViewer.isHorizontalAspectRatio(story.aspectRatio)
                        return isHorizontal ? .fit : .fill
                    }())
                    .frame(width: screenSize.width, height: screenSize.height)
                    .background(
                        // ✅ FONDO CON IMAGEN PRECARGADA para videos horizontales
                        Group {
                            if let backgroundFrameURL = story.backgroundFrameURL,
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
                        .scaledToFill() // Para imágenes SÍ mantener scaledToFill
                        .frame(width: screenSize.width, height: screenSize.height)
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
            
            // ✅ STICKERS SUPERPUESTOS (usando cache)
            if !storyStickers.isEmpty {
                ForEach(storyStickers, id: \.id) { sticker in
                    StoryStickerView(
                        sticker: sticker,
                        screenSize: screenSize,
                        storyId: story.id ?? "",
                        userId: story.authorId,
                        onPauseStory: pauseStory,
                        onResumeStory: resumeStory
                    )
                        
                }
                
            }
        }
        .gesture(longPressGesture)
        .clipped() // Ensure content doesn't overflow
    }
    
    private var navigationTouchAreas: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: geometry.size.width * 0.15) // Reduced from 0.2 to 0.15
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onPrevious()
                    }
                
                Spacer()
                
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: geometry.size.width * 0.15) // Reduced from 0.2 to 0.15
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onNext()
                    }
            }
            .frame(height: geometry.size.height * 0.85) // Limit height to avoid bottom area
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
    
    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if value.translation.height > 0 {
                    isDragging = true
                    dragOffset = value.translation.height
                    pauseStory()
                }
            }
            .onEnded { value in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    if value.translation.height > screenSize.height * 0.3 {
                        dismiss()
                    } else {
                        dragOffset = 0
                        if !isPaused {
                            resumeStory()
                        }
                    }
                }
                isDragging = false
            }
    }
    
    private var longPressGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .onChanged { _ in
                pauseStory()
            }
            .onEnded { _ in
                resumeStory()
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
        showSuccessAnimation("Reacción enviada")
    }
    
    private func handleEphemeralPhoto(_ photo: PhotosPickerItem?) {
        guard let photo = photo else { return }
        
        Task {
            do {
                guard let data = try await photo.loadTransferable(type: Data.self),
                      let uiImage = UIImage(data: data),
                      let storyId = story.id else {
                    print("Error loading ephemeral image")
                    return
                }
                
                storyViewModel.sendEphemeralMoment(
                    to: story.authorId,
                    storyId: storyId,
                    image: uiImage
                ) { success in
                    if success {
                        showSuccessAnimation("Momento enviado")
                    }
                }
            } catch {
                print("Error processing ephemeral image: \(error.localizedDescription)")
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
                        showSuccessAnimation("Imagen guardada")
                    } else if story.mediaItem.type == .video {
                        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("story_video.mp4")
                        try data.write(to: tempURL)
                        try await PHPhotoLibrary.shared().performChanges {
                            PHAssetCreationRequest.forAsset().addResource(with: .video, fileURL: tempURL, options: nil)
                        }
                        showSuccessAnimation("Video guardado")
                        try? FileManager.default.removeItem(at: tempURL)
                    }
                } catch {
                    print("Error saving media: \(error.localizedDescription)")
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
    
    // MARK: - Story Playback
    
    private func prepareAndStartStory() {
        print("🎬 [STORY] Preparando historia: \(story.id ?? "unknown")")
        
        // ✅ SIMPLIFICADO: Solo reset de estado
        progress = 0.0
        isPaused = false
        currentStoryId = story.id
        
        loadAuthorInteractionSettings()
        
        // Mark story as viewed
        if let storyId = story.id {
            storyViewModel.markStoryAsViewed(userId: story.authorId, storyId: storyId)
        }
        
        // ✅ SIMPLIFICADO: Solo timer para imágenes
        if story.mediaItem.type == .image {
            startImageTimer()
        }
    }
    
    private func stopAndCleanupStory() {
        print("🛑 [STORY] Limpiando historia anterior")
        
        // ✅ SIMPLIFICADO: Solo pausar y limpiar timer
        isPaused = true
        progress = 0.0
        imageTimer?.invalidate()
        imageTimer = nil
        
        // ✅ CLEANUP DE AUDIO
        cleanupAudioSession()
    }
    
    // ✅ NUEVA FUNCIÓN: Limpiar sesión de audio
    private func cleanupAudioSession() {
        print("🔇 [AUDIO] Limpiando sesión de audio")
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("⚠️ [AUDIO] Error limpiando sesión: \(error)")
        }
    }

    
    private func startImageTimer() {

        
        // Reset progress explícitamente
        progress = 0.0
        
        let duration = story.duration > 0 ? story.duration : defaultStoryDuration
        imageTimer?.invalidate()
        
        imageTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            guard !self.isPaused else { return }
            
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
        print("⏸️ [STORY] Pausando historia")
        isPaused = true
        imageTimer?.invalidate()
    }

    private func resumeStory() {
        guard !showQuickActions && !isKeyboardVisible && !isDragging else {
            print("⏸️ [STORY] No reanudando - overlay activo")
            return
        }
        
        print("▶️ [STORY] Reanudando historia")
        isPaused = false
        
        // ✅ SOLO REINICIAR TIMER PARA IMÁGENES
        if story.mediaItem.type == .image && imageTimer == nil {
            startImageTimer()
        }
    }
    
    // MARK: - Helpers
    
    private func handleStoryChange() {
        print("🔄 [STORY] Cambiando de historia")
        
        // ✅ SIMPLIFICADO: Cleanup inmediato
        stopAndCleanupStory()
        
        // ✅ RESET PROGRESO INMEDIATAMENTE
        progress = 0.0
        currentStoryId = story.id
        
        print("🔄 [STORY] Progress reset a 0.0 para historia: \(story.id ?? "unknown")")
        
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
}

// MARK: - Supporting Glassmorphic Views

struct GlassmorphicProgressBar: View {
    let progress: Double
    let isActive: Bool
    
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
                    .fill(
                        LinearGradient(
                            colors: [Color.blue, Color.purple, Color.pink],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(
                        width: geometry.size.width * min(max(progress, 0.0), 1.0),
                        height: 2.5
                    )
                    .cornerRadius(1.25)
                    .shadow(color: Color.purple.opacity(0.6), radius: 3, x: 0, y: 0)
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
                .foregroundColor(Color(hex: "00A896"))
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

struct GlassmorphicViewersSheet: View {
    let viewers: [StoryViewer]
    let reactions: [StoryReaction]
    @Environment(\.dismiss) var dismiss
    @State private var selectedTab = 0
    
    var body: some View {
        NavigationView {
            ZStack {
                // Glassmorphic background
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(hex: "1a1a2e"),
                        Color(hex: "16213e")
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Tab selector
                    GlassmorphicTabSelector(
                        tabs: ["Vistas (\(viewers.count))", "Reacciones (\(reactions.count))"],
                        selectedIndex: $selectedTab
                    )
                    .padding(.horizontal)
                    .padding(.top, 10)
                    
                    // Content
                    TabView(selection: $selectedTab) {
                        // Viewers tab
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(viewers) { viewer in
                                    GlassmorphicViewerRow(viewer: viewer)
                                }
                            }
                            .padding()
                        }
                        .tag(0)
                        
                        // Reactions tab
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(reactions) { reaction in
                                    GlassmorphicReactionRow(reaction: reaction)
                                }
                            }
                            .padding()
                        }
                        .tag(1)
                    }
                    .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("stories.activity.title")
                        .font(.custom("Poppins-SemiBold", size: 16))
                        .foregroundColor(.white)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cerrar") {
                        dismiss()
                    }
                    .font(.custom("Poppins-Medium", size: 14))
                    .foregroundColor(Color(hex: "00A896"))
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct GlassmorphicTabSelector: View {
    let tabs: [String]
    @Binding var selectedIndex: Int
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<tabs.count, id: \.self) { index in
                Button(action: {
                    withAnimation(.spring(response: 0.3)) {
                        selectedIndex = index
                    }
                }) {
                    Text(tabs[index])
                        .font(.custom("Poppins-Medium", size: 14))
                        .foregroundColor(selectedIndex == index ? .white : .white.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            selectedIndex == index ?
                            Color(hex: "00A896").opacity(0.3) : Color.clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(4)
        .storyGlassmorphic()
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct GlassmorphicViewerRow: View {
    let viewer: StoryViewer
    
    var body: some View {
        HStack(spacing: 12) {
            // Profile image
            if let profileImagePath = viewer.profileImagePath,
               let url = URL(string: profileImagePath) {
                KFImage(url)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .frame(width: 44, height: 44)
                    .foregroundColor(.white.opacity(0.5))
            }
            
            // User info
            VStack(alignment: .leading, spacing: 2) {
                Text(viewer.username ?? "Usuario")
                    .font(.custom("Poppins-Medium", size: 14))
                    .foregroundColor(.white)
                
                Text(timeAgo(from: viewer.timestamp))
                    .font(.custom("Poppins-Regular", size: 12))
                    .foregroundColor(.white.opacity(0.7))
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .storyGlassmorphic()
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
    
    var body: some View {
        HStack(spacing: 12) {
            // Profile image
            if let profileImagePath = profileImagePath,
               let url = URL(string: profileImagePath) {
                KFImage(url)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .frame(width: 44, height: 44)
                    .foregroundColor(.white.opacity(0.5))
            }
            
            // User info
            VStack(alignment: .leading, spacing: 2) {
                Text(username)
                    .font(.custom("Poppins-Medium", size: 14))
                    .foregroundColor(.white)
                
                Text(timeAgo(from: reaction.timestamp))
                    .font(.custom("Poppins-Regular", size: 12))
                    .foregroundColor(.white.opacity(0.7))
            }
            
            Spacer()
            
            // Reaction
            Text(reaction.reaction)
                .font(.system(size: 28))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .storyGlassmorphic()
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
    
    init(icon: String, message: String, showCloseButton: Bool = false, onClose: (() -> Void)? = nil) {
        self.icon = icon
        self.message = message
        self.showCloseButton = showCloseButton
        self.onClose = onClose
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: icon)
                .font(.system(size: 50))
                .foregroundColor(.white.opacity(0.6))
            
            Text(message)
                .foregroundColor(.white)
                .font(.custom("Poppins-Medium", size: 16))
                .multilineTextAlignment(.center)
            
            if showCloseButton, let onClose = onClose {
                Button(action: onClose) {
                    Text("stories.close")
                        .font(.custom("Poppins-Medium", size: 14))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                        )
                }
            }
        }
        .padding()
        .storyGlassmorphic()
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 40)
    }
}

// MARK: - Share Sheet
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
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
                        .fill(isCurrentUser ? Color(hex: "00A896").opacity(0.8) : Color.white.opacity(0.15))
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
                Text(isCurrentUser ? "Respondiste a su historia" : "Ha respondido a tu historia")
                    .font(.custom("Poppins-SemiBold", size: 13))
                    .foregroundColor(.white.opacity(0.9))
                
                // Show story type with icon
                if let storyMediaType = storyReplyData["storyMediaType"] {
                    HStack(spacing: 4) {
                        Image(systemName: storyMediaType == "video" ? "play.rectangle.fill" : "photo.fill")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "00A896"))
                        
                        Text(storyMediaType == "video" ? "Video" : "Foto")
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
                    Button("Cerrar") {
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
                Color.white.opacity(0.1)
                    .background(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 0)
                    .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
            )
    }
    
    func storyGlassmorphic() -> some View {
        self
            .background(
                Color.black.opacity(0.3)
                    .blur(radius: 10)
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
        print("🎯 Obteniendo historias de perfil para: '\(userId)' (viewer: '\(viewerId)')")
        
        guard !userId.isEmpty && !viewerId.isEmpty else {
            print("❌ ERROR: IDs vacíos en fetchStoriesForUserProfile")
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
                    print("❌ Error fetching profile stories: \(error.localizedDescription)")
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

                print("📊 Historias de perfil encontradas: \(userStories.count)")
                
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
        
        print("🔍 Filtrando \(stories.count) historias del perfil para viewer: \(viewerId)")
        
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
            
            print("📊 Historias de perfil filtradas: \(orderedVisibleStories.count)/\(stories.count)")
            
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

// MARK: - Interactive Poll Sticker (Como Instagram)
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
        ZStack {
            // ✅ Fondo con gradiente elegante (colores de la app)
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.blue.opacity(0.85),
                            Color.purple.opacity(0.85),
                            Color.pink.opacity(0.85)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.3), lineWidth: 1.5)
                )
            
            VStack(spacing: 8) {
                // ✅ Icono de poll
                Text("📊")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.top, 8)
                
                // ✅ Pregunta con mejor tipografía
                Text(pollData[0].count > 30 ? String(pollData[0].prefix(30)) + "..." : pollData[0])
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                
                // ✅ Opciones interactivas con diseño moderno
                VStack(spacing: 6) {
                    ForEach(0..<2, id: \.self) { index in
                        InteractivePollOptionButton(
                            text: pollData[index + 1].count > 22 ? String(pollData[index + 1].prefix(22)) + "..." : pollData[index + 1],
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
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
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
                    print("📊 No se encontraron votos para poll")
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
                    print("📊 Votos cargados: \(counts), Total: \(totalVotes)")
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
            ZStack(alignment: .leading) {
                // Fondo de la opción
                RoundedRectangle(cornerRadius: 22.5)
                    .fill(isSelected ? Color.blue.opacity(0.8) : Color.white.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22.5)
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )
                
                // Barra de progreso (solo si ya votó)
                if hasVoted {
                    RoundedRectangle(cornerRadius: 22.5)
                        .fill(Color.white.opacity(0.3))
                        .frame(width: 280 * (percentage / 100))
                        .animation(.easeInOut(duration: 0.5), value: percentage)
                }
                
                // Texto
                HStack {
                    Text(text)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    if hasVoted {
                        Text("\(Int(percentage))%")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .frame(height: 45)
        .disabled(hasVoted)
        .scaleEffect(isSelected ? 1.02 : 1.0)
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
                Button("Cerrar") {
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
        if sticker.isAnimated, let gifURL = sticker.gifURL {
            // Solo GIF animado
            Button(action: {
                handleStickerTap()
            }) {
                AnimatedStickerView(sticker: sticker, size: CGSize(width: 100 * sticker.scale, height: 100 * sticker.scale))
                    .frame(width: 100 * sticker.scale, height: 100 * sticker.scale)
            }
            .buttonStyle(PlainButtonStyle())
            .rotationEffect(sticker.rotation)
            .position(
                x: sticker.position.x * screenSize.width / 375,
                y: sticker.position.y * screenSize.height / 812
            )
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
            .frame(width: 280, height: 180)
            .rotationEffect(sticker.rotation)
            .position(
                x: sticker.position.x * screenSize.width / 375,
                y: sticker.position.y * screenSize.height / 812
            )
        } else if sticker.type == .question, let questionText = sticker.interactionData?.questionText {
            // ✅ QUESTION INTERACTIVO: Diseño completo e interactivo
            InteractiveQuestionSticker(
                questionText: questionText,
                storyId: storyId,
                userId: userId,
                onPauseStory: onPauseStory,
                onResumeStory: onResumeStory
            )
            .frame(width: 280, height: 120)
            .rotationEffect(sticker.rotation)
            .position(
                x: sticker.position.x * screenSize.width / 375,
                y: sticker.position.y * screenSize.height / 812
            )
        } else if sticker.type == .location, let locationName = sticker.interactionData?.location {
            // ✅ LOCATION INTERACTIVO: Diseño completo e interactivo
            InteractiveLocationSticker(
                locationName: locationName,
                coordinate: sticker.interactionData?.locationCoordinate,
                onPauseStory: onPauseStory,
                onResumeStory: onResumeStory
            )
            .frame(height: 40)
            .rotationEffect(sticker.rotation)
            .position(
                x: sticker.position.x * screenSize.width / 375,
                y: sticker.position.y * screenSize.height / 812
            )
        } else if sticker.type == .hashtag, let hashtag = sticker.interactionData?.hashtag {
            // ✅ HASHTAG INTERACTIVO: Diseño completo e interactivo
            InteractiveHashtagSticker(
                hashtag: hashtag,
                onPauseStory: onPauseStory,
                onResumeStory: onResumeStory
            )
            .frame(height: 40)
            .rotationEffect(sticker.rotation)
            .position(
                x: sticker.position.x * screenSize.width / 375,
                y: sticker.position.y * screenSize.height / 812
            )
        } else if sticker.type == .weather, let weatherSymbol = sticker.interactionData?.weatherSymbol {
            // ✅ WEATHER ANIMADO: Diseño animado según clima
            AnimatedWeatherSticker(
                weatherSymbol: weatherSymbol,
                temperature: sticker.interactionData?.questionText ?? "🌤️"
            )
            .frame(width: 140, height: 50)
            .rotationEffect(sticker.rotation)
            .position(
                x: sticker.position.x * screenSize.width / 375,
                y: sticker.position.y * screenSize.height / 812
            )
            .onAppear {

            }
        } else {
            // Solo imagen estática
            Button(action: {
                handleStickerTap()
            }) {
                Image(uiImage: sticker.image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 100 * sticker.scale, height: 100 * sticker.scale)
            }
            .buttonStyle(PlainButtonStyle())
            .rotationEffect(sticker.rotation)
            .position(
                x: sticker.position.x * screenSize.width / 375,
                y: sticker.position.y * screenSize.height / 812
            )
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
            // ✅ COMO INSTAGRAM: El poll es interactivo directamente, no necesita tap aquí
            break
            
        case .question:
            // ✅ COMO INSTAGRAM: El question es interactivo directamente, no necesita tap aquí
            break
            
        case .hashtag:
            // ✅ COMO INSTAGRAM: El hashtag es interactivo directamente, no necesita tap aquí
            break
            
        case .location:
            // ✅ COMO INSTAGRAM: El location es interactivo directamente, no necesita tap aquí
            break
            
        default:
            break
        }
    }
    
    // ✅ NUEVO: Manejar voto de poll directamente como Instagram
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
                    print("📊 Usuario ya votó en este poll")
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
                                print("✅ Voto guardado: Opción \(option)")
                            }
                        } else {
                            print("❌ Error guardando voto: \(error?.localizedDescription ?? "")")
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
            VStack(spacing: 8) {
                // Icono de pregunta
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.blue, Color.purple, Color.pink],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                // Texto de la pregunta
                Text(questionText)
                    .font(.custom("Poppins-SemiBold", size: 14))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                
                // Contador de respuestas
                if responseCount > 0 {
                    Text(String(format: NSLocalizedString("question.responses", comment: "Responses count"), responseCount))
                        .font(.custom("Poppins-Regular", size: 12))
                        .foregroundColor(.white.opacity(0.8))
                } else {
                    Text(isAuthor ? "Toca para ver respuestas" : "Toca para responder")
                        .font(.custom("Poppins-Regular", size: 12))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .frame(width: 280, height: 120)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.8), Color.purple.opacity(0.8), Color.pink.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.3), lineWidth: 1.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showingResponseInput) {
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
        .sheet(isPresented: $showingResponsesView) {
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
        NavigationView {
            VStack(spacing: 20) {
                // Header con la pregunta
                VStack(spacing: 12) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.blue, Color.purple, Color.pink],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Text(questionText)
                        .font(.custom("Poppins-SemiBold", size: 18))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
                
                // Campo de respuesta
                VStack(alignment: .leading, spacing: 8) {
                    Text("question.yourAnswer")
                        .font(.custom("Poppins-Medium", size: 14))
                        .foregroundColor(.secondary)
                    
                    TextField("Escribe tu respuesta...", text: $responseText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .focused($isTextFieldFocused)
                        .lineLimit(3...6)
                        .disabled(isLoading)
                }
                .padding(.horizontal, 20)
                
                // Botón de enviar
                Button(action: submitResponse) {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(.white)
                        } else {
                            Text("question.sendAnswer")
                                .font(.custom("Poppins-SemiBold", size: 16))
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [Color.blue, Color.purple, Color.pink],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(responseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                .padding(.horizontal, 20)
                
                Spacer()
            }
            .padding(.top, 20)
            .navigationTitle("Responder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancelar") {
                        dismiss()
                    }
                    .foregroundColor(.blue)
                }
            }
        }
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
                        print("❌ Error enviando respuesta: \(error?.localizedDescription ?? "")")
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
            Text(locationName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.blue, Color.purple, Color.pink],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.ultraThinMaterial.opacity(0.3))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(
                                    LinearGradient(
                                        colors: [Color.blue.opacity(0.6), Color.purple.opacity(0.6)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                )
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
            print("🗺️ InteractiveLocationSticker - locationName: \(locationName)")
            if let coord = coordinate {
                print("🗺️ InteractiveLocationSticker - coordinate: lat: \(coord.latitude), lon: \(coord.longitude)")
            } else {
                print("🗺️ InteractiveLocationSticker - coordinate: nil")
            }
        }
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
            Text("#\(hashtag)")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.pink, Color.orange, Color.yellow],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.ultraThinMaterial.opacity(0.3))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(
                                    LinearGradient(
                                        colors: [Color.pink.opacity(0.6), Color.orange.opacity(0.6)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                )
        }
        .buttonStyle(PlainButtonStyle())
        .fullScreenCover(isPresented: $showingHashtagExplore) {
            ExploreView(initialSearchQuery: "#\(hashtag)")
        }
        .onChange(of: showingHashtagExplore) { isPresented in
            if !isPresented {
                onResumeStory() // ✅ REANUDAR HISTORIA CUANDO SE CIERRA
            }
        }
        .onAppear {
            print("🏷️ InteractiveHashtagSticker - hashtag: #\(hashtag)")
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
        RoundedRectangle(cornerRadius: 20)
            .fill(getWeatherGradientColors(for: weatherSymbol)[0].opacity(0.3))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
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
