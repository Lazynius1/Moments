import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine
import CryptoKit

@MainActor
class ChatService: ObservableObject {
    // MARK: - Properties
    let db = Firestore.firestore()
    let firestoreservice = FirestoreService()
    let encryptionService = EncryptionService.shared // 🔐 Encryption service
    
    @Published var activeListeners: [String: ListenerRegistration] = [:]
    @Published var typingUsers: [String: Set<String>] = [:] // conversationId: Set<userId>
    private var listenerGenerations: [String: Int] = [:]
    
    private var typingTimer: Timer?
    private let typingTimeout: TimeInterval = 3.0

    struct ChatMediaUploadResult {
        let mediaUrl: String?
        let thumbnailUrl: String?
        let mediaObjectPath: String?
        let thumbnailObjectPath: String?
        let mediaEncryption: EncryptedChatMediaMetadata?
        let thumbnailEncryption: EncryptedChatMediaMetadata?
    }

    struct CachedResolvedMedia {
        let mediaUrl: String?
        let thumbnailUrl: String?
    }
    let encryptedMediaResolver: EncryptedMediaResolver
    
    // MARK: - Initialization
    static let shared = ChatService() // ✅ Singleton para acceso global
    
    init() {
        self.encryptedMediaResolver = EncryptedMediaResolver(encryptionService: EncryptionService.shared)
    }
    
    
    // MARK: - Listeners Management

    func removeAllListeners() {
        activeListeners.values.forEach { $0.remove() }
        activeListeners.removeAll()
        listenerGenerations.removeAll()
    }
    
    func removeListener(for conversationId: String) {
        bumpListenerGeneration(for: conversationId)
        activeListeners[conversationId]?.remove()
        activeListeners.removeValue(forKey: conversationId)

        let reactionsKey = "reactions_\(conversationId)"
        bumpListenerGeneration(for: reactionsKey)
        activeListeners[reactionsKey]?.remove()
        activeListeners.removeValue(forKey: reactionsKey)

        let prefsKey = "conversation_prefs_\(conversationId)"
        bumpListenerGeneration(for: prefsKey)
        activeListeners[prefsKey]?.remove()
        activeListeners.removeValue(forKey: prefsKey)

        let buzzKey = "buzz_\(conversationId)"
        bumpListenerGeneration(for: buzzKey)
        activeListeners[buzzKey]?.remove()
        activeListeners.removeValue(forKey: buzzKey)
        
        let typingKey = "typing_\(conversationId)"
        activeListeners[typingKey]?.remove()
        activeListeners.removeValue(forKey: typingKey)
        typingUsers.removeValue(forKey: conversationId)
    }

    func beginListenerGeneration(for key: String) -> Int {
        bumpListenerGeneration(for: key)
        return listenerGeneration(for: key)
    }

    func isCurrentListenerGeneration(_ generation: Int, for key: String) -> Bool {
        listenerGeneration(for: key) == generation
    }

    private func bumpListenerGeneration(for key: String) {
        listenerGenerations[key, default: 0] += 1
    }

    private func listenerGeneration(for key: String) -> Int {
        listenerGenerations[key, default: 0]
    }
    
    func removeTypingListener(for conversationId: String) {
        let typingKey = "typing_\(conversationId)"
        activeListeners[typingKey]?.remove()
        activeListeners.removeValue(forKey: typingKey)
        typingUsers.removeValue(forKey: conversationId)
    }
    
    func removeConversationsListener(for userId: String) {
        let listenerKey = "conversations_\(userId)"
        activeListeners[listenerKey]?.remove()
        activeListeners.removeValue(forKey: listenerKey)
    }
    
    // MARK: - Real-time Messages with Decryption
    func listenToMessages(
        conversationId: String,
        cutoffDate: Date? = nil,
        limit: Int = 50,
        replaceExisting: Bool = true,
        completion: @escaping (Result<[EnhancedMessage], Error>) -> Void
    ) {
        if !replaceExisting, activeListeners[conversationId] != nil {
            return
        }

        let generation = beginListenerGeneration(for: conversationId)
        activeListeners[conversationId]?.remove()
        activeListeners[conversationId] = nil

        let attachListener = { [weak self] in
            guard let self else { return }
            guard self.isCurrentListenerGeneration(generation, for: conversationId) else { return }
            let listener = self.db.collection("conversations")
                .document(conversationId)
                .collection("messages")
                .order(by: "timestamp", descending: false)
                .limit(toLast: limit)
                .addSnapshotListener { [weak self] snapshot, error in
                    Task {
                        await self?.handleMessagesSnapshot(
                            snapshot: snapshot,
                            error: error,
                            conversationId: conversationId,
                            cutoffDate: cutoffDate,
                            completion: completion
                        )
                    }
                }
            self.activeListeners[conversationId] = listener
        }

        if encryptionService.isConversationKeyCached(for: conversationId) {
            attachListener()
            return
        }

        Task {
            await preloadConversationKey(for: conversationId)
            await MainActor.run {
                guard self.isCurrentListenerGeneration(generation, for: conversationId) else { return }
                attachListener()
            }
        }
    }
    
    // ✅ ONE-SHOT FETCH: útil para pantallas de stats donde no necesitamos listener vivo
    func fetchRecentMessages(conversationId: String, cutoffDate: Date? = nil, limit: Int = 300, completion: @escaping (Result<[EnhancedMessage], Error>) -> Void) {
        Task { [weak self] in
            guard let self else { return }
            await preloadConversationKey(for: conversationId)
            do {
                let snapshot = try await db.collection("conversations")
                    .document(conversationId)
                    .collection("messages")
                    .order(by: "timestamp", descending: false)
                    .limit(toLast: limit)
                    .getDocuments()
                await handleMessagesSnapshot(
                    snapshot: snapshot,
                    error: nil,
                    conversationId: conversationId,
                    cutoffDate: cutoffDate,
                    completion: completion
                )
            } catch {
                await handleMessagesSnapshot(
                    snapshot: nil,
                    error: error,
                    conversationId: conversationId,
                    cutoffDate: cutoffDate,
                    completion: completion
                )
            }
        }
    }

    func fetchMessage(conversationId: String, messageId: String, completion: @escaping (Result<EnhancedMessage?, Error>) -> Void) {
        Task { [weak self] in
            guard let self else { return }
            await preloadConversationKey(for: conversationId)

            do {
                let document = try await db.collection("conversations")
                    .document(conversationId)
                    .collection("messages")
                    .document(messageId)
                    .getDocument()

                guard document.exists, let data = document.data() else {
                    await MainActor.run { completion(.success(nil)) }
                    return
                }

                if let deletedFor = data["deletedFor"] as? [String],
                   let currentUserId = Auth.auth().currentUser?.uid,
                   deletedFor.contains(currentUserId) {
                    await MainActor.run { completion(.success(nil)) }
                    return
                }

                if let vanishedFor = data["vanishedFor"] as? [String],
                   let currentUserId = Auth.auth().currentUser?.uid,
                   vanishedFor.contains(currentUserId) {
                    await MainActor.run { completion(.success(nil)) }
                    return
                }

                var message = await buildEnhancedMessage(
                    from: data,
                    docId: document.documentID,
                    conversationId: conversationId
                )
                let reactions = await fetchReactionMap(
                    conversationId: conversationId,
                    messageIds: [message.id]
                )
                message.reactions = mergeLegacyAndLiveReactions(
                    legacy: message.reactions,
                    live: reactions[message.id]
                )

                await MainActor.run { completion(.success(message)) }
            } catch {
                await MainActor.run { completion(.failure(error)) }
            }
        }
    }
    
    // ✅ NUEVO: Cargar mensajes anteriores (Paginación)
    func fetchOlderMessages(conversationId: String, before timestamp: Date, cutoffDate: Date? = nil, limit: Int = 25, completion: @escaping (Result<[EnhancedMessage], Error>) -> Void) {
        Task { [weak self] in
            guard let self else { return }
            await preloadConversationKey(for: conversationId)
            do {
                let snapshot = try await db.collection("conversations")
                    .document(conversationId)
                    .collection("messages")
                    .whereField("timestamp", isLessThan: Timestamp(date: timestamp))
                    .order(by: "timestamp", descending: true)
                    .limit(to: limit)
                    .getDocuments()
                await handleMessagesSnapshot(
                    snapshot: snapshot,
                    error: nil,
                    conversationId: conversationId,
                    cutoffDate: cutoffDate,
                    completion: completion
                )
            } catch {
                await handleMessagesSnapshot(
                    snapshot: nil,
                    error: error,
                    conversationId: conversationId,
                    cutoffDate: cutoffDate,
                    completion: completion
                )
            }
        }
    }

    /// Mensajes posteriores a un cursor estable (timestamp + documentID).
    func fetchMessagesAfter(
        conversationId: String,
        after cursor: MessageSyncCursor,
        cutoffDate: Date? = nil,
        limit: Int = 50,
        completion: @escaping (Result<[EnhancedMessage], Error>) -> Void
    ) {
        Task { [weak self] in
            guard let self else { return }
            await preloadConversationKey(for: conversationId)
            do {
                let collection = db.collection("conversations")
                    .document(conversationId)
                    .collection("messages")

                let snapshot: QuerySnapshot
                if cursor.messageId.isEmpty {
                    snapshot = try await collection
                        .whereField("timestamp", isGreaterThan: Timestamp(date: cursor.timestamp))
                        .order(by: "timestamp", descending: false)
                        .order(by: FieldPath.documentID(), descending: false)
                        .limit(to: limit)
                        .getDocuments()
                } else {
                    snapshot = try await collection
                        .order(by: "timestamp", descending: false)
                        .order(by: FieldPath.documentID(), descending: false)
                        .start(after: [Timestamp(date: cursor.timestamp), cursor.messageId])
                        .limit(to: limit)
                        .getDocuments()
                }

                await handleMessagesSnapshot(
                    snapshot: snapshot,
                    error: nil,
                    conversationId: conversationId,
                    cutoffDate: cutoffDate
                ) { result in
                    switch result {
                    case .success(let messages):
                        let filtered = messages.filter { message in
                            MessageSyncCursor(timestamp: message.timestamp, messageId: message.id)
                                .isAfter(cursor)
                        }
                        completion(.success(filtered))
                    case .failure(let error):
                        completion(.failure(error))
                    }
                }
            } catch {
                await handleMessagesSnapshot(
                    snapshot: nil,
                    error: error,
                    conversationId: conversationId,
                    cutoffDate: cutoffDate,
                    completion: completion
                )
            }
        }
    }

