import Foundation
import FirebaseFirestore
import FirebaseAuth
import CoreLocation

class EchoService {
    static let shared = EchoService()
    private let db = Firestore.firestore()
    private let firestoreService = FirestoreService()

    /// Límite de valores en `in` para Firestore (documentación actual; Firebase iOS 11+).
    private let maxAuthorIdsPerEchoQuery = 30
    /// Con muchos mutuos (p. ej. 1000), limitar paralelismo evita picos de red y presión sobre Firestore.
    private let maxConcurrentEchoMomentBatchQueries = 6

    private init() {}
    
    // MARK: - Echo Detection Logic
    /// Checks for overlapping moments from friends to suggest an Echo
    func checkForEchoOverlap(momentId: String, userId: String) {
        firestoreService.fetchMoment(momentId: momentId, userId: userId) { [weak self] result in
            switch result {
            case .success(let moment):
                self?.checkForEchoOverlap(newMoment: moment)
            case .failure(let error):
                print("Error fetching moment for Echo detection: \(error)")
            }
        }
    }
    
    private func checkForEchoOverlap(newMoment: Moment) {
        guard let userId = Auth.auth().currentUser?.uid,
              let coordinate = newMoment.locationCoordinate else { return }
        
        Task {
            do {
                // 1. Get Mutual Connection IDs
                let friendIds = try await getMutualIds(for: userId)
                
                if friendIds.isEmpty { return }
                
                // 2. Search for recent moments from friends (last 24 hours)
                // Expanded to 24h to capture "Same Day, Same Place" vibes (events, festivals, etc.)
                let searchWindow = Date().addingTimeInterval(-86400) // 24 hours

                let recentMoments = try await fetchRecentMomentsFromAuthors(
                    authorIds: friendIds,
                    since: searchWindow
                )

                let allNearbyMoments = recentMoments.filter { moment in
                    guard let friendCoord = moment.locationCoordinate else { return false }
                    let distance = calculateDistance(from: coordinate, to: friendCoord)
                    return distance <= 500 // 500 meters overlap (GPS tolerance)
                }
                
                // ✅ Usar PrivacyService para filtrar por audiencia (consistente con el resto de la app)
                PrivacyService.shared.filterVisibleContent(moments: allNearbyMoments, for: userId) { [weak self] visibleMoments in
                    guard let self = self, !visibleMoments.isEmpty else { return }
                    Task {
                        await self.proposeEcho(hostMoment: newMoment, nearbyMoments: visibleMoments)
                    }
                }
                
            } catch {
                print("Error checking for Echo overlap: \(error)")
            }
        }
    }
    
    private func getMutualIds(for userId: String) async throws -> [String] {
        let followingSnapshot = try await db.collection("users").document(userId).collection("following").getDocuments()
        let followersSnapshot = try await db.collection("users").document(userId).collection("followers").getDocuments()
        
        let followingIds = Set(followingSnapshot.documents.map { $0.documentID })
        let followerIds = Set(followersSnapshot.documents.map { $0.documentID })
        
        return Array(followingIds.intersection(followerIds))
    }

    /// Firestore limita el operador `in` a 30 valores. Partimos los mutuos en trozos y consultamos por **oleadas**
    /// (`maxConcurrentEchoMomentBatchQueries` en paralelo) para soportar p. ej. 1000 mutuos sin abrir ~34 queries a la vez.
    private func fetchRecentMomentsFromAuthors(authorIds: [String], since searchWindow: Date) async throws -> [Moment] {
        guard !authorIds.isEmpty else { return [] }

        let batchSize = maxAuthorIdsPerEchoQuery
        let chunks: [[String]] = stride(from: 0, to: authorIds.count, by: batchSize).map { start in
            Array(authorIds[start..<min(start + batchSize, authorIds.count)])
        }

        let db = self.db
        var allDocuments: [QueryDocumentSnapshot] = []
        allDocuments.reserveCapacity(chunks.count * 32)

        let waveSize = max(1, maxConcurrentEchoMomentBatchQueries)
        var chunkStart = 0
        while chunkStart < chunks.count {
            let chunkEnd = min(chunkStart + waveSize, chunks.count)
            let wave = Array(chunks[chunkStart..<chunkEnd])

            try await withThrowingTaskGroup(of: [QueryDocumentSnapshot].self) { group in
                for chunk in wave where !chunk.isEmpty {
                    group.addTask {
                        let momentQuery = db.collectionGroup("moments")
                            .whereField("authorId", in: chunk)
                            .whereField("timestamp", isGreaterThan: Timestamp(date: searchWindow))
                        let snapshot = try await momentQuery.getDocuments()
                        return snapshot.documents
                    }
                }
                for try await docs in group {
                    allDocuments.append(contentsOf: docs)
                }
            }

            chunkStart = chunkEnd
        }

        var seenDocumentPaths = Set<String>()
        var moments: [Moment] = []
        moments.reserveCapacity(allDocuments.count)
        for doc in allDocuments {
            let documentPath = doc.reference.path
            guard !seenDocumentPaths.contains(documentPath) else { continue }
            seenDocumentPaths.insert(documentPath)
            guard let moment = try? doc.data(as: Moment.self) else { continue }
            if moment.isArchived == true { continue }
            moments.append(moment)
        }
        return moments
    }

