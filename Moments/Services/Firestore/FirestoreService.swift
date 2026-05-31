import FirebaseFirestore
import Combine
import FirebaseAuth
import Kingfisher

class FirestoreService: ObservableObject {
    static let shared = FirestoreService() // Singleton
    let db: Firestore
    @Published var savedMomentIds: [String] = []
    @Published var savedMomentsLoadedForUserId: String?
    private var followingCache: [String: Bool] = [:]
    private var lastCacheUpdate: Date = Date() // Added for reactive saved moments
    let storySummaryRebuildQueue = DispatchQueue(label: "story.summary.rebuild.queue")
    var storySummaryRebuildInFlight: Set<String> = []
    var storySummaryLastRebuildAttempt: [String: Date] = [:]
    let storySummaryRebuildCooldown: TimeInterval = 60

    init() {
        db = Firestore.firestore()
        self.db.enableNetwork()
    }

    func updateMomentDetails(
        userId: String,
        momentId: String,
        content: String,
        audience: String,
        customListId: String?,
        customViewers: [String]?,
        taggedUsers: [String],
        mentionedUsers: [String],
        location: String?,
        locationCoordinate: Moment.LocationCoordinate?,
        mediaItems: [MediaItem]? = nil,
        completion: @escaping (Error?) -> Void
    ) {
        let momentRef = db.collection("users").document(userId).collection("moments").document(momentId)
        let encoder = Firestore.Encoder()

        var updateData: [String: Any] = [
            "content": content,
            "audience": audience,
            "updatedAt": FieldValue.serverTimestamp()
        ]

        if let customListId, !customListId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updateData["customListId"] = customListId
        } else {
            updateData["customListId"] = FieldValue.delete()
        }

        if taggedUsers.isEmpty {
            updateData["taggedUsers"] = FieldValue.delete()
        } else {
            updateData["taggedUsers"] = taggedUsers
        }

        if mentionedUsers.isEmpty {
            updateData["mentionedUsers"] = FieldValue.delete()
        } else {
            updateData["mentionedUsers"] = mentionedUsers
        }

