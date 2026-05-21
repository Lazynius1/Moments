import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseStorage
import Combine
import CryptoKit
import AVFoundation
import UIKit

class ChatService: ObservableObject {
    // MARK: - Properties
    private let db = Firestore.firestore()
    private let storage = Storage.storage()
    private let firestoreservice = FirestoreService()
    private let encryptionService = EncryptionService.shared // 🔐 Encryption service
    
    @Published var activeListeners: [String: ListenerRegistration] = [:]
    @Published var typingUsers: [String: Set<String>] = [:] // conversationId: Set<userId>
    
    private var typingTimer: Timer?
    private let typingTimeout: TimeInterval = 3.0
    
    // MARK: - Initialization
    static let shared = ChatService() // ✅ Singleton para acceso global
    
    init() {
    }
    
    deinit {
        removeAllListeners()
    }
    
    // MARK: - Listeners Management
    func removeAllListeners() {
        activeListeners.values.forEach { $0.remove() }
        activeListeners.removeAll()
    }
    
    func removeListener(for conversationId: String) {
        activeListeners[conversationId]?.remove()
        activeListeners.removeValue(forKey: conversationId)
        
        let typingKey = "typing_\(conversationId)"
        activeListeners[typingKey]?.remove()
        activeListeners.removeValue(forKey: typingKey)
        typingUsers.removeValue(forKey: conversationId)
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
    func listenToMessages(conversationId: String, limit: Int = 50, completion: @escaping (Result<[EnhancedMessage], Error>) -> Void) {
        Task {
            await preloadConversationKey(for: conversationId)
        }
        
        activeListeners[conversationId]?.remove()
        
        let listener = db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .order(by: "timestamp", descending: false)
            .limit(toLast: limit) // ✅ LIMITAR a los últimos mensajes
            .addSnapshotListener { [weak self] snapshot, error in
                // ✅ Envolver todo en Task para poder usar await
                Task {
                    await self?.handleMessagesSnapshot(
                        snapshot: snapshot,
                        error: error,
                        conversationId: conversationId,
                        completion: completion
                    )
                }
            }
        
        activeListeners[conversationId] = listener
    }
    
    // ✅ ONE-SHOT FETCH: útil para pantallas de stats donde no necesitamos listener vivo
    func fetchRecentMessages(conversationId: String, limit: Int = 300, completion: @escaping (Result<[EnhancedMessage], Error>) -> Void) {
        Task {
            await preloadConversationKey(for: conversationId)
            
            db.collection("conversations")
                .document(conversationId)
                .collection("messages")
                .order(by: "timestamp", descending: false)
                .limit(toLast: limit)
                .getDocuments { [weak self] snapshot, error in
                    Task {
                        await self?.handleMessagesSnapshot(
                            snapshot: snapshot,
                            error: error,
                            conversationId: conversationId,
                            completion: completion
                        )
                    }
                }
        }
    }
    
    // ✅ NUEVO: Cargar mensajes anteriores (Paginación)
    func fetchOlderMessages(conversationId: String, before timestamp: Date, limit: Int = 20, completion: @escaping (Result<[EnhancedMessage], Error>) -> Void) {
        Task {
            // Asegurar que tenemos la clave
             await preloadConversationKey(for: conversationId)
            
            db.collection("conversations")
                .document(conversationId)
                .collection("messages")
                .whereField("timestamp", isLessThan: Timestamp(date: timestamp))
                .order(by: "timestamp", descending: true) // Descendente para obtener los más cercanos a la fecha
                .limit(to: limit)
                .getDocuments { [weak self] snapshot, error in
                    Task {
                        await self?.handleMessagesSnapshot(
                            snapshot: snapshot,
                            error: error,
                            conversationId: conversationId,
                            completion: completion
                        )
                    }
                }
        }
    }

    // ✅ Nueva función helper para manejar el snapshot de manera async
    private func handleMessagesSnapshot(
        snapshot: QuerySnapshot?,
        error: Error?,
        conversationId: String,
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
        
        var messages: [EnhancedMessage] = []
        
        for doc in documents {
            let data = doc.data()
            
            // ✅ Filtrar mensajes eliminados para el usuario actual (estilo nativo)
            if let deletedFor = data["deletedFor"] as? [String],
               let currentUserId = Auth.auth().currentUser?.uid,
               deletedFor.contains(currentUserId) {
                continue
            }
            
            // Manual decoding with decryption
            let id = data["id"] as? String ?? doc.documentID
            let senderId = data["senderId"] as? String ?? ""
            let typeString = data["type"] as? String ?? MessageType.text.rawValue
            let type = MessageType(rawValue: typeString) ?? .text
            
            // 🔐 Decrypt content if it's text - AHORA FUNCIONA CON AWAIT
            let rawContent = data["content"] as? String
            let content: String?
            if let rawContent = rawContent, type == .text {
                // ✅ Ahora podemos usar await directamente
                content = await self.decryptMessageContent(rawContent, for: conversationId)
            } else {
                content = rawContent
            }
            
            let mediaUrl = data["mediaUrl"] as? String
            let thumbnailUrl = data["thumbnailUrl"] as? String
            let duration = data["duration"] as? Double
            let fileName = data["fileName"] as? String
            let fileSize = data["fileSize"] as? Int64
            let latitude = data["latitude"] as? Double
            let longitude = data["longitude"] as? Double
            let timestamp = (data["timestamp"] as? Timestamp)?.dateValue() ?? Date()
            let statusString = data["status"] as? String ?? MessageStatus.sent.rawValue
            let status = MessageStatus(rawValue: statusString) ?? .sent
            let isRead = data["isRead"] as? Bool ?? false
            let isDeleted = data["isDeleted"] as? Bool ?? false
            let deletedAt = (data["deletedAt"] as? Timestamp)?.dateValue()
            let editedAt = (data["editedAt"] as? Timestamp)?.dateValue()
            let reactions = data["reactions"] as? [String: [String]]
            let replyTo = data["replyTo"] as? String
            let expirationDate = (data["expirationDate"] as? Timestamp)?.dateValue()
            let isViewed = data["isViewed"] as? Bool ?? false
            let storyReplyData = data["storyReplyData"] as? [String: String]
            let sharedMomentData = data["sharedMomentData"] as? [String: String]
            let mediaBatchId = data["mediaBatchId"] as? String
            
            // ✅ DEBUG: Log status updates
            if status == .sending || status == .sent {
            }
            
            let message = EnhancedMessage(
                id: id,
                conversationId: conversationId,
                senderId: senderId,
                type: type,
                content: content, // ✅ Ahora está correctamente desencriptado
                mediaUrl: mediaUrl,
                thumbnailUrl: thumbnailUrl,
                duration: duration,
                fileName: fileName,
                fileSize: fileSize,
                latitude: latitude,
                longitude: longitude,
                timestamp: timestamp,
                status: status,
                isRead: isRead,
                isDeleted: isDeleted,
                deletedAt: deletedAt,
                editedAt: editedAt,
                reactions: reactions,
                replyTo: replyTo,
                expirationDate: expirationDate,
                isViewed: isViewed,
                storyReplyData: storyReplyData,
                sharedMomentData: sharedMomentData,
                mediaBatchId: mediaBatchId
            )
            
            messages.append(message)
        }
        
        
        // ✅ Marcar mensajes como entregados automáticamente
        if let currentUserId = Auth.auth().currentUser?.uid {
            markMessagesAsDelivered(messages: messages, conversationId: conversationId, currentUserId: currentUserId)
        }
        
        // ✅ Llamar completion en el Main Actor para actualizaciones de UI
        await MainActor.run {
            completion(.success(messages))
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
    
    func sendTextMessage(conversationId: String, senderId: String, content: String, replyTo: String? = nil, messageId: String? = nil, completion: @escaping (Result<EnhancedMessage, Error>) -> Void) {
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
                isViewed: false
            )
            
            sendMessage(message, useServerTimestamp: true, completion: completion)
        }
    }
    
    func sendEphemeralMessage(conversationId: String, senderId: String, content: String? = nil, mediaUrl: String? = nil, expirationHours: Int = 24, storyReplyData: [String: String]? = nil, completion: @escaping (Result<EnhancedMessage, Error>) -> Void) {
        let messageId = UUID().uuidString
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
                expirationDate: expirationDate,
                isViewed: false,
                storyReplyData: storyReplyData
            )
            
            sendMessage(message, useServerTimestamp: true, completion: completion)
        }
    }
    
    func sendMediaMessage(conversationId: String, senderId: String, type: MessageType, mediaData: Data, fileName: String? = nil, messageId: String? = nil, mediaBatchId: String? = nil, completion: @escaping (Result<EnhancedMessage, Error>) -> Void) {
        let finalMessageId = messageId ?? UUID().uuidString
        uploadMedia(data: mediaData, type: type, conversationId: conversationId, messageId: finalMessageId) { [weak self] result in
            switch result {
            case .success(let (mediaUrl, thumbnailUrl)):
                let finalMessageId = messageId ?? UUID().uuidString
                let message = EnhancedMessage(
                    id: finalMessageId,
                    conversationId: conversationId,
                    senderId: senderId,
                    type: type,
                    content: nil, // No text content to encrypt
                    mediaUrl: mediaUrl, // Media URLs are not encrypted
                    thumbnailUrl: thumbnailUrl,
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
                    mediaBatchId: mediaBatchId
                )
                
                self?.sendMessage(message, useServerTimestamp: true, completion: completion)
                
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    func sendLocationMessage(conversationId: String, senderId: String, latitude: Double, longitude: Double, messageId: String? = nil, completion: @escaping (Result<EnhancedMessage, Error>) -> Void) {
        let finalMessageId = messageId ?? UUID().uuidString
        let message = EnhancedMessage(
            id: finalMessageId,
            conversationId: conversationId,
            senderId: senderId,
            type: .location,
            content: nil, // No text content to encrypt
            mediaUrl: nil,
            thumbnailUrl: nil,
            duration: nil,
            fileName: nil,
            fileSize: nil,
            latitude: latitude, // Coordinates are not encrypted
            longitude: longitude,
            timestamp: Date(),
            status: .sending,
            isRead: false,
            isDeleted: false,
            deletedAt: nil,
            editedAt: nil,
            reactions: nil,
            replyTo: nil,
            expirationDate: nil,
            isViewed: false
        )
        
        sendMessage(message, useServerTimestamp: true, completion: completion)
    }
    
    func sendAudioMessage(conversationId: String, senderId: String, audioData: Data, duration: Double, messageId: String? = nil, completion: @escaping (Result<EnhancedMessage, Error>) -> Void) {
        let finalMessageId = messageId ?? UUID().uuidString
        uploadMedia(data: audioData, type: .audio, conversationId: conversationId, messageId: finalMessageId) { [weak self] result in
            switch result {
            case .success(let (mediaUrl, _)):
                let finalMessageId = messageId ?? UUID().uuidString
                let message = EnhancedMessage(
                    id: finalMessageId,
                    conversationId: conversationId,
                    senderId: senderId,
                    type: .audio,
                    content: nil, // No text content to encrypt
                    mediaUrl: mediaUrl, // Audio URLs are not encrypted
                    thumbnailUrl: nil,
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
                    isViewed: false
                )
                
                self?.sendMessage(message, useServerTimestamp: true, completion: completion)
                
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Core Send Message Method
    func sendMessage(_ message: EnhancedMessage, useServerTimestamp: Bool, completion: @escaping (Result<EnhancedMessage, Error>) -> Void) {
        // ✅ OFFLINE SUPPORT: Si no hay conexión, persistir acción y retornar éxito optimista
        if !NetworkMonitor.shared.isConnected {
            var pendingMessage = message
            pendingMessage.status = .pending
            
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
                    await LocalPersistenceService.shared.saveAction(action)
                    print("💾 ChatService: Mensaje guardado en outbox (offline)")
                    completion(.success(pendingMessage)) // Éxito optimista
                }
                return
            }
        }
        
        do {
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
                messageData["content"] = content // Already encrypted for text messages
            }
            if let mediaUrl = message.mediaUrl {
                messageData["mediaUrl"] = mediaUrl // Media URLs are not encrypted
            }
            if let thumbnailUrl = message.thumbnailUrl {
                messageData["thumbnailUrl"] = thumbnailUrl
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
            if let latitude = message.latitude {
                messageData["latitude"] = latitude // Coordinates are not encrypted
            }
            if let longitude = message.longitude {
                messageData["longitude"] = longitude
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
            if let mediaBatchId = message.mediaBatchId {
                messageData["mediaBatchId"] = mediaBatchId
            }
            
            // Set timestamp
            if useServerTimestamp {
                messageData["timestamp"] = FieldValue.serverTimestamp()
            } else {
                messageData["timestamp"] = Timestamp(date: message.timestamp)
            }
            
            
            // Write to Firestore
            messageRef.setData(messageData) { [weak self] error in
                if let error = error {
                    // Update status to failed if there's an error
                    self?.updateLocalMessageStatus(
                        conversationId: message.conversationId,
                        messageId: message.id,
                        status: .failed
                    )
                    self?.updateMessageStatus(
                        conversationId: message.conversationId,
                        messageId: message.id,
                        status: .failed
                    ) { _ in }
                    completion(.failure(error))
                    return
                }
                
                // ✅ Update conversation with last message (decrypt for preview)
                Task {
                    self?.updateConversation(
                        conversationId: message.conversationId,
                        lastMessage: self?.neutralConversationPreview(for: message.type) ?? MessageType.text.conversationPreview,
                        senderId: message.senderId
                    ) { updateError in
                        if let updateError = updateError {
                            // Silently handle error
                        }
                    }
                }
                
                // ✅ Marcar como enviado inmediatamente
                self?.updateMessageStatus(
                    conversationId: message.conversationId,
                    messageId: message.id,
                    status: .sent
                ) { _ in }
                
                // ✅ Llamar completion con éxito INMEDIATAMENTE
                var updatedMessage = message
                updatedMessage.status = .sent
                completion(.success(updatedMessage))
            }
        } catch {
            completion(.failure(error))
        }
    }
    
    // MARK: - Message Actions with Encryption
    func editMessage(conversationId: String, messageId: String, newContent: String, completion: @escaping (Error?) -> Void) {
        
        // 🔐 Encrypt new content before updating (Async)
        Task {
            let encryptedContent = await encryptMessageContent(newContent, for: conversationId)
            
            db.collection("conversations")
                .document(conversationId)
                .collection("messages")
                .document(messageId)
                .updateData([
                    "content": encryptedContent, // Store encrypted content
                    "editedAt": FieldValue.serverTimestamp()
                ]) { error in
                    if let error = error {
                    }
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
                "content": nil,
                "mediaUrl": nil
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
                
                if let error = error {
                    completion(error)
                    return
                }
                
                guard let document = snapshot, document.exists else {
                    completion(NSError(domain: "ChatService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Mensaje no encontrado"]))
                    return
                }
                
                let data = document.data() ?? [:]
                let mediaUrl = data["mediaUrl"] as? String
                
                // Mark message as deleted first
                self?.db.collection("conversations")
                    .document(conversationId)
                    .collection("messages")
                    .document(messageId)
                    .updateData([
                        "isDeleted": true,
                        "deletedAt": FieldValue.serverTimestamp(),
                        "content": nil, // Remove encrypted content
                        "mediaUrl": nil
                    ]) { updateError in
                        
                        if let updateError = updateError {
                            completion(updateError)
                            return
                        }
                        
                        
                        // Delete media file if exists
                        if let mediaUrl = mediaUrl, !mediaUrl.isEmpty {
                            
                            self?.deleteMediaFile(url: mediaUrl) { result in
                                switch result {
                                case .success(_):
                                    break
                                case .failure(_):
                                    break
                                }
                                completion(nil)
                            }
                        } else {
                            completion(nil)
                        }
                    }
            }
    }

    func deleteMediaFile(url: String, completion: @escaping (Result<Void, Error>) -> Void) {
        
        guard !url.isEmpty else {
            completion(.failure(NSError(domain: "ChatService", code: -1, userInfo: [NSLocalizedDescriptionKey: "URL inválida"])))
            return
        }
        
        let storageRef = Storage.storage().reference(forURL: url)
        
        storageRef.delete { error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }
    
    func addReaction(conversationId: String, messageId: String, emoji: String, userId: String, completion: @escaping (Error?) -> Void) {
        // ✅ Optimistic UI: Actualizar caché local en background (no bloquea el return)
        Task(priority: .background) { @MainActor in
            LocalPersistenceService.shared.toggleMessageReactionLocally(messageId: messageId, emoji: emoji, userId: userId)
        }
        
        let messageRef = db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document(messageId)
        
        db.runTransaction({ (transaction, errorPointer) -> Any? in
            let messageDocument: DocumentSnapshot
            do {
                try messageDocument = transaction.getDocument(messageRef)
            } catch let fetchError as NSError {
                errorPointer?.pointee = fetchError
                return nil
            }
            
            guard var reactions = messageDocument.data()?["reactions"] as? [String: [String]] else {
                transaction.updateData(["reactions": [emoji: [userId]]], forDocument: messageRef)
                return nil
            }
            
            if var userIds = reactions[emoji] {
                if userIds.contains(userId) {
                    userIds.removeAll { $0 == userId }
                    if userIds.isEmpty {
                        reactions.removeValue(forKey: emoji)
                    } else {
                        reactions[emoji] = userIds
                    }
                } else {
                    userIds.append(userId)
                    reactions[emoji] = userIds
                }
            } else {
                reactions[emoji] = [userId]
            }
            
            transaction.updateData(["reactions": reactions], forDocument: messageRef)
            return nil
        }) { (_, error) in
            if let error = error {
            }
            completion(error)
        }
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

                let batch = self.db.batch()
                for doc in conversationsToMarkAsDeleted {
                    // En lugar de eliminar, marcar como eliminada para este usuario
                    batch.updateData([
                        "deletedFor": FieldValue.arrayUnion([user1Id]),
                        "deletedAt": FieldValue.serverTimestamp()
                    ], forDocument: doc.reference)
                }

                batch.commit { error in
                    if let error = error {
                        completion(error)
                    } else {
                        // ✅ Esperar a que el borrado "for user" de mensajes termine para evitar reaperturas con historial viejo.
                        guard !conversationsToMarkAsDeleted.isEmpty else {
                            completion(nil)
                            return
                        }

                        let group = DispatchGroup()
                        var firstError: Error?

                        for doc in conversationsToMarkAsDeleted {
                            group.enter()
                            self.markAllMessagesAsDeletedForUser(conversationId: doc.documentID, userId: user1Id) { messageError in
                                if firstError == nil, let messageError {
                                    firstError = messageError
                                }
                                group.leave()
                            }
                        }

                        group.notify(queue: .main) {
                            completion(firstError)
                        }
                    }
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

                let batch = self.db.batch()
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
            .addSnapshotListener { snapshot, error in
                
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
                
                for doc in documents {
                    let data = doc.data()
                    
                    // ✅ Filtrar conversaciones eliminadas para este usuario (estilo nativo)
                    if let deletedFor = data["deletedFor"] as? [String], deletedFor.contains(userId) {
                        continue
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
                    
                    let conversation = Conversation(
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
                        encryptionVersion: encryptionVersion,
                        conversationKeyVersion: data["conversationKeyVersion"] as? Int
                    )
                    
                    conversations.append(conversation)
                }
                
                conversations.sort { $0.timestamp > $1.timestamp }

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
    // MARK: - Media Upload
    func uploadMedia(data: Data, type: MessageType, conversationId: String, messageId: String? = nil, completion: @escaping (Result<(mediaUrl: String, thumbnailUrl: String?), Error>) -> Void) {
        let ext = getFileExtension(for: type)
        let fileName = "\(UUID().uuidString).\(ext)"
        print("📤 ChatService: uploadMedia for type \(type) - Generated extension: \(ext)")
        let storageRef = storage.reference().child("conversations/\(conversationId)/\(fileName)")
        
        let metadata = StorageMetadata()
        metadata.contentType = getContentType(for: type)

        let uploadTask = storageRef.putData(data, metadata: metadata)
        
        // ✅ Track progress if messageId is provided
        if let msgId = messageId {
            uploadTask.observe(.progress) { snapshot in
                let percentComplete = Double(snapshot.progress?.completedUnitCount ?? 0) / Double(snapshot.progress?.totalUnitCount ?? 1)
                
                NotificationCenter.default.post(
                    name: NSNotification.Name("MediaUploadProgress"),
                    object: nil,
                    userInfo: ["messageId": msgId, "progress": percentComplete]
                )
            }
        }

        uploadTask.observe(.success) { _ in
            storageRef.downloadURL { url, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                guard let mediaUrl = url?.absoluteString else {
                    completion(
                        .failure(
                            NSError(
                                domain: "",
                                code: -1,
                                userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("messaging.error.fileUrlUnavailable", comment: "Unable to get media file URL")]
                            )
                        )
                    )
                    return
                }
                
                if type == .video {
                    self.generateVideoThumbnail(from: data, conversationId: conversationId) { thumbnailUrl in
                        completion(.success((mediaUrl: mediaUrl, thumbnailUrl: thumbnailUrl)))
                    }
                } else {
                    completion(.success((mediaUrl: mediaUrl, thumbnailUrl: nil)))
                }
            }
        }
        
        uploadTask.observe(.failure) { snapshot in
            if let error = snapshot.error {
                completion(.failure(error))
            }
        }
    }
    
    private func generateVideoThumbnail(from videoData: Data, conversationId: String, completion: @escaping (String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let tempVideoURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("chat_video_thumb_\(UUID().uuidString).mp4")
            
            do {
                try videoData.write(to: tempVideoURL, options: .atomic)
            } catch {
                completion(nil)
                return
            }
            
            defer {
                try? FileManager.default.removeItem(at: tempVideoURL)
            }
            
            let asset = AVURLAsset(url: tempVideoURL)
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true
            imageGenerator.maximumSize = CGSize(width: 720, height: 1280)
            
            let frameCandidates = [
                CMTime(seconds: 0.15, preferredTimescale: 600),
                CMTime(seconds: 0.0, preferredTimescale: 600),
                CMTime(seconds: 0.5, preferredTimescale: 600)
            ]
            
            var cgImage: CGImage?
            for time in frameCandidates {
                if let candidate = try? imageGenerator.copyCGImage(at: time, actualTime: nil) {
                    cgImage = candidate
                    break
                }
            }
            
            guard let cgImage,
                  let thumbnailData = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.78) else {
                completion(nil)
                return
            }
            
            let thumbnailPath = "conversations/\(conversationId)/thumbnails/\(UUID().uuidString).jpg"
            let thumbnailRef = self.storage.reference().child(thumbnailPath)
            let metadata = StorageMetadata()
            metadata.contentType = "image/jpeg"
            
            thumbnailRef.putData(thumbnailData, metadata: metadata) { _, error in
                if error != nil {
                    completion(nil)
                    return
                }
                
                thumbnailRef.downloadURL { url, _ in
                    completion(url?.absoluteString)
                }
            }
        }
    }
    
    // MARK: - Message Status
    func markMessagesAsRead(conversationId: String, messageIds: [String], readerId: String, completion: @escaping (Error?) -> Void) {
        
        // ✅ Verificar configuración de privacidad antes de marcar como leído
        db.collection("users").document(readerId).getDocument { [weak self] userSnapshot, userError in
            guard let self = self else { return }
            
            let userSettings = userSnapshot?.data()
            let globalEnabled = userSettings?["showReadReceipts"] as? Bool ?? true
            
            self.db.collection("conversations").document(conversationId).getDocument { convSnapshot, convError in
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
                
                let batch = self.db.batch()
                
                for messageId in messageIds {
                    let messageRef = self.db.collection("conversations")
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
                
                let conversationRef = self.db.collection("conversations").document(conversationId)
                batch.updateData([
                    "readStatus.\(readerId)": true,
                    "lastReadAt.\(readerId)": FieldValue.serverTimestamp()
                ], forDocument: conversationRef)
                
                batch.commit { error in
                    completion(error)
                }
            }
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
    
    // ✅ Marcar todos los mensajes pendientes como entregados (estilo WhatsApp)
    // Se llama cuando la app se abre/vuelve a primer plano
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
                    
                    self.db.collection("conversations")
                        .document(conversationId)
                        .collection("messages")
                        .whereField("senderId", isNotEqualTo: currentUserId)
                        .whereField("status", isEqualTo: MessageStatus.sent.rawValue)
                        .getDocuments { [weak self] messagesSnapshot, messagesError in
                            guard let messages = messagesSnapshot?.documents else { return }
                            
                            // 3. Marcar cada mensaje como entregado
                            for messageDoc in messages {
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
                
                self?.updateMessageStatus(
                    conversationId: conversationId,
                    messageId: messageId,
                    status: .delivered
                ) { error in 
                    completion?(error == nil)
                }
            }
    }
    
    private func updateMessageStatus(conversationId: String, messageId: String, status: MessageStatus, completion: @escaping (Error?) -> Void) {
        
        // ✅ Actualizar SOLO el status en Firestore (NO tocar timestamp para evitar reordenamiento)
        db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document(messageId)
            .updateData([
                "status": status.rawValue
            ]) { error in
                if let error = error {
                } else {
                }
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

                    conversationRef.setData(conversationData) { error in
                        if let error = error {
                            completion(.failure(error))
                        } else {
                            Task {
                                await encryptionService.cacheConversationKeyLocally(
                                    conversationId: conversationId,
                                    key: sharedEncryptionKey
                                )
                            }

                            if let customMessage = initialMessage, !customMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                self.sendInitialMessage(to: conversationId, from: user1Id, to: user2Id, message: customMessage) { _ in
                                    completion(.success(conversationId))
                                }
                            } else {
                                self.sendInitialMessage(to: conversationId, from: user1Id, to: user2Id) { _ in
                                    completion(.success(conversationId))
                                }
                            }
                        }
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
            db.collection("conversations")
                .document(conversationId)
                .collection("messages")
                .document(messageId)
                .setData(messageData) { error in
                    if let error = error {
                        completion(.failure(error))
                    } else {
                        
                        // Actualizar lastMessage en la conversación
                        self.db.collection("conversations")
                            .document(conversationId)
                            .updateData([
                                "lastMessage": self.neutralConversationPreview(for: .text),
                                "timestamp": timestamp
                            ]) { updateError in
                                if let updateError = updateError {
                                } else {
                                }
                                completion(.success(()))
                            }
                    }
                }
        }
    }

    // ✅ Función para actualizar datos de usuario en todas sus conversaciones
    func updateUserDataInAllConversations(userId: String, newUserData: AppUser) {
        
        db.collection("conversations")
            .whereField("participants", arrayContains: userId)
            .getDocuments { [weak self] snapshot, error in
                
                guard let documents = snapshot?.documents else { return }
                
                let batch = self?.db.batch()
                
                for doc in documents {
                    let conversationRef = doc.reference
                    batch?.updateData([
                        "participantData.\(userId).username": newUserData.username,
                        "participantData.\(userId).profileImagePath": newUserData.profileImagePath ?? "",
                        "participantData.\(userId).lastUpdated": FieldValue.serverTimestamp()
                    ], forDocument: conversationRef)
                }
                
                batch?.commit { error in
                    if let error = error {
                    } else {
                    }
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
            self?.stopTyping(conversationId: conversationId, userId: userId)
        }
    }
    
    func stopTyping(conversationId: String, userId: String) {
        typingTimer?.invalidate()
        
        let typingRef = db.collection("conversations")
            .document(conversationId)
            .collection("typing")
            .document(userId)
        
        typingRef.delete { error in
            if let error = error {
            }
        }
    }
    
    func listenToTypingIndicators(conversationId: String) {
        let typingKey = "typing_\(conversationId)"
        activeListeners[typingKey]?.remove()
        
        let listener = db.collection("conversations")
            .document(conversationId)
            .collection("typing")
            .addSnapshotListener { [weak self] snapshot, error in
                if let error = error {
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
    private func updateConversation(conversationId: String, lastMessage: String, senderId: String, completion: @escaping (Error?) -> Void) {
        db.collection("conversations").document(conversationId).getDocument { [weak self] snapshot, error in
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
            
            var readStatus: [String: Bool] = [:]
            participants.forEach { participant in
                readStatus[participant] = (participant == senderId)
            }
            
            // ✅ Verificar si la conversación está eliminada y restaurarla para quien corresponda.
            // Si el remitente envía un mensaje, la conversación debe reaparecer también para él.
            let deletedFor = doc.data()?["deletedFor"] as? [String] ?? []
            let participantsToRestore = deletedFor
            
            var updateData: [String: Any] = [
                "lastMessage": lastMessage,
                "timestamp": FieldValue.serverTimestamp(),
                "readStatus": readStatus
            ]
            
            // ✅ Restaurar conversación para participantes que la habían eliminado (estilo nativo)
            if !participantsToRestore.isEmpty {
                updateData["deletedFor"] = FieldValue.arrayRemove(participantsToRestore)
            }
            
            self?.db.collection("conversations").document(conversationId).updateData(updateData) { error in
                if let error = error {
                } else {
                    if !participantsToRestore.isEmpty {
                    } else {
                    }
                }
                completion(error)
            }
        }
    }

    private func neutralConversationPreview(for type: MessageType) -> String {
        type.conversationPreview
    }

    private func hydrateConversationPreviews(_ conversations: [Conversation]) async -> [Conversation] {
        guard !conversations.isEmpty else { return [] }
        var hydratedConversations: [Conversation] = []
        hydratedConversations.reserveCapacity(conversations.count)

        for conversation in conversations {
            let hydratedPreview = await resolveLatestConversationPreview(for: conversation)
            hydratedConversations.append(
                Conversation(
                    id: conversation.id,
                    participants: conversation.participants,
                    lastMessage: hydratedPreview,
                    timestamp: conversation.timestamp,
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
                    encryptionVersion: conversation.encryptionVersion,
                    conversationKeyVersion: conversation.conversationKeyVersion,
                    wrappedKeys: conversation.wrappedKeys
                )
            )
        }

        return hydratedConversations
    }

    private func resolveLatestConversationPreview(for conversation: Conversation) async -> String {
        guard
            conversation.encryptionVersion?.hasPrefix("3") == true,
            let conversationId = conversation.id
        else {
            return conversation.lastMessage ?? ""
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

                if messageType == .text {
                    guard let encryptedContent = data["content"] as? String, !encryptedContent.isEmpty else {
                        continue
                    }

                    let decryptedContent = await decryptMessageContent(encryptedContent, for: conversationId)
                    let trimmedContent = decryptedContent.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmedContent.isEmpty {
                        return trimmedContent
                    }
                    continue
                }

                return neutralConversationPreview(for: messageType)
            }
        } catch {
            return conversation.lastMessage ?? ""
        }

        return conversation.lastMessage ?? ""
    }
    
    func ensureEncryptionService() -> EncryptionService {
        return EncryptionService.shared
    }
    
    // MARK: - Search with Decryption
    func searchMessages(conversationId: String, query: String, completion: @escaping (Result<[EnhancedMessage], Error>) -> Void) {
        
        // Note: Searching encrypted content requires decrypting all messages
        db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .getDocuments { [weak self] snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    completion(.success([]))
                    return
                }
                
                var matchingMessages: [EnhancedMessage] = []
                
                for doc in documents {
                    let data = doc.data()
                    
                    // Decrypt content for searching
                    if let encryptedContent = data["content"] as? String {
                        // Use Task to handle async decryption in search
                        Task {
                            let decryptedContent = await self?.decryptMessageContent(encryptedContent, for: conversationId) ?? encryptedContent
                            
                            if decryptedContent.lowercased().contains(query.lowercased()) {
                                // Create message with decrypted content
                                let id = data["id"] as? String ?? doc.documentID
                                let senderId = data["senderId"] as? String ?? ""
                                let typeString = data["type"] as? String ?? MessageType.text.rawValue
                                let type = MessageType(rawValue: typeString) ?? .text
                                let timestamp = (data["timestamp"] as? Timestamp)?.dateValue() ?? Date()
                                let statusString = data["status"] as? String ?? MessageStatus.sent.rawValue
                                let status = MessageStatus(rawValue: statusString) ?? .sent
                                
                                let message = EnhancedMessage(
                                    id: id,
                                    conversationId: conversationId,
                                    senderId: senderId,
                                    type: type,
                                    content: decryptedContent, // Use decrypted content
                                    mediaUrl: data["mediaUrl"] as? String,
                                    thumbnailUrl: data["thumbnailUrl"] as? String,
                                    duration: data["duration"] as? Double,
                                    fileName: data["fileName"] as? String,
                                    fileSize: data["fileSize"] as? Int64,
                                    latitude: data["latitude"] as? Double,
                                    longitude: data["longitude"] as? Double,
                                    timestamp: timestamp,
                                    status: status,
                                    isRead: data["isRead"] as? Bool ?? false,
                                    isDeleted: data["isDeleted"] as? Bool ?? false,
                                    deletedAt: (data["deletedAt"] as? Timestamp)?.dateValue(),
                                    editedAt: (data["editedAt"] as? Timestamp)?.dateValue(),
                                    reactions: data["reactions"] as? [String: [String]],
                                    replyTo: data["replyTo"] as? String,
                                    expirationDate: (data["expirationDate"] as? Timestamp)?.dateValue(),
                                    isViewed: data["isViewed"] as? Bool ?? false,
                                    storyReplyData: data["storyReplyData"] as? [String: String]
                                )
                                
                                matchingMessages.append(message)
                            }
                        }
                        continue
                    }
                }
                
                completion(.success(matchingMessages))
            }
    }
    
    // MARK: - Ephemeral Messages
    func markEphemeralAsViewed(conversationId: String, messageId: String, completion: @escaping (Error?) -> Void) {
        db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document(messageId)
            .updateData(["isViewed": true]) { error in
                if let error = error {
                }
                completion(error)
            }
    }
    
    // MARK: - Ephemeral Cleanup System with Encryption
    func startEphemeralCleanupTimer() {
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            self.cleanupExpiredEphemeralMessages()
        }
        cleanupExpiredEphemeralMessages()
    }

    func cleanupExpiredEphemeralMessages() {
        let now = Date()
        
        db.collectionGroup("messages")
            .whereField("type", isEqualTo: MessageType.ephemeral.rawValue)
            .whereField("expirationDate", isLessThan: now)
            .whereField("isDeleted", isEqualTo: false)
            .getDocuments { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    return
                }
                
                
                let group = DispatchGroup()
                var cleanedCount = 0
                
                for document in documents {
                    group.enter()
                    
                    let data = document.data()
                    let mediaUrl = data["mediaUrl"] as? String
                    let conversationId = data["conversationId"] as? String ?? ""
                    let messageId = data["id"] as? String ?? document.documentID
                    
                    self.cleanupSingleEphemeralMessage(
                        conversationId: conversationId,
                        messageId: messageId,
                        mediaUrl: mediaUrl
                    ) { success in
                        if success {
                            cleanedCount += 1
                        }
                        group.leave()
                    }
                }
                
                group.notify(queue: .main) {
                }
            }
    }

    private func cleanupSingleEphemeralMessage(conversationId: String, messageId: String, mediaUrl: String?, completion: @escaping (Bool) -> Void) {
        let batch = db.batch()
        
        let messageRef = db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document(messageId)
        
        // Encrypt the expired message content (Async)
        Task {
            let expiredText = "📸 Momento efímero expirado"
            let encryptedExpiredText = await encryptMessageContent(expiredText, for: conversationId)
        
                    batch.updateData([
                "mediaUrl": FieldValue.delete(),
                "content": encryptedExpiredText, // Store encrypted expired message
                "isDeleted": true,
                "deletedAt": FieldValue.serverTimestamp()
            ], forDocument: messageRef)
            
            batch.commit { [weak self] error in
                if let error = error {
                    completion(false)
                    return
                }
                
                
                if let mediaUrl = mediaUrl, !mediaUrl.isEmpty {
                    self?.deleteImageFromStorage(mediaUrl: mediaUrl) { deleteSuccess in
                        if deleteSuccess {
                        } else {
                        }
                        completion(true)
                    }
                } else {
                    completion(true)
                }
            }
        }
    }

    private func deleteImageFromStorage(mediaUrl: String, completion: @escaping (Bool) -> Void) {
        let storageRef = Storage.storage().reference(forURL: mediaUrl)
        
        storageRef.delete { error in
            if let error = error {
                completion(false)
            } else {
                completion(true)
            }
        }
    }

    func forceCleanupExpiredEphemeralMessages(completion: @escaping (Int) -> Void) {
        cleanupExpiredEphemeralMessages()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            completion(0)
        }
    }
    
    // MARK: - Helper Methods
    private func getFileExtension(for type: MessageType) -> String {
        print("📤 ChatService: getFileExtension requested for type: \(type)")
        switch type {
        case .image, .gif, .viewOnceImage: return "jpg"
        case .video, .viewOnceVideo: return "mp4"
        case .audio: return "m4a"
        case .file: return "pdf"
        default: 
            print("📤 ChatService: getFileExtension falling back to default (txt) for type: \(type)")
            return "txt"
        }
    }
    
    private func getContentType(for type: MessageType) -> String {
        switch type {
        case .image, .viewOnceImage: return "image/jpeg"
        case .video, .viewOnceVideo: return "video/mp4"
        case .audio: return "audio/m4a"
        case .gif: return "image/gif"
        case .file: return "application/pdf"
        default: return "text/plain"
        }
    }
}


// MARK: - Enhanced Ephemeral Cleanup Manager
class EphemeralCleanupManager: ObservableObject {
    private let chatService = ChatService.shared
    
    init() {
        startCleanupSystem()
    }
    
    private func startCleanupSystem() {
        chatService.startEphemeralCleanupTimer()
    }
    
    func cleanupNow() {
        chatService.forceCleanupExpiredEphemeralMessages { count in
        }
    }
}

// MARK: - ChatService Extension for Sharing
extension ChatService {
    
    // ✅ Función para obtener o crear conversación
    func getOrCreateConversation(between user1Id: String, and user2Id: String, initialMessage: String? = nil, completion: @escaping (Result<String, Error>) -> Void) {
        
        // Buscar conversación existente
        db.collection("conversations")
            .whereField("participants", arrayContains: user1Id)
            .getDocuments { [weak self] snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                // Buscar conversación que contenga ambos usuarios
                let existingConversation = snapshot?.documents.first { doc in
                    let participants = doc.data()["participants"] as? [String] ?? []
                    return participants.contains(user2Id)
                }
                
                if let conversation = existingConversation {
                    let conversationId = conversation.documentID
                    let trimmedInitial = initialMessage?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                    // If caller provided an initial message, send it even when reusing an existing thread.
                    // This fixes the "Send does nothing" flow from New Conversation when the thread already exists.
                    guard !trimmedInitial.isEmpty else {
                        completion(.success(conversationId))
                        return
                    }

                    guard let self = self else {
                        completion(
                            .failure(
                                NSError(
                                    domain: "ChatService",
                                    code: -2,
                                    userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("messaging.error.serviceUnavailable", comment: "Messaging service unavailable")]
                                )
                            )
                        )
                        return
                    }

                    self.sendTextMessage(
                        conversationId: conversationId,
                        senderId: user1Id,
                        content: trimmedInitial
                    ) { sendResult in
                        switch sendResult {
                        case .success:
                            completion(.success(conversationId))
                        case .failure(let sendError):
                            completion(.failure(sendError))
                        }
                    }
                } else {
                    self?.checkMutualFollowAndCreateConversation(user1Id: user1Id, user2Id: user2Id, initialMessage: initialMessage, completion: completion)
                }
            }
    }
    
    // ✅ NUEVA: Función para verificar seguimiento mutuo antes de crear conversación
    private func checkMutualFollowAndCreateConversation(user1Id: String, user2Id: String, initialMessage: String? = nil, completion: @escaping (Result<String, Error>) -> Void) {
        let firestoreService = FirestoreService()
        
        // Verificar si user1 sigue a user2
        firestoreService.isFollowing(currentUserId: user1Id, targetUserId: user2Id) { [weak self] user1FollowsUser2 in
            // Verificar si user2 sigue a user1
            firestoreService.isFollowing(currentUserId: user2Id, targetUserId: user1Id) { user2FollowsUser1 in
                let mutualFollow = user1FollowsUser2 && user2FollowsUser1
                
                if mutualFollow {
                    self?.createBidirectionalConversation(user1Id: user1Id, user2Id: user2Id, initialMessage: initialMessage, completion: completion)
                } else {
                    // Retornar error específico para indicar que se necesita solicitud
                    let error = NSError(
                        domain: "ChatService",
                        code: 403,
                        userInfo: [
                            NSLocalizedDescriptionKey: NSLocalizedString("messaging.error.messageRequestRequired", comment: "A message request is required to start this conversation")
                        ]
                    )
                    completion(.failure(error))
                }
            }
        }
    }
    
    func sendSharedMomentMessage(
        conversationId: String,
        senderId: String,
        moment: Moment,
        shareText: String,
        momentUrl: String,
        completion: @escaping (Result<EnhancedMessage, Error>) -> Void
    ) {
        // 🔐 Encrypt content before sending (Async)
        Task {
            let encryptedContent = await encryptMessageContent(shareText, for: conversationId)
            let freshMomentAuthor = UserCacheService.shared.getCachedUser(userId: moment.authorId)?.username ?? moment.username
            
            // ✅ Create shared moment data as [String: String] (compatible con tu EnhancedMessage)
            let sharedMomentData: [String: String] = [
                "momentId": moment.id ?? "",
                "momentAuthor": freshMomentAuthor,
                "momentAuthorId": moment.authorId,  // ✅ Agregar el ID del autor
                "momentContent": moment.content,
                "momentImageUrl": moment.thumbnailUrl ?? moment.imagePath ?? "", // ✅ MEJORADO: Usar thumbnailUrl si existe
                "momentVideoUrl": moment.videoUrl ?? "", // ✅ NUEVO: Agregar URL del video
                "momentTimestamp": String(moment.timestamp.timeIntervalSince1970), // ✅ Convert to String
                "shareUrl": momentUrl
            ]
            
            let messageId = UUID().uuidString
            
            // ✅ Usar tu init personalizado de EnhancedMessage
            let message = EnhancedMessage(
                id: messageId,
                conversationId: conversationId,
                senderId: senderId,
                type: .sharedMoment,
                content: encryptedContent,
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
                storyReplyData: nil,
                sharedMomentData: sharedMomentData  // ✅ Ahora es [String: String]
            )
            
            
            // ✅ Usar la función existente sendMessage
            sendMessage(message, useServerTimestamp: true) { result in
                switch result {
                case .success(let sentMessage):
                    // ✅ Usar la función existente updateConversation
                    self.updateConversation(
                        conversationId: conversationId,
                        lastMessage: self.neutralConversationPreview(for: .sharedMoment),
                        senderId: senderId
                    ) { updateError in
                        if let updateError = updateError {
                        }
                        completion(.success(sentMessage))
                    }
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }
}

extension ChatService {
    
    // ✅ Función simplificada para eliminar después de ver
    func deleteViewOnceAfterViewing(
        conversationId: String,
        messageId: String,
        completion: @escaping (Error?) -> Void
    ) {
        
        // Usar la función existente de eliminación con limpieza
        deleteMessageWithCleanup(
            conversationId: conversationId,
            messageId: messageId,
            completion: completion
        )
    }
    
    // ✅ Función simplificada para enviar view-once
    func sendViewOnceMessage(
        conversationId: String,
        senderId: String,
        mediaData: Data,
        mediaType: EnhancedCameraPickerView.MediaType,
        messageId: String? = nil,
        completion: @escaping (Result<EnhancedMessage, Error>) -> Void
    ) {
        // Determinar el tipo de mensaje
        let messageType: MessageType = mediaType == .image ? .viewOnceImage : .viewOnceVideo
        
        let finalMessageId = messageId ?? UUID().uuidString
        
        // Subir media primero
        uploadMedia(data: mediaData, type: messageType, conversationId: conversationId, messageId: finalMessageId) { [weak self] result in
            switch result {
            case .success(let (mediaUrl, thumbnailUrl)):
                let messageId = UUID().uuidString
                
                let message = EnhancedMessage(
                    id: messageId,
                    conversationId: conversationId,
                    senderId: senderId,
                    type: messageType,
                    content: nil,
                    mediaUrl: mediaUrl,
                    thumbnailUrl: thumbnailUrl,
                    duration: nil, // No necesitamos duración para la lógica simplificada
                    fileName: nil,
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
                    storyReplyData: nil,
                    sharedMomentData: nil,
                    viewedBy: [] // Inicializar como array vacío
                )
                
                // Crear datos del mensaje con metadata de view-once
                var messageData = self?.createBasicMessageData(from: message) ?? [:]
                messageData["isViewOnce"] = true
                messageData["viewedBy"] = [] // Array de user IDs que han visto el mensaje
                
                self?.saveViewOnceMessage(message: message, customData: messageData, completion: completion)
                
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // ✅ Marcar como visto (simplificado)
    func markViewOnceAsViewed(
        conversationId: String,
        messageId: String,
        viewerId: String,
        completion: @escaping (Error?) -> Void
    ) {
        
        let messageRef = db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document(messageId)
        
        db.runTransaction({ (transaction, errorPointer) -> Any? in
            let messageDocument: DocumentSnapshot
            do {
                try messageDocument = transaction.getDocument(messageRef)
            } catch let fetchError as NSError {
                errorPointer?.pointee = fetchError
                return nil
            }
            
            guard var viewedBy = messageDocument.data()?["viewedBy"] as? [String] else {
                transaction.updateData([
                    "viewedBy": [viewerId],
                    "isViewed": true,
                    "status": MessageStatus.read.rawValue // ✅ ACTUALIZAR STATUS A LEÍDO
                ], forDocument: messageRef)
                return nil
            }
            
            if !viewedBy.contains(viewerId) {
                viewedBy.append(viewerId)
                transaction.updateData([
                    "viewedBy": viewedBy,
                    "isViewed": true,
                    "status": MessageStatus.read.rawValue // ✅ ACTUALIZAR STATUS A LEÍDO
                ], forDocument: messageRef)
            }
            
            return nil
        }) { (_, error) in
            if let error = error {
            } else {
            }
            completion(error)
        }
    }
    
    // ✅ Función auxiliar para crear datos básicos del mensaje
    private func createBasicMessageData(from message: EnhancedMessage) -> [String: Any] {
        var data: [String: Any] = [
            "id": message.id,
            "conversationId": message.conversationId,
            "senderId": message.senderId,
            "type": message.type.rawValue,
            "timestamp": FieldValue.serverTimestamp(),
            "status": MessageStatus.sent.rawValue, // ✅ FORZAR ESTADO ENVIADO INICIALMENTE
            "isRead": message.isRead,
            "isDeleted": message.isDeleted,
            "isViewed": message.isViewed
        ]
        
        if let mediaUrl = message.mediaUrl {
            data["mediaUrl"] = mediaUrl
        }
        if let thumbnailUrl = message.thumbnailUrl {
            data["thumbnailUrl"] = thumbnailUrl
        }
        if let fileSize = message.fileSize {
            data["fileSize"] = fileSize
        }
        
        return data
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
    
    // ✅ Función auxiliar para guardar mensaje view-once
    private func saveViewOnceMessage(
        message: EnhancedMessage,
        customData: [String: Any],
        completion: @escaping (Result<EnhancedMessage, Error>) -> Void
    ) {
        let messageRef = db.collection("conversations")
            .document(message.conversationId)
            .collection("messages")
            .document(message.id)
        
        messageRef.setData(customData) { [weak self] error in
            if let error = error {
                self?.updateLocalMessageStatus(
                    conversationId: message.conversationId,
                    messageId: message.id,
                    status: .failed
                )
                completion(.failure(error))
                return
            }
            
            // ✅ Marcar como enviado inmediatamente en Firestore
            self?.updateMessageStatus(
                conversationId: message.conversationId,
                messageId: message.id,
                status: .sent
            ) { _ in }
            
            
            // Actualizar conversación con preview
            let lastMessagePreview = message.type == .viewOnceImage ?
                (self?.neutralConversationPreview(for: .viewOnceImage) ?? MessageType.viewOnceImage.conversationPreview) :
                (self?.neutralConversationPreview(for: .viewOnceVideo) ?? MessageType.viewOnceVideo.conversationPreview)
            
            self?.updateConversation(
                conversationId: message.conversationId,
                lastMessage: lastMessagePreview,
                senderId: message.senderId
            ) { updateError in
                if let updateError = updateError {
                }
                
                var updatedMessage = message
                updatedMessage.status = .sent
                completion(.success(updatedMessage))
            }
        }
    }
}