    // MARK: - Propose Echo
    private func proposeEcho(hostMoment: Moment, nearbyMoments: [Moment]) async {
        let hostId = hostMoment.authorId
        guard let coordinate = hostMoment.locationCoordinate else { return }
        
        // 1. Verificar si ya existe un Echo en esta zona (500m) y ventana de tiempo (24h)
        let existingEcho = await findExistingEcho(near: coordinate)
        
        if let existing = existingEcho, let existingId = existing.id {
            // ✅ Fusión de Echo: Añadirnos al existente
            await mergeWithExistingEcho(echoId: existingId, hostMoment: hostMoment)
            return
        }
        
        // 2. Si no existe, crear uno nuevo
        // Fetch host user details
        guard let hostUser = try? await firestoreService.db.collection("users").document(hostId).getDocument(as: AppUser.self) else { return }
        
        // ✅ TODOS empiezan como .pending (incluido el host)
        // Esto garantiza que nadie ve nada hasta que el host también acepte el Echo propuesto
        var participants: [EchoParticipant] = [
            EchoParticipant(userId: hostId, username: hostUser.username, profileImagePath: hostUser.profileImagePath, status: .pending)
        ]
        
        var addedParticipantIds: Set<String> = [hostId]
        var momentRefs: [EchoMomentRef] = []
        
        // Agregar momentos del Host
        if let mediaItems = hostMoment.mediaItems, !mediaItems.isEmpty {
            for item in mediaItems {
                momentRefs.append(EchoMomentRef(from: item, author: hostMoment))
            }
        } else {
            momentRefs.append(EchoMomentRef(from: hostMoment))
        }
        
        // Agregar momentos cercanos
        for m in nearbyMoments {
            if !addedParticipantIds.contains(m.authorId) {
                participants.append(EchoParticipant(userId: m.authorId, username: m.username, profileImagePath: m.profileImagePath, status: .pending))
                addedParticipantIds.insert(m.authorId)
            }
            
            if let mediaItems = m.mediaItems, !mediaItems.isEmpty {
                for item in mediaItems {
                    momentRefs.append(EchoMomentRef(from: item, author: m))
                }
            } else {
                momentRefs.append(EchoMomentRef(from: m))
            }
        }
        
        let newEcho = Echo(
            hostId: hostId,
            participants: participants,
            location: hostMoment.locationCoordinate!,
            locationName: hostMoment.location,
            moments: momentRefs
        )
        
        do {
            let docRef = try db.collection("echoes").addDocument(from: newEcho)
            let echoId = docRef.documentID
            sendEchoSuggestions(echoId: echoId, participants: participants, hostId: hostId)
            print("🚀 Echo proposed successfully with ID: \(echoId)")
        } catch {
            print("Error creating Echo document: \(error)")
        }
    }
    
    // MARK: - Deduplication Logic
    private func findExistingEcho(near coordinate: Moment.LocationCoordinate) async -> Echo? {
        let searchWindow = Date().addingTimeInterval(-86400) // 24 hours
        
        do {
            let snapshot = try await db.collection("echoes")
                .whereField("createdAt", isGreaterThan: Timestamp(date: searchWindow))
                .getDocuments()
            
            let echoes = snapshot.documents.compactMap { doc -> Echo? in
                var echo = try? doc.data(as: Echo.self)
                echo?.id = doc.documentID
                return echo
            }
            
            // Filtro manual por distancia (500m)
            return echoes.first { echo in
                calculateDistance(from: coordinate, to: echo.location) <= 500
            }
        } catch {
            print("Error searching for existing Echo: \(error)")
            return nil
        }
    }
    
