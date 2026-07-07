import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseStorage
import FirebaseCore
import Combine

class MessageRequestService: ObservableObject {
    // MARK: - Properties
    private let db = Firestore.firestore()
    private let storage = Storage.storage()
    private let firestoreService = FirestoreService()
    
    @Published var pendingRequests: [MessageRequest] = []
    @Published var outgoingPendingRequests: [MessageRequest] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private var listeners: [String: ListenerRegistration] = [:]
    private var authHandle: AuthStateDidChangeListenerHandle?

    private enum AcceptRequestServerErrorCode: String {
        case requestNotFound = "REQUEST_NOT_FOUND"
        case requestForbidden = "REQUEST_FORBIDDEN"
        case requestUntrusted = "REQUEST_UNTRUSTED"
        case requestNotPending = "REQUEST_NOT_PENDING"
        case userNotFound = "USER_NOT_FOUND"
        case inactiveUser = "INACTIVE_USER"
        case blockedRelationship = "BLOCKED_RELATIONSHIP"
        case requestAcceptFailed = "REQUEST_ACCEPT_FAILED"
    }
    
    // MARK: - Initialization
    init() {
        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }
            if user == nil {
                DispatchQueue.main.async {
                    self.removeAllListeners()
                    self.pendingRequests = []
                    self.outgoingPendingRequests = []
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

    private func localizedAcceptRequestError(code: AcceptRequestServerErrorCode?, fallbackStatusCode: Int? = nil) -> String {
        switch code {
        case .requestForbidden, .requestUntrusted:
            return NSLocalizedString("messageRequests.acceptError.forbidden", comment: "Message request cannot be accepted by this user")
        case .requestNotFound, .requestNotPending, .userNotFound, .inactiveUser, .blockedRelationship:
            return NSLocalizedString("messageRequests.acceptError.notAvailable", comment: "Message request is no longer available")
        case .requestAcceptFailed:
            return NSLocalizedString("messageRequests.acceptError.server", comment: "Message request acceptance failed")
        case .none:
            if fallbackStatusCode == 401 {
                return NSLocalizedString("messaging.error.notAuthenticated", comment: "User not authenticated.")
            }
            return NSLocalizedString("messageRequests.acceptError.server", comment: "Message request acceptance failed")
        }
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

    // MARK: - Listen to Outgoing Pending Requests
    func listenToOutgoingPendingRequests(for userId: String) {
        let listener = db.collection("messageRequests")
            .whereField("senderId", isEqualTo: userId)
            .whereField("status", isEqualTo: MessageRequest.RequestStatus.pending.rawValue)
            .order(by: "timestamp", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                if error != nil {
                    if Auth.auth().currentUser == nil {
                        DispatchQueue.main.async {
                            self?.outgoingPendingRequests = []
                        }
                    }
                    return
                }

                let requests = (snapshot?.documents ?? []).compactMap { document in
                    MessageRequest.fromFirestoreData(document.data(), id: document.documentID)
                }

                DispatchQueue.main.async {
                    self?.outgoingPendingRequests = requests
                }
            }

        listeners["outgoingPendingRequests"] = listener
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
                if existingRequest != nil {
                    DispatchQueue.main.async {
                        self?.isLoading = false
                        completion(.failure(NSError(
                            domain: "MessageRequest",
                            code: 409,
                            userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("chat.request.error.alreadyPending", comment: "Message request already pending")]
                        )))
                    }
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
    func acceptRequest(_ request: MessageRequest, completion: @escaping (Result<AcceptMessageRequestResult, Error>) -> Void) {
        guard let requestId = request.id else {
            completion(.failure(NSError(domain: "Request", code: 400, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("messageRequests.acceptError.notAvailable", comment: "Message request is no longer available")])))
            return
        }

        guard let currentUser = Auth.auth().currentUser else {
            completion(.failure(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("messaging.error.notAuthenticated", comment: "User not authenticated.")])))
            return
        }

        guard currentUser.uid == request.receiverId else {
            completion(.failure(NSError(domain: "MessageRequest", code: 403, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("messageRequests.acceptError.forbidden", comment: "Message request cannot be accepted by this user")])))
            return
        }

        isLoading = true

        Task {
            do {
                let idToken = try await currentUser.getIDToken()
                let projectId = FirebaseApp.app()?.options.projectID ?? ""
                let region = "europe-southwest1"

                guard let url = URL(string: "https://\(region)-\(projectId).cloudfunctions.net/acceptMessageRequest") else {
                    throw NSError(domain: "MessageRequest", code: 400, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("messaging.error.serviceUnavailable", comment: "Messaging service unavailable.")])
                }

                var urlRequest = URLRequest(url: url)
                urlRequest.httpMethod = "POST"
                urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                urlRequest.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
                urlRequest.httpBody = try JSONSerialization.data(withJSONObject: ["requestId": requestId])
                urlRequest.timeoutInterval = 15

                let (data, response) = try await URLSession.shared.data(for: urlRequest)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw NSError(domain: "MessageRequest", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("messaging.error.serviceUnavailable", comment: "Messaging service unavailable.")])
                }