    // ✅ Nueva función helper para manejar el snapshot de manera async
    private func handleMessagesSnapshot(
        snapshot: QuerySnapshot?,
        error: Error?,
        conversationId: String,
        cutoffDate: Date? = nil,
        completion: @escaping (Result<[EnhancedMessage], Error>) -> Void
    ) async {
        if let error = error {
            completion(.failure(error))
            return
        }
        
        guard let documents = snapshot?.documents else {
            completion(.success([]))
            return
        }

        // Clave de conversación antes de descifrar media (evita huecos en blanco al abrir el chat).
        await preloadConversationKey(for: conversationId)

        // Punto de corte temporal: ocultar mensajes que el usuario ya había borrado antes de restauración
        let cutoffDateToUse: Date?
        if let cutoffDate = cutoffDate {
            cutoffDateToUse = cutoffDate
        } else {
            cutoffDateToUse = await MainActor.run {
                conversationCutoffs[conversationId]
            }
        }
        
        var messages: [EnhancedMessage]

        if LocalFirstMessagingSettings.isEnabled {
            messages = await buildMessagesFromSnapshotUsingLocalCache(
                documents: documents,
                conversationId: conversationId,
                cutoffDate: cutoffDateToUse
            )
        } else {
            messages = []
            for doc in documents {
                let data = doc.data()

                if let deletedFor = data["deletedFor"] as? [String],
                   let currentUserId = Auth.auth().currentUser?.uid,
                   deletedFor.contains(currentUserId) {
                    continue
                }

                if let vanishedFor = data["vanishedFor"] as? [String],
                   let currentUserId = Auth.auth().currentUser?.uid,
                   vanishedFor.contains(currentUserId) {
                    continue
                }

                if let cutoff = cutoffDateToUse,
                   let msgTimestamp = (data["timestamp"] as? Timestamp)?.dateValue(),
                   msgTimestamp <= cutoff {
                    continue
                }

                let message = await buildEnhancedMessage(
                    from: data,
                    docId: doc.documentID,
                    conversationId: conversationId
                )
                messages.append(message)
            }
        }

        let fetchedReactions = await fetchReactionMap(
            conversationId: conversationId,
            messageIds: messages.map(\.id)
        )
        messages = messages.map { message in
            var updated = message
            updated.reactions = mergeLegacyAndLiveReactions(
                legacy: message.reactions,
                live: fetchedReactions[message.id]
            )
            return updated
        }
        
        
        // ✅ Marcar mensajes como entregados automáticamente
        if let currentUserId = Auth.auth().currentUser?.uid {
            markMessagesAsDelivered(messages: messages, conversationId: conversationId, currentUserId: currentUserId)
        }
        
        let finalMessages = messages
        await MainActor.run {
            completion(.success(finalMessages))
        }
    }
    
    // MARK: - Send Messages with Encryption
    func sendStoryReplyMessage(conversationId: String, senderId: String, content: String, storyReplyData: [String: String], completion: @escaping (Result<EnhancedMessage, Error>) -> Void) {
        let messageId = UUID().uuidString
        
        // 🔐 Encrypt content before sending (Async)
        Task {
            let encryptedContent = await encryptMessageContent(content, for: conversationId)
            
            let message = EnhancedMessage(
                id: messageId,
                conversationId: conversationId,
                senderId: senderId,
                type: .text,
                content: encryptedContent, // Store encrypted content
                mediaUrl: nil,
                thumbnailUrl: nil,
                duration: nil,
                fileName: nil,
                fileSize: nil,
                latitude: nil,
                longitude: nil,
                timestamp: Date(),
                status: .sending,
                isRead: false,
                isDeleted: false,
                deletedAt: nil,
                editedAt: nil,
                reactions: nil,
                replyTo: nil,
                expirationDate: nil,
                isViewed: false,
                storyReplyData: storyReplyData
            )
            
            sendMessage(message, useServerTimestamp: true, completion: completion)
        }
    }
    
    func sendTextMessage(conversationId: String, senderId: String, content: String, replyTo: String? = nil, messageId: String? = nil, isVanishModeMessage: Bool = false, vanishExpiresAt: Date? = nil, completion: @escaping (Result<EnhancedMessage, Error>) -> Void) {
        let finalMessageId = messageId ?? UUID().uuidString
        
        // 🔐 Encrypt content before sending (Async)
        Task {
            let encryptedContent = await encryptMessageContent(content, for: conversationId)
            
            let message = EnhancedMessage(
                id: finalMessageId,
                conversationId: conversationId,
                senderId: senderId,
                type: .text,
                content: encryptedContent, // Store encrypted content
                mediaUrl: nil,
                thumbnailUrl: nil,
                duration: nil,
                fileName: nil,
                fileSize: nil,
                latitude: nil,
                longitude: nil,
                timestamp: Date(),
                status: .sending,
                isRead: false,
                isDeleted: false,
                deletedAt: nil,
                editedAt: nil,
                reactions: nil,
                replyTo: replyTo,
                expirationDate: nil,
                isViewed: false,
                isVanishModeMessage: isVanishModeMessage ? true : nil,
                vanishExpiresAt: vanishExpiresAt
            )
            
            sendMessage(message, useServerTimestamp: true, completion: completion)
        }
    }

    /// GIF/sticker de Giphy: referencia pública (sin re-subida ni cifrado de bytes).
    func sendGiphyReferenceMessage(
        conversationId: String,
        senderId: String,
        type: MessageType,
        giphyId: String,
        mediaUrl: String,
        width: Int = 0,
        height: Int = 0,
        messageId: String? = nil,
        isVanishModeMessage: Bool = false,
        completion: @escaping (Result<EnhancedMessage, Error>) -> Void
    ) {
        let finalMessageId = messageId ?? UUID().uuidString
        let message = EnhancedMessage(
            id: finalMessageId,
            conversationId: conversationId,
            senderId: senderId,
            type: type,
            content: nil,
            mediaUrl: mediaUrl,
            thumbnailUrl: nil,
            duration: nil,
            fileName: "giphy_\(giphyId)",
            fileSize: nil,
            mediaWidth: width > 0 ? width : nil,
            mediaHeight: height > 0 ? height : nil,
            latitude: nil,
            longitude: nil,
            timestamp: Date(),
            status: .sending,
            isRead: false,
            isDeleted: false,
            deletedAt: nil,
            editedAt: nil,
            reactions: nil,
            replyTo: nil,
            expirationDate: nil,
            isViewed: false,
            isVanishModeMessage: isVanishModeMessage ? true : nil
        )
        sendMessage(message, useServerTimestamp: true, completion: completion)
    }
    
    func sendEphemeralMessage(
        conversationId: String,
        senderId: String,
        content: String? = nil,
        mediaUrl: String? = nil,
        mediaObjectPath: String? = nil,
        thumbnailUrl: String? = nil,
        thumbnailObjectPath: String? = nil,
        mediaEncryption: EncryptedChatMediaMetadata? = nil,
        thumbnailEncryption: EncryptedChatMediaMetadata? = nil,
        expirationHours: Int = 24,
        storyReplyData: [String: String]? = nil,
        messageId: String? = nil,
        completion: @escaping (Result<EnhancedMessage, Error>) -> Void
    ) {
        let messageId = messageId ?? UUID().uuidString
        let expirationDate = Calendar.current.date(byAdding: .hour, value: expirationHours, to: Date())
        
        // 🔐 Encrypt content if it's text (Async)
        Task {
            let encryptedContent: String? = await {
                guard let content = content else { return nil }
                return await encryptMessageContent(content, for: conversationId)
            }()
            
            let message = EnhancedMessage(
                id: messageId,
                conversationId: conversationId,
                senderId: senderId,
                type: .ephemeral,
                content: encryptedContent, // Store encrypted content
                mediaUrl: mediaUrl,
                thumbnailUrl: thumbnailUrl,
                mediaObjectPath: mediaObjectPath,
                thumbnailObjectPath: thumbnailObjectPath,
                mediaEncryption: mediaEncryption,
                thumbnailEncryption: thumbnailEncryption,
                duration: nil,
                fileName: nil,
                fileSize: nil,
                latitude: nil,
                longitude: nil,
                timestamp: Date(),
                status: .sending,
                isRead: false,
                isDeleted: false,
                deletedAt: nil,
                editedAt: nil,
                reactions: nil,
                replyTo: nil,
                expirationDate: expirationDate,
                isViewed: false,
                storyReplyData: storyReplyData
            )
            
            sendMessage(message, useServerTimestamp: true, completion: completion)
        }
    }
    
