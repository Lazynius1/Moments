import FirebaseFirestore
import Combine
import FirebaseAuth

class FirestoreService: ObservableObject {
    let db: Firestore
    @Published var savedMomentIds: [String] = []
    private var followingCache: [String: Bool] = [:]
    private var lastCacheUpdate: Date = Date() // Added for reactive saved moments

    init() {
        db = Firestore.firestore()
        self.db.enableNetwork()
    }
    
    // 🔗 HELPER: Calcular fecha de expiración para historias
    private func calculateStoryExpirationDate(isChain: Bool = false, chainId: String? = nil) -> Date {
        if isChain, let chainId = chainId {
            // Para historias de cadenas, usar la misma fecha de expiración que la parte 1
            return calculateChainExpirationDate(chainId: chainId)
        } else {
            // Para historias normales, 24 horas
            return Calendar.current.date(byAdding: .hour, value: 24, to: Date()) ?? Date()
        }
    }
    
    // 🔗 HELPER: Calcular fecha de expiración de una cadena (basada en createdAt de storyChains)
    private func calculateChainExpirationDate(chainId: String) -> Date {
        // Usar fecha actual + 48h para subir inmediatamente
        let currentExpiration = Calendar.current.date(byAdding: .hour, value: 48, to: Date()) ?? Date()
        
        // En background, actualizar con la fecha correcta de la cadena
        Task {
            await updateChainExpirationInBackground(chainId: chainId)
        }
        
        return currentExpiration
    }
    
    // 🔗 HELPER: Actualizar fecha de expiración de todas las partes de la cadena en background
    private func updateChainExpirationInBackground(chainId: String) async {
        do {
            // Obtener fecha de creación de la cadena
            let chainDoc = try await db.collection("storyChains")
                .document(chainId)
                .getDocument()
            
            guard let data = chainDoc.data(),
                  let createdAt = data["createdAt"] as? Timestamp else {
                return
            }
            
            // Calcular fecha correcta (48h desde creación de la cadena)
            let createdAtDate = createdAt.dateValue()
            let correctExpiration = Calendar.current.date(byAdding: .hour, value: 48, to: createdAtDate) ?? Date()
            
            // Buscar todas las partes de la cadena
            let storiesSnapshot = try await db.collectionGroup("stories")
                .whereField("chainId", isEqualTo: chainId)
                .getDocuments()
            
            // Actualizar todas las partes con la fecha correcta
            let batch = db.batch()
            for doc in storiesSnapshot.documents {
                batch.updateData([
                    "expirationDate": Timestamp(date: correctExpiration)
                ], forDocument: doc.reference)
            }
            
            try await batch.commit()
            
        } catch {
            // Error updating chain expiration
        }
    }
    
