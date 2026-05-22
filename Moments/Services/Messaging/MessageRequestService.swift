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
    private var authHandle: AuthStateDidChangeListenerHandle?
    
    // MARK: - Initialization
    init() {
        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }
            if user == nil {
                DispatchQueue.main.async {
                    self.removeAllListeners()
                    self.pendingRequests = []
                    self.isLoading = false
                    self.errorMessage = nil
                }
            }
        }
    }
    
    deinit {
        if let authHandle {
            Auth.auth().removeStateDidChangeListener(authHandle)
        }
        removeAllListeners()
    }
    
    // MARK: - Listeners Management
    func removeAllListeners() {
        listeners.values.forEach { $0.remove() }
        listeners.removeAll()
    }
    
    // MARK: - Listen to Pending Requests
    func listenToPendingRequests(for userId: String) {
        
        let listener = db.collection("messageRequests")
            .whereField("receiverId", isEqualTo: userId)
            .whereField("status", isEqualTo: MessageRequest.RequestStatus.pending.rawValue)
            .order(by: "timestamp", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                if let error = error {
                    if Auth.auth().currentUser == nil {
                        DispatchQueue.main.async {
                            self?.pendingRequests = []
                            self?.errorMessage = nil
                        }
                        return
                    }
                    self?.errorMessage = error.localizedDescription
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    self?.pendingRequests = []
                    return
                }
                
                
                let requests = documents.compactMap { document -> MessageRequest? in
                    let data = document.data()
                    
                    // Extraer campos directamente
                    guard let senderId = data["senderId"] as? String,
                          let receiverId = data["receiverId"] as? String,
                          let message = data["message"] as? String,
                          let statusRaw = data["status"] as? String,
                          let messageTypeRaw = data["messageType"] as? String,
                          let timestamp = data["timestamp"] as? Timestamp else {
                        return nil
                    }
                    
                    let senderUsername = data["senderUsername"] as? String
                    let senderProfileImagePath = data["senderProfileImagePath"] as? String
                    let mediaUrl = data["mediaUrl"] as? String
                    let thumbnailUrl = data["thumbnailUrl"] as? String
                    
                    guard let status = MessageRequest.RequestStatus(rawValue: statusRaw),
                          let messageType = MessageType(rawValue: messageTypeRaw) else {
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
                    
                    return request
                }
                
                DispatchQueue.main.async {
                    self?.pendingRequests = requests
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
        
        guard let currentUser = Auth.auth().currentUser else {
            completion(.failure(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Usuario no autenticado"])))
            return
        }
        
        
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
                
                let data = document.data()
                
                // Extraer campos directamente (mismo método que listenToPendingRequests)
                guard let senderId = data["senderId"] as? String,
                      let receiverId = data["receiverId"] as? String,
                      let message = data["message"] as? String,
                      let statusRaw = data["status"] as? String,
                      let messageTypeRaw = data["messageType"] as? String,
                      let timestamp = data["timestamp"] as? Timestamp else {
                    completion(.failure(NSError(domain: "Request", code: 400, userInfo: [NSLocalizedDescriptionKey: "Datos de solicitud incompletos"])))
                    return
                }
                
                let senderUsername = data["senderUsername"] as? String
                let senderProfileImagePath = data["senderProfileImagePath"] as? String
                let mediaUrl = data["mediaUrl"] as? String
                let thumbnailUrl = data["thumbnailUrl"] as? String
                
                guard let status = MessageRequest.RequestStatus(rawValue: statusRaw),
                      let messageType = MessageType(rawValue: messageTypeRaw) else {
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
                
                completion(.success(request))
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
                    completion(.failure(error))
                } else {
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
                        completion(.failure(error))
                    } else {
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
        guard let requestId = request.id else {
            completion(.failure(NSError(domain: "Request", code: 400, userInfo: [NSLocalizedDescriptionKey: "ID de solicitud no válido"])))
            return
        }
        
        // Crear conversación desde la solicitud primero
        createConversationFromRequest(request) { [weak self] result in
            switch result {
            case .success:
                // Eliminar la solicitud después de crear la conversación
                self?.db.collection("messageRequests").document(requestId).delete { _ in
                    completion(.success(()))
                }
            case .failure(let error):
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
                completion(.failure(error))
            } else {
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
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }
    
    // MARK: - Create Conversation From Request
    private func createConversationFromRequest(_ request: MessageRequest, completion: @escaping (Result<Void, Error>) -> Void) {
        Task { @MainActor [weak self] in
            let chatService = ChatService.shared
            chatService.createBidirectionalConversation(user1Id: request.senderId, user2Id: request.receiverId) { [weak self] result in
                switch result {
                case .success(let conversationId):
                    // Enviar el mensaje original de la solicitud
                    self?.sendOriginalMessage(from: request, in: conversationId) { messageResult in
                        switch messageResult {
                        case .success:
                            completion(.success(()))
                        case .failure:
                            // Aún completamos con éxito porque la conversación se creó
                            completion(.success(()))
                        }
                    }
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }
    
    // MARK: - Send Original Message
    private func sendOriginalMessage(from request: MessageRequest, in conversationId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        
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
        
        // Usar ChatService.shared para enviar el mensaje con encriptación
        Task { @MainActor in
            let chatService = ChatService.shared
            chatService.sendMessage(message, useServerTimestamp: true) { result in
                switch result {
                case .success:
                    completion(.success(()))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }
    
    // MARK: - Get Pending Request Count
    func getPendingRequestCount(for userId: String, completion: @escaping (Int) -> Void) {
        db.collection("messageRequests")
            .whereField("receiverId", isEqualTo: userId)
            .whereField("status", isEqualTo: MessageRequest.RequestStatus.pending.rawValue)
            .getDocuments { snapshot, error in
                if error != nil {
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
        let firestoreData: [String: Any] = [
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
        
        
        return firestoreData
    }
}