    func sendMediaMessage(conversationId: String, senderId: String, type: MessageType, mediaData: Data, fileName: String? = nil, messageId: String? = nil, mediaBatchId: String? = nil, isVanishModeMessage: Bool = false, vanishExpiresAt: Date? = nil, completion: @escaping (Result<EnhancedMessage, Error>) -> Void) {
        let finalMessageId = messageId ?? UUID().uuidString
        uploadMedia(data: mediaData, type: type, conversationId: conversationId, messageId: finalMessageId) { [weak self] result in
            switch result {
            case .success(let uploadResult):
                let finalMessageId = messageId ?? UUID().uuidString
                let message = EnhancedMessage(
                    id: finalMessageId,
                    conversationId: conversationId,
                    senderId: senderId,
                    type: type,
                    content: nil, // No text content to encrypt
                    mediaUrl: uploadResult.mediaUrl,
                    thumbnailUrl: uploadResult.thumbnailUrl,
                    mediaObjectPath: uploadResult.mediaObjectPath,
                    thumbnailObjectPath: uploadResult.thumbnailObjectPath,
                    mediaEncryption: uploadResult.mediaEncryption,
                    thumbnailEncryption: uploadResult.thumbnailEncryption,
                    duration: nil,
                    fileName: fileName,
                    fileSize: Int64(mediaData.count),
                    latitude: nil,
                    longitude: nil,
                    timestamp: Date(),
                    status: .sending,
                    isRead: false,
                    isDeleted: false,
                    deletedAt: nil,
                    editedAt: nil,
                    reactions: nil,
                    replyTo: nil,
                    expirationDate: nil,
                    isViewed: false,
                    mediaBatchId: mediaBatchId,
                    isVanishModeMessage: isVanishModeMessage ? true : nil,
                    vanishExpiresAt: vanishExpiresAt
                )
                
                self?.sendMessage(message, useServerTimestamp: true, completion: completion)
                
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    func sendLocationMessage(
        conversationId: String,
        senderId: String,
        latitude: Double,
        longitude: Double,
        messageId: String? = nil,
        isVanishModeMessage: Bool = false,
        completion: @escaping (Result<EnhancedMessage, Error>) -> Void
    ) {
        sendStaticLocationMessage(
            conversationId: conversationId,
            senderId: senderId,
            latitude: latitude,
            longitude: longitude,
            name: nil,
            address: nil,
            messageId: messageId,
            isVanishModeMessage: isVanishModeMessage,
            completion: completion
        )
    }

    // ✅ NUEVO: ubicación fija con nombre/dirección opcionales (coordenadas cifradas E2E en `content`)
    func sendStaticLocationMessage(
        conversationId: String,
        senderId: String,
        latitude: Double,
        longitude: Double,
        name: String?,
        address: String?,
        messageId: String? = nil,
        isVanishModeMessage: Bool = false,
        completion: @escaping (Result<EnhancedMessage, Error>) -> Void
    ) {
        let finalMessageId = messageId ?? UUID().uuidString

        // 🔐 Cifrar las coordenadas + lugar igual que el texto
        Task {
            let payload = ChatLocationPayload(lat: latitude, lng: longitude, name: name, address: address)
            let encryptedContent = await encryptMessageContent(payload.encodedJSON() ?? "", for: conversationId)

            let message = EnhancedMessage(
                id: finalMessageId,
                conversationId: conversationId,
                senderId: senderId,
                type: .location,
                content: encryptedContent, // Coordenadas cifradas (no en texto plano)
                isLiveLocation: false,
                timestamp: Date(),
                status: .sending,
                isRead: false,
                isDeleted: false,
                isViewed: false,
                isVanishModeMessage: isVanishModeMessage ? true : nil
            )

            sendMessage(message, useServerTimestamp: true, completion: completion)
        }
    }

    // ✅ NUEVO: crear mensaje de ubicación en vivo (coordenadas cifradas E2E en `content`)
    func sendLiveLocationMessage(
        conversationId: String,
        senderId: String,
        latitude: Double,
        longitude: Double,
        name: String?,
        address: String?,
        duration: LiveLocationDuration,
        sessionId: String,
        expiresAt: Date,
        messageId: String? = nil,
        isVanishModeMessage: Bool = false,
        completion: @escaping (Result<EnhancedMessage, Error>) -> Void
    ) {
        let finalMessageId = messageId ?? UUID().uuidString

        Task {
            let payload = ChatLocationPayload(lat: latitude, lng: longitude, name: name, address: address)
            let encryptedContent = await encryptMessageContent(payload.encodedJSON() ?? "", for: conversationId)

            let message = EnhancedMessage(
                id: finalMessageId,
                conversationId: conversationId,
                senderId: senderId,
                type: .location,
                content: encryptedContent,
                isLiveLocation: true,
                liveLocationExpiresAt: expiresAt,
                liveLocationDuration: duration.firestoreValue,
                liveLocationSessionId: sessionId,
                locationUpdatedAt: Date(),
                timestamp: Date(),
                status: .sending,
                isRead: false,
                isDeleted: false,
                isViewed: false,
                isVanishModeMessage: isVanishModeMessage ? true : nil
            )

            sendMessage(message, useServerTimestamp: true, completion: completion)
        }
    }

    // ✅ NUEVO: patch de posición para ubicación en vivo (coordenadas cifradas en `content`)
    func updateLiveLocationMessage(
        conversationId: String,
        messageId: String,
        latitude: Double,
        longitude: Double,
        completion: ((Error?) -> Void)? = nil
    ) {
        let ref = db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document(messageId)
        Task {
            let payload = ChatLocationPayload(lat: latitude, lng: longitude)
            let encryptedContent = await encryptMessageContent(payload.encodedJSON() ?? "", for: conversationId)
            ref.updateData([
                "content": encryptedContent,
                "locationUpdatedAt": FieldValue.serverTimestamp()
            ]) { error in
                completion?(error)
            }
        }
    }

    // ✅ NUEVO: detener sesión de ubicación en vivo
    func stopLiveLocationMessage(
        conversationId: String,
        messageId: String,
        completion: ((Error?) -> Void)? = nil
    ) {
        let ref = db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document(messageId)
        ref.updateData([
            "liveLocationStoppedAt": FieldValue.serverTimestamp()
        ]) { error in
            completion?(error)
        }
    }

    /// Estado real (servidor) de un mensaje de ubicación en vivo.
    struct LiveLocationStatus {
        let exists: Bool
        let senderId: String?
        /// `true` si ya no debe seguir publicándose (detenida, caducada o ya no es live).
        let isStopped: Bool
        let expiresAt: Date?
    }

    /// Lee desde Firestore el estado actual de una sesión de ubicación en vivo,
    /// para validar antes de reanudar tras reabrir la app.
    func fetchLiveLocationStatus(conversationId: String, messageId: String) async -> LiveLocationStatus? {
        let ref = db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document(messageId)
        do {
            let snapshot = try await ref.getDocument()
            guard snapshot.exists, let data = snapshot.data() else {
                return LiveLocationStatus(exists: false, senderId: nil, isStopped: true, expiresAt: nil)
            }
            let senderId = data["senderId"] as? String
            let isLive = data["isLiveLocation"] as? Bool ?? false
            let stopped = data["liveLocationStoppedAt"] != nil
            let expiresAt = (data["liveLocationExpiresAt"] as? Timestamp)?.dateValue()
            return LiveLocationStatus(
                exists: true,
                senderId: senderId,
                isStopped: stopped || !isLive,
                expiresAt: expiresAt
            )
        } catch {
            // Error de red u otro: devolvemos nil para no decidir a ciegas.
            return nil
        }
    }
    
    func sendAudioMessage(
        conversationId: String,
        senderId: String,
        audioData: Data,
        duration: Double,
        messageId: String? = nil,
        isVanishModeMessage: Bool = false,
        completion: @escaping (Result<EnhancedMessage, Error>) -> Void
    ) {
        let finalMessageId = messageId ?? UUID().uuidString
        uploadMedia(data: audioData, type: .audio, conversationId: conversationId, messageId: finalMessageId) { [weak self] result in
            switch result {
            case .success(let uploadResult):
                let finalMessageId = messageId ?? UUID().uuidString
                let message = EnhancedMessage(
                    id: finalMessageId,
                    conversationId: conversationId,
                    senderId: senderId,
                    type: .audio,
                    content: nil, // No text content to encrypt
                    mediaUrl: uploadResult.mediaUrl,
                    thumbnailUrl: uploadResult.thumbnailUrl,
                    mediaObjectPath: uploadResult.mediaObjectPath,
                    thumbnailObjectPath: uploadResult.thumbnailObjectPath,
                    mediaEncryption: uploadResult.mediaEncryption,
                    thumbnailEncryption: uploadResult.thumbnailEncryption,
                    duration: duration,
                    fileName: "audio_\(finalMessageId).m4a",
                    fileSize: Int64(audioData.count),
                    latitude: nil,
                    longitude: nil,
                    timestamp: Date(),
                    status: .sending,
                    isRead: false,
                    isDeleted: false,
                    deletedAt: nil,
                    editedAt: nil,
                    reactions: nil,
                    replyTo: nil,
                    expirationDate: nil,
                    isViewed: false,
                    isVanishModeMessage: isVanishModeMessage ? true : nil
                )

                self?.sendMessage(message, useServerTimestamp: true, completion: completion)

            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - Core Send Message Method
    func sendMessage(_ message: EnhancedMessage, useServerTimestamp: Bool, completion: @escaping (Result<EnhancedMessage, Error>) -> Void) {
        nonisolated(unsafe) let message = message
        // ✅ OFFLINE SUPPORT: Si no hay conexión, persistir acción y retornar éxito optimista
        if !NetworkMonitor.shared.isConnected {
            let pendingMessage: EnhancedMessage = {
                let m = message
                m.status = .pending
                return m
            }()
            
            let payload = MessagePayload(
                message: pendingMessage,
                useServerTimestamp: useServerTimestamp
            )
            
            if let data = try? JSONEncoder().encode(payload) {
                let action = CachedAction(
                    id: message.id, // Usar el ID del mensaje para evitar duplicados
                    type: CachedAction.ActionType.message.rawValue,
                    payloadData: data
                )
                
                Task {
                    LocalPersistenceService.shared.saveAction(action)
                    print("💾 ChatService: Mensaje guardado en outbox (offline)")
                    completion(.success(pendingMessage)) // Éxito optimista
                }
                return
            }
        }
        
        let messageRef = db.collection("conversations")
            .document(message.conversationId)
            .collection("messages")
            .document(message.id)
        
        // Create message data that matches the EnhancedMessage structure
        var messageData: [String: Any] = [
            "id": message.id,
            "conversationId": message.conversationId,
            "senderId": message.senderId,
            "type": message.type.rawValue,
            "status": MessageStatus.sent.rawValue, // ✅ FORZAR ESTADO ENVIADO INICIALMENTE
            "isRead": message.isRead,
            "isDeleted": message.isDeleted,
            "isViewed": message.isViewed
        ]
        
        // ✅ Add optional fields (content is already encrypted if needed)
        if let content = message.content {
            if message.type == .chatNotice {
                messageData["content"] = content
            } else {
                messageData["content"] = content // Already encrypted for text messages
            }
        }
        if let mediaObjectPath = message.mediaObjectPath {
            messageData["mediaObjectPath"] = mediaObjectPath
        } else if let mediaUrl = message.mediaUrl {
            messageData["mediaUrl"] = mediaUrl
        }
        if let thumbnailObjectPath = message.thumbnailObjectPath {
            messageData["thumbnailObjectPath"] = thumbnailObjectPath
        } else if let thumbnailUrl = message.thumbnailUrl {
            messageData["thumbnailUrl"] = thumbnailUrl
        }
        if let mediaEncryption = message.mediaEncryption {
            messageData["mediaEncryption"] = mediaEncryption.firestoreData
        }
        if let thumbnailEncryption = message.thumbnailEncryption {
            messageData["thumbnailEncryption"] = thumbnailEncryption.firestoreData
        }
        if let duration = message.duration {
            messageData["duration"] = duration
        }
        if let fileName = message.fileName {
            messageData["fileName"] = fileName
        }
        if let fileSize = message.fileSize {
            messageData["fileSize"] = fileSize
        }
        if let mediaWidth = message.mediaWidth {
            messageData["mediaWidth"] = mediaWidth
        }
        if let mediaHeight = message.mediaHeight {
            messageData["mediaHeight"] = mediaHeight
        }
        if let latitude = message.latitude {
            messageData["latitude"] = latitude // Coordinates are not encrypted
        }
        if let longitude = message.longitude {
            messageData["longitude"] = longitude
        }
        // ✅ NUEVO: Ubicación (fija + en vivo)
        if let locationName = message.locationName {
            messageData["locationName"] = locationName
        }
        if let locationAddress = message.locationAddress {
            messageData["locationAddress"] = locationAddress
        }
        if let isLiveLocation = message.isLiveLocation {
            messageData["isLiveLocation"] = isLiveLocation
        }
        if let liveLocationExpiresAt = message.liveLocationExpiresAt {
            messageData["liveLocationExpiresAt"] = Timestamp(date: liveLocationExpiresAt)
        }
        if let liveLocationDuration = message.liveLocationDuration {
            messageData["liveLocationDuration"] = liveLocationDuration
        }
        if let liveLocationSessionId = message.liveLocationSessionId {
            messageData["liveLocationSessionId"] = liveLocationSessionId
        }
        if let locationUpdatedAt = message.locationUpdatedAt {
            messageData["locationUpdatedAt"] = Timestamp(date: locationUpdatedAt)
        }
        if let replyTo = message.replyTo {
            messageData["replyTo"] = replyTo
        }
        if let expirationDate = message.expirationDate {
            messageData["expirationDate"] = Timestamp(date: expirationDate)
        }
        if let storyReplyData = message.storyReplyData {
            messageData["storyReplyData"] = storyReplyData
        }
        if let sharedMomentData = message.sharedMomentData {
            messageData["sharedMomentData"] = sharedMomentData
        }
        if let sharedStoryData = message.sharedStoryData {
            messageData["sharedStoryData"] = sharedStoryData
        }
        if let mediaBatchId = message.mediaBatchId {
            messageData["mediaBatchId"] = mediaBatchId
        }
        if message.isForwarded == true {
            messageData["isForwarded"] = true
        }
        if message.isVanishModeMessage == true {
            messageData["isVanishModeMessage"] = true
        }
        if let vanishExpiresAt = message.vanishExpiresAt {
            messageData["vanishExpiresAt"] = Timestamp(date: vanishExpiresAt)
        }
        if let starredBy = message.starredBy, !starredBy.isEmpty {
            messageData["starredBy"] = starredBy
        }
        
        // Set timestamp
        if useServerTimestamp {
            messageData["timestamp"] = FieldValue.serverTimestamp()
        } else {
            messageData["timestamp"] = Timestamp(date: message.timestamp)
        }
        
        // Write to Firestore
        let conversationId = message.conversationId
        let messageId = message.id
        let senderId = message.senderId
        let messageType = message.type
        
        messageRef.setData(messageData) { [weak self] error in
            if let error = error {
                // Update status to failed if there's an error
                Task { @MainActor in
                    self?.updateLocalMessageStatus(
                        conversationId: conversationId,
                        messageId: messageId,
                        status: .failed
                    )
                    self?.updateMessageStatus(
                        conversationId: conversationId,
                        messageId: messageId,
                        status: .failed
                    ) { _ in }
                }
                completion(.failure(error))
                return
            }
            
            // ✅ Update conversation with last message (decrypt for preview)
            Task { @MainActor in
                self?.updateConversation(
                    conversationId: conversationId,
                    lastMessage: self?.neutralConversationPreview(for: messageType) ?? MessageType.text.conversationPreview,
                    senderId: senderId,
                    messageType: messageType
                ) { updateError in
                    if updateError != nil {
                        // Silently handle error
                    }
                }
            }
            
            // ✅ Marcar como enviado inmediatamente
            Task { @MainActor in
                self?.updateMessageStatus(
                    conversationId: conversationId,
                    messageId: messageId,
                    status: .sent
                ) { _ in }
            }
            
            let updatedMessage: EnhancedMessage = {
                let m = message
                m.status = .sent
                return m
            }()
            completion(.success(updatedMessage))
        }
    }

    // MARK: - Message Actions with Encryption
    func editMessage(conversationId: String, messageId: String, newContent: String, completion: @escaping (Error?) -> Void) {
        
        // 🔐 Encrypt new content before updating (Async)
        Task {
            let encryptedContent = await encryptMessageContent(newContent, for: conversationId)
            do {
                try await db.collection("conversations")
                    .document(conversationId)
                    .collection("messages")
                    .document(messageId)
                    .updateData([
                        "content": encryptedContent,
                        "editedAt": FieldValue.serverTimestamp()
                    ])
                completion(nil)
            } catch {
                completion(error)
            }
        }
    }
    
    func deleteMessage(conversationId: String, messageId: String, completion: @escaping (Error?) -> Void) {
        db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document(messageId)
            .updateData([
                "isDeleted": true,
                "deletedAt": FieldValue.serverTimestamp(),
                "content": FieldValue.delete(),
                "mediaUrl": FieldValue.delete()
            ]) { error in
                completion(error)
            }
    }
    
    func deleteMessageForMe(conversationId: String, messageId: String, userId: String, completion: @escaping (Error?) -> Void) {
        db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document(messageId)
            .updateData([
                "deletedFor": FieldValue.arrayUnion([userId])
            ]) { error in
                completion(error)
            }
    }
    
    func deleteMessageWithCleanup(conversationId: String, messageId: String, completion: @escaping (Error?) -> Void) {
        
        db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document(messageId)
            .getDocument { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    completion(error)
                    return
                }
                
                guard let document = snapshot, document.exists else {
                    completion(NSError(domain: "ChatService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Mensaje no encontrado"]))
                    return
                }
                
                let data = document.data() ?? [:]
                let mediaResources: [String] = [
                    data["mediaObjectPath"] as? String,
                    data["thumbnailObjectPath"] as? String,
                    data["mediaUrl"] as? String,
                    data["thumbnailUrl"] as? String
                ].compactMap { value -> String? in
                    guard let value, !value.isEmpty else { return nil }
                    return value
                }
                
                // Mark message as deleted first
                Firestore.firestore().collection("conversations")
                    .document(conversationId)
                    .collection("messages")
                    .document(messageId)
                    .updateData([
                        "isDeleted": true,
                        "deletedAt": FieldValue.serverTimestamp(),
                        "content": FieldValue.delete(), // Remove encrypted content
                        "mediaUrl": FieldValue.delete(),
                        "thumbnailUrl": FieldValue.delete(),
                        "mediaObjectPath": FieldValue.delete(),
                        "thumbnailObjectPath": FieldValue.delete(),
                        "mediaEncryption": FieldValue.delete(),
                        "thumbnailEncryption": FieldValue.delete()
                    ]) { updateError in
                        
                        if let updateError = updateError {
                            completion(updateError)
                            return
                        }
                        
                        
                        // Delete media file if exists
                        if !mediaResources.isEmpty {
                            self.deleteMediaFiles(urls: mediaResources) { _ in
                                completion(nil)
                            }
                        } else {
                            completion(nil)
                        }
                    }
            }
    }

    func addReaction(conversationId: String, messageId: String, emoji: String, userId: String, completion: @escaping (Error?) -> Void) {
        // ✅ Optimistic UI: Actualizar caché local en background (no bloquea el return)
        Task(priority: .background) { @MainActor in
            LocalPersistenceService.shared.toggleMessageReactionLocally(messageId: messageId, emoji: emoji, userId: userId)
        }

        let reactionRef = db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document(messageId)
            .collection("messageReactions")
            .document(userId)

        reactionRef.getDocument { snapshot, error in
            if let error {
                completion(error)
                return
            }

            let existingEmoji = snapshot?.data()?["emoji"] as? String
            if existingEmoji == emoji {
                reactionRef.delete(completion: completion)
                return
            }

            let payload: [String: Any] = [
                "conversationId": conversationId,
                "messageId": messageId,
                "userId": userId,
                "emoji": emoji,
                "timestamp": FieldValue.serverTimestamp()
            ]

            if snapshot?.exists == true {
                reactionRef.updateData([
                    "emoji": emoji,
                    "timestamp": FieldValue.serverTimestamp()
                ], completion: completion)
            } else {
                reactionRef.setData(payload, completion: completion)
            }
        }
    }

    func setLastMessageReaction(
        conversationId: String,
        messageId: String,
        emoji: String,
        byUserId: String,
        completion: @escaping (Error?) -> Void
    ) {
        let payload: [String: Any] = [
            "lastMessageReaction": [
                "messageId": messageId,
                "emoji": emoji,
                "byUserId": byUserId
            ]
        ]
        db.collection("conversations").document(conversationId).updateData(payload, completion: completion)
    }

    func clearLastMessageReaction(conversationId: String, completion: @escaping (Error?) -> Void) {
        db.collection("conversations").document(conversationId).updateData([
            "lastMessageReaction": FieldValue.delete()
        ], completion: completion)
    }

    // MARK: - User Permissions
    func canSendMessage(from senderId: String, to userId: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        FirestoreService().fetchUserProfile(userId: userId) { result in
            switch result {
            case .success(let user):
                if user.blockedUsers.contains(senderId) {
                    completion(.success(false))
                    return
                }
                 FirestoreService().fetchUserProfile(userId: senderId) { result in
                    switch result {
                    case .success(let sender):
                        if sender.blockedUsers.contains(userId) {
                            completion(.success(false))
                            return
                        }
                        // ✅ FIX: No bloquear por horario (Active Hours solo para notificaciones)
                        completion(.success(true))
                    case .failure(let error):
                        completion(.failure(error))
                    }
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // ✅ Mapa en memoria: conversationId -> fecha de corte temporal del usuario actual
    // Se pobla al cargar el listener de conversaciones y se consulta en handleMessagesSnapshot.
    private var conversationCutoffs: [String: Date] = [:]
    private var archivedConversationIds: Set<String> = []

    func isConversationArchived(_ conversationId: String, for userId: String) -> Bool {
        archivedConversationIds.contains(conversationId)
    }

    /// Punto de corte en memoria (fallback cuando el modelo `Conversation` no trae `lastDeletedAt`).
    func deletedAtCutoff(for conversationId: String) -> Date? {
        conversationCutoffs[conversationId]
    }

    func deleteConversationsBetweenUsers(user1Id: String, user2Id: String, completion: @escaping (Error?) -> Void) {
        self.db.collection("conversations")
            .whereField("participants", arrayContains: user1Id)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(error)
                    return
                }

                guard let documents = snapshot?.documents else {
                    completion(nil)
                    return
                }

                let conversationsToMarkAsDeleted = documents.filter { doc in
                    if let participants = doc.data()["participants"] as? [String] {
                        return participants.contains(user2Id)
                    }
                    return false
                }

                let batch = Firestore.firestore().batch()
                let now = FieldValue.serverTimestamp()
                for doc in conversationsToMarkAsDeleted {
                    // Marcar conversación como eliminada para este usuario
                    // y guardar el punto de corte temporal (lastDeletedAt)
                    batch.updateData([
                        "deletedFor": FieldValue.arrayUnion([user1Id]),
                        "lastDeletedAt.\(user1Id)": now
                    ], forDocument: doc.reference)
                }

                batch.commit { error in
                    completion(error)
                }
            }
    }
    
    // ✅ NUEVA FUNCIÓN: Restaurar conversación eliminada (estilo nativo)
    func restoreConversation(conversationId: String, for userId: String, completion: @escaping (Error?) -> Void) {
        
        db.collection("conversations")
            .document(conversationId)
            .updateData([
                "deletedFor": FieldValue.arrayRemove([userId])
            ]) { error in
                if let error = error {
                    completion(error)
                } else {
                    completion(nil)
                }
            }
    }
    
    // ✅ NUEVA FUNCIÓN: Marcar todos los mensajes como eliminados para un usuario
    private func markAllMessagesAsDeletedForUser(conversationId: String, userId: String, completion: ((Error?) -> Void)? = nil) {
        
        db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .getDocuments { snapshot, error in
                if let error = error {
                    completion?(error)
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    completion?(nil)
                    return
                }
                
                guard !documents.isEmpty else {
                    completion?(nil)
                    return
                }

                let batch = Firestore.firestore().batch()
                for doc in documents {
                    batch.updateData([
                        "deletedFor": FieldValue.arrayUnion([userId])
                    ], forDocument: doc.reference)
                }
                
                batch.commit { error in
                    if let error = error {
                        completion?(error)
                    } else {
                        completion?(nil)
                    }
                }
            }
    }
    
    // ✅ NUEVAS FUNCIONES: Pin y Mute conversaciones
    func pinConversation(_ conversationId: String, for userId: String, completion: @escaping (Error?) -> Void) {
        
        db.collection("conversations")
            .document(conversationId)
            .updateData([
                "pinnedByUserIds": FieldValue.arrayUnion([userId]),
                "pinnedByTimestamps.\(userId)": FieldValue.serverTimestamp()
            ]) { error in
                if let error = error {
                    completion(error)
                } else {
                    completion(nil)
                }
            }
    }
    
    func unpinConversation(_ conversationId: String, for userId: String, completion: @escaping (Error?) -> Void) {
        
        db.collection("conversations")
            .document(conversationId)
            .updateData([
                "pinnedByUserIds": FieldValue.arrayRemove([userId]),
                "pinnedByTimestamps.\(userId)": FieldValue.delete()
            ]) { error in
                if let error = error {
                    completion(error)
                } else {
                    completion(nil)
                }
            }
    }
    
    func muteConversation(_ conversationId: String, for userId: String, completion: @escaping (Error?) -> Void) {
        
        db.collection("conversations")
            .document(conversationId)
            .updateData([
                "mutedByUserIds": FieldValue.arrayUnion([userId]),
                "mutedByTimestamps.\(userId)": FieldValue.serverTimestamp()
            ]) { error in
                if let error = error {
                    completion(error)
                } else {
                    completion(nil)
                }
            }
    }
    
    func unmuteConversation(_ conversationId: String, for userId: String, completion: @escaping (Error?) -> Void) {
        
        db.collection("conversations")
            .document(conversationId)
            .updateData([
                "mutedByUserIds": FieldValue.arrayRemove([userId]),
                "mutedByTimestamps.\(userId)": FieldValue.delete()
            ]) { error in
                if let error = error {
                    completion(error)
                } else {
                    completion(nil)
                }
            }
    }

    func archiveConversation(_ conversationId: String, for userId: String, completion: @escaping (Error?) -> Void) {
        db.collection("conversations")
            .document(conversationId)
            .updateData([
                "archivedByUserIds": FieldValue.arrayUnion([userId]),
                "archivedByTimestamps.\(userId)": FieldValue.serverTimestamp()
            ]) { error in
                if error == nil {
                    self.archivedConversationIds.insert(conversationId)
                }
                completion(error)
            }
    }

    func unarchiveConversation(_ conversationId: String, for userId: String, completion: @escaping (Error?) -> Void) {
        db.collection("conversations")
            .document(conversationId)
            .updateData([
                "archivedByUserIds": FieldValue.arrayRemove([userId]),
                "archivedByTimestamps.\(userId)": FieldValue.delete()
            ]) { error in
                if error == nil {
                    self.archivedConversationIds.remove(conversationId)
                }
                completion(error)
            }
    }
    
    func fetchConversations(for userId: String, completion: @escaping (Result<[Conversation], Error>) -> Void) {
        // Evitar listeners de listas de conversación huérfanos (p. ej. cambio de cuenta)
        let staleConversationKeys = activeListeners.keys.filter { $0.hasPrefix("conversations_") && $0 != "conversations_\(userId)" }
        for key in staleConversationKeys {
            activeListeners[key]?.remove()
            activeListeners.removeValue(forKey: key)
        }
        
        let listenerKey = "conversations_\(userId)"
        activeListeners[listenerKey]?.remove()
        
        let listener = db.collection("conversations")
            .whereField("participants", arrayContains: userId)
            .order(by: "timestamp", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }

                if let error = error {
                    if Auth.auth().currentUser == nil {
                        completion(.success([]))
                        return
                    }
                    completion(.failure(error))
                    return
                }

                guard let documents = snapshot?.documents else {
                    completion(.success([]))
                    return
                }

                var conversations: [Conversation] = []
                var archivedIds: Set<String> = []

                // Conversaciones que necesitan auto-restauración (mensaje nuevo tras borrado)
                var toRestore: [DocumentReference] = []

                for doc in documents {
                    let data = doc.data()

                    let deletedFor = data["deletedFor"] as? [String] ?? []
                    let isDeletedForMe = deletedFor.contains(userId)

                    // Leer lastDeletedAt para este usuario
                    let lastDeletedAtMap = data["lastDeletedAt"] as? [String: Timestamp]
                    let myDeletedAt = lastDeletedAtMap?[userId]?.dateValue()

                    if isDeletedForMe {
                        // Comparar el timestamp del último mensaje con el punto de corte
                        if let lastMsgTimestamp = (data["timestamp"] as? Timestamp)?.dateValue(),
                           let cutoff = myDeletedAt,
                           lastMsgTimestamp > cutoff {
                            // Auto-restaurar silenciosamente: llegó un mensaje nuevo
                            toRestore.append(doc.reference)
                        } else {
                            // Sigue borrada para este usuario
                            continue
                        }
                    }

                    guard
                        let participants = data["participants"] as? [String],
                        let timestamp = (data["timestamp"] as? Timestamp)?.dateValue(),
                        let readStatus = data["readStatus"] as? [String: Bool]
                    else {
                        continue
                    }

                    let otherParticipantId = participants.first { $0 != userId } ?? ""
                    let encryptionVersion = data["encryptionVersion"] as? String
                    let lastMessage = sanitizedConversationPreview(
                        data["lastMessage"] as? String,
                        encryptionVersion: encryptionVersion
                    )

                    // ✅ Intentar obtener datos del participantData (bidireccional)
                    let otherParticipantUsername: String
                    let otherParticipantProfileImagePath: String

                    if let participantData = data["participantData"] as? [String: [String: Any]],
                       let otherData = participantData[otherParticipantId] {
                        // ✅ Usar datos bidireccionales
                        otherParticipantUsername = otherData["username"] as? String ?? NSLocalizedString("messaging.user.default", comment: "Default user name")
                        otherParticipantProfileImagePath = otherData["profileImagePath"] as? String ?? ""
                    } else {
                        // ✅ Fallback: usar datos del sistema anterior o cache
                        if let cachedUser = UserCacheService.shared.getCachedUser(userId: otherParticipantId) {
                            otherParticipantUsername = cachedUser.username
                            otherParticipantProfileImagePath = cachedUser.profileImagePath ?? ""
                        } else {
                            // Último fallback: datos almacenados del sistema anterior
                            otherParticipantUsername = data["otherParticipantUsername"] as? String ?? NSLocalizedString("messaging.user.default", comment: "Default user name")
                            otherParticipantProfileImagePath = data["otherParticipantProfileImagePath"] as? String ?? ""
                        }
                    }

                    // ✅ Extraer campos de pin y mute
                    let pinnedByUserIds = data["pinnedByUserIds"] as? [String] ?? []
                    let legacyPinnedBy = data["pinnedBy"] as? String
                    let legacyIsPinned = data["isPinned"] as? Bool ?? false
                    let isPinned = pinnedByUserIds.contains(userId) || (legacyIsPinned && legacyPinnedBy == userId)
                    let mutedByUserIds = data["mutedByUserIds"] as? [String] ?? []
                    let legacyMutedBy = data["mutedBy"] as? String
                    let legacyIsMuted = data["isMuted"] as? Bool ?? false
                    let isMuted = mutedByUserIds.contains(userId) || (legacyIsMuted && legacyMutedBy == userId)
                    let archivedByUserIds = data["archivedByUserIds"] as? [String] ?? []
                    if archivedByUserIds.contains(userId) {
                        archivedIds.insert(doc.documentID)
                    }

                    var conversation = Conversation(
                        id: doc.documentID,
                        participants: participants,
                        lastMessage: lastMessage,
                        timestamp: timestamp,
                        readStatus: readStatus,
                        otherParticipantId: otherParticipantId,
                        otherParticipantUsername: otherParticipantUsername,
                        otherParticipantProfileImagePath: otherParticipantProfileImagePath,
                        isPinned: isPinned,
                        pinnedByUserIds: pinnedByUserIds,
                        pinnedBy: legacyPinnedBy,
                        isMuted: isMuted,
                        mutedByUserIds: mutedByUserIds,
                        mutedBy: legacyMutedBy,
                        archivedByUserIds: archivedByUserIds,
                        encryptionVersion: encryptionVersion,
                        conversationKeyVersion: data["conversationKeyVersion"] as? Int
                    )
                    if let readReceiptPreferences = data["readReceiptPreferences"] as? [String: Bool] {
                        conversation.readReceiptPreferences = readReceiptPreferences
                    }
                    if let forwardingPreferences = data["forwardingPreferences"] as? [String: Bool] {
                        conversation.forwardingPreferences = forwardingPreferences
                    }
                    if let buzzPreferences = data["buzzPreferences"] as? [String: Bool] {
                        conversation.buzzPreferences = buzzPreferences
                    }
                    // Hidratar lastDeletedAt desde Firestore
                    if let rawMap = data["lastDeletedAt"] as? [String: Timestamp] {
                        conversation.lastDeletedAt = rawMap.mapValues { $0.dateValue() }
                    }
                    if let rawMap = data["lastReadAt"] as? [String: Timestamp] {
                        conversation.lastReadAt = rawMap.mapValues { $0.dateValue() }
                    }
                    conversation.lastMessageSenderId = data["lastMessageSenderId"] as? String
                    if let rawType = data["lastMessageType"] as? String {
                        conversation.lastMessageType = MessageType(rawValue: rawType)
                    }
                    if let rawMap = data["lastMessageSeenAt"] as? [String: Timestamp], !rawMap.isEmpty {
                        conversation.lastMessageSeenAt = rawMap.mapValues { $0.dateValue() }
                    }
                    if let rawReaction = data["lastMessageReaction"] as? [String: String],
                       let messageId = rawReaction["messageId"],
                       let emoji = rawReaction["emoji"],
                       let byUserId = rawReaction["byUserId"] {
                        conversation.lastMessageReaction = ConversationLastMessageReaction(
                            messageId: messageId,
                            emoji: emoji,
                            byUserId: byUserId
                        )
                    }
                    conversation.vanishModeActive = data["vanishModeActive"] as? Bool ?? false
                    conversation.vanishModeEnabledBy = data["vanishModeEnabledBy"] as? String
                    if let enabledAt = data["vanishModeEnabledAt"] as? Timestamp {
                        conversation.vanishModeEnabledAt = enabledAt.dateValue()
                    }
                    conversation.vanishMessageTimer = data["vanishMessageTimer"] as? String
                        ?? VanishMessageTimer.default.rawValue
                    conversation.vanishSettingsNoticeMessageId = data["vanishSettingsNoticeMessageId"] as? String
                    conversation.vanishDisabledNoticeMessageId = data["vanishDisabledNoticeMessageId"] as? String
                    conversations.append(conversation)
                }

                // Actualizar mapa de cutoffs en memoria (para filtrar mensajes)
                for conversation in conversations {
                    guard let convId = conversation.id else { continue }
                    if let cutoff = conversation.deletedAtCutoff(for: userId) {
                        self.conversationCutoffs[convId] = cutoff
                    } else {
                        self.conversationCutoffs.removeValue(forKey: convId)
                    }
                }

                // Restaurar conversaciones auto-restauradas (sin batch para no acumular escrituras)
                for ref in toRestore {
                    ref.updateData([
                        "deletedFor": FieldValue.arrayRemove([userId])
                    ])
                }

                conversations.sort { $0.timestamp > $1.timestamp }
                self.archivedConversationIds = archivedIds

                Task { [weak self] in
                    guard let self else {
                        completion(.success(conversations))
                        return
                    }

                    let hydratedConversations = await self.hydrateConversationPreviews(conversations)
                    completion(.success(hydratedConversations))
                }
            }
        
        activeListeners[listenerKey] = listener
    }

    /// Escucha cambios en preferencias de privacidad del chat (reenvío, zumbidos…).
    func listenToConversationForwardingPreferences(
        conversationId: String,
        replaceExisting: Bool = true,
        onChange: @escaping (_ forwarding: [String: Bool], _ buzz: [String: Bool], _ vanishModeActive: Bool, _ vanishMessageTimer: VanishMessageTimer) -> Void
    ) {
        let listenerKey = "conversation_prefs_\(conversationId)"
        if !replaceExisting, activeListeners[listenerKey] != nil {
            return
        }
        let generation = beginListenerGeneration(for: listenerKey)
        activeListeners[listenerKey]?.remove()

        let listener = db.collection("conversations").document(conversationId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard self?.isCurrentListenerGeneration(generation, for: listenerKey) == true else { return }
                guard error == nil, let data = snapshot?.data() else { return }
                let forwarding = data["forwardingPreferences"] as? [String: Bool] ?? [:]
                let buzz = data["buzzPreferences"] as? [String: Bool] ?? [:]
                let vanishModeActive = data["vanishModeActive"] as? Bool ?? false
                let vanishMessageTimer = VanishMessageTimer(
                    storedValue: data["vanishMessageTimer"] as? String
                )
                onChange(forwarding, buzz, vanishModeActive, vanishMessageTimer)
            }

        activeListeners[listenerKey] = listener
    }

    // MARK: - Message Status
    func markMessagesAsRead(
        conversationId: String,
        messageIds: [String],
        readerId: String,
        marksLastMessageSeen: Bool = false,
        completion: @escaping (Error?) -> Void
    ) {
        guard !IncognitoModeService.isActiveSnapshot else {
            completion(nil)
            return
        }
        
        // ✅ Verificar configuración de privacidad antes de marcar como leído
        db.collection("users").document(readerId).getDocument { userSnapshot, userError in
            
            let userSettings = userSnapshot?.data()
            let globalEnabled = userSettings?["showReadReceipts"] as? Bool ?? true
            
            Firestore.firestore().collection("conversations").document(conversationId).getDocument { convSnapshot, convError in
                let convData = convSnapshot?.data()
                let preferences = convData?["readReceiptPreferences"] as? [String: Bool] ?? [:]
                
                // Prioridad 1: Ajuste específico del chat para este usuario
                let finalEnabled: Bool
                if let chatPreference = preferences[readerId] {
                    finalEnabled = chatPreference
                } else {
                    // Prioridad 2: Fallback al ajuste global
                    finalEnabled = globalEnabled
                }
                
                let batch = Firestore.firestore().batch()
                
                for messageId in messageIds {
                    let messageRef = Firestore.firestore().collection("conversations")
                        .document(conversationId)
                        .collection("messages")
                        .document(messageId)
                    
                    var messageUpdate: [String: Any] = [
                        "readBy": FieldValue.arrayUnion([readerId])
                    ]

                    if finalEnabled {
                        messageUpdate["isRead"] = true
                        messageUpdate["status"] = MessageStatus.read.rawValue
                    }

                    batch.updateData(messageUpdate, forDocument: messageRef)
                }
                
                let conversationRef = Firestore.firestore().collection("conversations").document(conversationId)
                var conversationUpdate: [String: Any] = [
                    "readStatus.\(readerId)": true,
                    "lastReadAt.\(readerId)": FieldValue.serverTimestamp()
                ]
                if marksLastMessageSeen, finalEnabled {
                    conversationUpdate["lastMessageSeenAt.\(readerId)"] = FieldValue.serverTimestamp()
                }
                batch.updateData(conversationUpdate, forDocument: conversationRef)

                batch.commit { error in
                    completion(error)
                }
            }
        }
    }

    func markConversationAsRead(conversationId: String, userId: String, completion: ((Error?) -> Void)? = nil) {
        db.collection("conversations")
            .document(conversationId)
            .updateData([
                "readStatus.\(userId)": true,
                "lastReadAt.\(userId)": FieldValue.serverTimestamp()
            ]) { error in
                completion?(error)
            }
    }
    
    // ✅ Función para marcar mensajes como entregados automáticamente
    func markMessagesAsDelivered(messages: [EnhancedMessage], conversationId: String, currentUserId: String) {
        let unreadMessages = messages.filter {
            $0.senderId != currentUserId &&
            $0.status == .sent &&
            !$0.isRead
        }
        
        for message in unreadMessages {
            updateMessageStatus(
                conversationId: conversationId,
                messageId: message.id,
                status: .delivered
            ) { _ in }
        }
    }
    
    func markAllPendingMessagesAsDelivered() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        // 1. Obtener todas las conversaciones del usuario
        db.collection("conversations")
            .whereField("participants", arrayContains: currentUserId)
            .getDocuments { [weak self] snapshot, error in
                guard let self = self, let documents = snapshot?.documents else { return }
                
                // 2. Para cada conversación, buscar mensajes con status "sent" del otro usuario
                for conversationDoc in documents {
                    let conversationId = conversationDoc.documentID
                    
                    Firestore.firestore().collection("conversations")
                        .document(conversationId)
                        .collection("messages")
                        .whereField("senderId", isNotEqualTo: currentUserId)
                        .whereField("status", isEqualTo: MessageStatus.sent.rawValue)
                        .getDocuments { [weak self] messagesSnapshot, messagesError in
                            guard let messages = messagesSnapshot?.documents else { return }
                            
                            // 3. Marcar cada mensaje como entregado
                            for messageDoc in messages {
                                Task { @MainActor in
                                    self?.updateMessageStatus(
                                        conversationId: conversationId,
                                        messageId: messageDoc.documentID,
                                        status: .delivered
                                    ) { _ in }
                                }
                            }
                        }
                }
            }
    }
    
    // ✅ Marcar un mensaje específico como entregado cuando llega la notificación push
    func markMessageAsDeliveredFromNotification(conversationId: String, messageId: String, completion: ((Bool) -> Void)? = nil) {
        guard let currentUserId = Auth.auth().currentUser?.uid else { 
            completion?(false)
            return 
        }
        
        // Verificar que el mensaje no sea nuestro antes de marcar como entregado
        db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document(messageId)
            .getDocument { [weak self] snapshot, error in
                guard let data = snapshot?.data(),
                      let senderId = data["senderId"] as? String,
                      senderId != currentUserId,
                      let status = data["status"] as? String,
                      status == MessageStatus.sent.rawValue
                else { 
                    completion?(false)
                    return 
                }
                
                Task { @MainActor in
                    self?.updateMessageStatus(
                        conversationId: conversationId,
                        messageId: messageId,
                        status: .delivered
                    ) { error in 
                        completion?(error == nil)
                    }
                }
            }
    }
    
    func updateMessageStatus(conversationId: String, messageId: String, status: MessageStatus, completion: @escaping (Error?) -> Void) {
        
        // ✅ Actualizar SOLO el status en Firestore (NO tocar timestamp para evitar reordenamiento)
        db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document(messageId)
            .updateData([
                "status": status.rawValue
            ]) { error in
                completion(error)
            }
    }
    
    // ✅ NUEVA: Función para actualizar estado local inmediatamente
    func updateLocalMessageStatus(conversationId: String, messageId: String, status: MessageStatus) {
        
        // Notificar a los listeners locales sobre el cambio de estado
        NotificationCenter.default.post(
            name: NSNotification.Name("MessageStatusUpdated"),
            object: nil,
            userInfo: [
                "conversationId": conversationId,
                "messageId": messageId,
                "status": status.rawValue
            ]
        )
    }
    
    // ✅ Función para crear conversación con datos bidireccionales
    // ✅ Función ACTUALIZADA para crear conversación con clave compartida
    func createBidirectionalConversation(user1Id: String, user2Id: String, initialMessage: String? = nil, completion: @escaping (Result<String, Error>) -> Void) {
        
        let participants = [user1Id, user2Id].sorted()
        let conversationRef = db.collection("conversations").document()
        let conversationId = conversationRef.documentID
        
        // ✅ Usar referencia fuerte para evitar liberación
        let userCache = UserCacheService.shared
        let group = DispatchGroup()
        var user1Data: AppUser?
        var user2Data: AppUser?
        var fetchError: Error?
        
        // Obtener usuario 1
        group.enter()
        userCache.getUser(userId: user1Id) { user in
            if let user = user {
                user1Data = user
            } else {
                fetchError = NSError(
                    domain: "ChatService",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: String(
                        format: NSLocalizedString("messaging.error.userDataFetch", comment: "Failed to load user data"),
                        user1Id
                    )]
                )
            }
            group.leave()
        }
        
        // Obtener usuario 2
        group.enter()
        userCache.getUser(userId: user2Id) { user in
            if let user = user {
                user2Data = user
            } else {
                fetchError = NSError(
                    domain: "ChatService",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: String(
                        format: NSLocalizedString("messaging.error.userDataFetch", comment: "Failed to load user data"),
                        user2Id
                    )]
                )
            }
            group.leave()
        }
        
        group.notify(queue: .main) {
            if let error = fetchError {
                completion(.failure(error))
                return
            }
            
            guard let user1 = user1Data, let user2 = user2Data else {
                let error = NSError(
                    domain: "ChatService",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("messaging.error.userDataIncomplete", comment: "Incomplete user data")]
                )
                completion(.failure(error))
                return
            }
            
            Task {
                do {
                    let sharedEncryptionKey = SymmetricKey(size: .bits256)
                    let keyData = sharedEncryptionKey.withUnsafeBytes { Data($0) }
                    let keyDataString = keyData.base64EncodedString()
                    let encryptionService = self.encryptionService
                    _ = try await encryptionService.ensureChatIdentity()

                    let participantData: [String: [String: Any]] = [
                        user1Id: [
                            "userId": user1.id,
                            "username": user1.username,
                            "profileImagePath": user1.profileImagePath ?? "",
                            "lastUpdated": FieldValue.serverTimestamp()
                        ],
                        user2Id: [
                            "userId": user2.id,
                            "username": user2.username,
                            "profileImagePath": user2.profileImagePath ?? "",
                            "lastUpdated": FieldValue.serverTimestamp()
                        ]
                    ]

                    let readStatus: [String: Bool] = [user1Id: true, user2Id: false]
                    var conversationData: [String: Any] = [
                        "participants": participants,
                        "lastMessage": "",
                        "timestamp": FieldValue.serverTimestamp(),
                        "readStatus": readStatus,
                        "participantData": participantData
                    ]

                    let wrappedKeys = try await encryptionService.buildWrappedConversationKeys(
                        for: participants,
                        conversationKey: sharedEncryptionKey,
                        wrappedBy: user1Id
                    )

                    if wrappedKeys.count == participants.count {
                        conversationData["wrappedKeys"] = wrappedKeys
                        conversationData["conversationKeyVersion"] = 1
                        conversationData["encryptionVersion"] = "3.0"
                    } else {
                        // Fallback temporal para usuarios que aun no han publicado chatKey.
                        conversationData["encryptionKey"] = keyDataString
                        conversationData["encryptionKeyCreatedAt"] = FieldValue.serverTimestamp()
                        conversationData["encryptionVersion"] = "1.0"
                    }

                    do {
                        try await conversationRef.setData(conversationData)
                        await encryptionService.cacheConversationKeyLocally(
                            conversationId: conversationId,
                            key: sharedEncryptionKey
                        )
                        if let customMessage = initialMessage, !customMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            self.sendInitialMessage(to: conversationId, from: user1Id, to: user2Id, message: customMessage) { _ in
                                completion(.success(conversationId))
                            }
                        } else {
                            self.sendInitialMessage(to: conversationId, from: user1Id, to: user2Id) { _ in
                                completion(.success(conversationId))
                            }
                        }
                    } catch {
                        completion(.failure(error))
                    }
                } catch {
                    completion(.failure(error))
                }
            }
        }
    }
    