    func updateMoment(userId: String, momentId: String, content: String, completion: @escaping (Error?) -> Void) {
        let momentRef = db.collection("users").document(userId).collection("moments").document(momentId)
        
        let updateData: [String: Any] = [
            "content": content,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        
        momentRef.updateData(updateData) { error in
            if let error = error {
                completion(error)
            } else {
                completion(nil)
            }
        }
    }

    func deleteMoment(userId: String, momentId: String, completion: @escaping (Error?) -> Void) {
        let momentRef = db.collection("users").document(userId).collection("moments").document(momentId)
        
        // Primero obtener el momento para limpiar archivos de Storage
        momentRef.getDocument { [weak self] snapshot, error in
            if let error = error {
                completion(error)
                return
            }
            
            guard let self = self else {
                completion(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Operación cancelada"]))
                return
            }
            
            // Obtener rutas de archivos para eliminar de Storage
            let data = snapshot?.data()
            let imagePath = data?["imagePath"] as? String
            let videoUrl = data?["videoUrl"] as? String
            
            // Eliminar el documento del momento
            momentRef.delete { error in
                if let error = error {
                    completion(error)
                    return
                }
                
                // Eliminar archivos de Storage en segundo plano
                let storageService = StorageService()
                let cleanupGroup = DispatchGroup()
                
                if let imagePath = imagePath, !imagePath.isEmpty {
                    cleanupGroup.enter()
                    storageService.deleteMedia(path: imagePath) { error in
                        if let error = error {
                            // Error silencioso para limpieza de archivos
                        }
                        cleanupGroup.leave()
                    }
                }
                
                if let videoUrl = videoUrl, !videoUrl.isEmpty {
                    cleanupGroup.enter()
                    storageService.deleteMedia(path: videoUrl) { error in
                        if let error = error {
                            // Error silencioso para limpieza de archivos
                        }
                        cleanupGroup.leave()
                    }
                }
                
                cleanupGroup.notify(queue: .main) {
                    // Limpieza completada
                }
                
                // Completar la operación aunque falle la limpieza de archivos
                completion(nil)
            }
        }
    }

    func deleteMomentComments(userId: String, momentId: String, completion: @escaping (Error?) -> Void) {
        let commentsRef = db.collection("users").document(userId)
            .collection("moments").document(momentId)
            .collection("comments")
        
        commentsRef.getDocuments { snapshot, error in
            if let error = error {
                completion(error)
                return
            }
            
            guard let documents = snapshot?.documents else {
                completion(nil)
                return
            }
            
            let batch = self.db.batch()
            for document in documents {
                batch.deleteDocument(document.reference)
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

    func deleteMomentReactions(userId: String, momentId: String, completion: @escaping (Error?) -> Void) {
        let reactionsRef = db.collection("users").document(userId)
            .collection("moments").document(momentId)
            .collection("reactions")
        
        reactionsRef.getDocuments { snapshot, error in
            if let error = error {
                completion(error)
                return
            }
            
            guard let documents = snapshot?.documents else {
                completion(nil)
                return
            }
            
            let batch = self.db.batch()
            for document in documents {
                batch.deleteDocument(document.reference)
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

    // Load saved moments for a user
    func loadSavedMoments(userId: String) {
        db.collection("users").document(userId).collection("savedMoments")
            .getDocuments { [weak self] snapshot, error in
                if let error = error {
                    return
                }
                let momentIds = snapshot?.documents.compactMap { $0.documentID } ?? []
                DispatchQueue.main.async {
                    self?.savedMomentIds = momentIds
                }
            }
    }

    func checkIfSaved(userId: String, momentId: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        db.collection("users").document(userId).collection("savedMoments").document(momentId).getDocument { snapshot, error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(snapshot?.exists ?? false))
            }
        }
    }

    func toggleSaveMoment(userId: String, momentId: String, completion: @escaping (Error?) -> Void) {
        let savedMomentRef = db.collection("users").document(userId).collection("savedMoments").document(momentId)
        db.runTransaction({ [weak self] (transaction, errorPointer) -> Any? in
            let snapshot: DocumentSnapshot
            do {
                try snapshot = transaction.getDocument(savedMomentRef)
                if snapshot.exists {
                    transaction.deleteDocument(savedMomentRef)
                    DispatchQueue.main.async {
                        self?.savedMomentIds.removeAll { $0 == momentId }
                    }
                } else {
                    transaction.setData(["momentId": momentId, "timestamp": Timestamp()], forDocument: savedMomentRef)
                    DispatchQueue.main.async {
                        self?.savedMomentIds.append(momentId)
                    }
                }
                return nil
            } catch let error {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }) { _, error in
            completion(error)
        }
    }
    
    func fetchVisits(userId: String, completion: @escaping (Result<[Visit], Error>) -> Void) {
        self.db.collection("users").document(userId).collection("visits")
            .order(by: "timestamp", descending: true)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let documents = snapshot?.documents else {
                    completion(.success([]))
                    return
                }

                let visits = documents.compactMap { doc -> Visit? in
                    do {
                        return try doc.data(as: Visit.self)
                    } catch {
                        return nil
                    }
                }
                completion(.success(visits))
            }
    }
    // FUNCIONES DE VISITAS //
    
    func registerVisit(visitorId: String, to targetUserId: String, completion: @escaping (Error?) -> Void) {
        // ✅ VALIDACIÓN BÁSICA
        guard visitorId != targetUserId else {
            completion(nil)
            return
        }
        
        
        // ✅ VERIFICAR BLOQUEOS
        checkIfBlocked(currentUserId: visitorId, targetUserId: targetUserId) { [weak self] isBlockedByVisitor, isVisitorBlocked, error in
            guard let self = self else {
                completion(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Operación cancelada"]))
                return
            }
            
            if let error = error {
                completion(error)
                return
            }
            
            if isBlockedByVisitor || isVisitorBlocked {
                completion(nil)
                return
            }
            
            // ✅ VERIFICAR VISITAS RECIENTES (5 minutos)
            let visitsRef = self.db.collection("users").document(targetUserId).collection("visits")
            let fiveMinutesAgo = Date().addingTimeInterval(-300)
            
            visitsRef
                .whereField("visitorId", isEqualTo: visitorId)
                .whereField("timestamp", isGreaterThan: Timestamp(date: fiveMinutesAgo))
                .limit(to: 1)
                .getDocuments { snapshot, error in
                    
                    if let error = error {
                        completion(error)
                        return
                    }
                    
                    // Si hay visita reciente, no registrar
                    if let documents = snapshot?.documents, !documents.isEmpty {
                        completion(nil)
                        return
                    }
                    
                    // ✅ CREAR Y GUARDAR VISITA
                    let visit = Visit(visitorId: visitorId, timestamp: Date())
                    
                    do {
                        let encoder = Firestore.Encoder()
                        let visitData = try encoder.encode(visit)
                        
                        // ✅ USAR addDocument para @DocumentID
                        visitsRef.addDocument(data: visitData) { error in
                            if let error = error {
                            completion(error)
                            return
                        }
                            
                            // ✅ ACTUALIZAR RESUMEN DIARIO
                            self.updateVisitSummary(targetUserId: targetUserId, visitorId: visitorId)
                            
                            completion(nil)
                        }
                    } catch {
                        completion(error)
                    }
                }
        }
    }

    // ✅ MÉTODO HELPER PARA ACTUALIZAR RESUMEN
    private func updateVisitSummary(targetUserId: String, visitorId: String) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let today = dateFormatter.string(from: Date())
        
        let visitSummaryRef = db.collection("users").document(targetUserId).collection("visitSummaries").document(today)
        
        visitSummaryRef.setData([
            "date": today,
            "visitorIds": FieldValue.arrayUnion([visitorId]),
            "visitCount": FieldValue.increment(Int64(1)),
            "timestamp": Timestamp(date: Date())
        ], merge: true) { error in
            if let error = error {
                // Error silencioso al actualizar resumen
            }
        }
    }

    func updateVisitSummaryNotification(userId: String, date: String) {
        let notificationRef = db.collection("users").document(userId).collection("notifications").document("visit_\(date)")
        let visitSummaryRef = db.collection("users").document(userId).collection("visitSummaries").document(date)
        
        visitSummaryRef.getDocument { [weak self] snapshot, error in
            guard let self = self,
                  let data = snapshot?.data(),
                  let visitCount = data["visitCount"] as? Int64,
                  let visitorIds = data["visitorIds"] as? [String] else {
                return
            }
            
            self.fetchUser(userId: visitorIds.last ?? "") { result in
                let lastUsername: String
                switch result {
                case .success(let user):
                    lastUsername = user.username
                case .failure:
                    lastUsername = "Alguien"
                }
                
                let notification = Notification(
                        id: "visit_\(date)",
                        type: .profileVisit,
                        senderId: visitorIds.last ?? "",
                        senderUsername: lastUsername,
                        timestamp: Date(),
                        isPending: true,
                        momentId: nil,
                        visitCount: Int(visitCount),
                        storyId: nil,
                        storyAuthorId: nil,
                        reaction: nil
                    )
                
                do {
                    try notificationRef.setData(from: notification, merge: true)
                } catch {
                    // Error silencioso al actualizar notificación
                }
            }
        }
    }
    
    // Crear usuario
    func createUser(userId: String, username: String, email: String, interests: [String], profileImagePath: String? = nil, completion: @escaping (Error?) -> Void) {
        

        
        // ✅ CREAR AppUser que coincida EXACTAMENTE con tu modelo User.swift
        let newUser = AppUser(
            id: userId,
            username: username.lowercased(),
            email: email,
            interests: interests,
            isPlusSubscriber: false,
            profileImagePath: profileImagePath,
            bio: nil,
            blockedUsers: [],
            isPrivate: false,
            showMutualConnections: true, // ✅ CAMPO OBLIGATORIO en tu modelo
            showFollowing: true,         // ✅ CAMPO OBLIGATORIO en tu modelo
            showAdmirers: true,          // ✅ CAMPO OBLIGATORIO en tu modelo
            activeHoursStart: nil,
            activeHoursEnd: nil,
            notificationPreferences: [
                NotificationType.like.rawValue: true,
                NotificationType.newFollower.rawValue: true,
                NotificationType.followRequest.rawValue: true,
                NotificationType.mutualConnection.rawValue: true,
                NotificationType.profileVisit.rawValue: true,
                NotificationType.comment.rawValue: true,
                NotificationType.storyReaction.rawValue: true,
                "commentsBestFriendsOnly": false,
                "muteOldPostLikes": false
            ],
            bestFriends: [],
            // ✅ CAMPOS DE ESTADO DE CUENTA
            isActive: true,
            deactivatedAt: nil,
            deactivatedBy: nil,
            // ✅ CAMPOS DE BADGES
            ownedBadges: [],
            plusSubscription: nil,
            primaryBadgeId: nil,
            showBadge: true,
            showPlusBadge: true,
            selectedProfileTheme: nil,
            isVerified: false, // ✅ NUEVO: Campo de verificación por defecto false
            // ✅ NUEVO: Campos de estado en línea
            onlineStatus: .offline,
            lastSeen: nil,
            isOnline: false
        )
        
        do {
    
            let encoder = Firestore.Encoder()
            var userData = try encoder.encode(newUser)
            
            // ✅ AGREGAR CAMPOS ADICIONALES DE FIRESTORE
            userData["createdAt"] = FieldValue.serverTimestamp()
            userData["updatedAt"] = FieldValue.serverTimestamp()
            
            // ✅ ASEGURAR CAMPOS DE ESTADO CORRECTOS
            userData["isActive"] = true
            userData["isSuspended"] = false
            
            // ✅ CORREGIDO: NO usar FieldValue.delete() con setData()
            // En su lugar, simplemente no incluir estos campos
            userData.removeValue(forKey: "deactivatedAt")
            userData.removeValue(forKey: "deactivatedBy")
            userData.removeValue(forKey: "reactivatedAt")
            userData.removeValue(forKey: "suspendedUntil")
            userData.removeValue(forKey: "suspensionReason")
            

            
            let usernameData: [String: Any] = [
                "userId": userId,
                "email": email,
                "createdAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp()
            ]
            

            
            let batch = db.batch()
            
            // ✅ Crear documento de usuario
            let userRef = db.collection("users").document(userId)
            batch.setData(userData, forDocument: userRef)
            
            
            // ✅ Crear documento de username
            let usernameRef = db.collection("usernames").document(username.lowercased())
            batch.setData(usernameData, forDocument: usernameRef)
            
            
            // ✅ Ejecutar batch
            batch.commit { error in
                if let error = error {
                    completion(error)
                } else {
                    // ✅ VERIFICACIÓN: Comprobar que el documento se creó correctamente
                    self.verifyUserCreation(userId: userId) { verified in
                        completion(nil)
                    }
                }
            }
            
        } catch {
            completion(error)
        }
    }
    
    // ✅ FUNCIÓN DE VERIFICACIÓN
    private func verifyUserCreation(userId: String, completion: @escaping (Bool) -> Void) {
        // Esperar un poco antes de verificar para dar tiempo a Firestore
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.db.collection("users").document(userId).getDocument { snapshot, error in
                if let error = error {
                    completion(false)
                    return
                }
                
                if let data = snapshot?.data() {
                    completion(true)
                } else {
                    completion(false)
                }
            }
        }
    }
    
    // ✅ FUNCIÓN FETCHUSER CORREGIDA para manejar mejor los errores
    func fetchUser(userId: String, completion: @escaping (Result<AppUser, Error>) -> Void) {
        guard !userId.isEmpty else {
            completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "El userId está vacío"])))
            return
        }
        db.collection("users").document(userId).getDocument { snapshot, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let document = snapshot, document.exists else {
                completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Documento no encontrado"])))
                return
            }
            do {
                // ✅ USAR EL DECODER DE FIRESTORE para manejar automáticamente los tipos
                let user = try document.data(as: AppUser.self)
                completion(.success(user))
            } catch {
                // ✅ FALLBACK: Intentar decodificación manual si falla la automática
                if let data = document.data() {
                    self.attemptManualDecoding(data: data, completion: completion)
                } else {
                    completion(.failure(error))
                }
            }
        }
    }
    
    // ✅ FUNCIÓN DE FALLBACK: Decodificación manual para casos problemáticos
    private func attemptManualDecoding(data: [String: Any], completion: @escaping (Result<AppUser, Error>) -> Void) {
        guard let id = data["id"] as? String,
              let email = data["email"] as? String else {
            completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Campos obligatorios faltantes"])))
            return
        }
        // Crear AppUser con valores por defecto para campos faltantes
        let user = AppUser(
            id: id,
            username: (data["username"] as? String) ?? "usuario_desconocido",
            email: email,
            interests: (data["interests"] as? [String]) ?? [],
            isPlusSubscriber: (data["isPlusSubscriber"] as? Bool) ?? false,
            profileImagePath: data["profileImagePath"] as? String,
            bio: data["bio"] as? String,
            blockedUsers: (data["blockedUsers"] as? [String]) ?? [],
            isPrivate: (data["isPrivate"] as? Bool) ?? false,
            showMutualConnections: (data["showMutualConnections"] as? Bool) ?? true,
            showFollowing: (data["showFollowing"] as? Bool) ?? true,
            activeHoursStart: data["activeHoursStart"] as? String,
            activeHoursEnd: data["activeHoursEnd"] as? String,
            notificationPreferences: data["notificationPreferences"] as? [String: Bool],
            bestFriends: (data["bestFriends"] as? [String]) ?? [],
            isActive: (data["isActive"] as? Bool) ?? true,
            deactivatedAt: nil, // Se manejará por separado si es necesario
            deactivatedBy: data["deactivatedBy"] as? String,
            ownedBadges: [], // Se cargará por separado si es necesario
            plusSubscription: nil, // Se cargará por separado si es necesario
            primaryBadgeId: data["primaryBadgeId"] as? String,
            showBadge: (data["showBadge"] as? Bool) ?? true
        )
        
        completion(.success(user))
    }
    
    // ✅ FUNCIÓN PARA OBTENER INTERESES DISPONIBLES
    func fetchAvailableInterests(completion: @escaping (Result<[String], Error>) -> Void) {
        db.collection("interests").getDocuments { snapshot, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            let interests = snapshot?.documents.compactMap { $0.data()["name"] as? String } ?? []
            completion(.success(interests))
        }
    }
    
    
    func fetchUserProfile(userId: String, completion: @escaping (Result<AppUser, Error>) -> Void) {
        self.db.collection("users").document(userId).getDocument(source: .default, completion: { snapshot, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let document = snapshot, document.exists else {
                completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Documento no encontrado"])))
                return
            }

            do {
                let user = try document.data(as: AppUser.self)
                completion(.success(user))
            } catch {
                completion(.failure(error))
            }
        })
    }

    func fetchConnections(userId: String, completion: @escaping (Result<[Connection], Error>) -> Void) {
        self.db.collection("users").document(userId).collection("connections")
            .order(by: "timestamp", descending: true)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let documents = snapshot?.documents else {
                    completion(.success([]))
                    return
                }

                let connections = documents.compactMap { doc -> Connection? in
                    do {
                        return try doc.data(as: Connection.self)
                    } catch {
                        return nil
                    }
                }
                completion(.success(connections))
            }
    }

