import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseStorage
import Combine
import CryptoKit

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
    init() {
        print("🔐 ChatService inicializado con encriptación E2E")
    }
    
    deinit {
        removeAllListeners()
    }
    
    // MARK: - Listeners Management
    func removeAllListeners() {
        activeListeners.values.forEach { $0.remove() }
        activeListeners.removeAll()
        print("All listeners removed")
    }
    
    func removeListener(for conversationId: String) {
        activeListeners[conversationId]?.remove()
        activeListeners.removeValue(forKey: conversationId)
        print("Listener removed for conversation: \(conversationId)")
    }
    
    // MARK: - Real-time Messages with Decryption
    func listenToMessages(conversationId: String, completion: @escaping (Result<[EnhancedMessage], Error>) -> Void) {
        print("🔐 Setting up encrypted listener for messages in conversation: \(conversationId)")
        
        Task {
            await preloadConversationKey(for: conversationId)
        }
        
        activeListeners[conversationId]?.remove()
        print("✅ Setting up listener for conversation: \(conversationId)")
        
        let listener = db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .order(by: "timestamp", descending: false)
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

    // ✅ Nueva función helper para manejar el snapshot de manera async
    private func handleMessagesSnapshot(
        snapshot: QuerySnapshot?,
        error: Error?,
        conversationId: String,
        completion: @escaping (Result<[EnhancedMessage], Error>) -> Void
    ) async {
        if let error = error {
            print("Error listening to messages: \(error.localizedDescription)")
            completion(.failure(error))
            return
        }
        
        guard let documents = snapshot?.documents else {
            print("No messages found for conversation: \(conversationId)")
            completion(.success([]))
            return
        }
        
        print("🔄 Listener triggered - Found \(documents.count) encrypted message documents")
        
        var messages: [EnhancedMessage] = []
        
        for doc in documents {
            let data = doc.data()
            
            // ✅ Filtrar mensajes eliminados para el usuario actual (estilo Instagram)
            if let deletedFor = data["deletedFor"] as? [String],
               let currentUserId = Auth.auth().currentUser?.uid,
               deletedFor.contains(currentUserId) {
                print("🚫 Mensaje \(doc.documentID) eliminado para \(currentUserId), saltando...")
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
            
            // ✅ DEBUG: Log status updates
            if status == .sending || status == .sent {
                print("📊 Message \(id) status: \(status.rawValue)")
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
                sharedMomentData: sharedMomentData
            )
            
            messages.append(message)
        }
        
        print("✅ Listener completed - Returning \(messages.count) messages")
        
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
            
            print("🔐 Sending encrypted story reply text message: \(messageId)")
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
            
            print("🔐 Sending encrypted text message: \(finalMessageId)")
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
            
            print("🔐 Sending encrypted ephemeral message: \(messageId)")
            sendMessage(message, useServerTimestamp: true, completion: completion)
        }
    }
    
    func sendMediaMessage(conversationId: String, senderId: String, type: MessageType, mediaData: Data, fileName: String? = nil, messageId: String? = nil, completion: @escaping (Result<EnhancedMessage, Error>) -> Void) {
        print("📎 Uploading media for conversation: \(conversationId), type: \(type)")
        uploadMedia(data: mediaData, type: type, conversationId: conversationId) { [weak self] result in
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
                    isViewed: false
                )
                
                print("📎 Media uploaded, sending message: \(finalMessageId)")
                self?.sendMessage(message, useServerTimestamp: true, completion: completion)
                
            case .failure(let error):
                print("❌ Error uploading media: \(error.localizedDescription)")
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
        
        print("📍 Sending location message: \(finalMessageId)")
        sendMessage(message, useServerTimestamp: true, completion: completion)
    }
    
    func sendAudioMessage(conversationId: String, senderId: String, audioData: Data, duration: Double, messageId: String? = nil, completion: @escaping (Result<EnhancedMessage, Error>) -> Void) {
        print("🎵 Uploading audio for conversation: \(conversationId), duration: \(duration)")
        uploadMedia(data: audioData, type: .audio, conversationId: conversationId) { [weak self] result in
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
                
                print("🎵 Audio uploaded, sending message: \(finalMessageId)")
                self?.sendMessage(message, useServerTimestamp: true, completion: completion)
                
            case .failure(let error):
                print("❌ Error uploading audio: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Core Send Message Method
    func sendMessage(_ message: EnhancedMessage, useServerTimestamp: Bool, completion: @escaping (Result<EnhancedMessage, Error>) -> Void) {
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
                "status": message.status.rawValue,
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
            
            // Set timestamp
            if useServerTimestamp {
                messageData["timestamp"] = FieldValue.serverTimestamp()
            } else {
                messageData["timestamp"] = Timestamp(date: message.timestamp)
            }
            
            print("🔐 Sending encrypted message with data keys: \(messageData.keys)")
            
            // Write to Firestore
            messageRef.setData(messageData) { [weak self] error in
                if let error = error {
                    print("❌ Error writing encrypted message to Firestore: \(error.localizedDescription)")
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
                
                print("✅ Encrypted message \(message.id) written to Firestore successfully")
                
                // ✅ Llamar completion handler inmediatamente después de escribir a Firestore
                var updatedMessage = message
                updatedMessage.status = .sent
                print("✅ Encrypted message \(message.id) sent successfully")
                completion(.success(updatedMessage))
            
                // ✅ Update conversation with last message (decrypt for preview)
                Task {
                    let lastMessagePreview: String = await {
                        if let content = message.content, message.type == .text {
                            // For UI preview, decrypt the content
                            return await self?.decryptMessageContent(content, for: message.conversationId) ?? "🔐 Mensaje encriptado"
                        } else if message.type == .image {
                            return "📷 Foto"
                        } else if message.type == .video {
                            return "🎥 Video"
                        } else if message.type == .audio {
                            return "🎵 Audio"
                        } else if message.type == .location {
                            return "📍 Ubicación"
                        } else if message.type == .ephemeral {
                            return "📸 Momento efímero"
                        }
                        return "📎 Archivo adjunto"
                    }()
                    
                    self?.updateConversation(
                        conversationId: message.conversationId,
                        lastMessage: lastMessagePreview, // ✅ Usar preview descifrado
                        senderId: message.senderId
                    ) { updateError in
                        if let updateError = updateError {
                            print("⚠️ Error updating conversation: \(updateError.localizedDescription)")
                        }
                    }
                }
                
                // Update message status to sent with a small delay to show the sending state
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    // ✅ Actualizar estado local inmediatamente
                    self?.updateLocalMessageStatus(
                        conversationId: message.conversationId,
                        messageId: message.id,
                        status: .sent
                    )
                    
                    self?.updateMessageStatus(
                        conversationId: message.conversationId,
                        messageId: message.id,
                        status: .sent
                    ) { statusError in
                        if let statusError = statusError {
                            print("❌ Error updating message status: \(statusError.localizedDescription)")
                            // No llamar completion aquí porque ya se llamó arriba
                            return
                        }
                        
                        print("✅ Message status updated to sent in Firestore")
                    }
                }
            }
        } catch {
            print("❌ Error encoding encrypted message: \(error.localizedDescription)")
            completion(.failure(error))
        }
    }
    
    // MARK: - Message Actions with Encryption
    func editMessage(conversationId: String, messageId: String, newContent: String, completion: @escaping (Error?) -> Void) {
        print("✏️ Editing encrypted message \(messageId) in conversation \(conversationId)")
        
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
                        print("❌ Error editing message: \(error.localizedDescription)")
                    }
                    completion(error)
                }
        }
    }
    
    func deleteMessage(conversationId: String, messageId: String, completion: @escaping (Error?) -> Void) {
        print("🗑️ Deleting message \(messageId) in conversation \(conversationId)")
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
                if let error = error {
                    print("❌ Error deleting message: \(error.localizedDescription)")
                }
                completion(error)
            }
    }
    
    func deleteMessageWithCleanup(conversationId: String, messageId: String, completion: @escaping (Error?) -> Void) {
        print("🗑️ Eliminando mensaje encriptado \(messageId) con limpieza de archivos")
        
        db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document(messageId)
            .getDocument { [weak self] snapshot, error in
                
                if let error = error {
                    print("❌ Error obteniendo mensaje para eliminar: \(error.localizedDescription)")
                    completion(error)
                    return
                }
                
                guard let document = snapshot, document.exists else {
                    print("❌ Mensaje no encontrado: \(messageId)")
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
                            print("❌ Error marcando mensaje encriptado como eliminado: \(updateError.localizedDescription)")
                            completion(updateError)
                            return
                        }
                        
                        print("✅ Mensaje encriptado marcado como eliminado en Firestore")
                        
                        // Delete media file if exists
                        if let mediaUrl = mediaUrl, !mediaUrl.isEmpty {
                            print("🗑️ Eliminando archivo de media: \(mediaUrl)")
                            
                            self?.deleteMediaFile(url: mediaUrl) { result in
                                switch result {
                                case .success:
                                    print("✅ Archivo de media eliminado exitosamente")
                                case .failure(let deleteError):
                                    print("⚠️ Error eliminando archivo de media: \(deleteError.localizedDescription)")
                                }
                                completion(nil)
                            }
                        } else {
                            print("✅ No hay archivo de media para eliminar")
                            completion(nil)
                        }
                    }
            }
    }

    func deleteMediaFile(url: String, completion: @escaping (Result<Void, Error>) -> Void) {
        print("🗑️ Intentando eliminar archivo de media: \(url)")
        
        guard !url.isEmpty else {
            print("❌ URL vacía proporcionada")
            completion(.failure(NSError(domain: "ChatService", code: -1, userInfo: [NSLocalizedDescriptionKey: "URL inválida"])))
            return
        }
        
        let storageRef = Storage.storage().reference(forURL: url)
        
        storageRef.delete { error in
            if let error = error {
                print("❌ Error eliminando archivo de Storage: \(error.localizedDescription)")
                completion(.failure(error))
            } else {
                print("✅ Archivo eliminado exitosamente de Storage")
                completion(.success(()))
            }
        }
    }
    
    func addReaction(conversationId: String, messageId: String, emoji: String, userId: String, completion: @escaping (Error?) -> Void) {
        print("😀 Adding reaction \(emoji) to message \(messageId)")
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
                print("❌ Error adding reaction: \(error.localizedDescription)")
            }
            completion(error)
        }
    }
    
    // MARK: - User Permissions
    func canSendMessage(from senderId: String, to userId: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        print("🔍 Verificando si \(senderId) puede enviar mensaje a \(userId)")
        FirestoreService().fetchUserProfile(userId: userId) { result in
            switch result {
            case .success(let user):
                if user.blockedUsers.contains(senderId) {
                    print("🚫 El usuario \(userId) ha bloqueado a \(senderId)")
                    completion(.success(false))
                    return
                }
                 FirestoreService().fetchUserProfile(userId: senderId) { result in
                    switch result {
                    case .success(let sender):
                        if sender.blockedUsers.contains(userId) {
                            print("🚫 El usuario \(senderId) ha bloqueado a \(userId)")
                            completion(.success(false))
                            return
                        }
                        if user.isPrivate {
                           FirestoreService().fetchMutualConnections(userId: senderId) { result in
                                switch result {
                                case .success(let mutualConnections):
                                    let isMutual = mutualConnections.contains { $0.id == userId }
                                    if !isMutual {
                                        print("🔒 No hay conexión mutua entre \(senderId) y \(userId)")
                                        completion(.success(false))
                                        return
                                    }
                                    FirestoreService().checkActiveHours(user: user, completion: completion)
                                case .failure(let error):
                                    print("❌ Error al verificar conexiones mutuas: \(error.localizedDescription)")
                                    completion(.failure(error))
                                }
                            }
                        } else {
                            FirestoreService().checkActiveHours(user: user, completion: completion)
                        }
                    case .failure(let error):
                        print("❌ Error al obtener perfil del remitente: \(error.localizedDescription)")
                        completion(.failure(error))
                    }
                }
            case .failure(let error):
                print("❌ Error al obtener perfil del usuario: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }
    }

    func deleteConversationsBetweenUsers(user1Id: String, user2Id: String, completion: @escaping (Error?) -> Void) {
        print("🗑️ Marcando conversaciones como eliminadas para \(user1Id) (estilo Instagram)")
        self.db.collection("conversations")
            .whereField("participants", arrayContains: user1Id)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("❌ Error al buscar conversaciones: \(error.localizedDescription)")
                    completion(error)
                    return
                }

                guard let documents = snapshot?.documents else {
                    print("✅ No se encontraron conversaciones")
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
                    
                    // ✅ Marcar TODOS los mensajes como eliminados para este usuario (estilo Instagram)
                    self.markAllMessagesAsDeletedForUser(conversationId: doc.documentID, userId: user1Id)
                }

                batch.commit { error in
                    if let error = error {
                        print("❌ Error al marcar conversaciones como eliminadas: \(error.localizedDescription)")
                        completion(error)
                    } else {
                        print("✅ Conversaciones marcadas como eliminadas para \(user1Id)")
                        completion(nil)
                    }
                }
            }
    }
    
    // ✅ NUEVA FUNCIÓN: Restaurar conversación eliminada (estilo Instagram)
    func restoreConversation(conversationId: String, for userId: String, completion: @escaping (Error?) -> Void) {
        print("🔄 Restaurando conversación \(conversationId) para \(userId)")
        
        db.collection("conversations")
            .document(conversationId)
            .updateData([
                "deletedFor": FieldValue.arrayRemove([userId])
            ]) { error in
                if let error = error {
                    print("❌ Error restaurando conversación: \(error.localizedDescription)")
                    completion(error)
                } else {
                    print("✅ Conversación restaurada exitosamente para \(userId)")
                    completion(nil)
                }
            }
    }
    
    // ✅ NUEVA FUNCIÓN: Marcar todos los mensajes como eliminados para un usuario
    private func markAllMessagesAsDeletedForUser(conversationId: String, userId: String) {
        print("🗑️ Marcando todos los mensajes como eliminados para \(userId) en conversación \(conversationId)")
        
        db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .getDocuments { snapshot, error in
                if let error = error {
                    print("❌ Error obteniendo mensajes para marcar como eliminados: \(error.localizedDescription)")
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    print("✅ No hay mensajes para marcar como eliminados")
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
                        print("❌ Error marcando mensajes como eliminados: \(error.localizedDescription)")
                    } else {
                        print("✅ \(documents.count) mensajes marcados como eliminados para \(userId)")
                    }
                }
            }
    }
    
    // ✅ NUEVAS FUNCIONES: Pin y Mute conversaciones
    func pinConversation(_ conversationId: String, for userId: String, completion: @escaping (Error?) -> Void) {
        print("📌 Pinnando conversación \(conversationId) para usuario \(userId)")
        
        db.collection("conversations")
            .document(conversationId)
            .updateData([
                "isPinned": true,
                "pinnedAt": FieldValue.serverTimestamp(),
                "pinnedBy": userId
            ]) { error in
                if let error = error {
                    print("❌ Error pinnando conversación: \(error.localizedDescription)")
                    completion(error)
                } else {
                    print("✅ Conversación pinnada exitosamente")
                    completion(nil)
                }
            }
    }
    
    func unpinConversation(_ conversationId: String, for userId: String, completion: @escaping (Error?) -> Void) {
        print("📌 Despinnando conversación \(conversationId) para usuario \(userId)")
        
        db.collection("conversations")
            .document(conversationId)
            .updateData([
                "isPinned": false,
                "pinnedAt": FieldValue.delete(),
                "pinnedBy": FieldValue.delete()
            ]) { error in
                if let error = error {
                    print("❌ Error despinnando conversación: \(error.localizedDescription)")
                    completion(error)
                } else {
                    print("✅ Conversación despinnada exitosamente")
                    completion(nil)
                }
            }
    }
    
    func muteConversation(_ conversationId: String, for userId: String, completion: @escaping (Error?) -> Void) {
        print("🔇 Silenciando conversación \(conversationId) para usuario \(userId)")
        
        db.collection("conversations")
            .document(conversationId)
            .updateData([
                "isMuted": true,
                "mutedAt": FieldValue.serverTimestamp(),
                "mutedBy": userId
            ]) { error in
                if let error = error {
                    print("❌ Error silenciando conversación: \(error.localizedDescription)")
                    completion(error)
                } else {
                    print("✅ Conversación silenciada exitosamente")
                    completion(nil)
                }
            }
    }
    
    func unmuteConversation(_ conversationId: String, for userId: String, completion: @escaping (Error?) -> Void) {
        print("🔊 Desilenciando conversación \(conversationId) para usuario \(userId)")
        
        db.collection("conversations")
            .document(conversationId)
            .updateData([
                "isMuted": false,
                "mutedAt": FieldValue.delete(),
                "mutedBy": FieldValue.delete()
            ]) { error in
                if let error = error {
                    print("❌ Error desilenciando conversación: \(error.localizedDescription)")
                    completion(error)
                } else {
                    print("✅ Conversación desilenciada exitosamente")
                    completion(nil)
                }
            }
    }
    
    func fetchConversations(for userId: String, completion: @escaping (Result<[Conversation], Error>) -> Void) {
        
        db.collection("conversations")
            .whereField("participants", arrayContains: userId)
            .order(by: "timestamp", descending: true)
            .addSnapshotListener { snapshot, error in
                
                if let error = error {
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
                    
                    // ✅ Filtrar conversaciones eliminadas para este usuario (estilo Instagram)
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
                    let lastMessage = data["lastMessage"] as? String ?? ""
                    
                    // ✅ Intentar obtener datos del participantData (bidireccional)
                    let otherParticipantUsername: String
                    let otherParticipantProfileImagePath: String
                    
                    if let participantData = data["participantData"] as? [String: [String: Any]],
                       let otherData = participantData[otherParticipantId] {
                        // ✅ Usar datos bidireccionales
                        otherParticipantUsername = otherData["username"] as? String ?? "Usuario"
                        otherParticipantProfileImagePath = otherData["profileImagePath"] as? String ?? ""
                    } else {
                        // ✅ Fallback: usar datos del sistema anterior o cache
                        if let cachedUser = UserCacheService.shared.getCachedUser(userId: otherParticipantId) {
                            otherParticipantUsername = cachedUser.username
                            otherParticipantProfileImagePath = cachedUser.profileImagePath ?? ""
                        } else {
                            // Último fallback: datos almacenados del sistema anterior
                            otherParticipantUsername = data["otherParticipantUsername"] as? String ?? "Usuario"
                            otherParticipantProfileImagePath = data["otherParticipantProfileImagePath"] as? String ?? ""
                        }
                    }
                    
                    // ✅ Extraer campos de pin y mute
                    let isPinned = data["isPinned"] as? Bool ?? false
                    let isMuted = data["isMuted"] as? Bool ?? false
                    
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
                        isMuted: isMuted
                    )
                    
                    conversations.append(conversation)
                }
                
                conversations.sort { $0.timestamp > $1.timestamp }
                completion(.success(conversations))
            }
    }
    // MARK: - Media Upload
    func uploadMedia(data: Data, type: MessageType, conversationId: String, completion: @escaping (Result<(mediaUrl: String, thumbnailUrl: String?), Error>) -> Void) {
        let fileName = "\(UUID().uuidString).\(getFileExtension(for: type))"
        let storageRef = storage.reference().child("conversations/\(conversationId)/\(fileName)")
        
        let metadata = StorageMetadata()
        metadata.contentType = getContentType(for: type)

        storageRef.putData(data, metadata: metadata) { [weak self] _, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            storageRef.downloadURL { url, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                guard let mediaUrl = url?.absoluteString else {
                    completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No se pudo obtener la URL del archivo"])))
                    return
                }
                
                if type == .video {
                    self?.generateVideoThumbnail(from: data) { thumbnailUrl in
                        print("✅ Media upload complete, mediaUrl: \(mediaUrl), thumbnailUrl: \(thumbnailUrl ?? "nil")")
                        completion(.success((mediaUrl: mediaUrl, thumbnailUrl: thumbnailUrl)))
                    }
                } else {
                    print("✅ Media upload complete, mediaUrl: \(mediaUrl)")
                    completion(.success((mediaUrl: mediaUrl, thumbnailUrl: nil)))
                }
            }
        }
    }
    
    private func generateVideoThumbnail(from videoData: Data, completion: @escaping (String?) -> Void) {
        print("🎬 Generating video thumbnail (not implemented)")
        completion(nil)
    }
    
    // MARK: - Message Status
    func markMessagesAsRead(conversationId: String, messageIds: [String], readerId: String, completion: @escaping (Error?) -> Void) {
        print("👁️ Marking \(messageIds.count) messages as read in conversation \(conversationId)")
        let batch = db.batch()
        
        for messageId in messageIds {
            let messageRef = db.collection("conversations")
                .document(conversationId)
                .collection("messages")
                .document(messageId)
            
            batch.updateData([
                "isRead": true,
                "status": MessageStatus.read.rawValue
            ], forDocument: messageRef)
        }
        
        let conversationRef = db.collection("conversations").document(conversationId)
        batch.updateData(["readStatus.\(readerId)": true], forDocument: conversationRef)
        
        batch.commit { error in
            if let error = error {
                print("❌ Error marking messages as read: \(error.localizedDescription)")
            }
            completion(error)
        }
    }
    
    // ✅ NUEVA: Función para marcar mensajes como entregados automáticamente
    func markMessagesAsDelivered(messages: [EnhancedMessage], conversationId: String, currentUserId: String) {
        let unreadMessages = messages.filter {
            $0.senderId != currentUserId &&
            $0.status == .sent &&
            !$0.isRead
        }
        
        for message in unreadMessages {
            // Marcar como entregado
            updateMessageStatus(
                conversationId: conversationId,
                messageId: message.id,
                status: .delivered
            ) { error in
                if let error = error {
                    print("❌ Error marking message as delivered: \(error.localizedDescription)")
                } else {
                    print("✅ Message \(message.id) marked as delivered")
                    
                    // Marcar como leído después de un pequeño delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.updateMessageStatus(
                            conversationId: conversationId,
                            messageId: message.id,
                            status: .read
                        ) { readError in
                            if let readError = readError {
                                print("❌ Error marking message as read: \(readError.localizedDescription)")
                            } else {
                                print("✅ Message \(message.id) marked as read")
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func updateMessageStatus(conversationId: String, messageId: String, status: MessageStatus, completion: @escaping (Error?) -> Void) {
        print("📊 Updating message \(messageId) status to \(status.rawValue)")
        
        // ✅ Actualizar en Firestore
        db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document(messageId)
            .updateData([
                "status": status.rawValue,
                "timestamp": FieldValue.serverTimestamp() // Forzar actualización del listener
            ]) { error in
                if let error = error {
                    print("❌ Error updating message status: \(error.localizedDescription)")
                } else {
                    print("✅ Message status updated to \(status.rawValue) in Firestore")
                }
                completion(error)
            }
    }
    
    // ✅ NUEVA: Función para actualizar estado local inmediatamente
    func updateLocalMessageStatus(conversationId: String, messageId: String, status: MessageStatus) {
        print("📊 Updating local message \(messageId) status to \(status.rawValue)")
        
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
        print("🔄 Creando conversación bidireccional con clave compartida entre \(user1Id) y \(user2Id)")
        print("🔍 Debug - initialMessage en createBidirectionalConversation: '\(initialMessage ?? "nil")'")
        
        let participants = [user1Id, user2Id].sorted()
        let conversationRef = db.collection("conversations").document()
        let conversationId = conversationRef.documentID
        
        // ✅ CREAR CLAVE COMPARTIDA DE ENCRIPTACIÓN
        let sharedEncryptionKey = SymmetricKey(size: .bits256)
        let keyData = sharedEncryptionKey.withUnsafeBytes { Data($0) }
        let keyDataString = keyData.base64EncodedString()
        
        print("🔐 Generated shared encryption key for conversation: \(conversationId)")
        
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
                print("✅ Datos de usuario 1 obtenidos: \(user.username)")
            } else {
                fetchError = NSError(domain: "ChatService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No se pudo obtener datos del usuario 1: \(user1Id)"])
                print("❌ Error obteniendo usuario 1: \(user1Id)")
            }
            group.leave()
        }
        
        // Obtener usuario 2
        group.enter()
        userCache.getUser(userId: user2Id) { user in
            if let user = user {
                user2Data = user
                print("✅ Datos de usuario 2 obtenidos: \(user.username)")
            } else {
                fetchError = NSError(domain: "ChatService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No se pudo obtener datos del usuario 2: \(user2Id)"])
                print("❌ Error obteniendo usuario 2: \(user2Id)")
            }
            group.leave()
        }
        
        group.notify(queue: .main) {
            if let error = fetchError {
                print("❌ Error en createBidirectionalConversation: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            
            guard let user1 = user1Data, let user2 = user2Data else {
                let error = NSError(domain: "ChatService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Datos de usuarios incompletos"])
                print("❌ Datos de usuarios incompletos")
                completion(.failure(error))
                return
            }
            
            // ✅ Crear datos bidireccionales CON CLAVE COMPARTIDA
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
            
            let conversationData: [String: Any] = [
                "participants": participants,
                "lastMessage": "",
                "timestamp": FieldValue.serverTimestamp(),
                "readStatus": readStatus,
                "participantData": participantData,
                // 🔐 CLAVE COMPARTIDA PARA ENCRIPTACIÓN
                "encryptionKey": keyDataString,
                "encryptionKeyCreatedAt": FieldValue.serverTimestamp(),
                "encryptionVersion": "1.0"
            ]
            
            print("💾 Guardando conversación bidireccional con encriptación en Firestore...")
            conversationRef.setData(conversationData) { error in
                if let error = error {
                    print("❌ Error guardando conversación: \(error.localizedDescription)")
                    completion(.failure(error))
                } else {
                    print("✅ Conversación bidireccional con encriptación creada exitosamente: \(conversationId)")
                    
                    // ✅ PRECARGAR LA CLAVE LOCALMENTE (ya la tenemos)
                    Task {
                        await self.preloadConversationKey(for: conversationId)
                        print("✅ Encryption key preloaded for new conversation: \(conversationId)")
                    }
                    
                    // ✅ ENVIAR MENSAJE INICIAL (personalizado o automático)
                    print("🔍 Debug - initialMessage recibido: '\(initialMessage ?? "nil")'")
                    if let customMessage = initialMessage, !customMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        print("✅ Enviando mensaje personalizado del usuario: '\(customMessage)'")
                        // Enviar mensaje personalizado del usuario
                        self.sendInitialMessage(to: conversationId, from: user1Id, to: user2Id, message: customMessage) { result in
                            switch result {
                            case .success(_):
                                print("✅ Mensaje personalizado enviado exitosamente")
                            case .failure(let error):
                                print("⚠️ Error enviando mensaje personalizado: \(error.localizedDescription)")
                            }
                            completion(.success(conversationId))
                        }
                    } else {
                        // Enviar mensaje automático por defecto
                        self.sendInitialMessage(to: conversationId, from: user1Id, to: user2Id) { result in
                            switch result {
                            case .success(_):
                                print("✅ Mensaje inicial automático enviado exitosamente")
                            case .failure(let error):
                                print("⚠️ Error enviando mensaje inicial: \(error.localizedDescription)")
                            }
                            completion(.success(conversationId))
                        }
                    }
                }
            }
        }
    }
    
    // ✅ NUEVA: Función para enviar mensaje inicial automático
    private func sendInitialMessage(to conversationId: String, from senderId: String, to receiverId: String, message: String? = nil, completion: @escaping (Result<Void, Error>) -> Void) {
        print("💬 Enviando mensaje inicial a conversación: \(conversationId)")
        
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
                        print("❌ Error enviando mensaje inicial: \(error.localizedDescription)")
                        completion(.failure(error))
                    } else {
                        print("✅ Mensaje inicial enviado: \(messageId)")
                        
                        // Actualizar lastMessage en la conversación
                        self.db.collection("conversations")
                            .document(conversationId)
                            .updateData([
                                "lastMessage": initialMessage,
                                "timestamp": timestamp
                            ]) { updateError in
                                if let updateError = updateError {
                                    print("⚠️ Error actualizando lastMessage: \(updateError.localizedDescription)")
                                } else {
                                    print("✅ LastMessage actualizado en conversación")
                                }
                                completion(.success(()))
                            }
                    }
                }
        }
    }

    // ✅ Función para actualizar datos de usuario en todas sus conversaciones
    func updateUserDataInAllConversations(userId: String, newUserData: AppUser) {
        print("🔄 Actualizando datos de \(userId) en todas las conversaciones")
        
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
                        print("❌ Error actualizando conversaciones: \(error.localizedDescription)")
                    } else {
                        print("✅ Datos de usuario actualizados en \(documents.count) conversaciones")
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
                print("❌ Error deleting typing indicator: \(error.localizedDescription)")
            }
        }
    }
    
    func listenToTypingIndicators(conversationId: String) {
        let listener = db.collection("conversations")
            .document(conversationId)
            .collection("typing")
            .addSnapshotListener { [weak self] snapshot, error in
                if let error = error {
                    print("❌ Error listening to typing indicators: \(error.localizedDescription)")
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
        
        activeListeners["typing_\(conversationId)"] = listener
    }
    
    // MARK: - Conversation Management
    private func updateConversation(conversationId: String, lastMessage: String, senderId: String, completion: @escaping (Error?) -> Void) {
        print("📝 Updating conversation \(conversationId) with last message: \(lastMessage)")
        db.collection("conversations").document(conversationId).getDocument { [weak self] snapshot, error in
            if let error = error {
                print("❌ Error fetching conversation: \(error.localizedDescription)")
                completion(error)
                return
            }
            
            guard let doc = snapshot, doc.exists,
                  let participants = doc.data()?["participants"] as? [String] else {
                print("❌ Conversation not found or invalid participants")
                completion(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Conversación no encontrada"]))
                return
            }
            
            var readStatus: [String: Bool] = [:]
            participants.forEach { participant in
                readStatus[participant] = (participant == senderId)
            }
            
            // ✅ Verificar si la conversación está eliminada para algún participante y restaurarla
            let deletedFor = doc.data()?["deletedFor"] as? [String] ?? []
            let participantsToRestore = deletedFor.filter { $0 != senderId } // Restaurar para todos excepto el remitente
            
            var updateData: [String: Any] = [
                "lastMessage": lastMessage, // ✅ Preview descifrado para mostrar en la lista
                "timestamp": FieldValue.serverTimestamp(),
                "readStatus": readStatus
            ]
            
            // ✅ Restaurar conversación para participantes que la habían eliminado (estilo Instagram)
            if !participantsToRestore.isEmpty {
                updateData["deletedFor"] = FieldValue.arrayRemove(participantsToRestore)
                print("🔄 Restaurando conversación \(conversationId) para usuarios que la habían eliminado: \(participantsToRestore)")
            }
            
            self?.db.collection("conversations").document(conversationId).updateData(updateData) { error in
                if let error = error {
                    print("❌ Error updating conversation: \(error.localizedDescription)")
                } else {
                    if !participantsToRestore.isEmpty {
                        print("✅ Conversation updated and restored for \(participantsToRestore.count) users")
                    } else {
                        print("✅ Conversation updated with decrypted preview")
                    }
                }
                completion(error)
            }
        }
    }
    
    func ensureEncryptionService() -> EncryptionService {
        return EncryptionService.shared
    }
    
    // MARK: - Search with Decryption
    func searchMessages(conversationId: String, query: String, completion: @escaping (Result<[EnhancedMessage], Error>) -> Void) {
        print("🔍 Searching encrypted messages in conversation \(conversationId) with query: \(query)")
        
        // Note: Searching encrypted content requires decrypting all messages
        db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .getDocuments { [weak self] snapshot, error in
                if let error = error {
                    print("❌ Error searching messages: \(error.localizedDescription)")
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
                
                print("🔍 Search returned \(matchingMessages.count) decrypted messages")
                completion(.success(matchingMessages))
            }
    }
    
    // MARK: - Ephemeral Messages
    func markEphemeralAsViewed(conversationId: String, messageId: String, completion: @escaping (Error?) -> Void) {
        print("👁️ Marking ephemeral message \(messageId) as viewed")
        db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document(messageId)
            .updateData(["isViewed": true]) { error in
                if let error = error {
                    print("❌ Error marking ephemeral as viewed: \(error.localizedDescription)")
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
        print("🧹 Iniciando limpieza de mensajes efímeros encriptados expirados...")
        let now = Date()
        
        db.collectionGroup("messages")
            .whereField("type", isEqualTo: MessageType.ephemeral.rawValue)
            .whereField("expirationDate", isLessThan: now)
            .whereField("isDeleted", isEqualTo: false)
            .getDocuments { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("❌ Error buscando mensajes efímeros expirados: \(error.localizedDescription)")
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    print("✅ No hay mensajes efímeros expirados")
                    return
                }
                
                print("🗑️ Encontrados \(documents.count) mensajes efímeros encriptados expirados")
                
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
                    print("✅ Limpieza de mensajes encriptados completada: \(cleanedCount)/\(documents.count) mensajes procesados")
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
                    print("❌ Error actualizando mensaje efímero encriptado \(messageId): \(error.localizedDescription)")
                    completion(false)
                    return
                }
                
                print("✅ Mensaje efímero encriptado \(messageId) marcado como expirado")
                
                if let mediaUrl = mediaUrl, !mediaUrl.isEmpty {
                    self?.deleteImageFromStorage(mediaUrl: mediaUrl) { deleteSuccess in
                        if deleteSuccess {
                            print("🗑️ Imagen borrada de Storage: \(mediaUrl)")
                        } else {
                            print("⚠️ No se pudo borrar imagen de Storage: \(mediaUrl)")
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
                print("❌ Error borrando imagen de Storage: \(error.localizedDescription)")
                completion(false)
            } else {
                print("✅ Imagen borrada exitosamente de Storage")
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
        switch type {
        case .image, .gif: return "jpg"
        case .video: return "mp4"
        case .audio: return "m4a"
        case .file: return "pdf"
        default: return "txt"
        }
    }
    
    private func getContentType(for type: MessageType) -> String {
        switch type {
        case .image: return "image/jpeg"
        case .video: return "video/mp4"
        case .audio: return "audio/m4a"
        case .gif: return "image/gif"
        case .file: return "application/pdf"
        default: return "text/plain"
        }
    }
}


// MARK: - Enhanced Ephemeral Cleanup Manager
class EphemeralCleanupManager: ObservableObject {
    private let chatService = ChatService()
    
    init() {
        startCleanupSystem()
    }
    
    private func startCleanupSystem() {
        chatService.startEphemeralCleanupTimer()
        print("🚀 Sistema de limpieza de mensajes efímeros encriptados iniciado")
    }
    
    func cleanupNow() {
        chatService.forceCleanupExpiredEphemeralMessages { count in
            print("🧹 Limpieza manual de mensajes encriptados completada")
        }
    }
}

// MARK: - ChatService Extension for Sharing
extension ChatService {
    
    // ✅ Función para obtener o crear conversación
    func getOrCreateConversation(between user1Id: String, and user2Id: String, initialMessage: String? = nil, completion: @escaping (Result<String, Error>) -> Void) {
        print("🔍 Buscando conversación entre \(user1Id) y \(user2Id)")
        
        // Buscar conversación existente
        db.collection("conversations")
            .whereField("participants", arrayContains: user1Id)
            .getDocuments { [weak self] snapshot, error in
                if let error = error {
                    print("❌ Error buscando conversación: \(error.localizedDescription)")
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
                    print("✅ Conversación existente encontrada: \(conversationId)")
                    completion(.success(conversationId))
                } else {
                    print("🆕 Verificando si los usuarios se siguen mutuamente")
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
                    print("✅ Usuarios se siguen mutuamente, creando conversación")
                    self?.createBidirectionalConversation(user1Id: user1Id, user2Id: user2Id, initialMessage: initialMessage, completion: completion)
                } else {
                    print("❌ Usuarios no se siguen mutuamente, no se puede crear conversación directa")
                    // Retornar error específico para indicar que se necesita solicitud
                    let error = NSError(
                        domain: "ChatService",
                        code: 403,
                        userInfo: [
                            NSLocalizedDescriptionKey: "Los usuarios no se siguen mutuamente. Se requiere una solicitud de mensaje."
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
            
            // ✅ Create shared moment data as [String: String] (compatible con tu EnhancedMessage)
            let sharedMomentData: [String: String] = [
                "momentId": moment.id ?? "",
                "momentAuthor": moment.username,
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
            
            print("🔗 Sending shared moment message: \(messageId)")
            
            // ✅ Usar la función existente sendMessage
            sendMessage(message, useServerTimestamp: true) { result in
                switch result {
                case .success(let sentMessage):
                    // ✅ Usar la función existente updateConversation
                    self.updateConversation(
                        conversationId: conversationId,
                        lastMessage: "📷 Momento compartido", // Preview descifrado
                        senderId: senderId
                    ) { updateError in
                        if let updateError = updateError {
                            print("⚠️ Error updating conversation: \(updateError.localizedDescription)")
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
        print("🗑️ Deleting view-once message after viewing (Instagram style): \(messageId)")
        
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
        completion: @escaping (Result<EnhancedMessage, Error>) -> Void
    ) {
        // Determinar el tipo de mensaje
        let messageType: MessageType = mediaType == .image ? .viewOnceImage : .viewOnceVideo
        
        // Subir media primero
        uploadMedia(data: mediaData, type: messageType, conversationId: conversationId) { [weak self] result in
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
                
                print("📸 Saving view-once message to Firestore")
                self?.saveViewOnceMessage(message: message, customData: messageData, completion: completion)
                
            case .failure(let error):
                print("❌ Error uploading view-once media: \(error.localizedDescription)")
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
        print("👁️ Marking view-once message as viewed: \(messageId)")
        
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
                    "isViewed": true
                ], forDocument: messageRef)
                return nil
            }
            
            if !viewedBy.contains(viewerId) {
                viewedBy.append(viewerId)
                transaction.updateData([
                    "viewedBy": viewedBy,
                    "isViewed": true
                ], forDocument: messageRef)
            }
            
            return nil
        }) { (_, error) in
            if let error = error {
                print("❌ Error marking view-once as viewed: \(error.localizedDescription)")
            } else {
                print("✅ View-once message marked as viewed")
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
            "status": message.status.rawValue,
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
                print("❌ Error saving view-once message: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            
            print("✅ View-once message saved successfully")
            
            // Actualizar conversación con preview
            let lastMessagePreview = message.type == .viewOnceImage ?
                "📷 Foto (ver una vez)" : "🎥 Video (ver una vez)"
            
            self?.updateConversation(
                conversationId: message.conversationId,
                lastMessage: lastMessagePreview,
                senderId: message.senderId
            ) { updateError in
                if let updateError = updateError {
                    print("⚠️ Error updating conversation: \(updateError.localizedDescription)")
                }
                
                var updatedMessage = message
                updatedMessage.status = .sent
                completion(.success(updatedMessage))
            }
        }
    }
}
