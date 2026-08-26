import Foundation
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import FirebaseStorage
import Observation
import Combine

enum DirectMessageRoute: Equatable {
    case conversation(id: String)
    case conversationDraft(threadId: String)
    case outgoingRequest(threadId: String, messageCount: Int, limit: Int, cryptoConfigured: Bool)
    case incomingRequest(threadId: String, messageCount: Int)
}

struct MessageRequestInteractionContext: Hashable {
    enum Kind: String, Hashable {
        case general
        case storyMessage
        case storyEphemeral
        case shareStory
        case shareMoment
        case shareProfile
        case forwardText
    }

    let kind: Kind
    var storyId: String?
    var storyOwnerId: String?
    var sharedContentId: String?
    var sharedContentOwnerId: String?

    static let general = MessageRequestInteractionContext(kind: .general)

    var payload: [String: Any] {
        var value: [String: Any] = ["kind": kind.rawValue]
        if let storyId { value["storyId"] = storyId }
        if let storyOwnerId { value["storyOwnerId"] = storyOwnerId }
        if let sharedContentId { value["sharedContentId"] = sharedContentId }
        if let sharedContentOwnerId { value["sharedContentOwnerId"] = sharedContentOwnerId }
        return value
    }
}

struct MessageRequestSendResult: Hashable {
    let threadId: String
    let messageId: String
    let messageCount: Int
    let limit: Int
}

@MainActor
@Observable
final class MessageRequestInboxState {
    var requests: [MessageRequest] = []
    var oldRequests: [MessageRequest] = []
    var hiddenRequests: [MessageRequest] = []
    var outgoingRequests: [MessageRequest] = []
    var automaticFilterEnabled = true
    var customWords: [String] = []
    var isLoading = false
    var errorMessage: String?

    var visibleRequestCount: Int { requests.count }
}

@MainActor
final class MessageRequestService: ObservableObject {
    static let messageLimit = 5

    private let db = Firestore.firestore()
    private let encryptionService = EncryptionService.shared
    let state = MessageRequestInboxState()

    @Published var pendingRequests: [MessageRequest] = []
    @Published var oldRequests: [MessageRequest] = []
    @Published var hiddenRequests: [MessageRequest] = []
    @Published var outgoingPendingRequests: [MessageRequest] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var listeners: [String: ListenerRegistration] = [:]
    private var authHandle: AuthStateDidChangeListenerHandle?
    private var incomingGeneration = UUID()
    private var incomingDocuments: [QueryDocumentSnapshot] = []