        if let location, !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updateData["location"] = location
        } else {
            updateData["location"] = FieldValue.delete()
        }

        if let locationCoordinate {
            updateData["locationCoordinate"] = [
                "latitude": locationCoordinate.latitude,
                "longitude": locationCoordinate.longitude
            ]
        } else {
            updateData["locationCoordinate"] = FieldValue.delete()
        }

        if let mediaItems {
            updateData["mediaItems"] = serializedMediaItems(mediaItems, encoder: encoder)
        }

        momentRef.updateData(updateData) { error in
            if let error {
                completion(error)
                return
            }

            if audience == ContentAudience.custom.rawValue,
               let customViewers,
               !customViewers.isEmpty {
                self.saveCustomAudienceForContent(
                    contentType: "moment",
                    authorId: userId,
                    allowedUsers: customViewers
                ) { audienceError in
                    completion(audienceError)
                }
            } else {
                completion(nil)
            }
        }
    }

    func isUserPlus(userId: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        self.db.collection("users").document(userId).getDocument(source: .default, completion: { snapshot, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let data = snapshot?.data(),
                  let isPlus = data["isPlusSubscriber"] as? Bool else {
                completion(.success(false))
                return
            }
            completion(.success(isPlus))
        })
    }

    // ✅ FUNCIÓN fetchComments CORREGIDA - Incluye TODOS los campos necesarios
    // ✅ MÉTODO CORREGIDO para FirestoreService.swift - REEMPLAZAR el método existente
    func addReaction(to momentId: String, reaction: String, userId: String, authorId: String, completion: @escaping (Error?) -> Void) {
        // ✅ Optimistic UI: Actualizar caché local en background (no bloquea el return)
        Task(priority: .background) { @MainActor in
            LocalPersistenceService.shared.toggleMomentReactionLocally(momentId: momentId, reaction: reaction, userId: userId)
        }

        // ✅ OFFLINE SUPPORT: Si no hay conexión, persistir acción y retornar éxito optimista
        if !NetworkMonitor.shared.isConnected {
            let payload = ReactionPayload(
                momentId: momentId,
                reaction: reaction,
                authorId: authorId,
                userId: userId
            )

            if let data = try? JSONEncoder().encode(payload) {
                let action = CachedAction(
                    id: UUID().uuidString,
                    type: CachedAction.ActionType.reaction.rawValue,
                    payloadData: data
                )

                Task {
                    await LocalPersistenceService.shared.saveAction(action)
                    print("💾 FirestoreService: Reacción guardada en outbox (offline)")
                    completion(nil) // Éxito optimista
                }
                return
            }
        }

        // ✅ CAMBIO PRINCIPAL: Usar la subcolección de reacciones
        let reactionRef = db.collection("users").document(authorId)
            .collection("moments").document(momentId)
            .collection("reactions").document(userId) // Usar userId como ID del documento

        // Primero verificar si ya existe una reacción de este usuario
        reactionRef.getDocument { snapshot, error in
            if let error = error {
                completion(error)
                return
            }

            if let document = snapshot, document.exists {
                // Ya existe una reacción, verificar si es la misma
                let existingData = document.data() ?? [:]
                let existingReaction = existingData["reactionType"] as? String

                if existingReaction == reaction {
                    // Es la misma reacción, removerla
                    reactionRef.delete { error in
                        if let error = error {
                            completion(error)
                        } else {
                            // ✅ LIMPIEZA DE NOTIFICACIÓN (Deshacer reacción)
                            if userId != authorId {
                                Task { @MainActor in
                                    NotificationService.shared.removeNotification(
                                        type: .reaction,
                                        senderId: userId,
                                        recipientId: authorId,
                                        momentId: momentId,
                                        reaction: reaction
                                    )
                                }
                            }
                            completion(nil)
                        }
                    }
                } else {
                    // Es diferente reacción, actualizarla
                    let reactionData: [String: Any] = [
                        "userId": userId,
                        "reactionType": reaction,
                        "timestamp": FieldValue.serverTimestamp()
                    ]

                    reactionRef.setData(reactionData) { error in
                        if let error = error {
                            completion(error)
                        } else {
                            // Eliminamos notificación manual: servidor se encarga
                            completion(nil)
                        }
                    }
                }
            } else {
                // No existe reacción, crear nueva
                let reactionData: [String: Any] = [
                    "userId": userId,
                    "reactionType": reaction,
                    "timestamp": FieldValue.serverTimestamp()
                ]

                reactionRef.setData(reactionData) { error in
                    if let error = error {
                        completion(error)
                    } else {
                        // Eliminamos notificación manual: servidor se encarga
                        completion(nil)
                    }
                }
            }
        }
    }

    // ✅ MÉTODO AUXILIAR para obtener contador de reacciones

    // MARK: - SISTEMA COMPLETO DE SEGUIMIENTO ACTUALIZADO

    func sendFollowRequest(currentUserId: String, targetUserId: String, completion: @escaping (Error?) -> Void) {
        guard currentUserId != targetUserId else {
            completion(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No puedes enviarte una solicitud a ti mismo"]))
            return
        }

        checkIfBlocked(currentUserId: currentUserId, targetUserId: targetUserId) { [weak self] isBlockedByCurrentUser, isCurrentUserBlocked, error in
            guard let self = self else { return }

            if let error = error {
                completion(error)
                return
            }

            if isBlockedByCurrentUser || isCurrentUserBlocked {
                completion(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No se puede enviar solicitud debido a bloqueos"]))
                return
            }

            self.isFollowing(currentUserId: currentUserId, targetUserId: targetUserId) { isFollowing in
                if isFollowing {
                    completion(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Ya sigues a este usuario"]))
                    return
                }

                self.checkExistingFollowRequest(senderId: currentUserId, recipientId: targetUserId) { existingRequest in
                    if let existingRequest = existingRequest {
                        switch existingRequest.status {
                        case .pending:
                            completion(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Ya tienes una solicitud pendiente"]))
                            return
                        case .rejected:
                            let timeSinceRejection = Date().timeIntervalSince(existingRequest.timestamp)
                            if timeSinceRejection < 86400 {
                                let remainingHours = Int((86400 - timeSinceRejection) / 3600)
                                completion(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Debes esperar \(remainingHours) horas para enviar otra solicitud"]))
                                return
                            }
                        case .accepted:
                            completion(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Ya sigues a este usuario"]))
                            return
                        case .cancelled:
                            break
                        }
                    }

                    self.fetchUserProfile(userId: targetUserId) { result in
                        switch result {
                        case .success(let targetUser):
                            if !targetUser.isPrivate {
                                self.performFollow(currentUserId: currentUserId, targetUserId: targetUserId, completion: completion)
                                return
                            }

                            self.fetchUserProfile(userId: currentUserId) { result in
                                switch result {
                                case .success(let currentUser):
                                    self.createFollowRequest(
                                        senderId: currentUserId,
                                        senderUsername: currentUser.username,
                                        recipientId: targetUserId,
                                        completion: completion
                                    )
                                case .failure(let error):
                                    completion(error)
                                }
                            }

                        case .failure(let error):
                            completion(error)
                        }
                    }
                }
            }
        }
    }

    private func createFollowRequest(senderId: String, senderUsername: String, recipientId: String, completion: @escaping (Error?) -> Void) {
        let followRequest = FollowRequest(
            senderId: senderId,
            senderUsername: senderUsername,
            recipientId: recipientId
        )

        do {
            let encoder = Firestore.Encoder()
            let requestData = try encoder.encode(followRequest)

            let batch = db.batch()

            let senderRequestRef = db.collection("users").document(senderId)
                .collection("sentFollowRequests").document(followRequest.id)
            batch.setData(requestData, forDocument: senderRequestRef)

            let recipientRequestRef = db.collection("users").document(recipientId)
                .collection("receivedFollowRequests").document(followRequest.id)
            batch.setData(requestData, forDocument: recipientRequestRef)

            batch.commit { error in
                completion(error)
            }
        } catch {
            completion(error)
        }
    }

    private func checkExistingFollowRequest(senderId: String, recipientId: String, completion: @escaping (FollowRequest?) -> Void) {
        db.collection("users").document(senderId).collection("sentFollowRequests")
            .whereField("recipientId", isEqualTo: recipientId)
            .order(by: "timestamp", descending: true)
            .limit(to: 1)
            .getDocuments { snapshot, error in
                if error != nil {
                    completion(nil)
                    return
                }

                guard let document = snapshot?.documents.first else {
                    completion(nil)
                    return
                }

                do {
                    let request = try document.data(as: FollowRequest.self)
                    completion(request)
                } catch {
                    completion(nil)
                }
            }
    }

    func acceptFollowRequest(notificationId: String, recipientId: String, senderId: String, completion: @escaping (Error?) -> Void) {
        getFollowRequestByUsers(senderId: senderId, recipientId: recipientId) { [weak self] request in
            guard let self = self, let request = request else {
                completion(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Solicitud no encontrada"]))
                return
            }

            guard request.status == .pending else {
                completion(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "La solicitud ya fue procesada"]))
                return
            }

            if let expirationDate = request.expirationDate, Date() > expirationDate {
                self.rejectFollowRequest(notificationId: notificationId, recipientId: recipientId, senderId: senderId) { _ in }
                completion(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "La solicitud ha expirado"]))
                return
            }

            self.performFollow(
                currentUserId: senderId,
                targetUserId: recipientId,
                sendNotification: false,
                acceptedFollowRequestId: request.id
            ) { error in
                if let error = error {
                    completion(error)
                    return
                }

                let batch = self.db.batch()

                // 1. Eliminar solicitud de sentFollowRequests del remitente
                let senderRequestRef = self.db.collection("users").document(senderId)
                    .collection("sentFollowRequests").document(request.id)
                batch.deleteDocument(senderRequestRef)

                // 2. Eliminar solicitud de receivedFollowRequests del destinatario
                let recipientRequestRef = self.db.collection("users").document(recipientId)
                    .collection("receivedFollowRequests").document(request.id)
                batch.deleteDocument(recipientRequestRef)

                // 3. Eliminar notificación de solicitud (doc de la fila + ID estable)
                let notificationsRef = self.db.collection("users").document(recipientId).collection("notifications")
                batch.deleteDocument(notificationsRef.document(notificationId))
                batch.deleteDocument(notificationsRef.document("followRequest_\(senderId)"))

                batch.commit { error in
                    if let error = error {
                        completion(error)
                        return
                    }

                    // El servidor crea la notificación requestAccepted desde onFollowerAdded.
                    completion(nil)
                }
            }
        }
    }

    func rejectFollowRequest(notificationId: String, recipientId: String, senderId: String, completion: @escaping (Error?) -> Void) {
        getFollowRequestByUsers(senderId: senderId, recipientId: recipientId) { [weak self] request in
            guard let self = self, let request = request else {
                completion(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Solicitud no encontrada"]))
                return
            }

            let batch = self.db.batch()

            // 1. Eliminar solicitud de sentFollowRequests del remitente
            let senderRequestRef = self.db.collection("users").document(senderId)
                .collection("sentFollowRequests").document(request.id)
            batch.deleteDocument(senderRequestRef)

            // 2. Eliminar solicitud de receivedFollowRequests del destinatario
            let recipientRequestRef = self.db.collection("users").document(recipientId)
                .collection("receivedFollowRequests").document(request.id)
            batch.deleteDocument(recipientRequestRef)

            // 3. Eliminar notificación (doc de la fila + ID estable)
            let notificationsRef = self.db.collection("users").document(recipientId).collection("notifications")
            batch.deleteDocument(notificationsRef.document(notificationId))
            batch.deleteDocument(notificationsRef.document("followRequest_\(senderId)"))

            batch.commit { error in
                if let error = error {
                    completion(error)
                } else {
                    completion(nil)
                }
            }
        }
    }

    func cancelFollowRequest(currentUserId: String, targetUserId: String, completion: @escaping (Error?) -> Void) {
        checkExistingFollowRequest(senderId: currentUserId, recipientId: targetUserId) { [weak self] request in
            guard let self = self, let request = request else {
                completion(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Solicitud no encontrada"]))
                return
            }

            guard request.status == .pending else {
                completion(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "La solicitud ya no está pendiente"]))
                return
            }

            let batch = self.db.batch()

            let senderRequestRef = self.db.collection("users").document(currentUserId)
                .collection("sentFollowRequests").document(request.id)
            batch.deleteDocument(senderRequestRef)

            let recipientRequestRef = self.db.collection("users").document(targetUserId)
                .collection("receivedFollowRequests").document(request.id)
            batch.deleteDocument(recipientRequestRef)

            let notificationRef = self.db.collection("users").document(targetUserId)
                .collection("notifications").document("followRequest_\(currentUserId)")
            batch.deleteDocument(notificationRef)

            batch.commit { error in
                completion(error)
            }
        }
    }

    private func getFollowRequestByUsers(senderId: String, recipientId: String, completion: @escaping (FollowRequest?) -> Void) {
        db.collection("users").document(recipientId).collection("receivedFollowRequests")
            .whereField("senderId", isEqualTo: senderId)
            .whereField("status", isEqualTo: FollowRequestStatus.pending.rawValue)
            .limit(to: 1)
            .getDocuments { snapshot, error in
                if error != nil {
                    completion(nil)
                    return
                }

                guard let document = snapshot?.documents.first else {
                    completion(nil)
                    return
                }

                do {
                    let request = try document.data(as: FollowRequest.self)
                    completion(request)
                } catch {
                    completion(nil)
                }
            }
    }

    private func updateFollowRequestStatus(requestId: String, senderId: String, recipientId: String, newStatus: FollowRequestStatus, completion: @escaping (Error?) -> Void) {
        let batch = db.batch()

        let senderRequestRef = db.collection("users").document(senderId)
            .collection("sentFollowRequests").document(requestId)
        batch.updateData(["status": newStatus.rawValue], forDocument: senderRequestRef)

        let recipientRequestRef = db.collection("users").document(recipientId)
            .collection("receivedFollowRequests").document(requestId)
        batch.updateData(["status": newStatus.rawValue], forDocument: recipientRequestRef)

        batch.commit { error in
            if let error = error {
                completion(error)
            } else {
                completion(nil)
            }
        }
    }

    // MARK: - FUNCIÓN FOLLOWUSER ACTUALIZADA CON CACHE MANAGEMENT
    func followUser(currentUserId: String, targetUserId: String, completion: @escaping (Error?) -> Void) {
        // ✅ Optimistic UI: Actualizar conexiones localmente (Low priority background)
        Task(priority: .background) { @MainActor in
            LocalPersistenceService.shared.toggleFollowLocally(currentUserId: currentUserId, targetUserId: targetUserId, isFollow: true)
        }

        guard currentUserId != targetUserId else {
            completion(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No puedes seguirte a ti mismo"]))
            return
        }

        // ✅ OFFLINE SUPPORT: Si no hay conexión, persistir acción y retornar éxito optimista
        if !NetworkMonitor.shared.isConnected {
            let payload = FollowActionPayload(
                followerId: currentUserId,
                followedId: targetUserId,
                followedUsername: "", // Se puede dejar vacío y dejar que el sync lo resuelva
                isFollow: true
            )

            if let data = try? JSONEncoder().encode(payload) {
                let action = CachedAction(
                    id: "follow_\(currentUserId)_\(targetUserId)",
                    type: CachedAction.ActionType.follow.rawValue,
                    payloadData: data
                )

                Task {
                    await LocalPersistenceService.shared.saveAction(action)
                    print("💾 FirestoreService: Follow guardado en outbox (offline)")
                    completion(nil) // Éxito optimista
                }
                return
            }
        }

        // Limpiar cache antes de la operación
        invalidateFollowingCache(currentUserId: currentUserId, targetUserId: targetUserId)

        checkIfBlocked(currentUserId: currentUserId, targetUserId: targetUserId) { [weak self] isBlockedByCurrentUser, isCurrentUserBlocked, error in
            guard let self = self else { return }

            if let error = error {
                completion(error)
                return
            }

            if isBlockedByCurrentUser || isCurrentUserBlocked {
                completion(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No se puede seguir debido a bloqueos"]))
                return
            }

            self.fetchUserProfile(userId: targetUserId) { result in
                switch result {
                case .success(let targetUser):
                    if targetUser.isPrivate {
                        // Para perfiles privados, usar el sistema de solicitudes
                        self.sendFollowRequest(currentUserId: currentUserId, targetUserId: targetUserId, completion: completion)
                    } else {
                        // Para perfiles públicos, seguir directamente
                        self.performFollow(currentUserId: currentUserId, targetUserId: targetUserId) { error in
                            // Limpiar cache después de follow exitoso
                            if error == nil {
                                self.invalidateFollowingCache(currentUserId: currentUserId, targetUserId: targetUserId)
                            }
                            completion(error)
                        }
                    }
                case .failure(let error):
                    completion(error)
                }
            }
        }
    }

    private func performFollow(
        currentUserId: String,
        targetUserId: String,
        sendNotification: Bool = true,
        acceptedFollowRequestId: String? = nil,
        completion: @escaping (Error?) -> Void
    ) {
        fetchUserProfile(userId: currentUserId) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(_):
                let batch = db.batch()

                // Añadir a following del usuario actual
                let followingRef = db.collection("users").document(currentUserId).collection("following").document(targetUserId)
                var followingData: [String: Any] = [
                    "userId": targetUserId,
                    "timestamp": Timestamp(date: Date())
                ]
                if let acceptedFollowRequestId {
                    followingData["acceptedFollowRequestId"] = acceptedFollowRequestId
                    followingData["source"] = "followRequestAccepted"
                    followingData["acceptedAt"] = Timestamp(date: Date())
                }
                batch.setData(followingData, forDocument: followingRef)

                // Añadir a followers del usuario objetivo
                let followerRef = db.collection("users").document(targetUserId).collection("followers").document(currentUserId)
                var followerData: [String: Any] = [
                    "userId": currentUserId,
                    "timestamp": Timestamp(date: Date())
                ]
                if let acceptedFollowRequestId {
                    followerData["acceptedFollowRequestId"] = acceptedFollowRequestId
                    followerData["source"] = "followRequestAccepted"
                    followerData["acceptedAt"] = Timestamp(date: Date())
                }
                batch.setData(followerData, forDocument: followerRef)


                batch.commit { error in
                    if let error = error {
                        completion(error)
                    } else {
                        self.invalidateFollowingCache(currentUserId: currentUserId, targetUserId: targetUserId)

                        // Eliminamos notificación manual: servidor se encarga (onFollowerAdded)
                        completion(nil)
                    }
                }
            case .failure(let error):
                completion(error)
            }
        }
    }

    // MARK: - FUNCIÓN UNFOLLOWUSER CORREGIDA CON CACHE MANAGEMENT
    func unfollowUser(currentUserId: String, targetUserId: String, completion: @escaping (Error?) -> Void) {
        // ✅ Optimistic UI: Actualizar conexiones localmente (Low priority background)
        Task(priority: .background) { @MainActor in
            LocalPersistenceService.shared.toggleFollowLocally(currentUserId: currentUserId, targetUserId: targetUserId, isFollow: false)
        }

        guard currentUserId != targetUserId else {
            let error = NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No puedes dejar de seguirte a ti mismo"])
            completion(error)
            return
        }

        // ✅ OFFLINE SUPPORT: Si no hay conexión, persistir acción y retornar éxito optimista
        if !NetworkMonitor.shared.isConnected {
            let payload = FollowActionPayload(
                followerId: currentUserId,
                followedId: targetUserId,
                followedUsername: "",
                isFollow: false
            )

            if let data = try? JSONEncoder().encode(payload) {
                let action = CachedAction(
                    id: "unfollow_\(currentUserId)_\(targetUserId)",
                    type: CachedAction.ActionType.follow.rawValue,
                    payloadData: data
                )

                Task {
                    await LocalPersistenceService.shared.saveAction(action)
                    print("💾 FirestoreService: Unfollow guardado en outbox (offline)")
                    completion(nil) // Éxito optimista
                }
                return
            }
        }

        // LIMPIAR CACHE ANTES DE VERIFICAR
        let cacheKey = "\(currentUserId)_\(targetUserId)"
        followingCache.removeValue(forKey: cacheKey)

        // Verificar primero si realmente está siguiendo (SIN CACHE)
        db.collection("users").document(currentUserId).collection("following").document(targetUserId).getDocument { [weak self] snapshot, error in
            guard let self = self else { return }

            if let error = error {
                completion(error)
                return
            }

            let isCurrentlyFollowing = snapshot?.exists == true

            if !isCurrentlyFollowing {
                completion(nil)
                return
            }

            // Crear batch para operación atómica
            let batch = self.db.batch()

            // Referencias a los documentos
            let followingRef = self.db.collection("users").document(currentUserId).collection("following").document(targetUserId)
            let followerRef = self.db.collection("users").document(targetUserId).collection("followers").document(currentUserId)


            // Añadir operaciones de borrado al batch
            batch.deleteDocument(followingRef)
            batch.deleteDocument(followerRef)

            // Ejecutar batch
            batch.commit { error in
                if let error = error {
                    completion(error)
                } else {

                    // LIMPIAR CACHE DESPUÉS DEL UNFOLLOW EXITOSO
                    self.followingCache.removeValue(forKey: cacheKey)
                    // ✅ LIMPIEZA DE NOTIFICACIÓN (Unfollow) — defensa en profundidad; servidor también limpia vía onFollowerRemoved
                    Task { @MainActor in
                        let notificationService = NotificationService.shared
                        notificationService.removeNotification(
                            type: .newFollower,
                            senderId: currentUserId,
                            recipientId: targetUserId
                        )
                        notificationService.removeNotification(
                            type: .mutualConnection,
                            senderId: currentUserId,
                            recipientId: targetUserId
                        )
                        notificationService.removeNotification(
                            type: .mutualConnection,
                            senderId: targetUserId,
                            recipientId: currentUserId
                        )
                    }

                    // VERIFICACIÓN POST-UNFOLLOW CON DELAY (sin cache)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.db.collection("users").document(currentUserId).collection("following").document(targetUserId).getDocument { snapshot, error in
                            if error == nil {
                                let stillFollowing = snapshot?.exists == true

                                if stillFollowing {
                                    // Intentar force unfollow
                                    self.forceUnfollow(currentUserId: currentUserId, targetUserId: targetUserId) { forceError in
                                        if let forceError = forceError {
                                            completion(forceError)
                                        } else {
                                            completion(nil)
                                        }
                                    }
                                } else {
                                    completion(nil)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - FUNCIÓN ISFOLLOWING MEJORADA (siempre directa para operaciones críticas)
    func isFollowing(currentUserId: String, targetUserId: String, completion: @escaping (Bool) -> Void) {
        let cacheKey = "\(currentUserId)_\(targetUserId)"

        // Limpiar cache si es muy viejo (15 segundos - más corto)
        if Date().timeIntervalSince(lastCacheUpdate) > 15 {
            followingCache.removeAll()
            lastCacheUpdate = Date()
        }
        db.collection("users").document(currentUserId).collection("following").document(targetUserId).getDocument { [weak self] snapshot, error in
            if error != nil {
                completion(false)
            } else {
                let isFollowing = snapshot?.exists == true

                // Actualizar cache solo si es exitoso
                if error == nil {
                    self?.followingCache[cacheKey] = isFollowing
                }

                completion(isFollowing)
            }
        }
    }

    // MARK: - FUNCIÓN ISFOLLOWING CON CACHE (para UI normal)
    func isFollowingCached(currentUserId: String, targetUserId: String, completion: @escaping (Bool) -> Void) {
        let cacheKey = "\(currentUserId)_\(targetUserId)"

        // Limpiar cache si es muy viejo
        if Date().timeIntervalSince(lastCacheUpdate) > 15 {
            followingCache.removeAll()
            lastCacheUpdate = Date()
        }

        // Verificar cache primero
        if let cachedResult = followingCache[cacheKey] {
            completion(cachedResult)
            return
        }

        // Si no hay cache, hacer consulta directa
        isFollowing(currentUserId: currentUserId, targetUserId: targetUserId, completion: completion)
    }

    // MARK: - FUNCIONES DE CACHE MANAGEMENT
    func invalidateFollowingCache(currentUserId: String, targetUserId: String) {
        let cacheKey = "\(currentUserId)_\(targetUserId)"
        followingCache.removeValue(forKey: cacheKey)
    }

    func clearFollowingCache() {
        followingCache.removeAll()
    }

    // MARK: - FUNCIÓN FORCE UNFOLLOW (para casos extremos)
    func forceUnfollow(currentUserId: String, targetUserId: String, completion: @escaping (Error?) -> Void) {

        let group = DispatchGroup()
        var errors: [Error] = []

        // 1. Borrar de following
        group.enter()
        db.collection("users").document(currentUserId).collection("following").document(targetUserId).delete { error in
            if let error = error {
                errors.append(error)
            }
            group.leave()
        }

        // 2. Borrar de followers
        group.enter()
        db.collection("users").document(targetUserId).collection("followers").document(currentUserId).delete { error in
            if let error = error {
                errors.append(error)
            }
            group.leave()
        }

        // 3. Limpiar cache
        group.enter()
        DispatchQueue.main.async {
            self.clearFollowingCache()
            group.leave()
        }

        group.notify(queue: .main) {
            if let firstError = errors.first {
                completion(firstError)
            } else {
                // Verificación final
                self.isFollowing(currentUserId: currentUserId, targetUserId: targetUserId) { stillFollowing in
                    // Verification completed
                }

                completion(nil)
            }
        }
    }

    // MARK: - FETCH METHODS CORREGIDOS
    func fetchFollowing(userId: String, completion: @escaping (Result<[AppUser], Error>) -> Void) {
        db.collection("users").document(userId).collection("following")
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let documents = snapshot?.documents, !documents.isEmpty else {
                    completion(.success([]))
                    return
                }

                // Extraer IDs de usuarios seguidos
                let followingIds: [String] = documents.compactMap { doc in
                    let data = doc.data()
                    return data["userId"] as? String ?? doc.documentID
                }

                guard !followingIds.isEmpty else {
                    completion(.success([]))
                    return
                }

                // Buscar datos completos de usuarios
                self.fetchUsersByIdsClean(userIds: followingIds) { result in
                    if case .success(let users) = result {
                    Task { @MainActor in
                        LocalPersistenceService.shared.saveFollowing(userId: userId, following: users)
                    }
                    }
                    completion(result)
                }
            }
    }

    // ✅ FUNCIÓN LIMPIA: fetchUsersByIds sin debug logs
    func fetchUsersByIdsClean(userIds: [String], completion: @escaping (Result<[AppUser], Error>) -> Void) {
        guard !userIds.isEmpty else {
            completion(.success([]))
            return
        }

        let batchSize = 10
        let batches = userIds.chunked(into: batchSize)

        let group = DispatchGroup()
        var allUsers: [AppUser] = []
        var capturedError: Error?
        let syncQueue = DispatchQueue(label: "users.fetch.sync")

        for batch in batches {
            group.enter()

            db.collection("users")
                .whereField(FieldPath.documentID(), in: batch)
                .getDocuments { snapshot, error in
                    if let error = error {
                        syncQueue.sync { capturedError = error }
                        group.leave()
                        return
                    }

                    let users = snapshot?.documents.compactMap { document -> AppUser? in
                        do {
                            let user = try document.data(as: AppUser.self)
                            return user.isActive ? user : nil // Solo usuarios activos
                        } catch {
                            return nil
                        }
                    } ?? []

                    // ✅ FIXED: El notify de abajo puede dispararse antes de que termine el async.
                    // Usamos .sync para garantizar que la mutación termine ANTES del group.leave()
                    syncQueue.sync {
                        allUsers.append(contentsOf: users)
                    }

                    group.leave()
                }
        }

        group.notify(queue: .main) {
            if let error = capturedError {
                completion(.failure(error))
            } else {
                completion(.success(allUsers))
            }
        }
    }

    // This is a helper method for async operations, assuming it exists elsewhere or is intended to be added.
    // If not, the `fetchFollowersWithTimestamps` method will not compile.
    func fetchUsersAsync(userIds: [String]) async throws -> [AppUser] {
        guard !userIds.isEmpty else { return [] }

        let batchSize = 10
        let batches = userIds.chunked(into: batchSize)
        var allUsers: [AppUser] = []

        for batch in batches {
            let snapshot = try await db.collection("users")
                .whereField(FieldPath.documentID(), in: batch)
                .getDocuments()

            let users = snapshot.documents.compactMap { document -> AppUser? in
                do {
                    let user = try document.data(as: AppUser.self)
                    return user.isActive ? user : nil
                } catch {
                    return nil
                }
            }
            allUsers.append(contentsOf: users)
        }
        return allUsers
    }

    func fetchFollowersWithTimestamps(userId: String) async throws -> [(user: AppUser, timestamp: Date)] {
        let snapshot = try await db.collection("users").document(userId).collection("followers")
            .order(by: "timestamp", descending: true)
            .limit(to: 100)
            .getDocuments()

        let followerData = snapshot.documents.compactMap { doc -> (id: String, timestamp: Date)? in
            let data = doc.data()
            guard let id = data["userId"] as? String,
                  let timestamp = (data["timestamp"] as? Timestamp)?.dateValue() else { return nil }
            return (id, timestamp)
        }

        if followerData.isEmpty { return [] }

        let followerIds = followerData.map { $0.id }
        let users = try await fetchUsersAsync(userIds: followerIds)
        let userDict = Dictionary(uniqueKeysWithValues: users.map { ($0.id, $0) })

        return followerData.compactMap { item in
            guard let user = userDict[item.id] else { return nil }
            return (user, item.timestamp)
        }
    }

    func fetchFollowers(userId: String, completion: @escaping (Result<[AppUser], Error>) -> Void) {

        db.collection("users").document(userId).collection("followers")
            .order(by: "timestamp", descending: true)
            .getDocuments { [weak self] snapshot, error in
                guard let self = self else { return }

                if let error = error {
                    completion(.failure(error))
                    return
                }

                let userIds = snapshot?.documents.compactMap { $0.data()["userId"] as? String } ?? []

                if userIds.isEmpty {
                    completion(.success([]))
                    return
                }

                self.fetchUsersByIdsClean(userIds: userIds) { result in
                    if case .success(let users) = result {
                    Task { @MainActor in
                        LocalPersistenceService.shared.saveFollowers(userId: userId, followers: users)
                    }
                    }
                    completion(result)
                }
            }
    }

    // MARK: - ACCOUNT HISTORY
    func logAccountHistoryEvent(userId: String, type: AccountHistoryEventType, oldValue: String?, newValue: String?) {
        let collection = db.collection("users").document(userId).collection("accountHistory")

        // Prevent generic duplicates
        if oldValue == newValue { return }

        let event = AccountHistoryItem(type: type, oldValue: oldValue, newValue: newValue)
        do {
            _ = try collection.addDocument(from: event)
        } catch {
            print("❌ FirestoreService: Error logging account history event - \(error)")
        }
    }

    func fetchAccountHistory(userId: String) async throws -> [AccountHistoryItem] {
        let snapshot = try await db.collection("users").document(userId).collection("accountHistory")
            .order(by: "timestamp", descending: true)
            .getDocuments()

        return snapshot.documents.compactMap { try? $0.data(as: AccountHistoryItem.self) }
    }

    // MARK: - RESTO DE FUNCIONES SIN CAMBIOS
    func updateBio(userId: String, oldBio: String? = nil, newBio: String, completion: @escaping (Error?) -> Void) {
        self.db.collection("users").document(userId).updateData([
            "bio": newBio
        ]) { error in
            if let error = error {
                completion(error)
            } else {
                if oldBio != newBio {
                    self.logAccountHistoryEvent(userId: userId, type: .bio, oldValue: oldBio, newValue: newBio)
                }
                completion(nil)
            }
        }
    }

    // ✅ NUEVO: Actualizar bio y link
    func updateProfileDetails(userId: String, oldBio: String? = nil, newBio: String?, oldWebsite: String? = nil, newWebsite: String?, completion: @escaping (Error?) -> Void) {
        var data: [String: Any] = [:]

        if let newBio = newBio {
            data["bio"] = newBio
        }

        // Permitimos guardar cadena vacía para borrar el link
        if let newWebsite = newWebsite {
            data["websiteUrl"] = newWebsite
        }

        guard !data.isEmpty else {
            completion(nil)
            return
        }

        self.db.collection("users").document(userId).updateData(data) { error in
            if error == nil {
                if let newB = newBio, newB != oldBio {
                    self.logAccountHistoryEvent(userId: userId, type: .bio, oldValue: oldBio, newValue: newB)
                }
                if let newW = newWebsite, newW != oldWebsite {
                    self.logAccountHistoryEvent(userId: userId, type: .website, oldValue: oldWebsite, newValue: newW)
                }
            }
            completion(error)
        }
    }



    func blockUser(currentUserId: String, targetUserId: String, completion: @escaping (Error?) -> Void) {
        self.db.collection("users").document(currentUserId).updateData([
            "blockedUsers": FieldValue.arrayUnion([targetUserId])
        ]) { error in
            if let error = error {
                completion(error)
                return
            }

            // Limpiar cache antes de unfollows
            self.invalidateFollowingCache(currentUserId: currentUserId, targetUserId: targetUserId)
            self.invalidateFollowingCache(currentUserId: targetUserId, targetUserId: currentUserId)

            self.unfollowUser(currentUserId: currentUserId, targetUserId: targetUserId) { error in
                self.unfollowUser(currentUserId: targetUserId, targetUserId: currentUserId) { error in
                    self.deleteNotificationsBetweenUsers(recipientId: currentUserId, senderId: targetUserId) { error in
                        self.deleteNotificationsBetweenUsers(recipientId: targetUserId, senderId: currentUserId) { error in
                            self.deleteVisitsBetweenUsers(userId: currentUserId, visitorId: targetUserId) { error in
                                self.deleteVisitsBetweenUsers(userId: targetUserId, visitorId: currentUserId) { error in
                                    completion(nil)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    func unblockUser(currentUserId: String, targetUserId: String, completion: @escaping (Error?) -> Void) {
        // Limpiar cache al desbloquear
        invalidateFollowingCache(currentUserId: currentUserId, targetUserId: targetUserId)
        invalidateFollowingCache(currentUserId: targetUserId, targetUserId: currentUserId)

        self.db.collection("users").document(currentUserId).updateData([
            "blockedUsers": FieldValue.arrayRemove([targetUserId])
        ]) { error in
            if let error = error {
                completion(error)
            } else {
                completion(nil)
            }
        }
    }

    func checkIfBlocked(currentUserId: String, targetUserId: String, completion: @escaping (Bool, Bool, Error?) -> Void) {
        let group = DispatchGroup()
        var isBlockedByCurrentUser = false
        var isCurrentUserBlocked = false
        var fetchError: Error?

        group.enter()
        db.collection("users").document(currentUserId).getDocument { snapshot, error in
            if let error = error {
                fetchError = error
            } else if let data = snapshot?.data(), let blockedUsers = data["blockedUsers"] as? [String] {
                isBlockedByCurrentUser = blockedUsers.contains(targetUserId)
            }
            group.leave()
        }

        group.enter()
        db.collection("users").document(targetUserId).getDocument { snapshot, error in
            if let error = error {
                fetchError = error
            } else if let data = snapshot?.data(), let blockedUsers = data["blockedUsers"] as? [String] {
                isCurrentUserBlocked = blockedUsers.contains(currentUserId)
            }
            group.leave()
        }

        group.notify(queue: .main) {
            completion(isBlockedByCurrentUser, isCurrentUserBlocked, fetchError)
        }
    }

    func checkActiveHours(user: AppUser, completion: @escaping (Result<Bool, Error>) -> Void) {
        guard let startHour = user.activeHoursStart, let endHour = user.activeHoursEnd,
              !startHour.isEmpty, !endHour.isEmpty else {
            completion(.success(true))
            return
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm"
        dateFormatter.timeZone = TimeZone.current

        guard let startDate = dateFormatter.date(from: startHour),
              let endDate = dateFormatter.date(from: endHour) else {
            completion(.success(true)) // Permitir si el formato es inválido
            return
        }

        let calendar = Calendar.current
        let now = Date()
        let currentTime = calendar.dateComponents([.hour, .minute], from: now)
        let startTime = calendar.dateComponents([.hour, .minute], from: startDate)
        let endTime = calendar.dateComponents([.hour, .minute], from: endDate)

        let currentMinutes = (currentTime.hour! * 60) + currentTime.minute!
        let startMinutes = (startTime.hour! * 60) + startTime.minute!
        let endMinutes = (endTime.hour! * 60) + endTime.minute!

        let isWithinHours: Bool
        if startMinutes <= endMinutes {
            isWithinHours = currentMinutes >= startMinutes && currentMinutes <= endMinutes
        } else {
            isWithinHours = currentMinutes >= startMinutes || currentMinutes <= endMinutes
        }

        completion(.success(isWithinHours))
    }

    func updateActiveHours(userId: String, startHour: String, endHour: String, completion: @escaping (Error?) -> Void) {
        let userRef = db.collection("users").document(userId)
        let timezoneIdentifier = TimeZone.current.identifier
        userRef.updateData([
            "activeHoursStart": startHour,
            "activeHoursEnd": endHour,
            "notificationTimeZone": timezoneIdentifier
        ]) { error in
            completion(error)
        }
    }

    func clearActiveHours(userId: String, completion: @escaping (Error?) -> Void) {
        let userRef = db.collection("users").document(userId)
        userRef.updateData([
            "activeHoursStart": FieldValue.delete(),
            "activeHoursEnd": FieldValue.delete()
        ]) { error in
            completion(error)
        }
    }

    func updateNotificationPreferences(userId: String, preferences: [String: Bool], completion: @escaping (Error?) -> Void) {
        db.collection("users").document(userId).updateData([
            "notificationPreferences": preferences
        ]) { error in
            completion(error)
        }
    }

    private func deleteNotificationsBetweenUsers(recipientId: String, senderId: String, completion: @escaping (Error?) -> Void) {
        self.db.collection("users").document(recipientId).collection("notifications")
            .whereField("senderId", isEqualTo: senderId)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(error)
                    return
                }

                guard let documents = snapshot?.documents else {
                    completion(nil)
                    return
                }

                let batch = self.db.batch()
                for doc in documents {
                    batch.deleteDocument(doc.reference)
                }

                batch.commit { error in
                    if let error = error {
                        completion(error)
                    } else {
                        completion(nil)
                    }
                }
            }
    }

    private func deleteVisitsBetweenUsers(userId: String, visitorId: String, completion: @escaping (Error?) -> Void) {
        self.db.collection("users").document(userId).collection("visits").document(visitorId).delete { error in
            if let error = error {
                completion(error)
            } else {
                completion(nil)
            }
        }
    }

    func canViewContent(currentUserId: String, targetUserId: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        self.fetchUserProfile(userId: targetUserId) { [weak self] result in
            guard let self = self else {
                completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("errors.operationCancelled", comment: "Operation cancelled")])))
                return
            }
            switch result {
            case .success(let targetUser):
                if targetUser.blockedUsers.contains(currentUserId) {
                    completion(.success(false))
                    return
                }

                self.fetchUserProfile(userId: currentUserId) { result in
                    switch result {
                    case .success(let currentUser):
                        if currentUser.blockedUsers.contains(targetUserId) {
                            completion(.success(false))
                            return
                        }

                        if !targetUser.isPrivate {
                            completion(.success(true))
                            return
                        }

                        self.fetchMutualConnections(userId: currentUserId) { result in
                            switch result {
                            case .success(let mutualConnections):
                                let isMutualConnection = mutualConnections.contains { $0.id == targetUserId }
                                completion(.success(isMutualConnection))
                            case .failure(let error):
                                completion(.failure(error))
                            }
                        }
                    case .failure(let error):
                        completion(.failure(error))
                    }
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }



    func fetchMoment(momentId: String, userId: String, completion: @escaping (Result<Moment, Error>) -> Void) {
        self.db.collection("users").document(userId).collection("moments").document(momentId).getDocument { snapshot, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let document = snapshot, document.exists else {
                completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("errors.momentNotFound", comment: "Moment not found")])))
                return
            }

            do {
                let moment = try document.data(as: Moment.self)
                if moment.isArchived == true {
                    completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("errors.momentNotFound", comment: "Moment not found")])))
                    return
                }
                completion(.success(moment))
            } catch {
                completion(.failure(error))
            }
        }
    }


    func fetchUsersWithSharedInterests(interests: [String], excludingUserId: String, completion: @escaping (Result<[AppUser], Error>) -> Void) {

        guard !interests.isEmpty else {
            completion(.success([]))
            return
        }

        self.fetchUserProfile(userId: excludingUserId) { [weak self] result in
            guard let self = self else {
                completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("errors.operationCancelled", comment: "Operation cancelled")])))
                return
            }

            switch result {
            case .success(let currentUser):
                let blockedUsers = Set(currentUser.blockedUsers)

                var allUsers: [AppUser] = []
                let group = DispatchGroup()

                let batchSize = 30
                let interestBatches = stride(from: 0, to: interests.count, by: batchSize).map {
                    Array(interests[$0..<min($0 + batchSize, interests.count)])
                }

                for batch in interestBatches {
                    group.enter()
                    self.db.collection("users")
                        .whereField("interests", arrayContainsAny: batch)
                        .limit(to: 50)
                        .getDocuments { snapshot, error in
                            if error != nil {
                                group.leave()
                                return
                            }

                            let users = snapshot?.documents.compactMap { doc -> AppUser? in
                                try? doc.data(as: AppUser.self)
                            } ?? []
                            allUsers.append(contentsOf: users)
                            group.leave()
                        }
                }

                group.notify(queue: .main) {
                    let filteredUsers = allUsers.filter { user in
                        guard user.id != excludingUserId else { return false }
                        if blockedUsers.contains(user.id) { return false }
                        if user.blockedUsers.contains(excludingUserId) { return false }
                        return true
                    }

                    var uniqueUsers: [AppUser] = []
                    var seenIds = Set<String>()
                    for user in filteredUsers {
                        if seenIds.insert(user.id).inserted {
                            uniqueUsers.append(user)
                        }
                    }
                    completion(.success(uniqueUsers))
                }

            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func fetchMomentsFromUsers(
        userIds: [String],
        perUserLimit: Int = 20,
        totalLimit: Int = 50,
        completion: @escaping (Result<[Moment], Error>) -> Void
    ) {
        let normalizedUserIds = Array(Set(userIds))
        guard !normalizedUserIds.isEmpty else {
            completion(.success([]))
            return
        }

        let batches = normalizedUserIds.chunked(into: 10)
        let group = DispatchGroup()
        let syncQueue = DispatchQueue(label: "moments.from.users.sync")
        var allMoments: [Moment] = []
        var capturedError: Error?

        for batch in batches {
            group.enter()
            self.fetchMomentsFromUsersBatch(
                userIds: batch,
                perUserLimit: max(1, perUserLimit)
            ) { result in
                syncQueue.sync {
                    switch result {
                    case .success(let moments):
                        allMoments.append(contentsOf: moments)
                    case .failure(let error):
                        capturedError = capturedError ?? error
                    }
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            let (sortedLimitedMoments, error): ([Moment], Error?) = syncQueue.sync {
                let sorted = allMoments.sorted { $0.timestamp > $1.timestamp }
                return (Array(sorted.prefix(max(1, totalLimit))), capturedError)
            }

            if sortedLimitedMoments.isEmpty, let error = error {
                completion(.failure(error))
            } else {
                completion(.success(sortedLimitedMoments))
            }
        }
    }

    private func fetchMomentsFromUsersBatch(
        userIds: [String],
        perUserLimit: Int,
        completion: @escaping (Result<[Moment], Error>) -> Void
    ) {
        guard !userIds.isEmpty else {
            completion(.success([]))
            return
        }

        // Try optimized collectionGroup query first.
        db.collectionGroup("moments")
            .whereField("authorId", in: userIds)
            .order(by: "timestamp", descending: true)
            .limit(to: max(perUserLimit * userIds.count, 20))
            .getDocuments { [weak self] snapshot, error in
                guard let self = self else {
                    completion(.failure(NSError(domain: "FirestoreService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Service deallocated"])))
                    return
                }

                if error != nil {
                    // Fallback path keeps behavior and safety if index/query is unavailable.
                    self.fetchMomentsFromUsersLegacy(userIds: userIds, perUserLimit: perUserLimit, completion: completion)
                    return
                }

                guard let documents = snapshot?.documents else {
                    completion(.success([]))
                    return
                }

                let decoded = documents.compactMap { doc -> Moment? in
                    try? doc.data(as: Moment.self)
                }

                let filteredScheduled = self.filterScheduledMomentsForCurrentViewer(decoded)
                var perAuthorCount: [String: Int] = [:]
                let perAuthorLimited = filteredScheduled.filter { moment in
                    let count = perAuthorCount[moment.authorId, default: 0]
                    guard count < perUserLimit else { return false }
                    perAuthorCount[moment.authorId] = count + 1
                    return true
                }

                completion(.success(perAuthorLimited))
            }
    }

    private func fetchMomentsFromUsersLegacy(
        userIds: [String],
        perUserLimit: Int,
        completion: @escaping (Result<[Moment], Error>) -> Void
    ) {
        let group = DispatchGroup()
        let syncQueue = DispatchQueue(label: "moments.from.users.legacy.sync")
        var allMoments: [Moment] = []
        var capturedError: Error?

        for userId in userIds {
            group.enter()
            self.fetchMoments(for: userId) { result in
                syncQueue.sync {
                    switch result {
                    case .success(let moments):
                        allMoments.append(contentsOf: Array(moments.prefix(perUserLimit)))
                    case .failure(let error):
                        capturedError = capturedError ?? error
                    }
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            let (sorted, error): ([Moment], Error?) = syncQueue.sync {
                (allMoments.sorted { $0.timestamp > $1.timestamp }, capturedError)
            }
            if sorted.isEmpty, let error = error {
                completion(.failure(error))
            } else {
                completion(.success(sorted))
            }
        }
    }

    private func filterScheduledMomentsForCurrentViewer(_ moments: [Moment]) -> [Moment] {
        let currentUserId = Auth.auth().currentUser?.uid
        let now = Date()

        return moments.filter { moment in
            if moment.isArchived == true {
                return false
            }
            if moment.authorId == currentUserId {
                return true
            }
            guard let scheduledDate = moment.scheduledDate else { return true }
            return scheduledDate <= now
        }
    }
}

extension FirestoreService {

    // ✅ NUEVA FUNCIÓN: addCommentReaction (similar a addReaction pero para comentarios)
}

extension FirestoreService {

    // MARK: - Obtener intereses del usuario actual
    func getCurrentUserInterests() throws -> [String] {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Usuario no autenticado"])
        }

        // Usar semáforo para hacer la llamada síncrona
        let semaphore = DispatchSemaphore(value: 0)
        var interests: [String] = []
        var fetchError: Error?

        db.collection("users").document(currentUserId).getDocument { document, error in
            if let error = error {
                fetchError = error
            } else if let data = document?.data(),
                      let userInterests = data["interests"] as? [String] {
                interests = userInterests
            }
            semaphore.signal()
        }

        semaphore.wait()

        if let error = fetchError {
            throw error
        }

        return interests
    }

}
