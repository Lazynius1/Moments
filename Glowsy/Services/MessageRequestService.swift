import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseStorage
import Combine

class MessageRequestService: ObservableObject {
    // MARK: - Properties
    private let db = Firestore.firestore()
    private let storage = Storage.storage()
    private let firestoreService = FirestoreService()
    
    @Published var pendingRequests: [MessageRequest] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private var listeners: [String: ListenerRegistration] = [:]
    
    // MARK: - Initialization
    init() {
        print("📨 MessageRequestService inicializado")
    }
    
    deinit {
        removeAllListeners()
    }
    
    // MARK: - Listeners Management
    func removeAllListeners() {
        listeners.values.forEach { $0.remove() }
        listeners.removeAll()
    }
    
    // MARK: - Listen to Pending Requests
    func listenToPendingRequests(for userId: String) {
        print("📨 Escuchando solicitudes pendientes para usuario: \(userId)")
        
        let listener = db.collection("messageRequests")
            .whereField("receiverId", isEqualTo: userId)
            .whereField("status", isEqualTo: MessageRequest.RequestStatus.pending.rawValue)
            .order(by: "timestamp", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                print("📨 Listener triggered - Error: \(error?.localizedDescription ?? "None")")
                print("📨 Documents count: \(snapshot?.documents.count ?? 0)")
                if let error = error {
                    print("❌ Error escuchando solicitudes: \(error.localizedDescription)")
                    self?.errorMessage = error.localizedDescription
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    print("📨 No documents found")
                    self?.pendingRequests = []
                    return
                }
                
                print("📨 Found \(documents.count) documents")
                for (index, doc) in documents.enumerated() {
                    print("📨 Document \(index): \(doc.data())")
                }
                
                let requests = documents.compactMap { document -> MessageRequest? in
                    do {
                        let data = document.data()
                        print("📨 Processing document data: \(data)")
                        
                        // Extraer campos directamente
                        guard let senderId = data["senderId"] as? String,
                              let receiverId = data["receiverId"] as? String,
                              let message = data["message"] as? String,
                              let statusRaw = data["status"] as? String,
                              let messageTypeRaw = data["messageType"] as? String,
                              let timestamp = data["timestamp"] as? Timestamp else {
                            print("❌ Missing required fields in document")
                            return nil
                        }
                        
                        let senderUsername = data["senderUsername"] as? String
                        let senderProfileImagePath = data["senderProfileImagePath"] as? String
                        let mediaUrl = data["mediaUrl"] as? String
                        let thumbnailUrl = data["thumbnailUrl"] as? String
                        
                        guard let status = MessageRequest.RequestStatus(rawValue: statusRaw),
                              let messageType = MessageType(rawValue: messageTypeRaw) else {
                            print("❌ Invalid status or messageType")
                            return nil
                        }
                        
                        let request = MessageRequest(
                            id: document.documentID,
                            senderId: senderId,
                            senderUsername: senderUsername,
                            senderProfileImagePath: senderProfileImagePath,
                            receiverId: receiverId,
                            message: message,
                            timestamp: timestamp.dateValue(),
                            status: status,
                            messageType: messageType,
                            mediaUrl: mediaUrl,
                            thumbnailUrl: thumbnailUrl
                        )
                        
                        print("✅ Successfully decoded request: \(request.senderUsername ?? "Unknown") -> \(request.message)")
                        return request
                    } catch {
                        print("❌ Error decodificando solicitud: \(error)")
                        return nil
                    }
                }
                
                DispatchQueue.main.async {
                    self?.pendingRequests = requests
                    print("📨 Actualizadas \(requests.count) solicitudes pendientes")
                }
            }
        
        listeners["pendingRequests"] = listener
    }
    