                guard httpResponse.statusCode == 200 else {
                    let serverErrorCode: AcceptRequestServerErrorCode? = {
                        guard
                            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                            let errorCode = json["errorCode"] as? String
                        else {
                            return nil
                        }
                        return AcceptRequestServerErrorCode(rawValue: errorCode)
                    }()

                    throw NSError(
                        domain: "MessageRequest",
                        code: httpResponse.statusCode,
                        userInfo: [NSLocalizedDescriptionKey: localizedAcceptRequestError(code: serverErrorCode, fallbackStatusCode: httpResponse.statusCode)]
                    )
                }

                guard
                    let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let conversationId = json["conversationId"] as? String,
                    let messageId = json["messageId"] as? String
                else {
                    throw NSError(
                        domain: "MessageRequest",
                        code: -2,
                        userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("messaging.error.serviceUnavailable", comment: "Messaging service unavailable.")]
                    )
                }

                await MainActor.run {
                    self.isLoading = false
                    completion(.success(AcceptMessageRequestResult(conversationId: conversationId, messageId: messageId)))
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    completion(.failure(error))
                }
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
    
    // MARK: - Cancel Outgoing Request
    func cancelRequest(_ request: MessageRequest, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let requestId = request.id else {
            completion(.failure(NSError(domain: "Request", code: 400, userInfo: [NSLocalizedDescriptionKey: "ID de solicitud no válido"])))
            return
        }

        guard Auth.auth().currentUser?.uid == request.senderId else {
            completion(.failure(NSError(domain: "MessageRequest", code: 403, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("messageRequests.acceptError.forbidden", comment: "Message request cannot be accepted by this user")])))
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
    static func fromFirestoreData(_ data: [String: Any], id: String) -> MessageRequest? {
        guard let senderId = data["senderId"] as? String,
              let receiverId = data["receiverId"] as? String,
              let message = data["message"] as? String,
              let statusRaw = data["status"] as? String,
              let messageTypeRaw = data["messageType"] as? String,
              let timestamp = data["timestamp"] as? Timestamp,
              let status = RequestStatus(rawValue: statusRaw),
              let messageType = MessageType(rawValue: messageTypeRaw) else {
            return nil
        }

        return MessageRequest(
            id: id,
            senderId: senderId,
            senderUsername: data["senderUsername"] as? String,
            senderProfileImagePath: data["senderProfileImagePath"] as? String,
            receiverId: receiverId,
            message: message,
            timestamp: timestamp.dateValue(),
            status: status,
            messageType: messageType,
            mediaUrl: data["mediaUrl"] as? String,
            thumbnailUrl: data["thumbnailUrl"] as? String
        )
    }

    func encode() throws -> [String: Any] {
        let firestoreData: [String: Any] = [
            "senderId": senderId,
            "createdBy": senderId,
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
