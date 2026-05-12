import FirebaseFirestore
import Combine
import FirebaseAuth
import Kingfisher

struct StoryAuthorSummary {
    let activeStoryCount: Int
    let latestStoryAt: Date?
    let latestExpirationAt: Date?
    let audiencesSummary: [String: Int]
    let updatedAt: Date?

    func shouldSkipDetailedFetch(maxStaleness: TimeInterval = 300) -> Bool {
        if let latestExpirationAt = latestExpirationAt, latestExpirationAt <= Date() {
            // Resumen vencido: evitar fetch detallado y tratar como sin historias.
            return true
        }
        guard activeStoryCount <= 0 else { return false }
        guard let updatedAt = updatedAt else { return false }
        return Date().timeIntervalSince(updatedAt) <= maxStaleness
    }
}

enum PublicProfileAvailability {
    case available
    case unavailable
}

class FirestoreService: ObservableObject {
    static let shared = FirestoreService() // Singleton
    let db: Firestore
    @Published var savedMomentIds: [String] = []
    @Published private(set) var savedMomentsLoadedForUserId: String?
    private var followingCache: [String: Bool] = [:]
    private var lastCacheUpdate: Date = Date() // Added for reactive saved moments
    private let storySummaryRebuildQueue = DispatchQueue(label: "story.summary.rebuild.queue")
    private var storySummaryRebuildInFlight: Set<String> = []
    private var storySummaryLastRebuildAttempt: [String: Date] = [:]
    private let storySummaryRebuildCooldown: TimeInterval = 60

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
            var affectedUserIds = Set<String>()
            for doc in storiesSnapshot.documents {
                batch.updateData([
                    "expirationDate": Timestamp(date: correctExpiration)
                ], forDocument: doc.reference)
                if let userId = doc.reference.parent.parent?.documentID, !userId.isEmpty {
                    affectedUserIds.insert(userId)
                }
            }
            
            try await batch.commit()

            for userId in affectedUserIds {
                rebuildStorySummary(for: userId) { _ in }
            }
            
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
        let userRef = db.collection("users").document(userId)
        let momentRef = userRef.collection("moments").document(momentId)
        let recentlyDeletedRef = userRef.collection("recentlyDeleted").document(momentId)
        
        // Soft delete: Mover a la colección 'recentlyDeleted'
        momentRef.getDocument { snapshot, error in
            if let error = error {
                completion(error)
                return
            }
            
            guard let data = snapshot?.data() else {
                completion(NSError(domain: "", code: -404, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("errors.momentNotFound", comment: "Moment not found")]))
                return
            }
            
            var deletedData = data
            deletedData["deletedAt"] = FieldValue.serverTimestamp()
            deletedData["type"] = "moment"
            