    // ✅ NUEVA: Función para enviar mensaje inicial automático
    private func sendInitialMessage(to conversationId: String, from senderId: String, to receiverId: String, message: String? = nil, completion: @escaping (Result<Void, Error>) -> Void) {
        
        // 🔐 Encrypt initial message content
        Task {
            let initialMessage = message ?? "👋"
            let encryptedContent = await encryptMessageContent(initialMessage, for: conversationId)
            
            let messageId = UUID().uuidString
            let timestamp = Date()
            
            let messageData: [String: Any] = [
                "id": messageId,
                "conversationId": conversationId,
                "senderId": senderId,
                "receiverId": receiverId,
                "content": encryptedContent,
                "type": "text",
                "timestamp": timestamp,
                "isRead": false,
                "isDeleted": false
            ]
            
            // Enviar mensaje
            do {
                try await db.collection("conversations")
                    .document(conversationId)
                    .collection("messages")
                    .document(messageId)
                    .setData(messageData)
                try await self.db.collection("conversations")
                    .document(conversationId)
                    .updateData([
                        "lastMessage": self.neutralConversationPreview(for: .text),
                        "timestamp": timestamp
                    ])
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }
    }

    // ✅ Función para actualizar datos de usuario en todas sus conversaciones
    func updateUserDataInAllConversations(userId: String, newUserData: AppUser) {
        
        db.collection("conversations")
            .whereField("participants", arrayContains: userId)
            .getDocuments { snapshot, error in
                
                guard let documents = snapshot?.documents else { return }
                
                let batch = Firestore.firestore().batch()
                
                for doc in documents {
                    let conversationRef = doc.reference
                    batch.updateData([
                        "participantData.\(userId).username": newUserData.username,
                        "participantData.\(userId).profileImagePath": newUserData.profileImagePath ?? "",
                        "participantData.\(userId).lastUpdated": FieldValue.serverTimestamp()
                    ], forDocument: conversationRef)
                }
                
                batch.commit { _ in
                }
            }
    }
    
    // MARK: - Typing Indicators
    func startTyping(conversationId: String, userId: String) {
        let typingRef = db.collection("conversations")
            .document(conversationId)
            .collection("typing")
            .document(userId)
        
        typingRef.setData([
            "userId": userId,
            "timestamp": FieldValue.serverTimestamp()
        ])
        
        typingTimer?.invalidate()
        typingTimer = Timer.scheduledTimer(withTimeInterval: typingTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.stopTyping(conversationId: conversationId, userId: userId)
            }
        }
    }
    