    // MARK: - Send Message Request
    func sendMessageRequest(
        to receiverId: String,
        message: String,
        messageType: MessageType = .text,
        mediaUrl: String? = nil,
        thumbnailUrl: String? = nil,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        print("📤 Iniciando envío de solicitud de mensaje...")
        print("📤 Receiver ID: \(receiverId)")
        print("📤 Message: \(message)")
        print("📤 Message Type: \(messageType)")
        
        guard let currentUser = Auth.auth().currentUser else {
            print("❌ Usuario no autenticado")
            completion(.failure(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Usuario no autenticado"])))
            return
        }
        
        print("📤 Usuario autenticado: \(currentUser.uid)")
        
        isLoading = true
        
        // Verificar si ya existe una solicitud pendiente
        checkExistingRequest(senderId: currentUser.uid, receiverId: receiverId) { [weak self] result in
            switch result {
            case .success(let existingRequest):
                if let existingRequest = existingRequest {
                    // Actualizar solicitud existente
                    self?.updateExistingRequest(
                        existingRequest,
                        newMessage: message,
                        messageType: messageType,
                        mediaUrl: mediaUrl,
                        thumbnailUrl: thumbnailUrl,
                        completion: completion
                    )
                } else {
                    // Crear nueva solicitud
                    self?.createNewRequest(
                        senderId: currentUser.uid,
                        receiverId: receiverId,
                        message: message,
                        messageType: messageType,
                        mediaUrl: mediaUrl,
                        thumbnailUrl: thumbnailUrl,
                        completion: completion
                    )
                }
                
            case .failure(let error):
                DispatchQueue.main.async {
                    self?.isLoading = false
                    completion(.failure(error))
                }
            }
        }
    }
    
    // MARK: - Check Existing Request
    private func checkExistingRequest(senderId: String, receiverId: String, completion: @escaping (Result<MessageRequest?, Error>) -> Void) {
        db.collection("messageRequests")
            .whereField("senderId", isEqualTo: senderId)
            .whereField("receiverId", isEqualTo: receiverId)
            .whereField("status", isEqualTo: MessageRequest.RequestStatus.pending.rawValue)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                guard let document = snapshot?.documents.first else {
                    completion(.success(nil))
                    return
                }
                
                do {
                    let data = document.data()
                    print("🔍 Processing existing request data: \(data)")
                    
                    // Extraer campos directamente (mismo método que listenToPendingRequests)
                    guard let senderId = data["senderId"] as? String,
                          let receiverId = data["receiverId"] as? String,
                          let message = data["message"] as? String,
                          let statusRaw = data["status"] as? String,
                          let messageTypeRaw = data["messageType"] as? String,
                          let timestamp = data["timestamp"] as? Timestamp else {
                        print("❌ Missing required fields in existing request document")
                        completion(.failure(NSError(domain: "Request", code: 400, userInfo: [NSLocalizedDescriptionKey: "Datos de solicitud incompletos"])))
                        return
                    }
                    
                    let senderUsername = data["senderUsername"] as? String
                    let senderProfileImagePath = data["senderProfileImagePath"] as? String
                    let mediaUrl = data["mediaUrl"] as? String
                    let thumbnailUrl = data["thumbnailUrl"] as? String
                    
                    guard let status = MessageRequest.RequestStatus(rawValue: statusRaw),
                          let messageType = MessageType(rawValue: messageTypeRaw) else {
                        print("❌ Invalid status or messageType in existing request")
                        completion(.failure(NSError(domain: "Request", code: 400, userInfo: [NSLocalizedDescriptionKey: "Estado o tipo de mensaje inválido"])))
                        return
                    }
                    
                    let request = MessageRequest(
                        id: document.documentID,
                        senderId: senderId,
                        senderUsername: senderUsername,
                        senderProfileImagePath: senderProfileImagePath,
                        receiverId: receiverId,
                        message: message,
                        timestamp: timestamp.dateValue(),
                        status: status,
                        messageType: messageType,
                        mediaUrl: mediaUrl,
                        thumbnailUrl: thumbnailUrl
                    )
                    
                    print("✅ Successfully found existing request: \(request.senderUsername ?? "Unknown") -> \(request.message)")
                    completion(.success(request))
                } catch {
                    print("❌ Error processing existing request: \(error)")
                    completion(.failure(error))
                }
            }
    }
    
    // MARK: - Create New Request
    private func createNewRequest(
        senderId: String,
        receiverId: String,
        message: String,
        messageType: MessageType,
        mediaUrl: String?,
        thumbnailUrl: String?,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        // Obtener información del remitente
        firestoreService.fetchUser(userId: senderId) { [weak self] (result: Result<AppUser, Error>) in
            switch result {
            case .success(let userData):
                let request = MessageRequest(
                    id: nil, // Firestore asignará el ID automáticamente
                    senderId: senderId,
                    senderUsername: userData.username,
                    senderProfileImagePath: userData.profileImagePath,
                    receiverId: receiverId,
                    message: message,
                    timestamp: Date(),
                    status: .pending,
                    messageType: messageType,
                    mediaUrl: mediaUrl,
                    thumbnailUrl: thumbnailUrl
                )
                
                print("📤 MessageType raw value: \(messageType.rawValue)")
                
                self?.saveRequest(request, completion: completion)
                
            case .failure(let error):
                DispatchQueue.main.async {
                    self?.isLoading = false
                    completion(.failure(error))
                }
            }
        }
    }
    
    // MARK: - Update Existing Request
    private func updateExistingRequest(
        _ existingRequest: MessageRequest,
        newMessage: String,
        messageType: MessageType,
        mediaUrl: String?,
        thumbnailUrl: String?,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let requestId = existingRequest.id else {
            completion(.failure(NSError(domain: "Request", code: 400, userInfo: [NSLocalizedDescriptionKey: "ID de solicitud no válido"])))
            return
        }
        
        let updateData: [String: Any] = [
            "message": newMessage,
            "messageType": messageType.rawValue,
            "mediaUrl": mediaUrl as Any,
            "thumbnailUrl": thumbnailUrl as Any,
            "timestamp": Timestamp(date: Date())
        ]
        
        db.collection("messageRequests").document(requestId).updateData(updateData) { [weak self] error in
            DispatchQueue.main.async {
                self?.isLoading = false
                if let error = error {
                    print("❌ Error actualizando solicitud: \(error.localizedDescription)")
                    completion(.failure(error))
                } else {
                    print("✅ Solicitud actualizada exitosamente")
                    completion(.success(()))
                }
            }
        }
    }
    
    // MARK: - Save Request
    private func saveRequest(_ request: MessageRequest, completion: @escaping (Result<Void, Error>) -> Void) {
        do {
            let data = try request.encode()
            db.collection("messageRequests").addDocument(data: data) { [weak self] error in
                DispatchQueue.main.async {
                    self?.isLoading = false
                    if let error = error {
                        print("❌ Error guardando solicitud: \(error.localizedDescription)")
                        completion(.failure(error))
                    } else {
                        print("✅ Solicitud guardada exitosamente")
                        completion(.success(()))
                    }
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.isLoading = false
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Accept Request
    func acceptRequest(_ request: MessageRequest, completion: @escaping (Result<Void, Error>) -> Void) {
        print("🔄 MessageRequestService.acceptRequest llamado para: \(request.senderUsername ?? "Unknown")")
        guard let requestId = request.id else {
            completion(.failure(NSError(domain: "Request", code: 400, userInfo: [NSLocalizedDescriptionKey: "ID de solicitud no válido"])))
            return
        }
        
        // Crear conversación desde la solicitud primero
        print("🔄 Iniciando proceso de aceptación de solicitud...")
        createConversationFromRequest(request) { [weak self] result in
            print("🔄 createConversationFromRequest completado con resultado: \(result)")
            switch result {
            case .success:
                // Eliminar la solicitud después de crear la conversación
                print("🗑️ Intentando eliminar solicitud con ID: \(requestId)")
                self?.db.collection("messageRequests").document(requestId).delete { error in
                    if let error = error {
                        print("❌ Error eliminando solicitud: \(error.localizedDescription)")
                        print("🔍 Detalles del error: \(error)")
                        // Aún completamos con éxito porque la conversación se creó
                        print("🔄 Completando con éxito a pesar del error de eliminación...")
                        completion(.success(()))
                    } else {
                        print("✅ Solicitud eliminada exitosamente")
                        print("🎉 Proceso de aceptación completado exitosamente")
                        completion(.success(()))
                    }
                }
            case .failure(let error):
                print("❌ Error creando conversación: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Reject Request
    func rejectRequest(_ request: MessageRequest, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let requestId = request.id else {
            completion(.failure(NSError(domain: "Request", code: 400, userInfo: [NSLocalizedDescriptionKey: "ID de solicitud no válido"])))
            return
        }
        
        db.collection("messageRequests").document(requestId).delete { error in
            if let error = error {
                print("❌ Error rechazando solicitud: \(error.localizedDescription)")
                completion(.failure(error))
            } else {
                print("✅ Solicitud rechazada y eliminada exitosamente")
                completion(.success(()))
            }
        }
    }
    
    // MARK: - Block User
    func blockUser(_ request: MessageRequest, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let requestId = request.id else {
            completion(.failure(NSError(domain: "Request", code: 400, userInfo: [NSLocalizedDescriptionKey: "ID de solicitud no válido"])))
            return
        }
        
        db.collection("messageRequests").document(requestId).delete { error in
            if let error = error {
                print("❌ Error bloqueando usuario: \(error.localizedDescription)")
                completion(.failure(error))
            } else {
                print("✅ Usuario bloqueado y solicitud eliminada exitosamente")
                completion(.success(()))
            }
        }
    }
    
    // MARK: - Create Conversation From Request
    private func createConversationFromRequest(_ request: MessageRequest, completion: @escaping (Result<Void, Error>) -> Void) {
        print("🔄 Iniciando creación de conversación desde solicitud...")
        let chatService = ChatService()
        chatService.createBidirectionalConversation(user1Id: request.senderId, user2Id: request.receiverId) { [weak self] result in
            switch result {
            case .success(let conversationId):
                print("✅ Conversación creada desde solicitud: \(conversationId)")
                print("🔄 Procediendo a enviar mensaje original...")
                
                // Enviar el mensaje original de la solicitud
                self?.sendOriginalMessage(from: request, in: conversationId) { messageResult in
                    switch messageResult {
                    case .success:
                        print("✅ Mensaje original enviado exitosamente")
                        print("🔄 Completando proceso de aceptación...")
                        completion(.success(()))
                    case .failure(let error):
                        print("❌ Error enviando mensaje original: \(error.localizedDescription)")
                        print("🔄 Completando proceso de aceptación (sin mensaje original)...")
                        // Aún completamos con éxito porque la conversación se creó
                        completion(.success(()))
                    }
                }
                
            case .failure(let error):
                print("❌ Error creando conversación desde solicitud: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Send Original Message
    private func sendOriginalMessage(from request: MessageRequest, in conversationId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        print("🔄 Transfiriendo mensaje original de solicitud a conversación...")
        print("📝 Contenido del mensaje: \(request.message)")
        print("👤 Remitente: \(request.senderId)")
        print("💬 Tipo de mensaje: \(request.messageType)")
        print("🆔 ID de conversación: \(conversationId)")
        
        // Crear el mensaje usando el sistema de encriptación
        let message = EnhancedMessage(
            id: UUID().uuidString,
            conversationId: conversationId,
            senderId: request.senderId,
            type: request.messageType,
            content: request.message,
            mediaUrl: request.mediaUrl,
            thumbnailUrl: request.thumbnailUrl,
            duration: nil,
            fileName: nil,
            fileSize: nil,
            latitude: nil,
            longitude: nil,
            timestamp: request.timestamp,
            status: .sent,
            isRead: false,
            isDeleted: false,
            deletedAt: nil,
            editedAt: nil,
            reactions: nil,
            replyTo: nil,
            expirationDate: nil,
            isViewed: false,
            storyReplyData: nil,
            sharedMomentData: nil
        )
        
        // Usar ChatService para enviar el mensaje con encriptación
        let chatService = ChatService()
        print("🔄 Llamando a ChatService.sendMessage...")
        chatService.sendMessage(message, useServerTimestamp: true) { result in
            print("🔄 ChatService.sendMessage completado con resultado: \(result)")
            switch result {
            case .success:
                print("✅ Mensaje original transferido exitosamente con encriptación")
                print("🔄 Llamando a completion(.success(()))...")
                completion(.success(()))
            case .failure(let error):
                print("❌ Error transfiriendo mensaje: \(error.localizedDescription)")
                print("🔄 Llamando a completion(.failure(error))...")
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Get Pending Request Count
    func getPendingRequestCount(for userId: String, completion: @escaping (Int) -> Void) {
        db.collection("messageRequests")
            .whereField("receiverId", isEqualTo: userId)
            .whereField("status", isEqualTo: MessageRequest.RequestStatus.pending.rawValue)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("❌ Error obteniendo conteo de solicitudes: \(error.localizedDescription)")
                    completion(0)
                    return
                }
                
                let count = snapshot?.documents.count ?? 0
                completion(count)
            }
    }
    
    // MARK: - Can Send Request
    func canSendRequest(from senderId: String, to receiverId: String, completion: @escaping (Bool) -> Void) {
        // Verificar si ya existe una solicitud pendiente
        checkExistingRequest(senderId: senderId, receiverId: receiverId) { result in
            switch result {
            case .success(let existingRequest):
                completion(existingRequest == nil)
            case .failure:
                completion(false)
            }
        }
    }
}

// MARK: - MessageRequest Extension for Encoding
extension MessageRequest {
    func encode() throws -> [String: Any] {
        var firestoreData: [String: Any] = [
            "senderId": senderId,
            "senderUsername": senderUsername as Any,
            "senderProfileImagePath": senderProfileImagePath as Any,
            "receiverId": receiverId,
            "message": message,
            "timestamp": Timestamp(date: timestamp),
            "status": status.rawValue,
            "messageType": messageType.rawValue,
            "mediaUrl": mediaUrl as Any,
            "thumbnailUrl": thumbnailUrl as Any
        ]
        
        print("📤 Firestore data being sent: \(firestoreData)")
        
        return firestoreData
    }
}