            // Guardar en recentlyDeleted
            recentlyDeletedRef.setData(deletedData) { error in
                if let error = error {
                    completion(error)
                    return
                }
                
                // Borrar de la colección original
                momentRef.delete { error in
                    completion(error)
                }
            }
        }
    }


    func permanentlyDeleteMoment(userId: String, momentId: String, completion: @escaping (Error?) -> Void) {
        let recentlyDeletedRef = db.collection("users").document(userId).collection("recentlyDeleted").document(momentId)
        
        recentlyDeletedRef.getDocument { [weak self] snapshot, error in
            if let error = error {
                completion(error)
                return
            }
            
            guard let self = self else { return }
            
            let data = snapshot?.data()
            let imagePath = data?["imagePath"] as? String
            let videoUrl = data?["videoUrl"] as? String
            
            recentlyDeletedRef.delete { error in
                if let error = error {
                    completion(error)
                    return
                }
                
                // Limpiar Storage
                let storageService = StorageService()
                if let imagePath = imagePath, !imagePath.isEmpty {
                    storageService.deleteMedia(path: imagePath) { _ in }
                }
                if let videoUrl = videoUrl, !videoUrl.isEmpty {
                    storageService.deleteMedia(path: videoUrl) { _ in }
                }
                
                completion(nil)
            }
        }
    }

    func permanentlyDeleteMoment(momentId: String, userId: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            permanentlyDeleteMoment(userId: userId, momentId: momentId) { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func restoreMoment(userId: String, momentId: String, completion: @escaping (Error?) -> Void) {
        let userRef = db.collection("users").document(userId)
        let momentRef = userRef.collection("moments").document(momentId)
        let recentlyDeletedRef = userRef.collection("recentlyDeleted").document(momentId)
        
        recentlyDeletedRef.getDocument { snapshot, error in
            if let error = error {
                completion(error)
                return
            }
            
            guard var data = snapshot?.data() else {
                completion(NSError(domain: "", code: -404, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("errors.documentNotFound", comment: "Document not found")]))
                return
            }
            
            // Limpiar metadatos de borrado
            data.removeValue(forKey: "deletedAt")
            data.removeValue(forKey: "type")
            
            // Restaurar a la colección original
            momentRef.setData(data) { error in
                if let error = error {
                    completion(error)
                    return
                }
                
                // Borrar de recentlyDeleted
                recentlyDeletedRef.delete { error in
                    completion(error)
                }
            }
        }
    }

    func restoreMoment(momentId: String, userId: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            restoreMoment(userId: userId, momentId: momentId) { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func archiveMoment(userId: String, momentId: String, completion: @escaping (Error?) -> Void) {
        let momentRef = db.collection("users").document(userId).collection("moments").document(momentId)
        momentRef.updateData([
            "isArchived": true,
            "archivedAt": FieldValue.serverTimestamp()
        ]) { error in
            completion(error)
        }
    }

    func unarchiveMoment(userId: String, momentId: String, completion: @escaping (Error?) -> Void) {
        let momentRef = db.collection("users").document(userId).collection("moments").document(momentId)
        momentRef.updateData([
            "isArchived": FieldValue.delete(),
            "archivedAt": FieldValue.delete()
        ]) { error in
            completion(error)
        }
    }

    func unarchiveMoment(momentId: String, userId: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            unarchiveMoment(userId: userId, momentId: momentId) { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func fetchArchivedMoments(userId: String, completion: @escaping (Result<[Moment], Error>) -> Void) {
        db.collection("users").document(userId).collection("moments")
            .whereField("isArchived", isEqualTo: true)
            .order(by: "archivedAt", descending: true)
            .limit(to: 100)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                let moments = snapshot?.documents.compactMap { doc -> Moment? in
                    try? doc.data(as: Moment.self)
                } ?? []
                completion(.success(moments))
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
                if error != nil {
                    DispatchQueue.main.async {
                        self?.savedMomentIds = []
                        self?.savedMomentsLoadedForUserId = userId
                    }
                    return
                }
                let momentIds = snapshot?.documents.compactMap { $0.documentID } ?? []
                DispatchQueue.main.async {
                    self?.savedMomentIds = momentIds
                    self?.savedMomentsLoadedForUserId = userId
                }
            }
    }
    
    func hasLoadedSavedMoments(for userId: String) -> Bool {
        savedMomentsLoadedForUserId == userId
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
        // ✅ OFFLINE SUPPORT
        if !NetworkMonitor.shared.isConnected {
            let payload = SavePayload(userId: userId, momentId: momentId)
            if let data = try? JSONEncoder().encode(payload) {
                let action = CachedAction(
                    id: UUID().uuidString,
                    type: CachedAction.ActionType.save.rawValue,
                    payloadData: data
                )
                
                Task {
                    await LocalPersistenceService.shared.saveAction(action)
                    print("💾 FirestoreService: Guardado (save) en outbox (offline)")
                    completion(nil) // Éxito optimista
                }
                return
            }
        }

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

    func fetchVisitsWithUsers(userId: String) async throws -> [(user: AppUser, visit: Visit)] {
        let snapshot = try await db.collection("users").document(userId).collection("visits")
            .order(by: "timestamp", descending: true)
            .limit(to: 50)
            .getDocuments()
            
        let visits = snapshot.documents.compactMap { try? $0.data(as: Visit.self) }
        if visits.isEmpty { return [] }
        
        let visitorIds = Array(Set(visits.map { $0.visitorId }))
        let users = try await fetchUsersAsync(userIds: visitorIds)
        let userDict = Dictionary(uniqueKeysWithValues: users.map { ($0.id, $0) })
        
        return visits.compactMap { visit in
            guard let user = userDict[visit.visitorId] else { return nil }
            return (user, visit)
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
                completion(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("errors.operationCancelled", comment: "Operation cancelled")]))
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
                "commentsMutualsOnly": false,
                "muteOldPostReactions": false
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
    
    // ✅ NUEVO: Cambio de username con cooldown de 6 meses
    func changeUsername(
        userId: String,
        oldUsername: String,
        newUsername: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let clean = newUsername.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        // Validación básica
        guard clean.count >= 3 && clean.count <= 30 else {
            completion(.failure(NSError(domain: "", code: 1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("username.error.length", comment: "Username must be between 3 and 30 characters")])))
            return
        }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_")
        guard clean.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            completion(.failure(NSError(domain: "", code: 2, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("username.error.characters", comment: "Username can only contain letters, numbers, and underscores")])))
            return
        }
        guard clean != oldUsername.lowercased() else {
            completion(.failure(NSError(domain: "", code: 3, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("username.error.same", comment: "New username must be different from current")])))
            return
        }
        
        let userRef = db.collection("users").document(userId)
        let oldUsernameRef = db.collection("usernames").document(oldUsername.lowercased())
        let newUsernameRef = db.collection("usernames").document(clean)
        
        // 1. Verificar cooldown y disponibilidad en paralelo
        userRef.getDocument { [weak self] userSnap, error in
            guard let self = self else { return }
            if let error = error { completion(.failure(error)); return }
            let userData = userSnap?.data() ?? [:]
            let userEmail =
                (userData["email"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let fallbackAuthEmail =
                Auth.auth().currentUser?.email?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Verificar cooldown de 6 meses
            if let ts = userData["lastUsernameChange"] as? Timestamp {
                let lastChange = ts.dateValue()
                let sixMonthsAgo = Calendar.current.date(byAdding: .month, value: -6, to: Date()) ?? Date()
                if lastChange > sixMonthsAgo {
                    let nextAvailable = Calendar.current.date(byAdding: .month, value: 6, to: lastChange) ?? Date()
                    let formatter = DateFormatter()
                    formatter.dateStyle = .long
                    formatter.locale = Locale.current
                    let dateStr = formatter.string(from: nextAvailable)
                    completion(.failure(NSError(domain: "", code: 4, userInfo: [NSLocalizedDescriptionKey: String(format: NSLocalizedString("username.error.cooldown", comment: "Username can be changed on %@"), dateStr)])))
                    return
                }
            }
            
            // 2. Verificar disponibilidad del nuevo username
            newUsernameRef.getDocument { snap, error in
                if let error = error { completion(.failure(error)); return }
                if snap?.exists == true {
                    completion(.failure(NSError(domain: "", code: 5, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("username.error.taken", comment: "This username is already taken")])))
                    return
                }

                oldUsernameRef.getDocument { oldUsernameSnap, error in
                    if let error = error { completion(.failure(error)); return }

                    // 3. Actualizar en batch atómico (preservando createdAt/email para login por username)
                    var newUsernameData = oldUsernameSnap?.data() ?? [:]
                    newUsernameData["userId"] = userId
                    newUsernameData["updatedAt"] = FieldValue.serverTimestamp()

                    if let email = userEmail, !email.isEmpty {
                        newUsernameData["email"] = email
                    } else if let email = fallbackAuthEmail, !email.isEmpty {
                        newUsernameData["email"] = email
                    }

                    if newUsernameData["createdAt"] == nil {
                        newUsernameData["createdAt"] = FieldValue.serverTimestamp()
                    }

                    let batch = self.db.batch()
                    batch.deleteDocument(oldUsernameRef)
                    batch.setData(newUsernameData, forDocument: newUsernameRef)
                    batch.updateData([
                        "username": clean,
                        "lastUsernameChange": FieldValue.serverTimestamp()
                    ], forDocument: userRef)

                    batch.commit { error in
                        if let error = error {
                            completion(.failure(error))
                        } else {
                            completion(.success(()))
                        }
                    }
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
        
        // ✅ NUEVO: Si estamos offline, intentar obtener el documento SOLO de la caché para evitar delays
        let source: FirestoreSource = NetworkMonitor.shared.isConnected ? .default : .cache
        
        db.collection("users").document(userId).getDocument(source: source) { snapshot, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let document = snapshot, document.exists else {
                completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("errors.documentNotFound", comment: "Document not found")])))
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

    // ✅ NUEVO: Buscar usuario por Username (para deep links y menciones)
    func fetchUserByUsername(_ username: String, completion: @escaping (Result<AppUser, Error>) -> Void) {
        let cleanUsername = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        db.collection("users")
            .whereField("username", isEqualTo: cleanUsername)
            .limit(to: 1)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                guard let documents = snapshot?.documents, let document = documents.first else {
                    completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Usuario no encontrado"])))
                    return
                }
                
                do {
                    let user = try document.data(as: AppUser.self)
                    completion(.success(user))
                } catch {
                    // Fallback a decodificación manual si falla
                    let data = document.data()
                    self.attemptManualDecoding(data: data, completion: completion)
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
                completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("errors.documentNotFound", comment: "Document not found")])))
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

    func checkPublicProfileAvailability(userId: String, completion: @escaping (PublicProfileAvailability) -> Void) {
        db.collection("users").document(userId).getDocument(source: .default) { snapshot, error in
            if error != nil {
                completion(.available)
                return
            }

            guard let document = snapshot, document.exists, let data = document.data() else {
                completion(.unavailable)
                return
            }

            let isActive = data["isActive"] as? Bool ?? true
            guard isActive else {
                completion(.unavailable)
                return
            }

            let isSuspended = data["isSuspended"] as? Bool ?? false
            guard isSuspended else {
                completion(.available)
                return
            }

            if let suspendedUntil = data["suspendedUntil"] as? Timestamp,
               Date() > suspendedUntil.dateValue() {
                completion(.available)
            } else {
                completion(.unavailable)
            }
        }
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
                // Simplificamos para evitar cualquier problema de índice o cierre complejo
                let ids = users.map { $0.id }
                followingIds = Set(ids)
            case .failure(let error):
                fetchError = error
            }
        }
        
        group.enter()
        fetchFollowers(userId: userId) { result in
            defer { group.leave() }
            switch result {
            case .success(let users):
                let ids = users.map { $0.id }
                followerIds = Set(ids)
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
            
            // Usamos fetchUsersByIdsClean que ya tiene lógica de chunking
            self.fetchUsersByIdsClean(userIds: mutualIds, completion: completion)
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
    
    func removeProfilePicture(userId: String, completion: @escaping (Error?) -> Void) {
        self.db.collection("users").document(userId).updateData([
            "profileImagePath": FieldValue.delete()
        ]) { error in
            completion(error)
        }
    }

    private func serializedMediaItems(_ mediaItems: [MediaItem], encoder: Firestore.Encoder) -> [[String: Any]] {
        mediaItems.map { item in
            var mediaData: [String: Any] = [
                "id": item.id,
                "type": item.type.rawValue,
                "url": item.url
            ]

            if let aspectRatio = item.aspectRatio {
                mediaData["aspectRatio"] = aspectRatio
            }
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
            if let tags = item.tags, !tags.isEmpty {
                mediaData["tags"] = tags.compactMap { tag in
                    try? encoder.encode(tag)
                }
            }
            if let moderationState = item.moderationState?.rawValue {
                mediaData["moderationState"] = moderationState
            }
            if let moderationReason = item.moderationReason {
                mediaData["moderationReason"] = moderationReason
            }
            if let moderationCategory = item.moderationCategory {
                mediaData["moderationCategory"] = moderationCategory
            }
            if let moderationConfidence = item.moderationConfidence {
                mediaData["moderationConfidence"] = moderationConfidence
            }
            if let moderatedAt = item.moderatedAt {
                mediaData["moderatedAt"] = Timestamp(date: moderatedAt)
            }

            return mediaData
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
        scheduledDate: Date? = nil,
        completion: @escaping (Error?) -> Void
    ) {
        self.fetchUser(userId: userId) { [weak self] result in
            guard let self = self else {
                completion(NSError(
                    domain: "",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("errors.operationCancelled", comment: "Operation cancelled")]
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
                    allowSharing: allowSharing,
                    scheduledDate: scheduledDate
                )
                
                do {
                    let encoder = Firestore.Encoder()
                    var momentData = try encoder.encode(moment)
                    
                    momentData["mediaItems"] = self.serializedMediaItems(mediaItems, encoder: encoder)
                    
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
                completion(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("errors.operationCancelled", comment: "Operation cancelled")]))
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
                            if let stickerId = sticker.stickerId {
                                stickerData["stickerId"] = stickerId
                            }
                            
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
                            if let latitude = sticker.latitude, let longitude = sticker.longitude {
                                stickerData["latitude"] = latitude
                                stickerData["longitude"] = longitude
                            }
                            if let questionText = sticker.questionText {
                                stickerData["questionText"] = questionText
                            }
                            if let pollOptions = sticker.pollOptions {
                                stickerData["pollOptions"] = pollOptions
                            }
                            
                            if let weatherSymbol = sticker.weatherSymbol {
                                stickerData["weatherSymbol"] = weatherSymbol
                            }
                            if let linkURL = sticker.linkURL {
                                stickerData["linkURL"] = linkURL
                            }
                            if let linkTitle = sticker.linkTitle {
                                stickerData["linkTitle"] = linkTitle
                            }
                            if let countdownTitle = sticker.countdownTitle {
                                stickerData["countdownTitle"] = countdownTitle
                            }
                            if let countdownTargetAtMs = sticker.countdownTargetAtMs {
                                stickerData["countdownTargetAtMs"] = countdownTargetAtMs
                            }
                            if let sliderEmoji = sticker.sliderEmoji {
                                stickerData["sliderEmoji"] = sliderEmoji
                            }
                            if let sliderPrompt = sticker.sliderPrompt {
                                stickerData["sliderPrompt"] = sliderPrompt
                            }
                            if let caption = sticker.caption {
                                stickerData["caption"] = caption
                            }
                            if let profileImagePath = sticker.profileImagePath {
                                stickerData["profileImagePath"] = profileImagePath
                            }
                            if let momentId = sticker.momentId {
                                stickerData["momentId"] = momentId
                            }
                            if let mediaCount = sticker.mediaCount {
                                stickerData["mediaCount"] = mediaCount
                            }
                            if let quizQuestion = sticker.quizQuestion {
                                stickerData["quizQuestion"] = quizQuestion
                            }
                            if let quizOptions = sticker.quizOptions {
                                stickerData["quizOptions"] = quizOptions
                            }
                            if let quizCorrectIndex = sticker.quizCorrectIndex {
                                stickerData["quizCorrectIndex"] = quizCorrectIndex
                            }
                            if let revealType = sticker.revealType {
                                stickerData["revealType"] = revealType
                            }
                            if let frameStyle = sticker.frameStyle {
                                stickerData["frameStyle"] = frameStyle
                            }
                            
                            // ✅ INCLUIR PROPIEDADES DE ANIMACIÓN
                            if sticker.isAnimated {
                                stickerData["isAnimated"] = true
                                if let gifURL = sticker.gifURL {
                                    stickerData["gifURL"] = String(describing: gifURL)
                                }
                                if let videoURL = sticker.videoURL {
                                    stickerData["videoURL"] = videoURL
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
                                self.bumpStorySummaryOnCreate(
                                    userId: userId,
                                    audience: story.audience,
                                    timestamp: story.timestamp,
                                    expirationDate: story.expirationDate
                                )
                                self.rebuildStorySummary(for: userId) { rebuildError in
                                    _ = rebuildError
                                }
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

                self.applySearchMuteFilterIfNeeded(users: users) { filteredUsers in
                    completion(.success(Array(filteredUsers.prefix(max(1, limit)))))
                }
            }
    }

    private func applySearchMuteFilterIfNeeded(users: [AppUser], completion: @escaping ([AppUser]) -> Void) {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            completion(users)
            return
        }

        db.collection("users").document(currentUserId).getDocument { snapshot, _ in
            guard
                let muteSettings = snapshot?.data()?["muteSettings"] as? [String: Any],
                let hideFromSearch = muteSettings["hideFromSearch"] as? Bool,
                hideFromSearch
            else {
                completion(users)
                return
            }

            let mutedUsers = Set((muteSettings["mutedUsers"] as? [String] ?? []).filter { !$0.isEmpty })
            guard !mutedUsers.isEmpty else {
                completion(users)
                return
            }

            completion(users.filter { !mutedUsers.contains($0.id) })
        }
    }

    func fetchMutedUserIds(userId: String, completion: @escaping (Set<String>) -> Void) {
        guard !userId.isEmpty else {
            completion([])
            return
        }

        db.collection("users").document(userId).getDocument { snapshot, _ in
            let muteSettings = snapshot?.data()?["muteSettings"] as? [String: Any]
            let mutedUsers = (muteSettings?["mutedUsers"] as? [String] ?? [])
                .filter { !$0.isEmpty }
            completion(Set(mutedUsers))
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
                    
                    // 🔥 FILTRAR MOMENTOS PROGRAMADOS (Solo mostrar si la fecha programada ya pasó o si no tiene fecha)
                    let now = Date()
                    let filteredMoments = allMoments.filter { moment in
                        if moment.isArchived == true { return false }
                        guard let scheduledDate = moment.scheduledDate else { return true }
                        return scheduledDate <= now
                    }
                    
                    let limitedMoments = Array(filteredMoments.prefix(10))
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
                    
                    // 🔥 FILTRAR MOMENTOS PROGRAMADOS
                    let now = Date()
                    let filteredMoments = allMoments.filter { moment in
                        if moment.isArchived == true { return false }
                        guard let scheduledDate = moment.scheduledDate else { return true }
                        return scheduledDate <= now
                    }
                    
                    let limitedMoments = Array(filteredMoments.prefix(10))
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
                
                // 🔥 FILTRAR MOMENTOS PROGRAMADOS (Si el usuario actual no es el autor)
                let currentUserId = Auth.auth().currentUser?.uid
                let now = Date()
                
                let filteredMoments = moments.filter { moment in
                    // Excluir momentos archivados del perfil principal
                    if moment.isArchived == true { return false }
                    
                    // Si el usuario es el autor, sí puede ver sus propios momentos programados
                    if moment.authorId == currentUserId {
                        return true
                    }
                    
                    // Para otros usuarios, solo si la fecha programada ya pasó o si no es un post programado
                    guard let scheduledDate = moment.scheduledDate else { return true }
                    return scheduledDate <= now
                }
                
                completion(.success(filteredMoments))
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
    func addComment(to momentId: String, userId: String, authorId: String, content: String, parentCommentId: String? = nil, commentId: String? = nil, completion: @escaping (Result<Void, Error>) -> Void) {
        
        // ✅ Usar el ID proporcionado o generar uno nuevo
        let commentId = commentId ?? UUID().uuidString
        
        // ✅ OFFLINE SUPPORT
        if !NetworkMonitor.shared.isConnected {
            let payload = CommentPayload(
                momentId: momentId,
                authorId: userId,
                senderId: authorId,
                content: content,
                parentCommentId: parentCommentId,
                commentId: commentId // ✅ Persistir el ID
            )
            
            if let data = try? JSONEncoder().encode(payload) {
                let action = CachedAction(
                    id: UUID().uuidString,
                    type: CachedAction.ActionType.comment.rawValue,
                    payloadData: data
                )
                
                Task {
                    await LocalPersistenceService.shared.saveAction(action)
                    // ✅ Optimistic UI: Incrementar contador localmente
                    await MainActor.run {
                        LocalPersistenceService.shared.updateCommentCountLocally(momentId: momentId, increment: 1)
                    }
                    print("💾 FirestoreService: Comentario guardado en outbox (offline)")
                    completion(.success(()))
                }
                return
            }
        }
        
        // Code below uses commentId naturally
        let now = Date()
        
        // Get current user's username
        fetchUser(userId: authorId) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let user):
                // ✅ Optimistic UI: Incrementar contador localmente (Background)
                Task(priority: .background) { @MainActor in
                    LocalPersistenceService.shared.updateCommentCountLocally(momentId: momentId, increment: 1)
                }
                
                // ✅ DATOS DEL COMENTARIO CON ESTRUCTURA CORRECTA
                var commentData: [String: Any] = [
                    "authorId": authorId,
                    "username": user.username,
                    "content": content,
                    "text": content, // ✅ COMPATIBILIDAD: El servidor espera 'text' para notificaciones
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
                                fromUsername: user.username,
                                content: content
                            )
                        } else {
                            // Es un comentario nuevo - servidor se encarga de la notificación
                        }
                        
                        // Handle mentions
                        let mentions = self.extractMentions(from: content)
                        self.handleMentions(mentions, momentId: momentId, fromUserId: authorId, fromUsername: user.username, content: content)
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
        ]) { [weak self] error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
                
                // Handle new mentions in edited comment
                let mentions = self?.extractMentions(from: content) ?? []
                if !mentions.isEmpty {
                    let currentUserId = Auth.auth().currentUser?.uid ?? ""
                    self?.fetchUserProfile(userId: currentUserId) { result in
                        if case .success(let user) = result {
                            self?.handleMentions(mentions, momentId: momentId, fromUserId: currentUserId, fromUsername: user.username, content: content)
                        } else {
                            // Fallback if fetch fails
                            self?.handleMentions(mentions, momentId: momentId, fromUserId: currentUserId, fromUsername: "Alguien", content: content)
                        }
                    }
                }
            }
        }
    }
    
    func deleteComment(to momentId: String, commentId: String, userId: String, authorId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        // ✅ Optimistic UI: Decrementar contador localmente
        Task(priority: .background) { @MainActor in
            LocalPersistenceService.shared.updateCommentCountLocally(momentId: momentId, increment: -1)
        }
        
        // ✅ OFFLINE SUPPORT: Si no hay conexión, persistir acción y retornar éxito optimista
        if !NetworkMonitor.shared.isConnected {
            let payload = DeleteCommentPayload(
                momentId: momentId,
                commentId: commentId,
                userId: userId,
                authorId: authorId
            )
            
            if let data = try? JSONEncoder().encode(payload) {
                let action = CachedAction(
                    id: UUID().uuidString,
                    type: CachedAction.ActionType.deleteComment.rawValue,
                    payloadData: data
                )
                
                Task {
                    await LocalPersistenceService.shared.saveAction(action)
                    print("💾 FirestoreService: Borrado de comentario guardado en outbox (offline)")
                    completion(.success(())) // Éxito optimista
                }
                return
            }
        }

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
                        
                        // ✅ Limpiar notificaciones de las respuestas
                        if let replyAuthorId = nestedDoc.data()["authorId"] as? String {
                            // Notificación al autor del comentario padre (que se está borrando)
                            Task { @MainActor in
                                NotificationService.shared.removeNotification(
                                    type: .comment,
                                    senderId: replyAuthorId,
                                    recipientId: authorId, // El autor del comentario padre
                                    momentId: momentId,
                                    commentId: nestedDoc.documentID
                                )
                            }
                        }
                    }
                    
                    // Commit the batch
                    batch.commit { batchError in
                        if let batchError = batchError {
                            completion(.failure(batchError))
                        } else {
                            // ✅ Limpiar notificación del comentario principal
                            Task { @MainActor in
                                NotificationService.shared.removeNotification(
                                    type: .comment,
                                    senderId: authorId,
                                    recipientId: userId, // El dueño del momento
                                    momentId: momentId,
                                    commentId: commentId
                                )
                            }
                            completion(.success(()))
                        }
                    }
                }
        }
    }
    
    private func notifyCommentReply(parentCommentId: String, momentId: String, momentAuthorId: String, fromUserId: String, fromUsername: String, content: String) {
        // Buscar el comentario padre para obtener su autor
        db.collection("users").document(momentAuthorId).collection("moments").document(momentId).collection("comments").document(parentCommentId).getDocument { snapshot, error in
            
            guard let data = snapshot?.data(),
                  let parentAuthorId = data["authorId"] as? String else { return }
            
            Task { @MainActor in
                NotificationService.shared.sendInteractionNotification(
                    type: .comment,
                    to: parentAuthorId,
                    momentId: momentId,
                    commentId: parentCommentId,
                    reaction: content, // ✅ Pasar contenido para el banner
                    senderUsername: fromUsername
                )
            }
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
    
    private func handleMentions(_ mentions: [String], momentId: String, fromUserId: String, fromUsername: String, content: String) {
        for mention in mentions {
            // Find user by username and send notification
            db.collection("users").whereField("username", isEqualTo: mention.lowercased()).getDocuments(source: .default) { snapshot, error in
                guard let documents = snapshot?.documents, let userDoc = documents.first else { return }
                
                let mentionedUserId = userDoc.documentID
                Task { @MainActor in
                    NotificationService.shared.sendInteractionNotification(
                        type: .mention,
                        to: mentionedUserId,
                        momentId: momentId,
                        reaction: content, // ✅ Pasar contenido para el banner
                        senderUsername: fromUsername
                    )
                }
            }
        }
    }
    
    func fetchSuggestedUsers(completion: @escaping (Result<[AppUser], Error>) -> Void) {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            completion(.success([]))
            return
        }
        
        // Primero intentamos obtener conexiones mutuas por prioridad
        fetchMutualConnections(userId: currentUserId) { result in
            switch result {
            case .success(let mutuals):
                if mutuals.count >= 5 {
                    // Si hay suficientes mutuos, devolvemos esos más algunos aleatorios
                    self.db.collection("users")
                        .limit(to: 20)
                        .getDocuments { snapshot, error in
                            var allUsers = mutuals
                            if let documents = snapshot?.documents {
                                let randomUsers = documents.compactMap { try? $0.data(as: AppUser.self) }
                                    .filter { user in 
                                        !mutuals.contains(where: { $0.id == user.id }) && 
                                        user.id != currentUserId 
                                    }
                                allUsers.append(contentsOf: randomUsers)
                            }
                            completion(.success(Array(allUsers.prefix(20))))
                        }
                } else {
                    // Si no, simplemente devolvemos una lista más amplia
                    self.db.collection("users")
                        .limit(to: 30)
                        .getDocuments { snapshot, error in
                            if let error = error {
                                completion(.failure(error))
                                return
                            }
                            let users = snapshot?.documents.compactMap { try? $0.data(as: AppUser.self) }
                                .filter { $0.id != currentUserId }
                            completion(.success(users ?? []))
                        }
                }
            case .failure:
                // Fallback a lista simple si fallan las conexiones mutuas
                self.db.collection("users")
                    .limit(to: 30)
                    .getDocuments { snapshot, error in
                        if let error = error {
                            completion(.failure(error))
                            return
                        }
                        let users = snapshot?.documents.compactMap { try? $0.data(as: AppUser.self) }
                            .filter { $0.id != currentUserId }
                        completion(.success(users ?? []))
                    }
            }
        }
    }
    
    // ✅ NUEVO: Buscar usuarios por prefijo de username (Búsqueda Real)
    func searchUsers(query: String, completion: @escaping (Result<[AppUser], Error>) -> Void) {
        let cleanQuery = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanQuery.isEmpty else {
            completion(.success([]))
            return
        }
        
        let currentUserId = Auth.auth().currentUser?.uid
        
        db.collection("users")
            .whereField("username", isGreaterThanOrEqualTo: cleanQuery)
            .whereField("username", isLessThanOrEqualTo: cleanQuery + "\u{f8ff}")
            .limit(to: 30)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                let users = snapshot?.documents.compactMap { doc -> AppUser? in
                    try? doc.data(as: AppUser.self)
                }.filter { $0.id != currentUserId } ?? []

                self.applySearchMuteFilterIfNeeded(users: users) { filteredUsers in
                    completion(.success(filteredUsers))
                }
            }
    }
    
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
        reactionRef.getDocument { [weak self] snapshot, error in
            guard let self = self else {
                completion(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("errors.operationCancelled", comment: "Operation cancelled")]))
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
            
            batch.commit { [weak self] error in
                if let error = error {
                    completion(error)
                } else {
                    // Eliminamos notificación manual: servidor se encarga
                    completion(nil)
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
            
            self.performFollow(currentUserId: senderId, targetUserId: recipientId, sendNotification: false) { error in
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
                    if let error = error {
                        completion(error)
                        return
                    }

                    // ✅ Notificar al solicitante que su solicitud fue aceptada
                    // Usar username real del usuario que acepta para evitar fallback "Alguien".
                    self.fetchUserProfile(userId: recipientId) { result in
                        let accepterUsername: String?
                        switch result {
                        case .success(let accepterUser):
                            accepterUsername = accepterUser.username
                        case .failure:
                            accepterUsername = nil
                        }

                        Task { @MainActor in
                            NotificationService.shared.sendInteractionNotification(
                                type: .requestAccepted,
                                to: senderId,
                                senderUsername: accepterUsername
                            )
                        }
                    }
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

    private func performFollow(currentUserId: String, targetUserId: String, sendNotification: Bool = true, completion: @escaping (Error?) -> Void) {
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
                        self?.invalidateFollowingCache(currentUserId: currentUserId, targetUserId: targetUserId)
                        
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
                    // ✅ LIMPIEZA DE NOTIFICACIÓN (Unfollow)
                    Task { @MainActor in
                        NotificationService.shared.removeNotification(
                            type: .newFollower,
                            senderId: currentUserId,
                            recipientId: targetUserId
                        )
                    }
                    
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
    private func fetchUsersAsync(userIds: [String]) async throws -> [AppUser] {
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
                Task { @MainActor in
                    NotificationService.shared.sendInteractionNotification(type: .mention, to: mentionedUserId, momentId: momentId, reaction: commentContent)
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
                Task { @MainActor in
                    NotificationService.shared.sendInteractionNotification(
                        type: .like,
                        to: recipientId,
                        momentId: momentId,
                        commentId: commentId,
                        reaction: reaction, // ✅ Pasar emoji para el banner
                        senderUsername: user.username
                    )
                }
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
        scheduledDate: Date? = nil,
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
        case .onlyMe: contentAudience = .onlyMe
        }
        
        self.fetchUser(userId: userId) { [weak self] result in
            guard let self = self else {
                completion(nil, NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("errors.operationCancelled", comment: "Operation cancelled")]))
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
                    allowSharing: allowSharing,
                    scheduledDate: scheduledDate
                )
                
                do {
                    let encoder = Firestore.Encoder()
                    var momentData = try encoder.encode(moment)
                    
                    momentData["mediaItems"] = self.serializedMediaItems(mediaItems, encoder: encoder)
                    
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
                completion(nil, NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("errors.operationCancelled", comment: "Operation cancelled")]))
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
                    // El payload Codable de Story incluye `stickers` con CGPoint anidado.
                    // Para Firestore saneamos ese array manualmente justo debajo.
                    storyData.removeValue(forKey: "stickers")
                    storyData.removeValue(forKey: "textPosition")
                    
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
                                "positionX": Double(sticker.position.x),
                                "positionY": Double(sticker.position.y),
                                "scale": Double(sticker.scale),
                                "rotation": sticker.rotation
                            ]
                            if let stickerId = sticker.stickerId {
                                stickerData["stickerId"] = stickerId
                            }
                            
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
                            if let latitude = sticker.latitude, let longitude = sticker.longitude {
                                stickerData["latitude"] = latitude
                                stickerData["longitude"] = longitude
                            }
                            if let questionText = sticker.questionText {
                                stickerData["questionText"] = questionText
                            }
                            if let pollOptions = sticker.pollOptions {
                                stickerData["pollOptions"] = pollOptions
                            }
                            
                            if let weatherSymbol = sticker.weatherSymbol {
                                stickerData["weatherSymbol"] = weatherSymbol
                            }
                            if let linkURL = sticker.linkURL {
                                stickerData["linkURL"] = linkURL
                            }
                            if let linkTitle = sticker.linkTitle {
                                stickerData["linkTitle"] = linkTitle
                            }
                            if let countdownTitle = sticker.countdownTitle {
                                stickerData["countdownTitle"] = countdownTitle
                            }
                            if let countdownTargetAtMs = sticker.countdownTargetAtMs {
                                stickerData["countdownTargetAtMs"] = countdownTargetAtMs
                            }
                            if let sliderEmoji = sticker.sliderEmoji {
                                stickerData["sliderEmoji"] = sliderEmoji
                            }
                            if let sliderPrompt = sticker.sliderPrompt {
                                stickerData["sliderPrompt"] = sliderPrompt
                            }
                            if let caption = sticker.caption {
                                stickerData["caption"] = caption
                            }
                            if let profileImagePath = sticker.profileImagePath {
                                stickerData["profileImagePath"] = profileImagePath
                            }
                            if let momentId = sticker.momentId {
                                stickerData["momentId"] = momentId
                            }
                            if let mediaCount = sticker.mediaCount {
                                stickerData["mediaCount"] = mediaCount
                            }
                            if let quizQuestion = sticker.quizQuestion {
                                stickerData["quizQuestion"] = quizQuestion
                            }
                            if let quizOptions = sticker.quizOptions {
                                stickerData["quizOptions"] = quizOptions
                            }
                            if let quizCorrectIndex = sticker.quizCorrectIndex {
                                stickerData["quizCorrectIndex"] = quizCorrectIndex
                            }
                            if let revealType = sticker.revealType {
                                stickerData["revealType"] = revealType
                            }
                            if let frameStyle = sticker.frameStyle {
                                stickerData["frameStyle"] = frameStyle
                            }
                            
                            // ✅ INCLUIR PROPIEDADES DE ANIMACIÓN
                            if sticker.isAnimated {
                                stickerData["isAnimated"] = true
                                if let gifURL = sticker.gifURL {
                                    stickerData["gifURL"] = String(describing: gifURL)
                                }
                                if let videoURL = sticker.videoURL {
                                    stickerData["videoURL"] = videoURL
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
                        
                        // 🔗 SI ES UNA NUEVA CADENA (POSITION 1), CREAR DOCUMENTO GLOBAL DE METADATOS
                        if chainPosition == 1 {
                            let chainMetadata: [String: Any] = [
                                "chainId": chainId,
                                "authorId": userId,
                                "title": chainTitle ?? "",
                                "createdAt": FieldValue.serverTimestamp(),
                                "allowOthersToContinue": allowOthersToContinue ?? true,
                                "continuationAudience": continuationAudience?.rawValue ?? "everyone",
                                "continuationCustomViewers": continuationCustomViewers ?? [],
                                "continuationCustomListId": continuationCustomListId ?? "",
                                "continuationCustomListName": continuationCustomListName ?? "",
                                "isExpired": false
                            ]
                            
                            self.db.collection("storyChains").document(chainId).setData(chainMetadata, merge: true) { error in
                                if let error = error {
                                    // Error silencioso
                                }
                            }
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
                                self.bumpStorySummaryOnCreate(
                                    userId: userId,
                                    audience: story.audience,
                                    timestamp: story.timestamp,
                                    expirationDate: story.expirationDate
                                )
                                self.rebuildStorySummary(for: userId) { rebuildError in
                                    _ = rebuildError
                                }
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
                // ✅ FIXED: Sincronizar para evitar crash en el group.notify
                syncQueue.sync {
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
        scheduledDate: Date? = nil,
        completion: @escaping (String?, Error?) -> Void
    ) {
        self.fetchUser(userId: userId) { [weak self] result in
            guard let self = self else {
                completion(nil, NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("errors.operationCancelled", comment: "Operation cancelled")]))
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
                    allowSharing: allowSharing,
                    scheduledDate: scheduledDate
                )
                
                do {
                    let encoder = Firestore.Encoder()
                    var momentData = try encoder.encode(moment)
                    
                    momentData["mediaItems"] = self.serializedMediaItems(mediaItems, encoder: encoder)
                    
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
                completion(nil, NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("errors.operationCancelled", comment: "Operation cancelled")]))
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
                            if let stickerId = sticker.stickerId {
                                stickerData["stickerId"] = stickerId
                            }
                            
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
                            if let latitude = sticker.latitude, let longitude = sticker.longitude {
                                stickerData["latitude"] = latitude
                                stickerData["longitude"] = longitude
                            }
                            if let questionText = sticker.questionText {
                                stickerData["questionText"] = questionText
                            }
                            if let pollOptions = sticker.pollOptions {
                                stickerData["pollOptions"] = pollOptions
                            }
                            
                            if let weatherSymbol = sticker.weatherSymbol {
                                stickerData["weatherSymbol"] = weatherSymbol
                            }
                            if let linkURL = sticker.linkURL {
                                stickerData["linkURL"] = linkURL
                            }
                            if let linkTitle = sticker.linkTitle {
                                stickerData["linkTitle"] = linkTitle
                            }
                            if let countdownTitle = sticker.countdownTitle {
                                stickerData["countdownTitle"] = countdownTitle
                            }
                            if let countdownTargetAtMs = sticker.countdownTargetAtMs {
                                stickerData["countdownTargetAtMs"] = countdownTargetAtMs
                            }
                            if let sliderEmoji = sticker.sliderEmoji {
                                stickerData["sliderEmoji"] = sliderEmoji
                            }
                            if let sliderPrompt = sticker.sliderPrompt {
                                stickerData["sliderPrompt"] = sliderPrompt
                            }
                            if let caption = sticker.caption {
                                stickerData["caption"] = caption
                            }
                            if let profileImagePath = sticker.profileImagePath {
                                stickerData["profileImagePath"] = profileImagePath
                            }
                            if let momentId = sticker.momentId {
                                stickerData["momentId"] = momentId
                            }
                            if let mediaCount = sticker.mediaCount {
                                stickerData["mediaCount"] = mediaCount
                            }
                            if let quizQuestion = sticker.quizQuestion {
                                stickerData["quizQuestion"] = quizQuestion
                            }
                            if let quizOptions = sticker.quizOptions {
                                stickerData["quizOptions"] = quizOptions
                            }
                            if let quizCorrectIndex = sticker.quizCorrectIndex {
                                stickerData["quizCorrectIndex"] = quizCorrectIndex
                            }
                            if let revealType = sticker.revealType {
                                stickerData["revealType"] = revealType
                            }
                            if let frameStyle = sticker.frameStyle {
                                stickerData["frameStyle"] = frameStyle
                            }

                            // ✅ INCLUIR PROPIEDADES DE ANIMACIÓN
                            if sticker.isAnimated {
                                stickerData["isAnimated"] = true
                                if let gifURL = sticker.gifURL {
                                    stickerData["gifURL"] = String(describing: gifURL)
                                }
                                if let videoURL = sticker.videoURL {
                                    stickerData["videoURL"] = videoURL
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
                        
                        // 🔗 SI ES UNA NUEVA CADENA (POSITION 1), CREAR DOCUMENTO GLOBAL DE METADATOS
                        if chainPosition == 1 {
                            let chainMetadata: [String: Any] = [
                                "chainId": chainId,
                                "authorId": userId,
                                "title": chainTitle ?? "",
                                "createdAt": FieldValue.serverTimestamp(),
                                "allowOthersToContinue": allowOthersToContinue ?? true,
                                "continuationAudience": continuationAudience?.rawValue ?? "everyone",
                                "continuationCustomViewers": continuationCustomViewers ?? [],
                                "continuationCustomListId": continuationCustomListId ?? "",
                                "continuationCustomListName": continuationCustomListName ?? "",
                                "isExpired": false
                            ]
                            
                            self.db.collection("storyChains").document(chainId).setData(chainMetadata, merge: true) { error in
                                if let error = error {
                                    // Error silencioso
                                }
                            }
                        }
                    }

                    // 🔥 USAR EL storyId GENERADO COMO DOCUMENT ID
                    self.db.collection("users").document(userId)
                        .collection("stories").document(storyId)
                        .setData(storyData) { error in
                            if let error = error {
                                completion(nil, error) // 🔥 DEVOLVER nil para el ID en caso de error
                            } else {
                                self.bumpStorySummaryOnCreate(
                                    userId: userId,
                                    audience: story.audience,
                                    timestamp: story.timestamp,
                                    expirationDate: story.expirationDate
                                )
                                self.rebuildStorySummary(for: userId) { rebuildError in
                                    _ = rebuildError
                                }
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

    // MARK: - HIGHLIGHTED STORIES METHODS
    
    func fetchHighlights(userId: String, completion: @escaping (Result<[HighlightedStory], Error>) -> Void) {
        db.collection("users").document(userId).collection("highlights")
            .order(by: "createdAt", descending: true)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                let highlights = snapshot?.documents.compactMap { doc -> HighlightedStory? in
                    try? doc.data(as: HighlightedStory.self)
                } ?? []
                
                completion(.success(highlights))
            }
    }
    
    // ✅ NUEVO: Obtener todas las historias (activas y archivadas) para crear destacadas
    func fetchAllStories(userId: String, completion: @escaping (Result<[Story], Error>) -> Void) {
        db.collection("users").document(userId).collection("stories")
            .order(by: "timestamp", descending: true)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                let stories = snapshot?.documents.compactMap { doc -> Story? in
                    try? doc.data(as: Story.self)
                } ?? []
                
                completion(.success(stories))
            }
    }
    
    // ✅ NUEVA: Paginación para mejor rendimiento
    func fetchStoriesPaginated(userId: String, limit: Int, lastDocument: DocumentSnapshot?, completion: @escaping (Result<(stories: [Story], lastDoc: DocumentSnapshot?), Error>) -> Void) {
        var query = db.collection("users").document(userId).collection("stories")
            .order(by: "timestamp", descending: true)
            .limit(to: limit)
        
        if let lastDoc = lastDocument {
            query = query.start(afterDocument: lastDoc)
        }
        
        query.getDocuments { snapshot, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let snapshot = snapshot else {
                completion(.success((stories: [], lastDoc: nil)))
                return
            }
            
            let stories = snapshot.documents.compactMap { doc -> Story? in
                try? doc.data(as: Story.self)
            }
            
            completion(.success((stories: stories, lastDoc: snapshot.documents.last)))
        }
    }
    
    // ✅ NUEVO: Obtener historias específicas por ID
    func fetchStoriesByIds(userId: String, storyIds: [String], completion: @escaping (Result<[Story], Error>) -> Void) {
        let group = DispatchGroup()
        var stories: [Story] = []
        var lastError: Error?
        
        for storyId in storyIds {
            group.enter()
            db.collection("users").document(userId).collection("stories").document(storyId).getDocument { snapshot, error in
                defer { group.leave() }
                
                if let error = error {
                    lastError = error
                    return
                }
                
                if let snapshot = snapshot, snapshot.exists {
                    if let story = try? snapshot.data(as: Story.self) {
                        stories.append(story)
                    }
                }
            }
        }
        
        group.notify(queue: .main) {
            if stories.isEmpty && !storyIds.isEmpty && lastError != nil {
                completion(.failure(lastError!))
            } else {
                // Mantener el orden de los IDs originales
                let orderedStories = storyIds.compactMap { id in
                    stories.first(where: { $0.id == id })
                }
                completion(.success(orderedStories))
            }
        }
    }

    /// Obtiene historias activas para un conjunto de autores de forma batched (collectionGroup),
    /// con fallback seguro al flujo legacy por usuario si falta índice.
    func fetchActiveStoriesForUsers(
        userIds: [String],
        completion: @escaping (Result<[String: [Story]], Error>) -> Void
    ) {
        let normalizedUserIds = Array(Set(userIds.filter { !$0.isEmpty }))
        guard !normalizedUserIds.isEmpty else {
            completion(.success([:]))
            return
        }

        let batches = normalizedUserIds.chunked(into: 10)
        let group = DispatchGroup()
        let syncQueue = DispatchQueue(label: "active.stories.users.sync")
        var aggregated: [String: [Story]] = [:]
        var capturedError: Error?

        for batch in batches {
            group.enter()
            self.fetchActiveStoriesBatch(userIds: batch) { result in
                syncQueue.sync {
                    switch result {
                    case .success(let storiesByUser):
                        for (authorId, stories) in storiesByUser {
                            aggregated[authorId, default: []].append(contentsOf: stories)
                        }
                    case .failure(let error):
                        capturedError = capturedError ?? error
                    }
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            let (finalMap, error): ([String: [Story]], Error?) = syncQueue.sync {
                var sortedMap: [String: [Story]] = [:]
                for (authorId, stories) in aggregated {
                    sortedMap[authorId] = stories.sorted { $0.timestamp < $1.timestamp }
                }
                return (sortedMap, capturedError)
            }

            if finalMap.isEmpty, let error = error {
                completion(.failure(error))
            } else {
                completion(.success(finalMap))
            }
        }
    }

    private func fetchActiveStoriesBatch(
        userIds: [String],
        completion: @escaping (Result<[String: [Story]], Error>) -> Void
    ) {
        guard !userIds.isEmpty else {
            completion(.success([:]))
            return
        }

        db.collectionGroup("stories")
            .whereField("authorId", in: userIds)
            .whereField("expirationDate", isGreaterThan: Timestamp(date: Date()))
            .getDocuments { [weak self] snapshot, error in
                guard let self = self else {
                    completion(.failure(NSError(domain: "FirestoreService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Service deallocated"])))
                    return
                }

                if error != nil {
                    // Fallback para mantener compatibilidad sin depender de índice nuevo.
                    self.fetchActiveStoriesLegacy(userIds: userIds, completion: completion)
                    return
                }

                guard let documents = snapshot?.documents else {
                    completion(.success([:]))
                    return
                }

                var storiesByUser: [String: [Story]] = [:]
                for document in documents {
                    guard let story = try? document.data(as: Story.self) else { continue }
                    storiesByUser[story.authorId, default: []].append(story)
                }

                completion(.success(storiesByUser))
            }
    }

    private func fetchActiveStoriesLegacy(
        userIds: [String],
        completion: @escaping (Result<[String: [Story]], Error>) -> Void
    ) {
        let group = DispatchGroup()
        let syncQueue = DispatchQueue(label: "active.stories.legacy.sync")
        var storiesByUser: [String: [Story]] = [:]
        var capturedError: Error?

        for userId in userIds {
            group.enter()
            db.collection("users").document(userId).collection("stories")
                .whereField("expirationDate", isGreaterThan: Timestamp(date: Date()))
                .getDocuments { snapshot, error in
                    syncQueue.sync {
                        if let error = error {
                            capturedError = capturedError ?? error
                        } else {
                            let stories = snapshot?.documents.compactMap { try? $0.data(as: Story.self) } ?? []
                            storiesByUser[userId] = stories.sorted { $0.timestamp < $1.timestamp }
                        }
                    }
                    group.leave()
                }
        }

        group.notify(queue: .main) {
            let (resultMap, error): ([String: [Story]], Error?) = syncQueue.sync {
                (storiesByUser, capturedError)
            }
            if resultMap.isEmpty, let error = error {
                completion(.failure(error))
            } else {
                completion(.success(resultMap))
            }
        }
    }

    /// Obtiene resumen de stories por autor desde users/{id}.storySummary (lectura ligera).
    func fetchStorySummariesForUsers(
        userIds: [String],
        completion: @escaping (Result<[String: StoryAuthorSummary], Error>) -> Void
    ) {
        let normalizedUserIds = Array(Set(userIds.filter { !$0.isEmpty }))
        guard !normalizedUserIds.isEmpty else {
            completion(.success([:]))
            return
        }

        let batches = normalizedUserIds.chunked(into: 10)
        let group = DispatchGroup()
        let syncQueue = DispatchQueue(label: "story.summary.users.sync")
        var mergedSummaries: [String: StoryAuthorSummary] = [:]
        var capturedError: Error?

        for batch in batches {
            group.enter()
            db.collection("users")
                .whereField(FieldPath.documentID(), in: batch)
                .getDocuments { snapshot, error in
                    syncQueue.sync {
                        if let error = error {
                            capturedError = capturedError ?? error
                        } else {
                            for document in snapshot?.documents ?? [] {
                                guard let summary = self.parseStorySummary(from: document.data()) else { continue }
                                let normalized = self.normalizedStorySummary(summary)
                                mergedSummaries[document.documentID] = normalized
                                if summary.activeStoryCount > 0 && normalized.activeStoryCount == 0 {
                                    self.scheduleStorySummaryRebuildIfNeeded(for: document.documentID)
                                }
                            }
                        }
                    }
                    group.leave()
                }
        }

        group.notify(queue: .main) {
            let (result, error): ([String: StoryAuthorSummary], Error?) = syncQueue.sync {
                (mergedSummaries, capturedError)
            }
            if result.isEmpty, let error = error {
                completion(.failure(error))
            } else {
                completion(.success(result))
            }
        }
    }

    /// Recalcula y guarda storySummary para un autor.
    func rebuildStorySummary(for userId: String, completion: ((Error?) -> Void)? = nil) {
        guard !userId.isEmpty else {
            completion?(NSError(domain: "FirestoreService", code: -1, userInfo: [NSLocalizedDescriptionKey: "userId vacío"]))
            return
        }

        db.collection("users").document(userId).collection("stories")
            .whereField("expirationDate", isGreaterThan: Timestamp(date: Date()))
            .getDocuments { snapshot, error in
                if let error = error {
                    completion?(error)
                    return
                }

                let stories = snapshot?.documents.compactMap { try? $0.data(as: Story.self) } ?? []
                let activeCount = stories.count
                let latestStoryAt = stories.map(\.timestamp).max()
                let latestExpirationAt = stories.map(\.expirationDate).max()
                var audiencesSummary: [String: Int] = [:]
                for story in stories {
                    let key = (story.audience?.isEmpty == false ? story.audience! : "everyone")
                    audiencesSummary[key, default: 0] += 1
                }

                let userRef = self.db.collection("users").document(userId)
                let batch = self.db.batch()
                // Reemplazo explícito de subcampos para evitar arrastrar claves antiguas en audiencesSummary.
                var summaryPayload: [AnyHashable: Any] = [
                    FieldPath(["storySummary", "activeStoryCount"]): activeCount,
                    FieldPath(["storySummary", "audiencesSummary"]): audiencesSummary,
                    FieldPath(["storySummary", "updatedAt"]): FieldValue.serverTimestamp()
                ]
                if let latestStoryAt = latestStoryAt {
                    summaryPayload[FieldPath(["storySummary", "latestStoryAt"])] = Timestamp(date: latestStoryAt)
                } else {
                    summaryPayload[FieldPath(["storySummary", "latestStoryAt"])] = FieldValue.delete()
                }
                if let latestExpirationAt = latestExpirationAt {
                    summaryPayload[FieldPath(["storySummary", "latestExpirationAt"])] = Timestamp(date: latestExpirationAt)
                } else {
                    summaryPayload[FieldPath(["storySummary", "latestExpirationAt"])] = FieldValue.delete()
                }
                batch.updateData(summaryPayload, forDocument: userRef)
                batch.updateData(
                    self.legacyStorySummaryCleanupPayload(audienceKeys: Array(audiencesSummary.keys)),
                    forDocument: userRef
                )
                batch.commit { writeError in
                    completion?(writeError)
                }
            }
    }

    private func parseStorySummary(from userData: [String: Any]) -> StoryAuthorSummary? {
        guard let summary = userData["storySummary"] as? [String: Any] else { return nil }

        let activeCount = (summary["activeStoryCount"] as? NSNumber)?.intValue ?? (summary["activeStoryCount"] as? Int) ?? 0
        let latestStoryAt = (summary["latestStoryAt"] as? Timestamp)?.dateValue()
        let latestExpirationAt = (summary["latestExpirationAt"] as? Timestamp)?.dateValue()
        let updatedAt = (summary["updatedAt"] as? Timestamp)?.dateValue()

        var audiencesSummary: [String: Int] = [:]
        if let rawAudiences = summary["audiencesSummary"] as? [String: Any] {
            for (key, value) in rawAudiences {
                if let number = value as? NSNumber {
                    audiencesSummary[key] = number.intValue
                }
            }
        } else if let typedAudiences = summary["audiencesSummary"] as? [String: Int] {
            audiencesSummary = typedAudiences
        }

        return StoryAuthorSummary(
            activeStoryCount: activeCount,
            latestStoryAt: latestStoryAt,
            latestExpirationAt: latestExpirationAt,
            audiencesSummary: audiencesSummary,
            updatedAt: updatedAt
        )
    }

    private func normalizedStorySummary(_ summary: StoryAuthorSummary) -> StoryAuthorSummary {
        guard let latestExpirationAt = summary.latestExpirationAt, latestExpirationAt <= Date() else {
            if summary.latestExpirationAt == nil,
               summary.activeStoryCount > 0,
               let latestStoryAt = summary.latestStoryAt,
               latestStoryAt <= Date().addingTimeInterval(-(52 * 60 * 60)) {
                // Compatibilidad con summaries antiguos sin latestExpirationAt.
                return StoryAuthorSummary(
                    activeStoryCount: 0,
                    latestStoryAt: nil,
                    latestExpirationAt: latestStoryAt,
                    audiencesSummary: [:],
                    updatedAt: summary.updatedAt
                )
            }
            return summary
        }

        return StoryAuthorSummary(
            activeStoryCount: 0,
            latestStoryAt: nil,
            latestExpirationAt: latestExpirationAt,
            audiencesSummary: [:],
            updatedAt: summary.updatedAt
        )
    }

    private func scheduleStorySummaryRebuildIfNeeded(for userId: String) {
        guard !userId.isEmpty else { return }

        var shouldSchedule = false
        storySummaryRebuildQueue.sync {
            let now = Date()
            if let lastAttempt = storySummaryLastRebuildAttempt[userId],
               now.timeIntervalSince(lastAttempt) < storySummaryRebuildCooldown {
                shouldSchedule = false
                return
            }
            if storySummaryRebuildInFlight.contains(userId) {
                shouldSchedule = false
                return
            }
            storySummaryRebuildInFlight.insert(userId)
            storySummaryLastRebuildAttempt[userId] = now
            shouldSchedule = true
        }

        guard shouldSchedule else { return }

        rebuildStorySummary(for: userId) { [weak self] _ in
            guard let self = self else { return }
            self.storySummaryRebuildQueue.async {
                self.storySummaryRebuildInFlight.remove(userId)
            }
        }
    }

    private func bumpStorySummaryOnCreate(userId: String, audience: String?, timestamp: Date, expirationDate: Date) {
        guard !userId.isEmpty else { return }

        let audienceKey = (audience?.isEmpty == false ? audience! : "everyone")
        var payload: [AnyHashable: Any] = [
            FieldPath(["storySummary", "activeStoryCount"]): FieldValue.increment(Int64(1)),
            FieldPath(["storySummary", "latestStoryAt"]): Timestamp(date: timestamp),
            FieldPath(["storySummary", "latestExpirationAt"]): Timestamp(date: expirationDate),
            FieldPath(["storySummary", "updatedAt"]): FieldValue.serverTimestamp(),
            FieldPath(["storySummary", "audiencesSummary", audienceKey]): FieldValue.increment(Int64(1))
        ]
        self.legacyStorySummaryCleanupPayload(audienceKeys: [audienceKey]).forEach { key, value in
            payload[key] = value
        }

        db.collection("users").document(userId).updateData(payload) { error in
            _ = error
        }
    }

    private func legacyStorySummaryCleanupPayload(audienceKeys: [String]) -> [AnyHashable: Any] {
        let defaultAudienceKeys = ["everyone", "connections", "mutuals", "bestFriends", "custom", "customList", "onlyMe"]
        let keys = Array(Set(defaultAudienceKeys + audienceKeys))

        var payload: [AnyHashable: Any] = [
            FieldPath(["storySummary.activeStoryCount"]): FieldValue.delete(),
            FieldPath(["storySummary.latestStoryAt"]): FieldValue.delete(),
            FieldPath(["storySummary.latestExpirationAt"]): FieldValue.delete(),
            FieldPath(["storySummary.updatedAt"]): FieldValue.delete(),
            FieldPath(["storySummary.audiencesSummary"]): FieldValue.delete()
        ]
        for key in keys {
            payload[FieldPath(["storySummary.audiencesSummary.\(key)"])] = FieldValue.delete()
        }
        return payload
    }
    
    func createHighlight(userId: String, title: String, storyIds: [String], coverImageUrl: String?, completion: @escaping (Error?) -> Void) {
        let highlight = HighlightedStory(
            id: nil,
            title: title,
            coverImageUrl: coverImageUrl,
            storiesCount: storyIds.count,
            createdAt: Date(),
            storyIds: storyIds,
            authorId: userId
        )
        
        do {
            let _ = try db.collection("users").document(userId).collection("highlights").addDocument(from: highlight) { error in
                completion(error)
            }
        } catch {
            completion(error)
        }
    }
    
    func deleteHighlight(userId: String, highlightId: String, completion: @escaping (Error?) -> Void) {
        db.collection("users").document(userId).collection("highlights").document(highlightId).delete { error in
            completion(error)
        }
    }
    
    func updateHighlight(userId: String, highlightId: String, title: String, storyIds: [String], coverImageUrl: String?, completion: @escaping (Error?) -> Void) {
        let updateData: [String: Any] = [
            "title": title,
            "storyIds": storyIds,
            "storiesCount": storyIds.count,
            "coverImageUrl": coverImageUrl as Any
        ]
        
        db.collection("users").document(userId).collection("highlights").document(highlightId).updateData(updateData) { error in
            completion(error)
        }
    }
    
    // MARK: - PREFETCHING METHODS (PHASE 8)
    
    /// Precarga las historias de un usuario en el caché local para una apertura instantánea
    func prefetchStoriesForUser(userId: String) {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        db.collection("users").document(userId).collection("stories")
            .whereField("expirationDate", isGreaterThan: Timestamp(date: Date()))
            .order(by: "timestamp", descending: true)
            .limit(to: 5)
            .getDocuments { snapshot, _ in
                guard let documents = snapshot?.documents, !documents.isEmpty else { return }
                
                let stories = documents.compactMap { try? $0.data(as: Story.self) }
                
                // ✅ COMPROBACIÓN DE PRIVACIDAD POR HISTORIA (NUEVO)
                // Usamos ContentVisibilityService para filtrar cada historia individualmente
                let visibilityService = ContentVisibilityService.shared
                let group = DispatchGroup()
                var authorizedStories: [Story] = []
                let syncQueue = DispatchQueue(label: "prefetch.visibility.sync")
                
                for story in stories {
                    group.enter()
                    
                    // ✅ MAPEO DE AUDIENCIA (NUEVO)
                    // Convertimos el string de la DB al enum que entiende el servicio de visibilidad
                    let visibilityType: ContentVisibilityType
                    if let audienceStr = story.audience {
                        switch audienceStr {
                        case "everyone": visibilityType = .everyone
                        case "connections": visibilityType = .connections
                        case "bestFriends": visibilityType = .bestFriends
                        case "custom", "customList": visibilityType = .custom
                        case "onlyMe": visibilityType = .onlyMe
                        default: visibilityType = .everyone
                        }
                    } else {
                        visibilityType = .everyone
                    }
                    
                    visibilityService.canUserSeeContent(
                        contentOwnerId: story.authorId,
                        viewerId: currentUserId,
                        contentType: visibilityType,
                        customViewers: story.customListId != nil ? [story.customListId!] : [],
                        hiddenFrom: [] 
                    ) { canSee in
                        if canSee {
                            syncQueue.sync {
                                authorizedStories.append(story)
                            }
                        }
                        group.leave()
                    }
                }
                
                group.notify(queue: .main) {
                    self.prefetchStoriesToCache(authorizedStories)
                }
            }
    }
    
    /// Precarga las imágenes de un array de historias en el caché de Kingfisher
    private func prefetchStoriesToCache(_ stories: [Story]) {
        let urls = stories.compactMap { story -> URL? in
            let urlString = story.mediaItem.url
            return URL(string: urlString)
        }
        
        if !urls.isEmpty {
            ImagePrefetchManager.shared.prefetch(urls: urls)
        }
    }
}