    func stopTyping(conversationId: String, userId: String) {
        typingTimer?.invalidate()
        
        let typingRef = db.collection("conversations")
            .document(conversationId)
            .collection("typing")
            .document(userId)
        
        typingRef.delete { error in
        }
    }
    
    func listenToTypingIndicators(conversationId: String) {
        let typingKey = "typing_\(conversationId)"
        activeListeners[typingKey]?.remove()
        
        let listener = db.collection("conversations")
            .document(conversationId)
            .collection("typing")
            .addSnapshotListener { [weak self] snapshot, error in
                if error != nil {
                    return
                }
                
                guard let snapshot = snapshot else {
                    return
                }
                
                let typingUserIds = Set(snapshot.documents.map { $0.documentID })
                
                DispatchQueue.main.async {
                    self?.typingUsers[conversationId] = typingUserIds
                }
            }
        
        activeListeners[typingKey] = listener
    }
    
    // MARK: - Conversation Management
    func updateConversation(
        conversationId: String,
        lastMessage: String,
        senderId: String,
        messageType: MessageType? = nil,
        completion: @escaping (Error?) -> Void
    ) {
        db.collection("conversations").document(conversationId).getDocument { snapshot, error in
            if let error = error {
                completion(error)
                return
            }
            
            guard let doc = snapshot, doc.exists,
                  let participants = doc.data()?["participants"] as? [String] else {
                completion(
                    NSError(
                        domain: "",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("messaging.error.conversationNotFound", comment: "Conversation not found")]
                    )
                )
                return
            }
            
            // ✅ Verificar si la conversación está eliminada y restaurarla para quien corresponda.
            // Si el remitente envía un mensaje, la conversación debe reaparecer también para él.
            let deletedFor = doc.data()?["deletedFor"] as? [String] ?? []
            let shouldRestoreSender = deletedFor.contains(senderId)
            
            var updateData: [String: Any] = [
                "lastMessage": lastMessage,
                "timestamp": FieldValue.serverTimestamp(),
                "readStatus.\(senderId)": true,
                "lastMessageSenderId": senderId,
                "lastMessageSeenAt": FieldValue.delete(),
                "lastMessageReaction": FieldValue.delete()
            ]
            if let messageType {
                updateData["lastMessageType"] = messageType.rawValue
            }
            
            // ✅ Restaurar sólo al remitente para respetar las reglas de deletedFor por usuario.
            if shouldRestoreSender {
                updateData["deletedFor"] = FieldValue.arrayRemove([senderId])
            }
            
            Firestore.firestore().collection("conversations").document(conversationId).updateData(updateData) { error in
                completion(error)
            }
        }
    }

    func neutralConversationPreview(for type: MessageType) -> String {
        type.conversationPreview
    }

    private struct ConversationLatestSnapshot {
        let preview: String
        let timestamp: Date?
        let senderId: String?
        let messageType: MessageType?
        let viewOncePending: Bool
    }

    private func hydrateConversationPreviews(_ conversations: [Conversation]) async -> [Conversation] {
        guard !conversations.isEmpty else { return [] }
        var hydratedConversations: [Conversation] = []
        hydratedConversations.reserveCapacity(conversations.count)

        for conversation in conversations {
            let snapshot = await resolveLatestConversationSnapshot(for: conversation)
            let resolvedTimestamp = resolvedConversationTimestamp(
                conversation: conversation,
                latestMessageTimestamp: snapshot.timestamp
            )
            let resolvedSenderId = resolvedLastMessageSenderId(
                conversation: conversation,
                latestMessageTimestamp: snapshot.timestamp,
                latestMessageSenderId: snapshot.senderId
            )
            var hydrated = Conversation(
                id: conversation.id,
                participants: conversation.participants,
                lastMessage: snapshot.preview,
                timestamp: resolvedTimestamp,
                readStatus: conversation.readStatus,
                otherParticipantId: conversation.otherParticipantId,
                otherParticipantUsername: conversation.otherParticipantUsername,
                otherParticipantProfileImagePath: conversation.otherParticipantProfileImagePath,
                isPinned: conversation.isPinned,
                pinnedByUserIds: conversation.pinnedByUserIds,
                pinnedBy: conversation.pinnedBy,
                isMuted: conversation.isMuted,
                mutedByUserIds: conversation.mutedByUserIds,
                mutedBy: conversation.mutedBy,
                archivedByUserIds: conversation.archivedByUserIds,
                encryptionVersion: conversation.encryptionVersion,
                conversationKeyVersion: conversation.conversationKeyVersion,
                wrappedKeys: conversation.wrappedKeys
            )
            hydrated.readReceiptPreferences = conversation.readReceiptPreferences
            hydrated.buzzPreferences = conversation.buzzPreferences
            hydrated.forwardingPreferences = conversation.forwardingPreferences
            hydrated.lastDeletedAt = conversation.lastDeletedAt
            hydrated.lastReadAt = conversation.lastReadAt
            hydrated.lastMessageSenderId = resolvedSenderId
            hydrated.lastMessageSeenAt = conversation.lastMessageSeenAt
            hydrated.lastMessageReaction = conversation.lastMessageReaction
            hydrated.lastMessageType = snapshot.messageType ?? conversation.lastMessageType
            hydrated.lastMessageViewOncePending = snapshot.viewOncePending
            hydrated.vanishModeActive = conversation.vanishModeActive
            hydrated.vanishModeEnabledBy = conversation.vanishModeEnabledBy
            hydrated.vanishModeEnabledAt = conversation.vanishModeEnabledAt
            hydrated.vanishMessageTimer = conversation.vanishMessageTimer
            hydrated.vanishSettingsNoticeMessageId = conversation.vanishSettingsNoticeMessageId
            hydrated.vanishDisabledNoticeMessageId = conversation.vanishDisabledNoticeMessageId
            hydratedConversations.append(hydrated)
        }

        return hydratedConversations
    }

    private func resolvedConversationTimestamp(
        conversation: Conversation,
        latestMessageTimestamp: Date?
    ) -> Date {
        var best = conversation.timestamp
        if let latestMessageTimestamp, latestMessageTimestamp > best {
            best = latestMessageTimestamp
        }
        if let conversationId = conversation.id,
           let localTimestamp = LocalPersistenceService.shared.lastMessageTimestamp(for: conversationId),
           localTimestamp > best {
            best = localTimestamp
        }
        return best
    }

    private func resolvedLastMessageSenderId(
        conversation: Conversation,
        latestMessageTimestamp: Date?,
        latestMessageSenderId: String?
    ) -> String? {
        if let latestMessageTimestamp, latestMessageTimestamp > conversation.timestamp {
            return latestMessageSenderId ?? conversation.lastMessageSenderId
        }
        return conversation.lastMessageSenderId ?? latestMessageSenderId
    }

    private func viewOncePendingInSnapshot(
        messageType: MessageType,
        messageSenderId: String?,
        messageData: [String: Any]
    ) -> Bool {
        guard messageType.isViewOnce,
              let currentUserId = Auth.auth().currentUser?.uid,
              let senderId = messageSenderId,
              senderId != currentUserId else {
            return false
        }
        let viewedBy = messageData["viewedBy"] as? [String] ?? []
        return !viewedBy.contains(currentUserId)
    }

    private func fallbackViewOncePending(for conversation: Conversation) -> Bool {
        guard let type = conversation.lastMessageType,
              type.isViewOnce,
              let currentUserId = Auth.auth().currentUser?.uid else {
            return false
        }
        guard conversation.lastMessageSenderId != currentUserId else { return false }
        return !(conversation.readStatus[currentUserId] ?? true)
    }

    private func makeConversationSnapshot(
        preview: String,
        timestamp: Date?,
        senderId: String?,
        messageType: MessageType?,
        messageData: [String: Any]? = nil,
        fallbackConversation: Conversation? = nil
    ) -> ConversationLatestSnapshot {
        let pending: Bool = {
            if let messageType, let messageData {
                return viewOncePendingInSnapshot(
                    messageType: messageType,
                    messageSenderId: senderId,
                    messageData: messageData
                )
            }
            if let fallbackConversation {
                return fallbackViewOncePending(for: fallbackConversation)
            }
            return false
        }()

        return ConversationLatestSnapshot(
            preview: preview,
            timestamp: timestamp,
            senderId: senderId,
            messageType: messageType,
            viewOncePending: pending
        )
    }

    private func resolveLatestConversationSnapshot(for conversation: Conversation) async -> ConversationLatestSnapshot {
        guard let conversationId = conversation.id else {
            return makeConversationSnapshot(
                preview: conversation.lastMessage ?? "",
                timestamp: nil,
                senderId: nil,
                messageType: conversation.lastMessageType,
                fallbackConversation: conversation
            )
        }

        let previewEnabled = ChatPreviewPrivacy.isUserPreviewEnabled(for: conversationId)
        guard previewEnabled else {
            return makeConversationSnapshot(
                preview: conversation.lastMessage ?? "",
                timestamp: nil,
                senderId: nil,
                messageType: conversation.lastMessageType,
                fallbackConversation: conversation
            )
        }

        do {
            let snapshot = try await db.collection("conversations")
                .document(conversationId)
                .collection("messages")
                .order(by: "timestamp", descending: true)
                .limit(to: 5)
                .getDocuments()

            for document in snapshot.documents {
                let data = document.data()

                if data["isDeleted"] as? Bool == true {
                    continue
                }

                guard
                    let rawType = data["type"] as? String,
                    let messageType = MessageType(rawValue: rawType)
                else {
                    continue
                }

                let messageTimestamp = (data["timestamp"] as? Timestamp)?.dateValue()
                let messageSenderId = data["senderId"] as? String
                let isVanishMessage = ChatPreviewPrivacy.isVanishModeMessage(in: data)
                if !ChatPreviewPrivacy.shouldRevealPreview(
                    for: conversationId,
                    isVanishModeMessage: isVanishMessage
                ) {
                    return makeConversationSnapshot(
                        preview: neutralConversationPreview(for: messageType),
                        timestamp: messageTimestamp,
                        senderId: messageSenderId,
                        messageType: messageType,
                        messageData: data
                    )
                }

                if messageType == .text {
                    guard let encryptedContent = data["content"] as? String, !encryptedContent.isEmpty else {
                        continue
                    }

                    let decryptedContent = await decryptMessageContent(encryptedContent, for: conversationId)
                    let trimmedContent = decryptedContent.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmedContent.isEmpty {
                        return makeConversationSnapshot(
                            preview: trimmedContent,
                            timestamp: messageTimestamp,
                            senderId: messageSenderId,
                            messageType: messageType,
                            messageData: data
                        )
                    }
                    continue
                }

                if messageType == .chatNotice {
                    let noticeText = EnhancedMessage.chatNoticePreviewText(for: data["content"] as? String ?? "")
                    if !noticeText.isEmpty {
                        return makeConversationSnapshot(
                            preview: noticeText,
                            timestamp: messageTimestamp,
                            senderId: messageSenderId,
                            messageType: messageType,
                            messageData: data
                        )
                    }
                    continue
                }

                return makeConversationSnapshot(
                    preview: neutralConversationPreview(for: messageType),
                    timestamp: messageTimestamp,
                    senderId: messageSenderId,
                    messageType: messageType,
                    messageData: data
                )
            }
        } catch {
            return makeConversationSnapshot(
                preview: conversation.lastMessage ?? "",
                timestamp: nil,
                senderId: nil,
                messageType: conversation.lastMessageType,
                fallbackConversation: conversation
            )
        }

        return makeConversationSnapshot(
            preview: conversation.lastMessage ?? "",
            timestamp: nil,
            senderId: nil,
            messageType: conversation.lastMessageType,
            fallbackConversation: conversation
        )
    }

    private func resolveLatestConversationPreview(for conversation: Conversation) async -> String {
        await resolveLatestConversationSnapshot(for: conversation).preview
    }
    
    func ensureEncryptionService() -> EncryptionService {
        return EncryptionService.shared
    }
    
    func preloadConversationKey(for conversationId: String) async {
        await encryptionService.preloadConversationKeys(for: [conversationId])
    }
    
    func decryptMessageContent(_ content: String, for conversationId: String) async -> String {
        return await encryptionService.decryptChatMessage(content, for: conversationId) ?? content
    }
    
    func encryptMessageContent(_ content: String, for conversationId: String) async -> String {
        return await encryptionService.encryptChatMessage(content, for: conversationId) ?? content
    }
    
}