    private func mergeWithExistingEcho(echoId: String, hostMoment: Moment) async {
        let hostId = hostMoment.authorId
        let echoRef = db.collection("echoes").document(echoId)
        
        // Fetch host user details
        guard let hostUser = try? await firestoreService.db.collection("users").document(hostId).getDocument(as: AppUser.self) else { return }
        
        do {
            try await db.runTransaction { (transaction, errorPointer) -> Any? in
                let snapshot: DocumentSnapshot
                do {
                    try snapshot = transaction.getDocument(echoRef)
                } catch let error as NSError {
                    errorPointer?.pointee = error
                    return nil
                }
                
                guard var echo = try? snapshot.data(as: Echo.self) else { return nil }
                
                // 1. Añadir participante si no está
                if !echo.participantIds.contains(hostId) {
                    echo.participants.append(EchoParticipant(userId: hostId, username: hostUser.username, profileImagePath: hostUser.profileImagePath, status: .pending))
                    echo.participantIds.append(hostId)
                }
                
                // 2. Añadir momentos (si no están ya)
                let existingMediaUrls = Set(echo.moments.map { $0.mediaUrl })
                
                if let mediaItems = hostMoment.mediaItems, !mediaItems.isEmpty {
                    for item in mediaItems {
                        if !existingMediaUrls.contains(item.url) {
                            echo.moments.append(EchoMomentRef(from: item, author: hostMoment))
                        }
                    }
                } else if let url = hostMoment.videoUrl ?? hostMoment.imagePath, !existingMediaUrls.contains(url) {
                    echo.moments.append(EchoMomentRef(from: hostMoment))
                }
                
                do {
                    try transaction.setData(from: echo, forDocument: echoRef)
                } catch let error as NSError {
                    errorPointer?.pointee = error
                    return nil
                }
                
                return nil
            }
            print("♻️ Merged moment into existing Echo: \(echoId)")
        } catch {
            print("Error merging with existing Echo: \(error)")
        }
    }
    
    // MARK: - Helpers
    private func calculateDistance(from: Moment.LocationCoordinate, to: Moment.LocationCoordinate) -> Double {
        let loc1 = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let loc2 = CLLocation(latitude: to.latitude, longitude: to.longitude)
        return loc1.distance(from: loc2)
    }
    