    init() {
        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard user == nil else { return }
            Task { @MainActor [weak self] in
                self?.removeAllListeners()
                self?.publishIncoming([])
                self?.outgoingPendingRequests = []
                self?.state.outgoingRequests = []
                self?.setLoading(false)
                self?.setError(nil)
            }
        }
    }

    deinit {
        if let authHandle { Auth.auth().removeStateDidChangeListener(authHandle) }
        listeners.values.forEach { $0.remove() }
    }

    func removeAllListeners() {
        listeners.values.forEach { $0.remove() }
        listeners.removeAll()
    }

    func listenToPendingRequests(for userId: String) {
        listeners["incoming"]?.remove()
        listeners["preferences"]?.remove()
        incomingGeneration = UUID()
        let generation = incomingGeneration

        // V2 se particiona localmente en Solicitudes/Antiguas/Ocultas.
        listeners["incoming"] = db.collection("messageRequests")
            .whereField("receiverId", isEqualTo: userId)
            .whereField("status", isEqualTo: MessageRequest.RequestStatus.pending.rawValue)
            .order(by: "timestamp", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor [weak self] in
                    guard let self, generation == self.incomingGeneration else { return }
                    if let error {
                        if Auth.auth().currentUser == nil {
                            self.publishIncoming([])
                            self.setError(nil)
                        } else {
                            self.setError(error.localizedDescription)
                        }
                        return
                    }
                    self.incomingDocuments = snapshot?.documents ?? []
                    let hydrated = await self.hydrateRequests(self.incomingDocuments)
                    guard generation == self.incomingGeneration else { return }
                    self.publishIncoming(hydrated)
                }
            }

        listeners["preferences"] = db.collection("users")
            .document(userId)
            .collection("messageRequestPreferences")
            .document("settings")
            .addSnapshotListener { [weak self] snapshot, _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if snapshot?.exists != true {
                        try? await self.db.collection("users").document(userId)
                            .collection("messageRequestPreferences").document("settings")
                            .setData([
                                "automaticFilterEnabled": true,
                                "customWords": [String](),
                                "updatedAt": FieldValue.serverTimestamp()
                            ], merge: true)
                    }
                    let data = snapshot?.data() ?? [:]
                    self.state.automaticFilterEnabled = data["automaticFilterEnabled"] as? Bool ?? true
                    self.state.customWords = data["customWords"] as? [String] ?? []
                    let hydrated = await self.hydrateRequests(self.incomingDocuments)
                    self.publishIncoming(hydrated)
                }
            }
    }

    func listenToOutgoingPendingRequests(for userId: String) {
        listeners["outgoing"]?.remove()
        listeners["outgoing"] = db.collection("users")
            .document(userId)
            .collection("messageRequestOutbox")
            .whereField("status", isEqualTo: MessageRequest.RequestStatus.pending.rawValue)
            .order(by: "lastActivityAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let error {
                        if Auth.auth().currentUser != nil { self.setError(error.localizedDescription) }
                        return
                    }
                    let requests = await self.hydrateOutgoingRequests(snapshot?.documents ?? [], senderId: userId)
                    self.outgoingPendingRequests = requests
                    self.state.outgoingRequests = requests
                }
            }
    }

    func saveHiddenWords(_ words: [String], automaticFilterEnabled: Bool) async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw serviceError(code: 401, key: "messaging.error.notAuthenticated")
        }
        let normalized = Array(Set(words.compactMap(Self.normalizedWord))).sorted().prefix(100)
        try await db.collection("users").document(userId)
            .collection("messageRequestPreferences").document("settings")
            .setData([
                "automaticFilterEnabled": automaticFilterEnabled,
                "customWords": Array(normalized),
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)
    }

    func loadHiddenWordsPreferences() async throws -> (automatic: Bool, words: [String]) {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw serviceError(code: 401, key: "messaging.error.notAuthenticated")
        }
        let data = try await db.collection("users").document(userId)
            .collection("messageRequestPreferences").document("settings")
            .getDocument().data() ?? [:]
        let automatic = data["automaticFilterEnabled"] as? Bool ?? true
        let words = data["customWords"] as? [String] ?? []
        state.automaticFilterEnabled = automatic
        state.customWords = words
        return (automatic, words)
    }

    func resolveRoute(
        to receiverId: String,
        interaction: MessageRequestInteractionContext = .general,
        reserve: Bool = true
    ) async throws -> DirectMessageRoute {
        guard !receiverId.isEmpty else { throw serviceError(code: 400, key: "messaging.error.invalidRecipient") }
        let json = try await post(
            endpoint: "routeDirectMessageV2",
            payload: [
                "recipientId": receiverId,
                "interactionKind": interaction.kind.rawValue,
                "context": interaction.payload,
                "reserve": reserve
            ]
        )
        switch json["result"] as? String {
        case "conversation":
            guard let id = json["conversationId"] as? String, !id.isEmpty else { throw serviceError() }
            return .conversation(id: id)
        case "conversationDraft":
            guard let id = json["threadId"] as? String, !id.isEmpty else { throw serviceError() }
            return .conversationDraft(threadId: id)
        case "outgoingRequest":
            guard let id = json["threadId"] as? String, !id.isEmpty else { throw serviceError() }
            return .outgoingRequest(
                threadId: id,
                messageCount: json["messageCount"] as? Int ?? 0,
                limit: json["limit"] as? Int ?? Self.messageLimit,
                cryptoConfigured: json["cryptoConfigured"] as? Bool ?? false
            )
        case "incomingRequest":
            guard let id = json["threadId"] as? String, !id.isEmpty else { throw serviceError() }
            return .incomingRequest(threadId: id, messageCount: json["messageCount"] as? Int ?? 0)
        default:
            throw serviceError()
        }
    }

    func activateConversationDraft(to receiverId: String, threadId: String) async throws -> String {
        guard let senderId = Auth.auth().currentUser?.uid,
              !receiverId.isEmpty,
              !threadId.isEmpty else {
            throw serviceError(code: 401, key: "messaging.error.notAuthenticated")
        }
        let wrapped = try await encryptionService.prepareMessageRequestKey(
            threadId: threadId,
            participantIds: [senderId, receiverId].sorted(),
            wrappedBy: senderId
        )
        let serializable = wrapped.mapValues { value in value.compactMapValues { $0 as? String } }
        do {
            let json = try await post(
                endpoint: "activateDirectConversationV2",
                payload: [
                    "recipientId": receiverId,
                    "threadId": threadId,
                    "wrappedKeys": serializable
                ]
            )
            guard let conversationId = json["conversationId"] as? String, !conversationId.isEmpty else {
                throw serviceError()
            }
            if json["usedExistingContext"] as? Bool == true || conversationId != threadId {
                await encryptionService.deleteConversationKeys(for: threadId)
            }
            return conversationId
        } catch {
            await encryptionService.deleteConversationKeys(for: threadId)
            throw error
        }
    }

    func appendRequestMessage(
        to receiverId: String,
        text: String,
        messageType: MessageType = .text,
        interaction: MessageRequestInteractionContext = .general,
        encryptedMedia: [String: Any]? = nil,
        expirationDate: Date? = nil,
        allowReplay: Bool = false
    ) async throws -> MessageRequestSendResult {
        guard let senderId = Auth.auth().currentUser?.uid else {
            throw serviceError(code: 401, key: "messaging.error.notAuthenticated")
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || encryptedMedia != nil else {
            throw serviceError(code: 400, key: "messaging.error.emptyMessage")
        }
        guard Self.allowedPendingTypes.contains(messageType) else {
            throw serviceError(code: 400, key: "messaging.message.unsupportedFile")
        }

        let prepared = try await prepareOutgoingThread(
            senderId: senderId,
            receiverId: receiverId,
            interaction: interaction
        )
        let threadId = prepared.threadId
        let currentCount = prepared.messageCount

        let ciphertext = try await encryptionService.encryptChatMessage(text, for: threadId)
        let messageId = UUID().uuidString
        var message: [String: Any] = [
            "id": messageId,
            "clientNonce": messageId,
            "ciphertext": ciphertext,
            "type": messageType.rawValue,
            "context": interaction.payload,
            "allowReplay": allowReplay
        ]
        if let encryptedMedia { message["media"] = encryptedMedia }
        if let expirationDate { message["expirationDateMillis"] = Int64(expirationDate.timeIntervalSince1970 * 1_000) }
        let json = try await post(endpoint: "appendMessageRequestV2", payload: ["threadId": threadId, "message": message])
        return MessageRequestSendResult(
            threadId: threadId,
            messageId: json["messageId"] as? String ?? messageId,
            messageCount: json["messageCount"] as? Int ?? currentCount + 1,
            limit: json["limit"] as? Int ?? Self.messageLimit
        )
    }

    func appendEphemeralMedia(
        to receiverId: String,
        data: Data,
        mediaType: EnhancedCameraPickerView.MediaType,
        allowReplay: Bool,
        interaction: MessageRequestInteractionContext = .general,
        expiresAt: Date? = nil
    ) async throws -> MessageRequestSendResult {
        guard let senderId = Auth.auth().currentUser?.uid else {
            throw serviceError(code: 401, key: "messaging.error.notAuthenticated")
        }
        let prepared = try await prepareOutgoingThread(
            senderId: senderId,
            receiverId: receiverId,
            interaction: interaction
        )
        let messageId = UUID().uuidString
        let isVideo = mediaType == .video
        let messageType: MessageType = expiresAt == nil
            ? (isVideo ? .viewOnceVideo : .viewOnceImage)
            : .ephemeral
        let contentType = isVideo ? "video/mp4" : "image/jpeg"
        let fileExtension = isVideo ? "mp4" : "jpg"
        let encrypted = try await encryptionService.encryptChatMedia(
            data,
            for: prepared.threadId,
            messageId: messageId,
            purpose: .primary,
            contentType: contentType,
            fileExtension: fileExtension
        )
        let storagePath = "directThreads/\(prepared.threadId)/\(messageId)/media.enc"
        let target = StorageUploadTarget(
            objectPath: storagePath,
            contentType: "application/octet-stream",
            customMetadata: [
                "ownerId": senderId,
                "threadId": prepared.threadId,
                "messageId": messageId,
                "encrypted": "true"
            ]
        )
        do {
            _ = try await MediaUploadService.shared.uploadEncryptedBlob(target: target, data: encrypted.ciphertext)
            let ciphertext = try await encryptionService.encryptChatMessage(
                isVideo ? "🎥" : "📷",
                for: prepared.threadId
            )
            var media = encrypted.metadata.firestoreData
            media["storagePath"] = storagePath
            media["kind"] = isVideo ? "video" : "image"
            var message: [String: Any] = [
                "id": messageId,
                "clientNonce": messageId,
                "ciphertext": ciphertext,
                "type": messageType.rawValue,
                "context": interaction.payload,
                "media": media,
                "allowReplay": allowReplay
            ]
            if let expiresAt {
                message["expirationDateMillis"] = Int64(expiresAt.timeIntervalSince1970 * 1_000)
            }
            let json = try await post(endpoint: "appendMessageRequestV2", payload: [
                "threadId": prepared.threadId,
                "message": message
            ])
            return MessageRequestSendResult(
                threadId: prepared.threadId,
                messageId: json["messageId"] as? String ?? messageId,
                messageCount: json["messageCount"] as? Int ?? prepared.messageCount + 1,
                limit: json["limit"] as? Int ?? Self.messageLimit
            )
        } catch {
            try? await Storage.storage().reference(withPath: storagePath).delete()
            throw error
        }
    }

    func sendMessageRequest(
        to receiverId: String,
        message: String,
        messageType: MessageType = .text,
        mediaUrl: String? = nil,
        thumbnailUrl: String? = nil,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        setLoading(true)
        Task { @MainActor in
            do {
                if mediaUrl != nil || thumbnailUrl != nil {
                    throw serviceError(code: 400, key: "messaging.message.unsupportedFile")
                }
                _ = try await appendRequestMessage(to: receiverId, text: message, messageType: messageType)
                setLoading(false)
                completion(.success(()))
            } catch {
                setLoading(false)
                setError(error.localizedDescription)
                completion(.failure(error))
            }
        }
    }

    func acceptRequest(_ request: MessageRequest, completion: @escaping (Result<AcceptMessageRequestResult, Error>) -> Void) {
        guard let requestId = request.id else {
            completion(.failure(serviceError(code: 400, key: "messageRequests.acceptError.notAvailable")))
            return
        }
        guard Auth.auth().currentUser?.uid == request.receiverId else {
            completion(.failure(serviceError(code: 403, key: "messageRequests.acceptError.forbidden")))
            return
        }
        setLoading(true)
        Task { @MainActor in
            do {
                let result = try await acceptIncomingThread(threadId: requestId)
                setLoading(false)
                completion(.success(result))
            } catch {
                setLoading(false)
                completion(.failure(error))
            }
        }
    }

    func acceptIncomingThread(threadId: String) async throws -> AcceptMessageRequestResult {
        guard !threadId.isEmpty else {
            throw serviceError(code: 400, key: "messageRequests.acceptError.notAvailable")
        }
        let json = try await post(endpoint: "acceptMessageRequestV2", payload: ["threadId": threadId])
        guard let conversationId = json["conversationId"] as? String else { throw serviceError() }
        let ids = json["messageIds"] as? [String] ?? []
        return AcceptMessageRequestResult(
            conversationId: conversationId,
            messageId: json["messageId"] as? String ?? ids.first ?? "",
            messageIds: ids
        )
    }

    func rejectRequest(_ request: MessageRequest, completion: @escaping (Result<Void, Error>) -> Void) {
        manage(request, action: "reject", completion: completion)
    }

    func cancelRequest(_ request: MessageRequest, completion: @escaping (Result<Void, Error>) -> Void) {
        manage(request, action: "cancel", completion: completion)
    }

    func cancelRequest(threadId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        manageThread(threadId, action: "cancel", completion: completion)
    }

    func blockUser(_ request: MessageRequest, completion: @escaping (Result<Void, Error>) -> Void) {
        manage(request, action: "block", completion: completion)
    }

    func reportRequest(_ request: MessageRequest, completion: @escaping (Result<Void, Error>) -> Void) {
        manage(request, action: "report", completion: completion)
    }

    func moveRequest(
        _ request: MessageRequest,
        to folder: MessageRequestFolder,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        manage(request, action: folder == .hidden ? "moveToHidden" : "moveToRequests", completion: completion)
    }

    func consumePendingEphemeral(threadId: String, messageId: String) async throws {
        _ = try await post(endpoint: "consumePendingEphemeralV2", payload: [
            "threadId": threadId,
            "messageId": messageId
        ])
    }

    func loadIncomingRequest(threadId: String) async throws -> MessageRequest {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw serviceError(code: 401, key: "messaging.error.notAuthenticated")
        }
        let snapshot = try await db.collection("messageRequests").document(threadId).getDocument()
        guard let data = snapshot.data(),
              data["receiverId"] as? String == currentUserId,
              let base = MessageRequest.fromFirestoreData(data, id: threadId) else {
            throw serviceError(code: 404, key: "messageRequests.acceptError.notAvailable")
        }
        let hydrated = await hydrateTimeline(threadId: threadId, base: base)
        let manualFolder = data["manualFolder"] as? String
        if manualFolder != MessageRequestFolder.normal.rawValue,
           state.automaticFilterEnabled,
           hydrated.messages.contains(where: { containsCustomHiddenWord($0.content) }) {
            return copy(hydrated, folder: .hidden)
        }
        return hydrated
    }

    func loadOutgoingRequest(threadId: String, receiverId: String) async throws -> MessageRequest {
        guard let senderId = Auth.auth().currentUser?.uid else {
            throw serviceError(code: 401, key: "messaging.error.notAuthenticated")
        }
        let snapshot = try await db.collection("users").document(senderId)
            .collection("messageRequestOutbox").document(threadId).getDocument()
        guard let data = snapshot.data(), data["receiverId"] as? String == receiverId else {
            throw serviceError(code: 404, key: "messageRequests.acceptError.notAvailable")
        }
        let timestamp = (data["lastActivityAt"] as? Timestamp)?.dateValue() ?? Date()
        let base = MessageRequest(
            id: threadId,
            senderId: senderId,
            senderUsername: data["receiverUsername"] as? String,
            senderProfileImagePath: data["receiverProfileImagePath"] as? String,
            receiverId: receiverId,
            message: "",
            timestamp: timestamp,
            status: .pending,
            messageType: .text,
            mediaUrl: nil,
            thumbnailUrl: nil,
            messageCount: data["messageCount"] as? Int ?? 0,
            schemaVersion: data["schemaVersion"] as? Int ?? 2,
            lastActivityAt: timestamp
        )
        return await hydrateTimeline(threadId: threadId, base: base)
    }

    func getPendingRequestCount(for userId: String, completion: @escaping (Int) -> Void) {
        completion(Auth.auth().currentUser?.uid == userId ? pendingRequests.count : 0)
    }

    func canSendRequest(from senderId: String, to receiverId: String, completion: @escaping (Bool) -> Void) {
        guard Auth.auth().currentUser?.uid == senderId else { completion(false); return }
        Task { @MainActor in
            do {
                switch try await resolveRoute(to: receiverId, reserve: false) {
                case let .outgoingRequest(_, count, limit, _): completion(count < limit)
                case .conversation, .conversationDraft, .incomingRequest: completion(true)
                }
            } catch {
                completion(false)
            }
        }
    }

    private func manage(_ request: MessageRequest, action: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let threadId = request.id else { completion(.failure(serviceError(code: 400))); return }
        manageThread(threadId, action: action, completion: completion)
    }

    private func manageThread(_ threadId: String, action: String, completion: @escaping (Result<Void, Error>) -> Void) {
        Task { @MainActor in
            do {
                _ = try await post(endpoint: "manageMessageRequestV2", payload: ["threadId": threadId, "action": action])
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }
    }

    private func prepareOutgoingThread(
        senderId: String,
        receiverId: String,
        interaction: MessageRequestInteractionContext
    ) async throws -> (threadId: String, messageCount: Int) {
        let route = try await resolveRoute(to: receiverId, interaction: interaction)
        let threadId: String
        let messageCount: Int
        let cryptoConfigured: Bool
        switch route {
        case let .outgoingRequest(id, count, _, configured):
            threadId = id
            messageCount = count
            cryptoConfigured = configured
        case .conversation, .conversationDraft:
            throw NSError(
                domain: "MessageRequest.RouteConversation",
                code: 409,
                userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("chat.request.error.notAllowed", comment: "")]
            )
        case .incomingRequest:
            throw NSError(
                domain: "MessageRequest.IncomingMustAccept",
                code: 409,
                userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("messageRequests.accept", comment: "")]
            )
        }
        guard messageCount < Self.messageLimit else {
            throw serviceError(code: 429, key: "messageRequests.limitReached")
        }
        if !cryptoConfigured {
            let wrapped = try await encryptionService.prepareMessageRequestKey(
                threadId: threadId,
                participantIds: [senderId, receiverId].sorted(),
                wrappedBy: senderId
            )
            let serializable = wrapped.mapValues { value in value.compactMapValues { $0 as? String } }
            let configuration = try await post(endpoint: "configureMessageRequestV2", payload: [
                "threadId": threadId,
                "wrappedKeys": serializable
            ])
            if configuration["usedExistingContext"] as? Bool == true {
                await encryptionService.deleteConversationKeys(for: threadId)
            }
        }
        return (threadId, messageCount)
    }

    private func hydrateOutgoingRequests(
        _ documents: [QueryDocumentSnapshot],
        senderId: String
    ) async -> [MessageRequest] {
        var result: [MessageRequest] = []
        for document in documents {
            let data = document.data()
            guard let receiverId = data["receiverId"] as? String else { continue }
            guard (data["messageCount"] as? Int ?? 0) > 0 else { continue }
            let timestamp = (data["lastActivityAt"] as? Timestamp)?.dateValue() ?? Date()
            let base = MessageRequest(
                id: document.documentID,
                senderId: senderId,
                senderUsername: data["receiverUsername"] as? String,
                senderProfileImagePath: data["receiverProfileImagePath"] as? String,
                receiverId: receiverId,
                message: "",
                timestamp: timestamp,
                status: .pending,
                messageType: .text,
                mediaUrl: nil,
                thumbnailUrl: nil,
                messageCount: data["messageCount"] as? Int ?? 0,
                schemaVersion: data["schemaVersion"] as? Int ?? 2,
                lastActivityAt: timestamp
            )
            result.append(await hydrateTimeline(threadId: document.documentID, base: base))
        }
        return result.sorted { $0.lastActivityAt > $1.lastActivityAt }
    }

    private func hydrateRequests(_ documents: [QueryDocumentSnapshot]) async -> [MessageRequest] {
        var result: [MessageRequest] = []
        for document in documents {
            if let request = await hydrateRequest(document) {
                result.append(request)
            }
        }
        return result.sorted { $0.lastActivityAt > $1.lastActivityAt }
    }

    private func hydrateRequest(_ document: QueryDocumentSnapshot) async -> MessageRequest? {
        let data = document.data()
        guard let base = MessageRequest.fromFirestoreData(data, id: document.documentID) else { return nil }
        guard base.schemaVersion >= 2, base.messageCount > 0 else { return nil }

        let hydrated = await hydrateTimeline(threadId: document.documentID, base: base)
        let manualFolder = data["manualFolder"] as? String
        var folder = base.folder
        if manualFolder != MessageRequestFolder.normal.rawValue,
           state.automaticFilterEnabled,
           hydrated.messages.contains(where: { containsCustomHiddenWord($0.content) }) {
            folder = .hidden
        }
        return copy(hydrated, folder: folder)
    }

    private func hydrateTimeline(threadId: String, base: MessageRequest) async -> MessageRequest {
        do {
            let snapshot = try await db.collection("messageRequests").document(threadId).collection("messages")
                .order(by: "sequence", descending: false)
                .limit(to: Self.messageLimit)
                .getDocuments()
            var messages: [MessageRequestMessage] = []
            for child in snapshot.documents {
                let value = child.data()
                guard let ciphertext = value["content"] as? String else { continue }
                let decrypted: String
                do {
                    decrypted = try await encryptionService.decryptChatMessageStrict(ciphertext, for: threadId)
                } catch {
                    AppLog.error("MessageRequestService: no se pudo descifrar \(threadId)/\(child.documentID): \(error.localizedDescription)")
                    continue
                }
                let type = MessageType(rawValue: value["type"] as? String ?? "") ?? .text
                let context = value["context"] as? [String: Any] ?? [:]
                let encryptedMedia = value["encryptedMedia"] as? [String: Any]
                messages.append(MessageRequestMessage(
                    id: child.documentID,
                    senderId: value["senderId"] as? String ?? base.senderId,
                    content: decrypted,
                    timestamp: (value["timestamp"] as? Timestamp)?.dateValue() ?? base.timestamp,
                    type: type,
                    sequence: value["sequence"] as? Int ?? messages.count + 1,
                    mediaUrl: encryptedMedia?["storagePath"] as? String ?? value["mediaUrl"] as? String,
                    thumbnailUrl: encryptedMedia?["thumbnailStoragePath"] as? String,
                    mediaEncryption: encryptedMedia.flatMap { EncryptedChatMediaMetadata(map: $0) },
                    contextKind: value["contextKind"] as? String ?? context["kind"] as? String ?? "general",
                    storyId: context["storyId"] as? String,
                    storyOwnerId: context["storyOwnerId"] as? String,
                    sharedContentId: context["sharedContentId"] as? String,
                    sharedContentOwnerId: context["sharedContentOwnerId"] as? String,
                    expirationDate: (value["expirationDate"] as? Timestamp)?.dateValue(),
                    isViewOnce: value["isViewOnce"] as? Bool ?? false,
                    allowReplay: value["allowReplay"] as? Bool ?? false
                ))
            }
            AppLog.debug("MessageRequestService: \(messages.count) mensajes descifrados para \(threadId)")
            let last = messages.last
            return MessageRequest(
                id: base.id,
                senderId: base.senderId,
                senderUsername: base.senderUsername,
                senderProfileImagePath: base.senderProfileImagePath,
                receiverId: base.receiverId,
                message: last?.content ?? "",
                timestamp: base.timestamp,
                status: base.status,
                messageType: last?.type ?? base.messageType,
                mediaUrl: last?.mediaUrl,
                thumbnailUrl: last?.thumbnailUrl,
                folder: base.folder,
                messages: messages,
                messageCount: base.messageCount,
                schemaVersion: base.schemaVersion,
                generation: base.generation,
                lastActivityAt: base.lastActivityAt
            )
        } catch {
            setError(error.localizedDescription)
            return base
        }
    }

    private func copy(_ request: MessageRequest, folder: MessageRequestFolder) -> MessageRequest {
        MessageRequest(
            id: request.id,
            senderId: request.senderId,
            senderUsername: request.senderUsername,
            senderProfileImagePath: request.senderProfileImagePath,
            receiverId: request.receiverId,
            message: request.message,
            timestamp: request.timestamp,
            status: request.status,
            messageType: request.messageType,
            mediaUrl: request.mediaUrl,
            thumbnailUrl: request.thumbnailUrl,
            folder: folder,
            messages: request.messages,
            messageCount: request.messageCount,
            schemaVersion: request.schemaVersion,
            generation: request.generation,
            lastActivityAt: request.lastActivityAt
        )
    }

    func decryptedPendingMediaURL(
        threadId: String,
        message: MessageRequestMessage
    ) async throws -> URL {
        guard !message.isExpired,
              let storagePath = message.mediaUrl,
              let metadata = message.mediaEncryption else {
            throw serviceError(code: 410, key: "messageRequests.media.unavailable")
        }
        let encrypted = try await Storage.storage().reference(withPath: storagePath)
            .data(maxSize: 85 * 1_024 * 1_024)
        let decrypted = try await encryptionService.decryptChatMedia(
            encrypted,
            metadata: metadata,
            for: threadId,
            messageId: message.id
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pending-request-\(message.id).\(metadata.fileExtension)")
        try decrypted.write(to: url, options: .atomic)
        return url
    }

    private func publishIncoming(_ requests: [MessageRequest]) {
        pendingRequests = requests.filter { $0.folder == .normal }
        oldRequests = requests.filter { $0.folder == .old }
        hiddenRequests = requests.filter { $0.folder == .hidden }
        state.requests = pendingRequests
        state.oldRequests = oldRequests
        state.hiddenRequests = hiddenRequests
    }

    private func containsCustomHiddenWord(_ text: String) -> Bool {
        let normalizedText = Self.normalizedText(text)
        return state.customWords.compactMap(Self.normalizedWord).contains { normalizedText.contains($0) }
    }

    private static func normalizedWord(_ value: String) -> String? {
        let normalized = normalizedText(value).trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private static func normalizedText(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
    }

    private static let allowedPendingTypes: Set<MessageType> = [
        .text, .ephemeral, .sharedMoment, .sharedStory, .sharedProfile, .viewOnceImage, .viewOnceVideo
    ]

    private func post(endpoint: String, payload: [String: Any]) async throws -> [String: Any] {
        guard let currentUser = Auth.auth().currentUser else {
            throw serviceError(code: 401, key: "messaging.error.notAuthenticated")
        }
        let token = try await currentUser.getIDToken()
        guard let projectId = FirebaseApp.app()?.options.projectID,
              let url = URL(string: "https://europe-southwest1-\(projectId).cloudfunctions.net/\(endpoint)") else {
            throw serviceError()
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw serviceError() }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(http.statusCode) else {
            let errorCode = json["errorCode"] as? String ?? "REQUEST_V2_FAILED"
            throw NSError(
                domain: "MessageRequestV2",
                code: http.statusCode,
                userInfo: [
                    NSLocalizedDescriptionKey: localizedError(for: errorCode),
                    "errorCode": errorCode
                ]
            )
        }
        return json
    }

    private func setLoading(_ value: Bool) {
        isLoading = value
        state.isLoading = value
    }

    private func setError(_ value: String?) {
        errorMessage = value
        state.errorMessage = value
    }

    private func serviceError(code: Int = -1, key: String = "messaging.error.serviceUnavailable") -> NSError {
        NSError(
            domain: "MessageRequestV2",
            code: code,
            userInfo: [NSLocalizedDescriptionKey: NSLocalizedString(key, comment: "")]
        )
    }

    private func localizedError(for code: String) -> String {
        let key: String
        switch code {
        case "DAILY_LIMIT": key = "messageRequests.error.dailyLimit"
        case "MESSAGE_LIMIT": key = "messageRequests.limitReached"
        case "COOLDOWN": key = "messageRequests.error.cooldown"
        case "DENIED", "REQUEST_FORBIDDEN", "SAFETY_RESTRICTED": key = "messageRequests.error.denied"
        case "INACTIVE_USER": key = "messageRequests.error.inactiveUser"
        case "EPHEMERAL_EXPIRED", "EPHEMERAL_CONSUMED": key = "messageRequests.media.unavailable"
        default: key = "messaging.error.serviceUnavailable"
        }
        return NSLocalizedString(key, comment: "")
    }
}

extension MessageRequest {
    static func fromFirestoreData(_ data: [String: Any], id: String) -> MessageRequest? {
        guard let senderId = (data["initiatorId"] ?? data["senderId"]) as? String,
              let receiverId = data["receiverId"] as? String else { return nil }
        let statusRaw = (data["state"] ?? data["status"]) as? String ?? RequestStatus.pending.rawValue
        guard let status = RequestStatus(rawValue: statusRaw) else { return nil }
        let timestamp = (data["timestamp"] as? Timestamp)?.dateValue()
            ?? (data["createdAt"] as? Timestamp)?.dateValue()
            ?? Date()
        let lastActivity = (data["lastActivityAt"] as? Timestamp)?.dateValue() ?? timestamp
        let type = MessageType(rawValue: data["lastMessageType"] as? String
            ?? data["messageType"] as? String
            ?? MessageType.text.rawValue) ?? .text
        return MessageRequest(
            id: id,
            senderId: senderId,
            senderUsername: data["senderUsername"] as? String,
            senderProfileImagePath: data["senderProfileImagePath"] as? String,
            receiverId: receiverId,
            message: data["message"] as? String ?? "",
            timestamp: timestamp,
            status: status,
            messageType: type,
            mediaUrl: data["mediaUrl"] as? String,
            thumbnailUrl: data["thumbnailUrl"] as? String,
            folder: MessageRequestFolder(rawValue: data["folder"] as? String ?? "") ?? .normal,
            messageCount: data["messageCount"] as? Int,
            schemaVersion: data["schemaVersion"] as? Int ?? 1,
            generation: data["generation"] as? Int ?? 1,
            lastActivityAt: lastActivity
        )
    }
}