    func fetchAdmirers(userId: String, completion: @escaping (Result<[Admirer], Error>) -> Void) {
        self.db.collection("users").document(userId).collection("admirers")
            .order(by: "timestamp", descending: true)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let documents = snapshot?.documents else {
                    completion(.success([]))
                    return
                }

                let admirers = documents.compactMap { doc -> Admirer? in
                    do {
                        return try doc.data(as: Admirer.self)
                    } catch {
                        return nil
                    }
                }
                completion(.success(admirers))
            }
    }



    func fetchMutualConnections(userId: String, completion: @escaping (Result<[AppUser], Error>) -> Void) {
        let group = DispatchGroup()
        var followingIds: Set<String> = []
        var followerIds: Set<String> = []
        var fetchError: Error?
        
        group.enter()
        fetchFollowing(userId: userId) { result in
            defer { group.leave() }
            switch result {
            case .success(let users):
                // ✅ Use compactMap to safely unwrap the optional IDs
                followingIds = Set(users.compactMap { $0.id })
            case .failure(let error):
                fetchError = error
            }
        }
        
        group.enter()
        fetchFollowers(userId: userId) { result in
            defer { group.leave() }
            switch result {
            case .success(let users):
                // ✅ Use compactMap here as well
                followerIds = Set(users.compactMap { $0.id })
            case .failure(let error):
                fetchError = error
            }
        }
        
        group.notify(queue: .main) {
            if let error = fetchError {
                completion(.failure(error))
                return
            }
            
            let mutualIds = Array(followingIds.intersection(followerIds))
            
            if mutualIds.isEmpty {
                completion(.success([]))
                return
            }
            
            // Now 'mutualIds' is correctly of type [String]
            self.fetchUsers(userIds: mutualIds, completion: completion)
        }
    }

    func updateProfilePicture(userId: String, profileImagePath: String, completion: @escaping (Error?) -> Void) {
        self.db.collection("users").document(userId).updateData([
            "profileImagePath": profileImagePath
        ]) { error in
            if let error = error {
                // Handle error silently
            } else {
                // Success
            }
            completion(error)
        }
    }
    
    func createMoment(
        userId: String,
        content: String,
        mediaItems: [MediaItem],
        taggedUsers: [String]? = nil,
        location: String? = nil,
        locationCoordinate: Moment.LocationCoordinate? = nil,  // ✅ NUEVO: Coordenadas de ubicación
        audience: String? = nil,
        aspectRatio: String? = nil,
        disableComments: Bool = false,
        hideLikeCounts: Bool = false,
        allowSharing: Bool = true,
        completion: @escaping (Error?) -> Void
    ) {
        self.fetchUser(userId: userId) { [weak self] result in
            guard let self = self else {
                completion(NSError(
                    domain: "",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Operación cancelada"]
                ))
                return
            }
            
            switch result {
            case .success(let user):
                let imagePath = mediaItems.first(where: { $0.type == .image })?.url
                
                // 🔥 EXTRAER DATOS DEL VIDEO COMPLETOS
                let videoItem = mediaItems.first(where: { $0.type == .video })
                let videoUrl = videoItem?.url
                let thumbnailUrl = videoItem?.thumbnailUrl
                let videoDuration = videoItem?.videoDuration
                let videoFileSize = videoItem?.videoFileSize
                let videoResolution = videoItem?.videoResolution
                
                let moment = Moment(
                    id: nil,
                    authorId: userId,
                    username: user.username,
                    content: content,
                    imagePath: imagePath,
                    videoUrl: videoUrl,
                    timestamp: Date(),
                    reactions: [:],
                    commentCount: 0,
                    profileImagePath: user.profileImagePath,
                    taggedUsers: taggedUsers,
                    location: location,
                    locationCoordinate: locationCoordinate,  // ✅ MOVIDO: Antes de audience
                    audience: audience,
                    mediaItems: mediaItems,
                    aspectRatio: aspectRatio ?? "1:1",
                    customListId: nil,
                    // 🔥 NUEVOS CAMPOS DE VIDEO
                    thumbnailUrl: thumbnailUrl,
                    videoDuration: videoDuration,
                    videoFileSize: videoFileSize,
                    videoResolution: videoResolution,
                    disableComments: disableComments,
                    hideLikeCounts: hideLikeCounts,
                    allowSharing: allowSharing
                )
                
                do {
                    let encoder = Firestore.Encoder()
                    var momentData = try encoder.encode(moment)
                    
                    // 🔥 INCLUIR METADATA COMPLETA EN MEDIAITEMS
                    momentData["mediaItems"] = mediaItems.map { item in
                        var mediaData: [String: Any] = [
                            "id": item.id,
                            "type": item.type.rawValue,
                            "url": item.url
                        ]
                        
                        // Añadir campos de video si existen
                        if let thumbnailUrl = item.thumbnailUrl {
                            mediaData["thumbnailUrl"] = thumbnailUrl
                        }
                        if let videoDuration = item.videoDuration {
                            mediaData["videoDuration"] = videoDuration
                        }
                        if let videoFileSize = item.videoFileSize {
                            mediaData["videoFileSize"] = videoFileSize
                        }
                        if let videoResolution = item.videoResolution {
                            mediaData["videoResolution"] = videoResolution
                        }
                        
                        return mediaData
                    }
                    
                    self.db.collection("users")
                        .document(userId)
                        .collection("moments")
                        .addDocument(data: momentData) { error in
                            if let error = error {
                                completion(error)
                            } else {
                                completion(nil)
                            }
                        }
                } catch {
                    completion(error)
                }
                
            case .failure(let error):
                completion(error)
            }
        }
    }

    func createStory(userId: String,mediaItem: MediaItem,audience: String? = nil,text: String? = nil,textPosition: CGPoint? = nil,textStyle: String? = nil,stickers: [StickerData]? = nil,drawingData: Data? = nil,chainId: String? = nil,chainPosition: Int? = nil,chainTitle: String? = nil,
    completion: @escaping (Error?) -> Void
    ) {
        self.fetchUser(userId: userId) { [weak self] result in
            guard let self = self else {
                completion(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Operación cancelada"]))
                return
            }

            switch result {
            case .success(let user):
                let isChain = chainId != nil
                let expirationDate = self.calculateStoryExpirationDate(isChain: isChain, chainId: chainId)
                let duration = mediaItem.type == .video ? 60.0 : 10.0
                let storyId = UUID().uuidString

                let story = Story(
                    id: storyId,
                    authorId: userId,
                    username: user.username,
                    mediaItem: mediaItem,
                    duration: duration,
                    timestamp: Date(),
                    expirationDate: expirationDate,
                    profileImagePath: user.profileImagePath,
                    audience: audience,
                    text: text,
                    textPosition: textPosition,
                    textStyle: textStyle,
                    stickers: stickers,
                    drawingData: drawingData,
                    chainId: chainId, // 🔗 AÑADIDO: ID de la cadena
                    chainPosition: chainPosition, // 🔗 AÑADIDO: Posición en la cadena
                    chainTitle: chainTitle // 🔗 AÑADIDO: Título de la cadena
                )

                do {
                    let encoder = Firestore.Encoder()
                    var storyData = try encoder.encode(story)
                    
                    // Manejar CGPoint para textPosition si existe
                    if let textPosition = textPosition {
                        storyData["textPositionX"] = textPosition.x
                        storyData["textPositionY"] = textPosition.y
                    }
                    
                    // Manejar stickers array
                    if let stickers = stickers {
                        storyData["stickers"] = stickers.map { sticker in
                            var stickerData: [String: Any] = [
                                "type": sticker.type,
                                "content": sticker.content,
                                "positionX": sticker.position.x,
                                "positionY": sticker.position.y,
                                "scale": sticker.scale,
                                "rotation": sticker.rotation
                            ]
                            
                            // ✅ INCLUIR PROPIEDADES DE ANIMACIÓN
                            if sticker.isAnimated {
                                stickerData["isAnimated"] = true
                                if let gifURL = sticker.gifURL {
                                    stickerData["gifURL"] = String(describing: gifURL)
                                }
                            }
                            
                            return stickerData
                        }
                    }

                    self.db.collection("users").document(userId)
                        .collection("stories").document(storyId)
                        .setData(storyData) { error in
                            if let error = error {
                                completion(error)
                            } else {
                                completion(nil)
                            }
                        }
                } catch {
                    completion(error)
                }

            case .failure(let error):
                completion(error)
            }
        }
    }
    
    func searchUsers(query: String, limit: Int = 10, completion: @escaping (Result<[AppUser], Error>) -> Void) {
        guard !query.isEmpty else {
            completion(.success([]))
            return
        }
        
        // Búsqueda por username que comience con el query
        db.collection("users")
            .whereField("username", isGreaterThanOrEqualTo: query.lowercased())
            .whereField("username", isLessThanOrEqualTo: query.lowercased() + "\u{f8ff}")
            .limit(to: 20)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    completion(.success([]))
                    return
                }
                
                let users = documents.compactMap { doc -> AppUser? in
                    do {
                        return try doc.data(as: AppUser.self)
                    } catch {
                        return nil
                    }
                }
                
                completion(.success(users))
            }
    }
    
    func fetchUsers(userIds: [String], completion: @escaping (Result<[AppUser], Error>) -> Void) {
        if userIds.isEmpty {
            completion(.success([]))
            return
        }

        self.db.collection("users")
            .whereField(FieldPath.documentID(), in: userIds)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let documents = snapshot?.documents else {
                    completion(.success([]))
                    return
                }

                let users = documents.compactMap { doc -> AppUser? in
                    do {
                        return try doc.data(as: AppUser.self)
                    } catch {
                        return nil
                    }
                }
                completion(.success(users))
            }
    }
    
    func fetchUserDataForGemini(userId: String, completion: @escaping (Result<AppUser, Error>) -> Void) {
        db.collection("users").document(userId).getDocument { snapshot, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let document = snapshot, document.exists else {
                completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Usuario no encontrado"])))
                return
            }
            do {
                let user = try document.data(as: AppUser.self)
                completion(.success(user))
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    func fetchInitialMoments(for userId: String, completion: @escaping (Result<(moments: [Moment], lastDocument: DocumentSnapshot?), Error>) -> Void) {
        self.fetchConnections(userId: userId) { result in
            switch result {
            case .success(let connections):
                let connectionIds = connections.map { $0.userId }
                if connectionIds.isEmpty {
                    completion(.success((moments: [], lastDocument: nil)))
                    return
                }

                var allMoments: [Moment] = []
                let group = DispatchGroup()
                var lastDocument: DocumentSnapshot?

                for connectionId in connectionIds {
                    group.enter()
                    self.db.collection("users").document(connectionId).collection("moments")
                        .order(by: "timestamp", descending: true)
                        .limit(to: 10)
                        .getDocuments { snapshot, error in
                            if let error = error {
                                group.leave()
                                return
                            }

                            let moments = snapshot?.documents.compactMap { doc -> Moment? in
                                try? doc.data(as: Moment.self)
                            } ?? []
                            allMoments.append(contentsOf: moments)
                            lastDocument = snapshot?.documents.last
                            group.leave()
                        }
                }

                group.notify(queue: .main) {
                    allMoments.sort { $0.timestamp > $1.timestamp }
                    let limitedMoments = Array(allMoments.prefix(10))
                    completion(.success((moments: limitedMoments, lastDocument: lastDocument)))
                }

            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    func fetchMoreMoments(for userId: String, startAfter: DocumentSnapshot, completion: @escaping (Result<(moments: [Moment], lastDocument: DocumentSnapshot?), Error>) -> Void) {
        self.fetchConnections(userId: userId) { result in
            switch result {
            case .success(let connections):
                let connectionIds = connections.map { $0.userId }
                if connectionIds.isEmpty {
                    completion(.success((moments: [], lastDocument: nil)))
                    return
                }

                var allMoments: [Moment] = []
                let group = DispatchGroup()
                var lastDocument: DocumentSnapshot?

                for connectionId in connectionIds {
                    group.enter()
                    self.db.collection("users").document(connectionId).collection("moments")
                        .order(by: "timestamp", descending: true)
                        .start(afterDocument: startAfter)
                        .limit(to: 10)
                        .getDocuments { snapshot, error in
                            if let error = error {
                                group.leave()
                                return
                            }

                            let moments = snapshot?.documents.compactMap { doc -> Moment? in
                                try? doc.data(as: Moment.self)
                            } ?? []
                            allMoments.append(contentsOf: moments)
                            lastDocument = snapshot?.documents.last
                            group.leave()
                        }
                }

                group.notify(queue: .main) {
                    allMoments.sort { $0.timestamp > $1.timestamp }
                    let limitedMoments = Array(allMoments.prefix(10))
                    completion(.success((moments: limitedMoments, lastDocument: lastDocument)))
                }

            case .failure(let error):
                completion(.failure(error))
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
    
    func fetchMoments(for userId: String, completion: @escaping (Result<[Moment], Error>) -> Void) {
        self.db.collection("users").document(userId).collection("moments")
            .order(by: "timestamp", descending: true)
            .limit(to: 20)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let documents = snapshot?.documents else {
                    completion(.success([]))
                    return
                }

                let moments = documents.compactMap { doc -> Moment? in
                    try? doc.data(as: Moment.self)
                }
                completion(.success(moments))
            }
    }

    // ✅ FUNCIÓN fetchComments CORREGIDA - Incluye TODOS los campos necesarios
    func fetchComments(for momentId: String, userId: String, limit: Int = 10, lastDocument: DocumentSnapshot? = nil, completion: @escaping (Result<(comments: [Comment], lastDocument: DocumentSnapshot?), Error>) -> Void) {
        
        var query = db.collection("users").document(userId).collection("moments").document(momentId).collection("comments")
            .order(by: "timestamp", descending: false)
            .limit(to: limit)
        
        if let lastDocument = lastDocument {
            query = query.start(afterDocument: lastDocument)
        }
        
        query.getDocuments { snapshot, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            let comments = snapshot?.documents.compactMap { document -> Comment? in
                let data = document.data()
                guard let authorId = data["authorId"] as? String,
                      let username = data["username"] as? String,
                      let content = data["content"] as? String,
                      let timestamp = (data["timestamp"] as? Timestamp)?.dateValue() else {
                    return nil
                }
                
                // ✅ CAMPOS ADICIONALES NECESARIOS PARA ANIDACIÓN
                let profileImagePath = data["profileImagePath"] as? String
                let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue()
                let reactions = data["reactions"] as? [String: [String]] ?? [:] // ✅ IMPORTANTE
                let parentCommentId = data["parentCommentId"] as? String // ✅ CLAVE PARA ANIDACIÓN
                let isEdited = data["isEdited"] as? Bool ?? false // ✅ PARA INDICADOR DE EDITADO
                let editedTimestamp = (data["editedTimestamp"] as? Timestamp)?.dateValue() // ✅ TIMESTAMP DE EDICIÓN
                
                return Comment(
                    id: document.documentID,
                    authorId: authorId,
                    username: username,
                    content: content,
                    timestamp: timestamp,
                    profileImagePath: profileImagePath,
                    updatedAt: updatedAt,
                    reactions: reactions, // ✅ AGREGADO
                    parentCommentId: parentCommentId, // ✅ AGREGADO - CLAVE PARA ANIDACIÓN
                    isEdited: isEdited, // ✅ AGREGADO
                    editedTimestamp: editedTimestamp // ✅ AGREGADO
                )
            }.filter { $0.id != nil } ?? []
            
            let lastDoc = snapshot?.documents.last
            
            // ✅ DEBUGGING: Mostrar estructura de anidación
            let rootComments = comments.filter { $0.parentCommentId == nil }
            let replyComments = comments.filter { $0.parentCommentId != nil }
            
            completion(.success((comments: comments, lastDocument: lastDoc)))
        }
    }
    
    // ✅ FUNCIÓN addComment CORREGIDA - Asegura que parentCommentId se guarde correctamente
    func addComment(to momentId: String, userId: String, authorId: String, content: String, parentCommentId: String? = nil, completion: @escaping (Result<Void, Error>) -> Void) {
        let commentId = UUID().uuidString
        let now = Date()
        
        // Get current user's username
        fetchUser(userId: authorId) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let user):
                // ✅ DATOS DEL COMENTARIO CON ESTRUCTURA CORRECTA
                var commentData: [String: Any] = [
                    "authorId": authorId,
                    "username": user.username,
                    "content": content,
                    "timestamp": Timestamp(date: now),
                    "profileImagePath": user.profileImagePath ?? NSNull(),
                    "updatedAt": NSNull(),
                    "reactions": [:] as [String: [String]], // ✅ INICIALIZAR VACÍO
                    "isEdited": false,
                    "editedTimestamp": NSNull()
                ]
                
                // ✅ MANEJO CORRECTO DE parentCommentId
                if let parentCommentId = parentCommentId {
                    commentData["parentCommentId"] = parentCommentId
                } else {
                    commentData["parentCommentId"] = NSNull()
                }
                
                let batch = self.db.batch()
                
                // Add comment
                let commentRef = self.db.collection("users").document(userId).collection("moments").document(momentId).collection("comments").document(commentId)
                batch.setData(commentData, forDocument: commentRef)
                
                // Update comment count
                let momentRef = self.db.collection("users").document(userId).collection("moments").document(momentId)
                batch.updateData([
                    "commentCount": FieldValue.increment(Int64(1))
                ], forDocument: momentRef)
                
                batch.commit { error in
                    if let error = error {
                        completion(.failure(error))
                    } else {
                        completion(.success(()))
                        
                        // Send notifications
                        if let parentCommentId = parentCommentId {
                            // Es una respuesta - notificar al autor del comentario padre
                            self.notifyCommentReply(
                                parentCommentId: parentCommentId,
                                momentId: momentId,
                                momentAuthorId: userId,
                                fromUserId: authorId,
                                content: content
                            )
                        } else {
                            // Es un comentario nuevo - notificar al autor del momento
                            NotificationService.shared.sendCommentNotification(
                                to: userId,
                                from: authorId,
                                momentId: momentId,
                                content: content,
                                momentAuthor: user.username
                            )
                        }
                        
                        // Handle mentions
                        let mentions = self.extractMentions(from: content)
                        self.handleMentions(mentions, momentId: momentId, fromUserId: authorId, content: content)
                    }
                }
                
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    func updateComment(momentId: String, userId: String, commentId: String, content: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let commentRef = db.collection("users").document(userId).collection("moments").document(momentId).collection("comments").document(commentId)
        
        commentRef.updateData([
            "content": content,
            "isEdited": true,
            "editedTimestamp": Timestamp(date: Date())
        ]) { error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
                
                // Handle new mentions in edited comment
                let mentions = self.extractMentions(from: content)
                self.handleMentions(mentions, momentId: momentId, fromUserId: Auth.auth().currentUser?.uid ?? "", content: content)
            }
        }
    }
    
    func deleteComment(to momentId: String, commentId: String, userId: String, authorId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let batch = db.batch()
        
        // Delete comment
        let commentRef = db.collection("users").document(userId).collection("moments").document(momentId).collection("comments").document(commentId)
        
        // First check if comment exists
        commentRef.getDocument { snapshot, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard snapshot?.exists == true else {
                completion(.failure(NSError(domain: "CommentNotFound", code: 404, userInfo: [NSLocalizedDescriptionKey: "Comment not found"])))
                return
            }
            
            // Delete the comment
            batch.deleteDocument(commentRef)
            
            // Update comment count
            let momentRef = self.db.collection("users").document(userId).collection("moments").document(momentId)
            batch.updateData([
                "commentCount": FieldValue.increment(Int64(-1))
            ], forDocument: momentRef)
            
            // Also delete any nested comments (replies)
            self.db.collection("users").document(userId).collection("moments").document(momentId).collection("comments")
                .whereField("parentCommentId", isEqualTo: commentId)
                .getDocuments { nestedSnapshot, nestedError in
                    
                    if let nestedError = nestedError {
                        // Handle nested error silently
                    }
                    
                    let nestedDocs = nestedSnapshot?.documents ?? []
                    
                    // Delete nested comments
                    for nestedDoc in nestedDocs {
                        batch.deleteDocument(nestedDoc.reference)
                        // Decrement count for each nested comment too
                        batch.updateData([
                            "commentCount": FieldValue.increment(Int64(-1))
                        ], forDocument: momentRef)
                    }
                    
                    // Commit the batch
                    batch.commit { batchError in
                        if let batchError = batchError {
                            completion(.failure(batchError))
                        } else {
                            completion(.success(()))
                        }
                    }
                }
        }
    }
    
    private func notifyCommentReply(parentCommentId: String, momentId: String, momentAuthorId: String, fromUserId: String, content: String) {
        // Buscar el comentario padre para obtener su autor
        db.collection("users").document(momentAuthorId).collection("moments").document(momentId).collection("comments").document(parentCommentId).getDocument { snapshot, error in
            
            guard let data = snapshot?.data(),
                  let parentAuthorId = data["authorId"] as? String else { return }
            
            NotificationService.shared.sendCommentReplyNotification(
                to: parentAuthorId,
                from: fromUserId,
                momentId: momentId,
                content: content,
                parentCommentId: parentCommentId
            )
        }
    }
    
    private func extractMentions(from text: String) -> [String] {
        let pattern = #"@(\w+)"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex?.matches(in: text, range: range) ?? []
        
        return matches.compactMap { match in
            guard let range = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[range])
        }
    }
    
    private func handleMentions(_ mentions: [String], momentId: String, fromUserId: String, content: String) {
        for mention in mentions {
            // Find user by username and send notification
            db.collection("users").whereField("username", isEqualTo: mention.lowercased()).getDocuments { snapshot, error in
                guard let documents = snapshot?.documents, let userDoc = documents.first else { return }
                
                let mentionedUserId = userDoc.documentID
                NotificationService.shared.sendMentionNotification(
                    to: mentionedUserId,
                    from: fromUserId,
                    contentId: momentId,
                    contentType: "moment",
                    content: content
                )
            }
        }
    }
    
    func fetchSuggestedUsers(completion: @escaping (Result<[AppUser], Error>) -> Void) {
        self.db.collection("users")
            .limit(to: 10)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    completion(.success([]))
                    return
                }
                
                let users = documents.compactMap { doc -> AppUser? in
                    do {
                        return try doc.data(as: AppUser.self)
                    } catch {
                        return nil
                    }
                }.filter { $0.id != Auth.auth().currentUser?.uid }
                completion(.success(users))
            }
    }
    
    // ✅ MÉTODO CORREGIDO para FirestoreService.swift - REEMPLAZAR el método existente
    func addReaction(to momentId: String, reaction: String, userId: String, authorId: String, completion: @escaping (Error?) -> Void) {
        // ✅ CAMBIO PRINCIPAL: Usar la subcolección de reacciones
        let reactionRef = db.collection("users").document(authorId)
            .collection("moments").document(momentId)
            .collection("reactions").document(userId) // Usar userId como ID del documento
        
        // Primero verificar si ya existe una reacción de este usuario
        reactionRef.getDocument { [weak self] snapshot, error in
            guard let self = self else {
                completion(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Operación cancelada"]))
                return
            }
            
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
                            // Crear notificación solo si no es el autor
                            if userId != authorId {
                                self.createReactionNotification(userId: userId, authorId: authorId, momentId: momentId, reactionType: reaction, completion: completion)
                            } else {
                                completion(nil)
                            }
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
                        // Crear notificación solo si no es el autor
                        if userId != authorId {
                            self.createReactionNotification(userId: userId, authorId: authorId, momentId: momentId, reactionType: reaction, completion: completion)
                        } else {
                            completion(nil)
                        }
                    }
                }
            }
        }
    }

    // ✅ MÉTODO AUXILIAR para obtener contador de reacciones
    private func getMomentReactionCount(momentId: String, userId: String, completion: @escaping (Int) -> Void) {
        db.collection("users").document(userId)
            .collection("moments").document(momentId)
            .collection("reactions")
            .getDocuments { snapshot, error in
                let count = snapshot?.documents.count ?? 0
                completion(count)
            }
    }
    
    // ✅ MÉTODO AUXILIAR para notificaciones
    private func createReactionNotification(userId: String, authorId: String, momentId: String, reactionType: String, completion: @escaping (Error?) -> Void) {
        fetchUser(userId: userId) { result in
            switch result {
            case .success(let user):
                // ✅ OBTENER el contador actual de reacciones para el momento
                self.getMomentReactionCount(momentId: momentId, userId: authorId) { reactionCount in
                    self.createNotification(
                        recipientId: authorId,
                        senderId: userId,
                        senderUsername: user.username,
                        type: .reaction, // ✅ CORREGIDO: Usar .reaction para reacciones a momentos
                        momentId: momentId,
                        isPending: false,
                        reaction: reactionType, // ✅ Pasar el tipo de reacción (love, fire, etc.)
                        completion: { error in
                            if let error = error {
                            }
                            completion(error)
                        }
                    )
                }
            case .failure(let error):
                completion(error)
            }
        }
    }
    
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
            
            batch.commit { [weak self] error in
                if let error = error {
                    completion(error)
                } else {
                    self?.createNotification(
                        recipientId: recipientId,
                        senderId: senderId,
                        senderUsername: senderUsername,
                        type: .followRequest,
                        momentId: nil,
                        isPending: true,
                        completion: { notificationError in
                            completion(nil)
                        }
                    )
                }
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
                if let error = error {
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
            
            self.performFollow(currentUserId: senderId, targetUserId: recipientId) { error in
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
                
                // 3. Eliminar notificación de solicitud de seguimiento completamente
                let notificationRef = self.db.collection("users").document(recipientId)
                    .collection("notifications").document(notificationId)
                batch.deleteDocument(notificationRef)
                
                batch.commit { error in
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
            
            // 3. Eliminar notificación completamente
            let notificationRef = self.db.collection("users").document(recipientId)
                .collection("notifications").document(notificationId)
            batch.deleteDocument(notificationRef)
            
            batch.commit { error in
                if let error = error {
                    completion(error)
                } else {
                    completion(nil)
                }
            }
        }
    }

    private func getFollowRequestByUsers(senderId: String, recipientId: String, completion: @escaping (FollowRequest?) -> Void) {
        db.collection("users").document(recipientId).collection("receivedFollowRequests")
            .whereField("senderId", isEqualTo: senderId)
            .whereField("status", isEqualTo: FollowRequestStatus.pending.rawValue)
            .limit(to: 1)
            .getDocuments { snapshot, error in
                if let error = error {
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
        guard currentUserId != targetUserId else {
            completion(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No puedes seguirte a ti mismo"]))
            return
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

    private func performFollow(currentUserId: String, targetUserId: String, completion: @escaping (Error?) -> Void) {
        fetchUserProfile(userId: currentUserId) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let currentUser):
                let batch = db.batch()
                
                // Añadir a following del usuario actual
                let followingRef = db.collection("users").document(currentUserId).collection("following").document(targetUserId)
                let followingData: [String: Any] = [
                    "userId": targetUserId,
                    "timestamp": Timestamp(date: Date())
                ]
                batch.setData(followingData, forDocument: followingRef)
                
                // Añadir a followers del usuario objetivo
                let followerRef = db.collection("users").document(targetUserId).collection("followers").document(currentUserId)
                let followerData: [String: Any] = [
                    "userId": currentUserId,
                    "timestamp": Timestamp(date: Date())
                ]
                batch.setData(followerData, forDocument: followerRef)
                
                
                batch.commit { [weak self] error in
                    if let error = error {
                        completion(error)
                    } else {
                        
                        // Limpiar cache después de follow exitoso
                        self?.invalidateFollowingCache(currentUserId: currentUserId, targetUserId: targetUserId)
                        
                        // Crear notificación de nuevo seguidor
                        self?.createNotification(
                            recipientId: targetUserId,
                            senderId: currentUserId,
                            senderUsername: currentUser.username,
                            type: .newFollower,
                            momentId: nil,
                            isPending: false,
                            completion: { _ in completion(nil) }
                        )
                    }
                }
            case .failure(let error):
                completion(error)
            }
        }
    }

    // MARK: - FUNCIÓN UNFOLLOWUSER CORREGIDA CON CACHE MANAGEMENT
    func unfollowUser(currentUserId: String, targetUserId: String, completion: @escaping (Error?) -> Void) {
        
        // Verificar que los IDs no estén vacíos
        guard !currentUserId.isEmpty, !targetUserId.isEmpty else {
            let error = NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "IDs de usuario vacíos"])
            completion(error)
            return
        }
        
        // Verificar que no sean el mismo usuario
        guard currentUserId != targetUserId else {
            let error = NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No puedes dejar de seguirte a ti mismo"])
            completion(error)
            return
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
                    
                    // VERIFICACIÓN POST-UNFOLLOW CON DELAY (sin cache)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.db.collection("users").document(currentUserId).collection("following").document(targetUserId).getDocument { snapshot, error in
                            if let error = error {
                            } else {
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
            if let error = error {
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
                self.fetchUsersByIdsClean(userIds: followingIds, completion: completion)
            }
    }

    // ✅ FUNCIÓN LIMPIA: fetchUsersByIds sin debug logs
    private func fetchUsersByIdsClean(userIds: [String], completion: @escaping (Result<[AppUser], Error>) -> Void) {
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
                    defer { group.leave() }
                    
                    if let error = error {
                        syncQueue.async { capturedError = error }
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
                    
                    syncQueue.async {
                        allUsers.append(contentsOf: users)
                    }
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
                
                self.fetchUsers(userIds: userIds, completion: completion)
            }
    }

    // MARK: - RESTO DE FUNCIONES SIN CAMBIOS
    func updateBio(userId: String, bio: String, completion: @escaping (Error?) -> Void) {
        self.db.collection("users").document(userId).updateData([
            "bio": bio
        ]) { error in
            if let error = error {
                completion(error)
            } else {
                completion(nil)
            }
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
                    ChatService().deleteConversationsBetweenUsers(user1Id: currentUserId, user2Id: targetUserId) { error in
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

    func updateActiveHours(userId: String, startHour: String?, endHour: String?, completion: @escaping (Error?) -> Void) {
        self.db.collection("users").document(userId).updateData([
            "activeHoursStart": startHour as Any,
            "activeHoursEnd": endHour as Any
        ]) { error in
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
                completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Operación cancelada"])))
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

    func createNotification(recipientId: String, senderId: String, senderUsername: String, type: NotificationType, momentId: String? = nil, isPending: Bool, storyId: String? = nil, storyAuthorId: String? = nil, reaction: String? = nil, completion: @escaping (Error?) -> Void) {
        fetchUserProfile(userId: recipientId) { result in
            switch result {
            case .success(let user):
                // Verificar preferencias de notificación
                guard user.notificationPreferences?[type.rawValue] ?? true else {
                    completion(nil)
                    return
                }
                let notification = Notification(
                    id: UUID().uuidString,
                    type: type,
                    senderId: senderId,
                    senderUsername: senderUsername,
                    timestamp: Date(),
                    isPending: isPending,
                    momentId: momentId,
                    visitCount: nil,
                    storyId: storyId,
                    storyAuthorId: storyAuthorId,
                    reaction: reaction
                )
                self.createNotification(notification: notification, for: recipientId) { error in
                    completion(error)
                }
            case .failure(let error):
                completion(error)
            }
        }
    }

    func createNotification(notification: Notification, for userId: String, completion: @escaping (Error?) -> Void) {
        let notificationData: [String: Any] = [
            "id": notification.id,
            "type": notification.type.rawValue,
            "senderId": notification.senderId,
            "senderUsername": notification.senderUsername,
            "timestamp": Timestamp(date: notification.timestamp),
            "isPending": notification.isPending,
            "momentId": notification.momentId as Any,
            "visitCount": notification.visitCount as Any,
            "storyId": notification.storyId as Any,
            "storyAuthorId": notification.storyAuthorId as Any,
            "reaction": notification.reaction as Any
        ]
        
        db.collection("users")
            .document(userId)
            .collection("notifications")
            .document(notification.id)
            .setData(notificationData) { error in
                completion(error)
            }
    }
    
    func fetchNotifications(for userId: String, completion: @escaping (Result<[Notification], Error>) -> Void) {
        self.db.collection("users").document(userId).collection("notifications")
            .order(by: "timestamp", descending: true)
            .limit(to: 50)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let documents = snapshot?.documents else {
                    completion(.success([]))
                    return
                }

                let notifications = documents.compactMap { doc -> Notification? in
                    try? doc.data(as: Notification.self)
                }
                completion(.success(notifications))
            }
    }
    
    func markNotificationsAsRead(userId: String, notificationIds: [String], completion: @escaping (Error?) -> Void) {
            let batch = db.batch()
            
            for notificationId in notificationIds {
                let notificationRef = db.collection("users")
                    .document(userId)
                    .collection("notifications")
                    .document(notificationId)
                batch.updateData(["isPending": false], forDocument: notificationRef)
            }
            
            batch.commit { error in
                if let error = error {
                    completion(error)
                } else {
                    completion(nil)
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
                completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Momento no encontrado"])))
                return
            }

            do {
                let moment = try document.data(as: Moment.self)
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
                completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Operación cancelada"])))
                return
            }

            switch result {
            case .success(let currentUser):
                let blockedUsers = Set(currentUser.blockedUsers ?? [])

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
                            if let error = error {
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
                        if (user.blockedUsers ?? []).contains(excludingUserId) { return false }
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

    func fetchMomentsFromUsers(userIds: [String], completion: @escaping (Result<[Moment], Error>) -> Void) {
        
        guard !userIds.isEmpty else {
            completion(.success([]))
            return
        }

        var allMoments: [Moment] = []
        let group = DispatchGroup()

        for userId in userIds {
            group.enter()
            self.fetchMoments(for: userId) { result in
                switch result {
                case .success(let moments):
                    allMoments.append(contentsOf: moments)
                case .failure(let error):
                    break
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            allMoments.sort { $0.timestamp > $1.timestamp }
            let limitedMoments = Array(allMoments.prefix(50))
            completion(.success(limitedMoments))
        }
    }
}

// MARK: - ✨ NUEVOS: Métodos para comentarios avanzados
extension FirestoreService {
    
    func notifyUserMention(username: String, commentContent: String, momentId: String) {
        db.collection("users")
            .whereField("username", isEqualTo: username.lowercased())
            .getDocuments { [weak self] snapshot, error in
                
                guard let self = self,
                      let documents = snapshot?.documents,
                      let userDoc = documents.first else { return }
                
                let mentionedUserId = userDoc.documentID
                guard let currentUserId = Auth.auth().currentUser?.uid else { return }
                
                self.createNotification(
                    recipientId: mentionedUserId,
                    senderId: currentUserId,
                    senderUsername: "Usuario", // Mejorar obteniendo username real
                    type: .comment,
                    momentId: momentId,
                    isPending: true
                ) { _ in }
            }
    }
    
    func createCommentNotification(
        momentId: String,
        momentAuthorId: String,
        commentAuthorId: String,
        commentId: String,
        commentContent: String,
        isReply: Bool = false,
        parentCommentAuthorId: String? = nil
    ) {
        guard commentAuthorId != momentAuthorId else { return }
        
        fetchUser(userId: commentAuthorId) { result in
            switch result {
            case .success(let user):
                self.createNotification(
                    recipientId: momentAuthorId,
                    senderId: commentAuthorId,
                    senderUsername: user.username,
                    type: .comment,
                    momentId: momentId,
                    isPending: true
                ) { _ in }
            case .failure: break
            }
        }
    }
}

extension FirestoreService {
    
    // ✅ NUEVA FUNCIÓN: addCommentReaction (similar a addReaction pero para comentarios)
    func addCommentReaction(to momentId: String, commentId: String, reaction: String, userId: String, authorId: String, completion: @escaping (Error?) -> Void) {
        let commentRef = db.collection("users").document(userId).collection("moments").document(momentId).collection("comments").document(commentId)
        
        commentRef.getDocument { snapshot, error in
            if let error = error {
                completion(error)
                return
            }
            
            guard let data = snapshot?.data(),
                  var reactions = data["reactions"] as? [String: [String]] else {
                // Si no hay reacciones, inicializar con estructura vacía
                let initialReactions = [reaction: [Auth.auth().currentUser?.uid ?? ""]]
                commentRef.updateData(["reactions": initialReactions]) { error in
                    if let error = error {
                        completion(error)
                    } else {
                        // Enviar notificación
                        self.sendCommentReactionNotification(
                            to: authorId,
                            from: Auth.auth().currentUser?.uid ?? "",
                            momentId: momentId,
                            commentId: commentId,
                            reaction: reaction
                        )
                        completion(nil)
                    }
                }
                return
            }
            
            let currentUserId = Auth.auth().currentUser?.uid ?? ""
            var reactionUsers = reactions[reaction] ?? []
            let wasLiked = reactionUsers.contains(currentUserId)
            
            if wasLiked {
                // Remover reacción
                reactionUsers.removeAll { $0 == currentUserId }
            } else {
                // Agregar reacción
                reactionUsers.append(currentUserId)
                
                // Enviar notificación solo para nuevas reacciones (no cuando se remueve)
                if authorId != currentUserId {
                    self.sendCommentReactionNotification(
                        to: authorId,
                        from: currentUserId,
                        momentId: momentId,
                        commentId: commentId,
                        reaction: reaction
                    )
                }
            }
            
            reactions[reaction] = reactionUsers
            
            // Actualizar con metadata adicional
            let updateData: [String: Any] = [
                "reactions": reactions,
                "metadata.lastReactionTimestamp": Timestamp(date: Date()),
                "metadata.totalReactions": reactions.values.map { $0.count }.reduce(0, +)
            ]
            
            commentRef.updateData(updateData) { error in
                if let error = error {
                    completion(error)
                } else {
                    completion(nil)
                }
            }
        }
    }
    
    // ✅ FUNCIÓN AUXILIAR: Enviar notificación de reacción en comentario
    private func sendCommentReactionNotification(to recipientId: String, from senderId: String, momentId: String, commentId: String, reaction: String) {
        // Solo enviar notificación si no es el mismo usuario
        guard recipientId != senderId else { return }
        
        fetchUser(userId: senderId) { result in
            switch result {
            case .success(let user):
                // Usar el sistema de notificaciones existente
                NotificationService.shared.sendCommentLikeNotification(
                    to: recipientId,
                    from: senderId,
                    momentId: momentId,
                    commentId: commentId
                )
                // Notificación enviada
                
            case .failure(let error):
                // Error silencioso
                break
            }
        }
    }
    
    // ✅ FUNCIÓN AUXILIAR: Obtener estadísticas de reacciones de comentario
    func getCommentReactionStats(momentId: String, userId: String, commentId: String, completion: @escaping (Result<[String: Int], Error>) -> Void) {
        let commentRef = db.collection("users").document(userId).collection("moments").document(momentId).collection("comments").document(commentId)
        
        commentRef.getDocument { snapshot, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = snapshot?.data(),
                  let reactions = data["reactions"] as? [String: [String]] else {
                completion(.success([:]))
                return
            }
            
            // Convertir array de usuarios a conteo
            var stats: [String: Int] = [:]
            for (reaction, users) in reactions {
                stats[reaction] = users.count
            }
            
            completion(.success(stats))
        }
    }
    
    // ✅ FUNCIÓN AUXILIAR: Verificar si el usuario actual reaccionó
    func hasUserReactedToComment(momentId: String, userId: String, commentId: String, reaction: String, completion: @escaping (Bool) -> Void) {
        let commentRef = db.collection("users").document(userId).collection("moments").document(momentId).collection("comments").document(commentId)
        let currentUserId = Auth.auth().currentUser?.uid ?? ""
        
        commentRef.getDocument { snapshot, error in
            if let error = error {
                completion(false)
                return
            }
            
            guard let data = snapshot?.data(),
                  let reactions = data["reactions"] as? [String: [String]],
                  let reactionUsers = reactions[reaction] else {
                completion(false)
                return
            }
            
            completion(reactionUsers.contains(currentUserId))
        }
    }
}

// MARK: - Funciones actualizadas de FirestoreService

extension FirestoreService {
    // Updated: Create moment with visibility
    func createMomentWithVisibility(
        userId: String,
        content: String,
        mediaItems: [MediaItem],
        taggedUsers: [String]? = nil,
        location: String? = nil,
        audienceSetting: CaptionAndDetailsView.AudienceSetting,  // ✅ MOVIDO: Antes de locationCoordinate
        locationCoordinate: Moment.LocationCoordinate? = nil,  // ✅ NUEVO: Coordenadas de ubicación
        selectedListId: String? = nil,
        customViewers: [String]? = nil,
        aspectRatio: String? = nil,
        disableComments: Bool = false,
        hideLikeCounts: Bool = false,
        allowSharing: Bool = true,
        completion: @escaping (String?, Error?) -> Void
    ) {
        // Map AudienceSetting to ContentAudience
        let contentAudience: ContentAudience
        switch audienceSetting {
        case .everyone: contentAudience = .everyone
        case .mutuals: contentAudience = .connections
        case .admirers: contentAudience = .connections
        case .bestFriends: contentAudience = .bestFriends
        case .custom: contentAudience = selectedListId != nil ? .customList : .custom
        }
        
        self.fetchUser(userId: userId) { [weak self] result in
            guard let self = self else {
                completion(nil, NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Operación cancelada"]))
                return
            }
            
            switch result {
            case .success(let user):
                let imagePath = mediaItems.first(where: { $0.type == .image })?.url
                
                // 🔥 EXTRAER DATOS DEL VIDEO COMPLETOS
                let videoItem = mediaItems.first(where: { $0.type == .video })
                let videoUrl = videoItem?.url
                let thumbnailUrl = videoItem?.thumbnailUrl
                let videoDuration = videoItem?.videoDuration
                let videoFileSize = videoItem?.videoFileSize
                let videoResolution = videoItem?.videoResolution
                
                let moment = Moment(
                    id: nil,
                    authorId: userId,
                    username: user.username,
                    content: content,
                    imagePath: imagePath,
                    videoUrl: videoUrl,
                    timestamp: Date(),
                    reactions: [:],
                    commentCount: 0,
                    profileImagePath: user.profileImagePath,
                    taggedUsers: taggedUsers,
                    location: location,
                    locationCoordinate: locationCoordinate,  // ✅ MOVIDO: Antes de audience
                    audience: contentAudience.rawValue,
                    mediaItems: mediaItems,
                    aspectRatio: aspectRatio ?? "1:1",
                    customListId: selectedListId,
                    // 🔥 NUEVOS CAMPOS DE VIDEO
                    thumbnailUrl: thumbnailUrl,
                    videoDuration: videoDuration,
                    videoFileSize: videoFileSize,
                    videoResolution: videoResolution,
                    disableComments: disableComments,
                    hideLikeCounts: hideLikeCounts,
                    allowSharing: allowSharing
                )
                
                do {
                    let encoder = Firestore.Encoder()
                    var momentData = try encoder.encode(moment)
                    
                    // 🔥 INCLUIR METADATA COMPLETA EN MEDIAITEMS
                    momentData["mediaItems"] = mediaItems.map { item in
                        var mediaData: [String: Any] = [
                            "id": item.id,
                            "type": item.type.rawValue,
                            "url": item.url
                        ]
                        
                        // Añadir campos de video si existen
                        if let thumbnailUrl = item.thumbnailUrl {
                            mediaData["thumbnailUrl"] = thumbnailUrl
                        }
                        if let videoDuration = item.videoDuration {
                            mediaData["videoDuration"] = videoDuration
                        }
                        if let videoFileSize = item.videoFileSize {
                            mediaData["videoFileSize"] = videoFileSize
                        }
                        if let videoResolution = item.videoResolution {
                            mediaData["videoResolution"] = videoResolution
                        }
                        
                        return mediaData
                    }
                    
                    if audienceSetting == .custom, let customViewers = customViewers, !customViewers.isEmpty {
                        self.saveCustomAudienceForContent(
                            contentType: "moment",
                            authorId: userId,
                            allowedUsers: customViewers
                        ) { error in
                            // Error silencioso
                        }
                    }
                    
                    var ref: DocumentReference? = nil
                    ref = self.db.collection("users")
                        .document(userId)
                        .collection("moments")
                        .addDocument(data: momentData) { error in
                            if let error = error {
                                completion(nil, error)
                            } else {
                                completion(ref!.documentID, nil)
                            }
                        }
                } catch {
                    completion(nil, error)
                }
                
            case .failure(let error):
                completion(nil, error)
            }
        }
    }
    
    // Updated: Create story with visibility
    func createStoryWithVisibility(
        userId: String,
        mediaItem: MediaItem,
        audienceSetting: ContentAudience, // 🔥 CAMBIADO: Usar ContentAudience directamente
        customViewers: [String]? = nil,
        text: String? = nil,
        textPosition: CGPoint? = nil,
        textStyle: String? = nil,
        stickers: [StickerData]? = nil,
        drawingData: Data? = nil,
        aspectRatio: String? = nil, // ✅ AÑADIDO: Aspect ratio del video
        backgroundFrameURL: String? = nil, // ✅ AÑADIDO: URL del frame de fondo
        chainId: String? = nil, // 🔗 AÑADIDO: ID de la cadena
        chainPosition: Int? = nil, // 🔗 AÑADIDO: Posición en la cadena
        chainTitle: String? = nil, // 🔗 AÑADIDO: Título de la cadena
        allowOthersToContinue: Bool? = nil, // 🔗 AÑADIDO: Si otros pueden continuar la cadena
        continuationAudience: ContentAudience? = nil, // 🔗 AÑADIDO: Audiencia que puede continuar
        continuationCustomViewers: [String]? = nil, // 🔗 AÑADIDO: Usuarios específicos que pueden continuar
        continuationCustomListId: String? = nil, // 🔗 AÑADIDO: Lista específica que puede continuar
        continuationCustomListName: String? = nil, // 🔗 AÑADIDO: Nombre de la lista que puede continuar
        completion: @escaping (String?, Error?) -> Void // 🔥 ACTUALIZADO: Ahora devuelve String? para el storyId
    ) {

        self.fetchUser(userId: userId) { [weak self] result in
            guard let self = self else {
                completion(nil, NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Operación cancelada"]))
                return
            }

            switch result {
            case .success(let user):
                let isChain = chainId != nil
                let expirationDate = self.calculateStoryExpirationDate(isChain: isChain, chainId: chainId)
                let duration = mediaItem.type == .video ? 60.0 : 10.0
                let storyId = UUID().uuidString // 🔥 GENERAR ID ÚNICO

                let story = Story(
                    id: storyId,
                    authorId: userId,
                    username: user.username,
                    mediaItem: mediaItem,
                    duration: duration,
                    timestamp: Date(),
                    expirationDate: expirationDate,
                    profileImagePath: user.profileImagePath,
                    audience: audienceSetting.rawValue, // 🔥 USAR rawValue
                    customListId: nil, // Para listas se usa la otra función
                    text: text,
                    textPosition: textPosition,
                    textStyle: textStyle,
                    stickers: stickers,
                    drawingData: drawingData,
                    aspectRatio: aspectRatio, // ✅ AÑADIDO: Aspect ratio del video
                    backgroundFrameURL: backgroundFrameURL, // ✅ AÑADIDO: URL del frame de fondo
                    chainId: chainId, // 🔗 AÑADIDO: ID de la cadena
                    chainPosition: chainPosition, // 🔗 AÑADIDO: Posición en la cadena
                    chainTitle: chainTitle // 🔗 AÑADIDO: Título de la cadena
                )

                do {
                    let encoder = Firestore.Encoder()
                    var storyData = try encoder.encode(story)
                    
                    // 🔥 MANEJAR CAMPOS ESPECIALES
                    if let textPosition = textPosition {
                        storyData["textPositionX"] = textPosition.x
                        storyData["textPositionY"] = textPosition.y
                    }
                    
                    if let stickers = stickers {
                        storyData["stickers"] = stickers.map { sticker in
                            var stickerData: [String: Any] = [
                                "type": sticker.type,
                                "content": sticker.content,
                                "positionX": sticker.position.x,
                                "positionY": sticker.position.y,
                                "scale": sticker.scale,
                                "rotation": sticker.rotation
                            ]
                            
                            // ✅ INCLUIR CAMPOS DE INTERACCIÓN
                            if let username = sticker.username {
                                stickerData["username"] = username
                            }
                            if let userId = sticker.userId {
                                stickerData["userId"] = userId
                            }
                            if let hashtag = sticker.hashtag {
                                stickerData["hashtag"] = hashtag
                            }
                            if let location = sticker.location {
                                stickerData["location"] = location
                            }
                            if let questionText = sticker.questionText {
                                stickerData["questionText"] = questionText
                            }
                            if let pollOptions = sticker.pollOptions {
                                stickerData["pollOptions"] = pollOptions
                            }
                            
                            // ✅ INCLUIR PROPIEDADES DE ANIMACIÓN
                            if sticker.isAnimated {
                                stickerData["isAnimated"] = true
                                if let gifURL = sticker.gifURL {
                                    stickerData["gifURL"] = String(describing: gifURL)
                                }
                            }
                            
                            return stickerData
                        }
                    }
                    
                    // 🔗 AÑADIR CAMPOS DE CONFIGURACIÓN DE CONTINUACIÓN DE CADENAS
                    if let chainId = chainId {
                        if let allowOthersToContinue = allowOthersToContinue {
                            storyData["allowOthersToContinue"] = allowOthersToContinue
                        }
                        if let continuationAudience = continuationAudience {
                            storyData["continuationAudience"] = continuationAudience.rawValue
                        }
                        if let continuationCustomViewers = continuationCustomViewers {
                            storyData["continuationCustomViewers"] = continuationCustomViewers
                        }
                        if let continuationCustomListId = continuationCustomListId {
                            storyData["continuationCustomListId"] = continuationCustomListId
                        }
                        if let continuationCustomListName = continuationCustomListName {
                            storyData["continuationCustomListName"] = continuationCustomListName
                        }
                    }
                    
                    // 🔥 GUARDAR AUDIENCIA PERSONALIZADA SI ES NECESARIO
                    if audienceSetting == .custom, let customViewers = customViewers, !customViewers.isEmpty {
                        self.saveCustomAudienceForContent(
                            contentType: "story",
                            authorId: userId,
                            allowedUsers: customViewers
                        ) { error in
                            // Error silencioso
                        }
                    }

                    // 🔥 USAR EL storyId GENERADO COMO DOCUMENT ID
                    self.db.collection("users").document(userId)
                        .collection("stories").document(storyId)
                        .setData(storyData) { error in
                            if let error = error {
                                completion(nil, error) // 🔥 DEVOLVER nil para el ID en caso de error
                            } else {
                                completion(storyId, nil) // 🔥 DEVOLVER EL ID REAL
                            }
                        }
                } catch {
                    completion(nil, error) // 🔥 DEVOLVER nil para el ID en caso de error
                }

            case .failure(let error):
                completion(nil, error) // 🔥 DEVOLVER nil para el ID en caso de error
            }
        }
    }
    
    // ✅ NUEVA FUNCIÓN: Guardar audiencia personalizada para contenido específico
    private func saveCustomAudienceForContent(
        contentType: String,
        authorId: String,
        allowedUsers: [String],
        completion: @escaping (Error?) -> Void
    ) {
        let data: [String: Any] = [
            "contentType": contentType,
            "allowedUsers": allowedUsers,
            "createdAt": FieldValue.serverTimestamp(),
            "lastUpdated": FieldValue.serverTimestamp()
        ]
        
        db.collection("users").document(authorId)
            .collection("customAudiences")
            .document("default_\(contentType)")
            .setData(data, merge: true, completion: completion)
    }
    
    // ✅ NUEVA FUNCIÓN: Obtener audiencia personalizada
    func getCustomAudience(
        contentType: String,
        authorId: String,
        completion: @escaping ([String]) -> Void
    ) {
        db.collection("users").document(authorId)
            .collection("customAudiences")
            .document("default_\(contentType)")
            .getDocument { snapshot, error in
                guard let data = snapshot?.data(),
                      let allowedUsers = data["allowedUsers"] as? [String] else {
                    completion([])
                    return
                }
                completion(allowedUsers)
            }
    }
    
    // ✅ NUEVA FUNCIÓN: Aplicar filtros de visibilidad al obtener momentos
    func fetchMomentsWithVisibility(
        for userId: String,
        viewerId: String,
        completion: @escaping (Result<[Moment], Error>) -> Void
    ) {
        // Primero obtener todos los momentos
        fetchMoments(for: userId) { [weak self] result in
            switch result {
            case .success(let moments):
                // Aplicar filtros de visibilidad
                self?.filterMomentsForVisibility(
                    moments: moments,
                    viewerId: viewerId,
                    completion: completion
                )
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // ✅ NUEVA FUNCIÓN: Filtrar momentos por visibilidad
    private func filterMomentsForVisibility(
        moments: [Moment],
        viewerId: String,
        completion: @escaping (Result<[Moment], Error>) -> Void
    ) {
        let visibilityService = ContentVisibilityService.shared
        let group = DispatchGroup()
        var visibleMoments: [Moment] = []
        let syncQueue = DispatchQueue(label: "moments.visibility.filter")
        
        for moment in moments {
            group.enter()
            
            visibilityService.canUserSeeContent(
                contentOwnerId: moment.authorId,
                viewerId: viewerId,
                contentType: moment.visibilityType,
                customViewers: moment.customViewers,
                hiddenFrom: moment.hiddenFrom
            ) { canSee in
                syncQueue.async {
                    if canSee {
                        visibleMoments.append(moment)
                    }
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            // Mantener el orden original
            let orderedVisibleMoments = moments.filter { moment in
                visibleMoments.contains { $0.id == moment.id }
            }
            completion(.success(orderedVisibleMoments))
        }
    }
}

// MARK: - Extensión de FirestoreService para Listas Personalizadas
extension FirestoreService {
    
    // MARK: - Crear momento con lista personalizada
    func createMomentWithCustomList(
        userId: String,
        content: String,
        mediaItems: [MediaItem],
        customListId: String,
        taggedUsers: [String]? = nil,
        location: String? = nil,
        locationCoordinate: Moment.LocationCoordinate? = nil,  // ✅ NUEVO: Coordenadas de ubicación
        aspectRatio: String? = nil,
        disableComments: Bool = false,
        hideLikeCounts: Bool = false,
        allowSharing: Bool = true,
        completion: @escaping (String?, Error?) -> Void
    ) {
        self.fetchUser(userId: userId) { [weak self] result in
            guard let self = self else {
                completion(nil, NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Operación cancelada"]))
                return
            }
            
            switch result {
            case .success(let user):
                let imagePath = mediaItems.first(where: { $0.type == .image })?.url
                
                // 🔥 EXTRAER DATOS DEL VIDEO COMPLETOS
                let videoItem = mediaItems.first(where: { $0.type == .video })
                let videoUrl = videoItem?.url
                let thumbnailUrl = videoItem?.thumbnailUrl
                let videoDuration = videoItem?.videoDuration
                let videoFileSize = videoItem?.videoFileSize
                let videoResolution = videoItem?.videoResolution
                
                let moment = Moment(
                    id: nil,
                    authorId: userId,
                    username: user.username,
                    content: content,
                    imagePath: imagePath,
                    videoUrl: videoUrl,
                    timestamp: Date(),
                    reactions: [:],
                    commentCount: 0,
                    profileImagePath: user.profileImagePath,
                    taggedUsers: taggedUsers,
                    location: location,
                    locationCoordinate: locationCoordinate,  // ✅ MOVIDO: Antes de audience
                    audience: "customList",
                    mediaItems: mediaItems,
                    aspectRatio: aspectRatio ?? "1:1",
                    customListId: customListId,
                    // 🔥 NUEVOS CAMPOS DE VIDEO
                    thumbnailUrl: thumbnailUrl,
                    videoDuration: videoDuration,
                    videoFileSize: videoFileSize,
                    videoResolution: videoResolution,
                    disableComments: disableComments,
                    hideLikeCounts: hideLikeCounts,
                    allowSharing: allowSharing
                )
                
                do {
                    let encoder = Firestore.Encoder()
                    var momentData = try encoder.encode(moment)
                    
                    // 🔥 INCLUIR METADATA COMPLETA EN MEDIAITEMS
                    momentData["mediaItems"] = mediaItems.map { item in
                        var mediaData: [String: Any] = [
                            "id": item.id,
                            "type": item.type.rawValue,
                            "url": item.url
                        ]
                        
                        // Añadir campos de video si existen
                        if let thumbnailUrl = item.thumbnailUrl {
                            mediaData["thumbnailUrl"] = thumbnailUrl
                        }
                        if let videoDuration = item.videoDuration {
                            mediaData["videoDuration"] = videoDuration
                        }
                        if let videoFileSize = item.videoFileSize {
                            mediaData["videoFileSize"] = videoFileSize
                        }
                        if let videoResolution = item.videoResolution {
                            mediaData["videoResolution"] = videoResolution
                        }
                        
                        return mediaData
                    }
                    
                    var ref: DocumentReference? = nil
                    ref = self.db.collection("users")
                        .document(userId)
                        .collection("moments")
                        .addDocument(data: momentData) { error in
                            if let error = error {
                                completion(nil, error)
                            } else {
                                completion(ref!.documentID, nil)
                            }
                        }
                } catch {
                    completion(nil, error)
                }
                
            case .failure(let error):
                completion(nil, error)
            }
        }
    }

    // MARK: - Crear historia con lista personalizada (ACTUALIZADO)
    func createStoryWithCustomList(
        userId: String,
        mediaItem: MediaItem,
        customListId: String,
        text: String? = nil,
        textPosition: CGPoint? = nil,
        textStyle: String? = nil,
        stickers: [StickerData]? = nil,
        drawingData: Data? = nil,
        aspectRatio: String? = nil, // ✅ AÑADIDO: Aspect ratio del video
        backgroundFrameURL: String? = nil, // ✅ AÑADIDO: URL del frame de fondo
        chainId: String? = nil, // 🔗 AÑADIDO: ID de la cadena
        chainPosition: Int? = nil, // 🔗 AÑADIDO: Posición en la cadena
        chainTitle: String? = nil, // 🔗 AÑADIDO: Título de la cadena
        allowOthersToContinue: Bool? = nil, // 🔗 AÑADIDO: Si otros pueden continuar la cadena
        continuationAudience: ContentAudience? = nil, // 🔗 AÑADIDO: Audiencia que puede continuar
        continuationCustomViewers: [String]? = nil, // 🔗 AÑADIDO: Usuarios específicos que pueden continuar
        continuationCustomListId: String? = nil, // 🔗 AÑADIDO: Lista específica que puede continuar
        continuationCustomListName: String? = nil, // 🔗 AÑADIDO: Nombre de la lista que puede continuar
        completion: @escaping (String?, Error?) -> Void // 🔥 ACTUALIZADO: Ahora devuelve String? para el storyId
    ) {
        self.fetchUser(userId: userId) { [weak self] result in
            guard let self = self else {
                completion(nil, NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Operación cancelada"]))
                return
            }

            switch result {
            case .success(let user):
                let isChain = chainId != nil
                let expirationDate = self.calculateStoryExpirationDate(isChain: isChain, chainId: chainId)
                let duration = mediaItem.type == .video ? 60.0 : 10.0
                let storyId = UUID().uuidString // 🔥 GENERAR ID ÚNICO

                let story = Story(
                    id: storyId,
                    authorId: userId,
                    username: user.username,
                    mediaItem: mediaItem,
                    duration: duration,
                    timestamp: Date(),
                    expirationDate: expirationDate,
                    profileImagePath: user.profileImagePath,
                    audience: "customList", // 🔥 AUDIENCIA PARA LISTA PERSONALIZADA
                    customListId: customListId,
                    text: text,
                    textPosition: textPosition,
                    textStyle: textStyle,
                    stickers: stickers,
                    drawingData: drawingData,
                    aspectRatio: aspectRatio, // ✅ AÑADIDO: Aspect ratio del video
                    backgroundFrameURL: backgroundFrameURL, // ✅ AÑADIDO: URL del frame de fondo
                    chainId: chainId, // 🔗 AÑADIDO: ID de la cadena
                    chainPosition: chainPosition, // 🔗 AÑADIDO: Posición en la cadena
                    chainTitle: chainTitle // 🔗 AÑADIDO: Título de la cadena
                )

                do {
                    let encoder = Firestore.Encoder()
                    var storyData = try encoder.encode(story)
                    
                    // 🔥 MANEJAR CAMPOS ESPECIALES
                    if let textPosition = textPosition {
                        storyData["textPositionX"] = textPosition.x
                        storyData["textPositionY"] = textPosition.y
                    }
                    
                    if let stickers = stickers {
                        storyData["stickers"] = stickers.map { sticker in
                            var stickerData: [String: Any] = [
                                "type": sticker.type,
                                "content": sticker.content,
                                "positionX": sticker.position.x,
                                "positionY": sticker.position.y,
                                "scale": sticker.scale,
                                "rotation": sticker.rotation
                            ]
                            
                            // ✅ INCLUIR PROPIEDADES DE ANIMACIÓN
                            if sticker.isAnimated {
                                stickerData["isAnimated"] = true
                                if let gifURL = sticker.gifURL {
                                    stickerData["gifURL"] = String(describing: gifURL)
                                }
                            }
                            
                            return stickerData
                        }
                    }
                    
                    // 🔗 AÑADIR CAMPOS DE CONFIGURACIÓN DE CONTINUACIÓN DE CADENAS
                    if let chainId = chainId {
                        if let allowOthersToContinue = allowOthersToContinue {
                            storyData["allowOthersToContinue"] = allowOthersToContinue
                        }
                        if let continuationAudience = continuationAudience {
                            storyData["continuationAudience"] = continuationAudience.rawValue
                        }
                        if let continuationCustomViewers = continuationCustomViewers {
                            storyData["continuationCustomViewers"] = continuationCustomViewers
                        }
                        if let continuationCustomListId = continuationCustomListId {
                            storyData["continuationCustomListId"] = continuationCustomListId
                        }
                        if let continuationCustomListName = continuationCustomListName {
                            storyData["continuationCustomListName"] = continuationCustomListName
                        }
                    }

                    // 🔥 USAR EL storyId GENERADO COMO DOCUMENT ID
                    self.db.collection("users").document(userId)
                        .collection("stories").document(storyId)
                        .setData(storyData) { error in
                            if let error = error {
                                completion(nil, error) // 🔥 DEVOLVER nil para el ID en caso de error
                            } else {
                                completion(storyId, nil) // 🔥 DEVOLVER EL ID REAL
                            }
                        }
                } catch {
                    completion(nil, error) // 🔥 DEVOLVER nil para el ID en caso de error
                }

            case .failure(let error):
                completion(nil, error) // 🔥 DEVOLVER nil para el ID en caso de error
            }
        }
    }
    
    // MARK: - Verificar si usuario puede ver contenido con lista personalizada
    func canUserViewContentWithCustomList(
        contentId: String,
        contentType: String, // "moment" o "story"
        authorId: String,
        viewerId: String,
        completion: @escaping (Bool) -> Void
    ) {
        // Primero obtener el contenido para obtener el customListId
        let collection = contentType == "moment" ? "moments" : "stories"
        
        db.collection("users").document(authorId)
            .collection(collection).document(contentId)
            .getDocument { [weak self] document, error in
                guard let self = self,
                      let data = document?.data(),
                      let customListId = data["customListId"] as? String else {
                    completion(false)
                    return
                }
                
                // Verificar si el viewer está en la lista
                self.isUserInCustomList(
                    userId: viewerId,
                    listId: customListId,
                    listOwnerId: authorId,
                    completion: completion
                )
            }
    }
    
    // MARK: - Verificar si usuario está en lista personalizada
    private func isUserInCustomList(
        userId: String,
        listId: String,
        listOwnerId: String,
        completion: @escaping (Bool) -> Void
    ) {
        db.collection("users").document(listOwnerId)
            .collection("customAudienceLists").document(listId)
            .getDocument { document, error in
                guard let data = document?.data(),
                      let members = data["members"] as? [String] else {
                    completion(false)
                    return
                }
                
                completion(members.contains(userId))
            }
    }
    
    // MARK: - Obtener listas de un usuario
    func fetchCustomLists(
        for userId: String,
        completion: @escaping (Result<[CustomAudienceList], Error>) -> Void
    ) {
        db.collection("users").document(userId)
            .collection("customAudienceLists")
            .order(by: "updatedAt", descending: true)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                let lists = snapshot?.documents.compactMap { doc in
                    try? doc.data(as: CustomAudienceList.self)
                } ?? []
                
                completion(.success(lists))
            }
    }
    
    // MARK: - Obtener detalles de una lista
    func fetchCustomListDetails(
        listId: String,
        ownerId: String,
        completion: @escaping (Result<CustomAudienceList, Error>) -> Void
    ) {
        db.collection("users").document(ownerId)
            .collection("customAudienceLists").document(listId)
            .getDocument { document, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                guard let list = try? document?.data(as: CustomAudienceList.self) else {
                    completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Lista no encontrada"])))
                    return
                }
                
                completion(.success(list))
            }
    }
    
    // MARK: - Agregar miembros a lista
    func addMembersToCustomList(
        listId: String,
        ownerId: String,
        memberIds: [String],
        completion: @escaping (Error?) -> Void
    ) {
        db.collection("users").document(ownerId)
            .collection("customAudienceLists").document(listId)
            .updateData([
                "members": FieldValue.arrayUnion(memberIds),
                "updatedAt": FieldValue.serverTimestamp()
            ], completion: completion)
    }
    
    // MARK: - Remover miembros de lista
    func removeMembersFromCustomList(
        listId: String,
        ownerId: String,
        memberIds: [String],
        completion: @escaping (Error?) -> Void
    ) {
        db.collection("users").document(ownerId)
            .collection("customAudienceLists").document(listId)
            .updateData([
                "members": FieldValue.arrayRemove(memberIds),
                "updatedAt": FieldValue.serverTimestamp()
            ], completion: completion)
    }
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