    // MARK: - Participant Actions
    func acceptEcho(echoId: String, userId: String) async throws {
        let docRef = db.collection("echoes").document(echoId)
        
        try await db.runTransaction { (transaction, errorPointer) -> Any? in
            let snapshot: DocumentSnapshot
            do {
                try snapshot = transaction.getDocument(docRef)
            } catch let error as NSError {
                errorPointer?.pointee = error
                return nil
            }
            
            guard var echo = try? snapshot.data(as: Echo.self) else {
                let error = NSError(domain: "EchoService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Echo not found"])
                errorPointer?.pointee = error
                return nil
            }
            
            // Actualizar estado del participante
            if let index = echo.participants.firstIndex(where: { $0.userId == userId }) {
                if echo.participants[index].status == .accepted { return nil }
                echo.participants[index].status = .accepted
            } else {
                return nil
            }
            
            // Si hay al menos 2 aceptados, el Echo pasa a estar activo
            let acceptedCount = echo.participants.filter { $0.status == .accepted }.count
            if acceptedCount >= 2 && echo.status == .pending {
                echo.status = .active
            }
            
            do {
                try transaction.setData(from: echo, forDocument: docRef)
            } catch let error as NSError {
                errorPointer?.pointee = error
                return nil
            }
            
            return nil
        }
    }
    
    func declineEcho(echoId: String, userId: String) async throws {
        let docRef = db.collection("echoes").document(echoId)
        
        try await db.runTransaction { (transaction, errorPointer) -> Any? in
            let snapshot: DocumentSnapshot
            do {
                try snapshot = transaction.getDocument(docRef)
            } catch let error as NSError {
                errorPointer?.pointee = error
                return nil
            }
            
            guard var echo = try? snapshot.data(as: Echo.self) else {
                return nil
            }
            
            if let index = echo.participants.firstIndex(where: { $0.userId == userId }) {
                if echo.participants[index].status == .declined { return nil }
                echo.participants[index].status = .declined
            }
            
            do {
                try transaction.setData(from: echo, forDocument: docRef)
            } catch let error as NSError {
                errorPointer?.pointee = error
                return nil
            }
            
            return nil
        }
    }
    
    // MARK: - Notifications
    private func sendEchoSuggestions(echoId: String, participants: [EchoParticipant], hostId: String) {
        // ✅ Notificamos a todos (incluido el host) porque ahora el host también empieza como .pending
        let recipientIds = participants.map { $0.userId }
        
        for recipientId in recipientIds {
            // 1. Standard Notification
            Task { @MainActor in
                NotificationService.shared.sendInteractionNotification(
                    type: .echoSuggestion,
                    to: recipientId,
                    echoId: echoId
                )
            }
            
            // 2. Nova Spark (Proactive suggestion)
            NovaActivityService.shared.triggerEchoSpark(echoId: echoId, userId: recipientId)
        }
    }
    
    // MARK: - Fetch Echoes
    
    /// Fetch pending Echo invitations for the current user
    func fetchPendingEchoes(userId: String, completion: @escaping ([Echo]) -> Void) -> ListenerRegistration {
        return db.collection("echoes")
            .whereField("participantIds", arrayContains: userId)
            .whereField("status", in: ["pending", "active"])
            .addSnapshotListener { [weak self] snapshot, error in
                if let error = error {
                    print("Error fetching pending echoes: \(error)")
                    completion([])
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    completion([])
                    return
                }
                
                let echoes = documents.compactMap { doc -> Echo? in
                    var echo = try? doc.data(as: Echo.self)
                    echo?.id = doc.documentID
                    
                    // ✅ FILTRO DE CADUCIDAD: 24 Horas
                    // Si ha expirado, no lo devolvemos y lo marcamos como expired en background
                    if let expiresAt = echo?.expiresAt, expiresAt < Date() {
                        if echo?.status != .expired {
                            self?.markEchoAsExpired(echoId: doc.documentID)
                        }
                        return nil
                    }
                    
                    // Only include if user has 'pending' status in participants
                    guard let participants = echo?.participants,
                          participants.contains(where: { $0.userId == userId && $0.status == .pending }) else {
                        return nil
                    }
                    
                    return echo
                }
                
                completion(echoes)
            }
    }
    
    // ✅ Helper para marcar como expirado
    private func markEchoAsExpired(echoId: String) {
        db.collection("echoes").document(echoId).updateData([
            "status": EchoStatus.expired.rawValue
        ]) { error in
            if let error = error {
                print("Error marking echo \(echoId) as expired: \(error)")
            }
        }
    }
    
    /// Fetch Echo history for the current user
    func fetchEchoHistory(userId: String, completion: @escaping ([Echo]) -> Void) -> ListenerRegistration {
        // Query for echoes where user is a participant (host is also a participant by default)
        // If the user leaves, they are removed from participantIds, so they won't see it anymore.
        return db.collection("echoes")
            .whereField("participantIds", arrayContains: userId)
            .addSnapshotListener { [weak self] snapshot, error in
                if let error = error {
                    print("Error fetching echo history: \(error)")
                    completion([])
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    completion([])
                    return
                }
                
                let echoes = documents.compactMap { doc -> Echo? in
                    var echo = try? doc.data(as: Echo.self)
                    echo?.id = doc.documentID
                    return echo
                }
                
                // Auto-repair check: If any echo is missing participantIds, repair it in background
                for echo in echoes where echo.participantIds.isEmpty {
                    self?.repairEcho(echo)
                }
                
                // Sort by creation date, newest first
                let sorted = echoes.sorted { $0.createdAt > $1.createdAt }
                completion(sorted)
            }
    }
    

    
    /// Leave an Echo (removes participant and their moments)
    func leaveEcho(echoId: String, userId: String, completion: @escaping (Error?) -> Void) {
        let echoRef = db.collection("echoes").document(echoId)
        
        db.runTransaction({ (transaction, errorPointer) -> Any? in
            let echoSnapshot: DocumentSnapshot
            do {
                try echoSnapshot = transaction.getDocument(echoRef)
            } catch let fetchError as NSError {
                errorPointer?.pointee = fetchError
                return nil
            }
            
            guard var echo = try? echoSnapshot.data(as: Echo.self) else {
                let error = NSError(domain: "AppErrorDomain", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to fetch echo"])
                errorPointer?.pointee = error
                return nil
            }
            
            // ✅ LOCK-IN: No permitir salir si el Echo sigue activo (no ha expirado)
            // Esto evita que usuarios se unan y se salgan inmediatamente, dejando colgados a los demás
            if Date() < echo.expiresAt {
                let error = NSError(domain: "EchoService", code: 403, userInfo: [
                    NSLocalizedDescriptionKey: NSLocalizedString("echo.leave.locked", comment: "Error message when trying to leave an active Echo")
                ])
                errorPointer?.pointee = error
                return nil
            }
            
            // 1. Remove from participants
            echo.participants.removeAll { $0.userId == userId }
            
            // 2. Remove from participantIds
            echo.participantIds.removeAll { $0 == userId }
            
            // 3. Remove user's moments
            echo.moments.removeAll { $0.authorId == userId }
            
            // 4. Update or Delete
            if echo.participants.isEmpty {
                transaction.deleteDocument(echoRef)
            } else {
                do {
                    try transaction.setData(from: echo, forDocument: echoRef)
                } catch let error as NSError {
                    errorPointer?.pointee = error
                    return nil
                }
            }
            
            return nil
        }) { (_, error) in
            completion(error)
        }
    }
    
    // MARK: - Maintenance
    
    /// Updates legacy echoes to include participantIds field
    func repairEcho(_ echo: Echo) {
        guard let echoId = echo.id, echo.participantIds.isEmpty else { return }
        
        let ids = echo.participants.map { $0.userId }
        db.collection("echoes").document(echoId).updateData([
            "participantIds": ids
        ]) { error in
            if let error = error {
                print("Error repairing echo \(echoId): \(error)")
            } else {
                print("✅ Echo \(echoId) repaired with participantIds")
            }
        }
    }
}
