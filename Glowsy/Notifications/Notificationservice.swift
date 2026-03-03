import Foundation
import FirebaseFirestore
import FirebaseAuth
import UserNotifications

// MARK: - ✨ Glowsy Notification Service (Unified Source of Truth)
@MainActor
class NotificationService: ObservableObject {
    static let shared = NotificationService()
    private let db = Firestore.firestore()
    
    @Published var unreadCount: Int = 0
    @Published var notifications: [Notification] = []
    @Published var isLoading: Bool = false
    @Published var isLoadingMore: Bool = false
    @Published var canLoadMore: Bool = true
    
    private var listener: ListenerRegistration?
    private var lastDocument: DocumentSnapshot?
    private let pageSize = 20
    private var profileCache: [String: User] = [:]
    
    private init() {
        startObserving()
    }
    
    // MARK: - Lifecycle Management
    func startObserving() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        listener?.remove()
        isLoading = true
        
        let query = db.collection("users").document(userId).collection("notifications")
            .order(by: "timestamp", descending: true)
            .limit(to: pageSize)
        
        // 🔥 LOCAL-FIRST: Cargar del caché inmediatamente
        let cached = LocalPersistenceService.shared.loadNotifications()
        if !cached.isEmpty {
            self.notifications = cached
            self.updateUnreadCount()
            self.isLoading = false
            print("🔔 NotificationService: Cargadas \(cached.count) notificaciones del caché")
        }
        
        var isFirstSnapshot = true
        listener = query.addSnapshotListener { [weak self] snapshot, error in
            guard let self = self else { return }
            
            Task { @MainActor in
                guard let documents = snapshot?.documents else { 
                    self.isLoading = false
                    return 
                }
                
                self.lastDocument = documents.last
                self.canLoadMore = documents.count >= self.pageSize
                
                self.notifications = documents.compactMap { doc in
                    self.decodeNotificationDocument(doc)
                }
                // ✅ Guardar en caché local
                // Si es el primer snapshot, usamos sync: true para purgar borrados del servidor
                LocalPersistenceService.shared.saveNotifications(self.notifications, sync: isFirstSnapshot)
                isFirstSnapshot = false
                
                self.updateUnreadCount()
                self.isLoading = false
            }
        }

    }
    
    func loadMore() {
        guard let userId = Auth.auth().currentUser?.uid, 
              let lastDoc = lastDocument, 
              canLoadMore && !isLoading else { return }
        
        isLoadingMore = true
        
        db.collection("users").document(userId).collection("notifications")
            .order(by: "timestamp", descending: true)
            .start(afterDocument: lastDoc)
            .limit(to: pageSize)
            .getDocuments { [weak self] snapshot, error in
                guard let self = self else { return }
                
                Task { @MainActor in
                    guard let documents = snapshot?.documents else {
                        self.isLoadingMore = false
                        return
                    }
                    
                    self.lastDocument = documents.last
                    self.canLoadMore = documents.count >= self.pageSize
                    
                    let newNotifications = documents.compactMap { doc in
                        self.decodeNotificationDocument(doc)
                    }
                    
                    self.notifications.append(contentsOf: newNotifications)
                    self.isLoadingMore = false
                }
            }

    }
    
    private func updateUnreadCount() {
        self.unreadCount = notifications.filter { $0.isPending }.count
        UIApplication.shared.applicationIconBadgeNumber = self.unreadCount
    }

    private func decodeNotificationDocument(_ doc: QueryDocumentSnapshot) -> Notification? {
        do {
            var notification = try doc.data(as: Notification.self)
            if notification.id == nil || notification.id?.isEmpty == true {
                notification.id = doc.documentID
            }
            return notification
        } catch {
            print("❌ NotificationService: Failed to decode notification \(doc.documentID): \(error)")
            return nil
        }
    }
    
    // MARK: - Notification Creation Engine (Internal)
    
    private func triggerNotification(_ notification: Notification, to targetUserId: String) {
        // 1. Evitar auto-notificaciones
        guard targetUserId != Auth.auth().currentUser?.uid else { return }
        
        // 2. Verificar preferencias del destinatario
        db.collection("users").document(targetUserId).getDocument { [weak self] snapshot, error in
            guard let self = self else { return }
            
            Task { @MainActor in
                if let data = snapshot?.data(),
                   let preferences = data["notificationPreferences"] as? [String: Bool] {

                
                // ✅ 0. Verificar Horario "No Molestar" (DND)
                if let start = data["activeHoursStart"] as? String,
                   let end = data["activeHoursEnd"] as? String,
                   self.isInQuietHours(start: start, end: end) == true {
                    print("🔇 Notification silenced: User is in Do Not Disturb mode (\(start)-\(end))")
                    return
                }

                let isAllowed = preferences[notification.type.rawValue] ?? true
                if !isAllowed { return }
                
                // ✅ LÓGICA DE FILTRADO AVANZADO
                
                // 1. Filtro "Solo comentarios de Mutuals"
                if notification.type == .comment,
                   let commentsMutualsOnly = preferences["commentsMutualsOnly"],
                   commentsMutualsOnly == true {
                    
                    // Verificar si son mutuals
                    self.checkIfMutuals(user1: notification.senderId, user2: targetUserId) { isMutual in
                        if isMutual {
                            // ✅ Es mutual, verificar siguiente filtro o enviar
                             self.checkOldPostReactionFilter(notification: notification, preferences: preferences, targetUserId: targetUserId)
                        } else {
                            // ❌ No es mutual, silenciar notificación
                            print("🔇 Notification silenced: Comment not from mutual")
                            return
                        }
                    }
                    return // Salir para esperar el callback asíncrono
                }
                
                // 2. Filtro "Silenciar reacciones en posts antiguos"
                self.checkOldPostReactionFilter(notification: notification, preferences: preferences, targetUserId: targetUserId)
                return
                }
                
                // Si no hay preferencias, comportamiento por defecto (enviar)
                self.saveNotification(notification, for: targetUserId)
            }
        }

    }
    
    // ✅ Helper para verificar horario "No Molestar"
    private func isInQuietHours(start: String, end: String) -> Bool {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX") // Asegurar formato 24h constante
        
        let now = Date()
        let calendar = Calendar.current
        let currentComponents = calendar.dateComponents([.hour, .minute], from: now)
        
        guard let startTime = dateFormatter.date(from: start),
              let endTime = dateFormatter.date(from: end) else { return false }
        
        let startComponents = calendar.dateComponents([.hour, .minute], from: startTime)
        let endComponents = calendar.dateComponents([.hour, .minute], from: endTime)
        
        guard let currentHour = currentComponents.hour, let currentMinute = currentComponents.minute,
              let startHour = startComponents.hour, let startMinute = startComponents.minute,
              let endHour = endComponents.hour, let endMinute = endComponents.minute else { return false }
        
        let currentMinutes = currentHour * 60 + currentMinute
        let startMinutes = startHour * 60 + startMinute
        let endMinutes = endHour * 60 + endMinute
        
        if startMinutes > endMinutes {
            // Caso: Cruza la medianoche (ej: 23:00 a 07:00)
            // Es DND si es mayor que inicio (noche) O menor que fin (mañana)
            return currentMinutes >= startMinutes || currentMinutes <= endMinutes
        } else {
            // Caso: Mismo día (ej: 09:00 a 17:00)
            return currentMinutes >= startMinutes && currentMinutes <= endMinutes
        }
    }
    
    // ✅ Helper para verificar filtro de posts antiguos
    private func checkOldPostReactionFilter(notification: Notification, preferences: [String: Bool], targetUserId: String) {
        if (notification.type == .like || notification.type == .storyReaction),
           let muteOldReactions = preferences["muteOldPostReactions"],
           muteOldReactions == true,
           let momentId = notification.momentId {
            
            // Verificar antigüedad del post
            db.collection("moments").document(momentId).getDocument { [weak self] snapshot, error in
                guard let self = self else { return }
                
                Task { @MainActor in
                    if let data = snapshot?.data(),
                       let timestamp = data["timestamp"] as? Timestamp {

                    
                    let postDate = timestamp.dateValue()
                    let daysOld = Calendar.current.dateComponents([.day], from: postDate, to: Date()).day ?? 0
                    
                    if daysOld > 180 { // 180 días (aprox 6 meses) como umbral para "antiguo"
                         // ❌ Post antiguo, silenciar
                        print("🔇 Notification silenced: Reaction on old post (\(daysOld) days)")
                        return
                    }
                    }
                    // ✅ Post reciente o error al leer fecha, enviar notificación
                    self.saveNotification(notification, for: targetUserId)
                }
            }

        } else {
            // No aplica filtro, enviar
            saveNotification(notification, for: targetUserId)
        }
    }
    
    // ✅ Helper para verificar mutuals
    private func checkIfMutuals(user1: String, user2: String, completion: @escaping (Bool) -> Void) {
        let user1FollowingRef = db.collection("users").document(user1).collection("following").document(user2)
        let user2FollowingRef = db.collection("users").document(user2).collection("following").document(user1)
        
        user1FollowingRef.getDocument { [weak self] doc1, _ in
            guard let self = self else { return }
            
            if doc1?.exists == true {
                user2FollowingRef.getDocument { doc2, _ in
                    Task { @MainActor in
                        completion(doc2?.exists == true)
                    }
                }
            } else {
                Task { @MainActor in
                    completion(false)
                }
            }
        }

    }
    
    private func saveNotification(_ notification: Notification, for userId: String) {
        do {
            var notificationToSave = notification
            let notificationsRef = db.collection("users").document(userId).collection("notifications")
            let documentRef: DocumentReference

            if let notificationId = notificationToSave.id, !notificationId.isEmpty {
                documentRef = notificationsRef.document(notificationId)
            } else {
                documentRef = notificationsRef.document()
                notificationToSave.id = documentRef.documentID
            }

            try documentRef.setData(from: notificationToSave)
            // ✅ Actualizar caché local si somos nosotros viendo este cambio (aunque normalmente lo hará el listener)
            LocalPersistenceService.shared.saveNotifications([notificationToSave])
        } catch {
            print("❌ Error saving notification: \(error)")
        }
    }
    
    // MARK: - Public Sending Methods
    
    func sendInteractionNotification(type: NotificationType, to targetUserId: String, momentId: String? = nil, storyId: String? = nil, commentId: String? = nil, reaction: String? = nil, senderUsername: String? = nil, echoId: String? = nil) {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        // 1. Prioridad: Username pasado por parámetro
        // 2. Segunda opción: UserDefaults (rápido)
        // 3. Fallback: "Alguien" (mejor que "Usuario")
        let username = senderUsername ?? UserDefaults.standard.string(forKey: "current_username") ?? "Alguien"
        
        let notification = Notification(
            type: type,
            senderId: currentUserId,
            senderUsername: username,
            timestamp: Date(),
            isPending: true,
            momentId: momentId,
            storyId: storyId,
            reaction: reaction,
            commentId: commentId,
            echoId: echoId
        )
        
        triggerNotification(notification, to: targetUserId)
    }
    
    // Especial para menciones
    func sendMentionNotification(to userId: String, momentId: String? = nil, storyId: String? = nil) {
        sendInteractionNotification(type: .mention, to: userId, momentId: momentId, storyId: storyId)
    }
    
    // Especial para visitas (con agrupamiento por fecha manejado por ID)
    func updateVisitNotification(to userId: String, visitorUsername: String, visitorId: String, count: Int) {
        let dateString = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
        let notificationId = "visit_\(dateString)"
        
        let notification = Notification(
            id: notificationId,
            type: .profileVisit,
            senderId: visitorId,
            senderUsername: visitorUsername,
            timestamp: Date(),
            isPending: true,
            visitCount: count
        )
        
        saveNotification(notification, for: userId)
    }
    
    // MARK: - Actions
    
    func markAsRead(_ notification: Notification) {
        guard let userId = Auth.auth().currentUser?.uid, let notificationId = notification.id else { return }
        
        // ✅ OFFLINE-FIRST: Delegar a LocalPersistence (Optimistic UI + Sync)
        Task {
            await LocalPersistenceService.shared.markNotificationAsRead(notificationId: notificationId, userId: userId)
        }
        
        // Actualizar estado en memoria para reflejo inmediato en UI
        if let index = notifications.firstIndex(where: { $0.id == notification.id }) {
            notifications[index].isPending = false
            updateUnreadCount()
        }
    }
    
    func markAllAsRead() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        // ✅ Optimista: Limpiar estado local inmediatamente
        DispatchQueue.main.async {
            self.notifications.indices.forEach { self.notifications[$0].isPending = false }
            self.unreadCount = 0
            UIApplication.shared.applicationIconBadgeNumber = 0
        }
        
        // ✅ Real: Buscar TODAS las notificaciones no leídas en Firestore (no solo las cargadas)
        db.collection("users").document(userId).collection("notifications")
            .whereField("isPending", isEqualTo: true)
            .limit(to: 500) // Límite de seguridad para batch
            .getDocuments { [weak self] snapshot, error in
                guard let self = self else { return }
                
                Task { @MainActor in
                    guard let documents = snapshot?.documents, !documents.isEmpty else { return }
                    
                    let batch = self.db.batch()
                    
                    for doc in documents {
                        batch.updateData(["isPending": false], forDocument: doc.reference)
                    }
                    
                    batch.commit { error in
                        if let error = error {
                            print("❌ Error marking all as read: \(error)")
                        }
                    }
                }
            }

    }
    
    func deleteNotification(_ notification: Notification) {
        guard let userId = Auth.auth().currentUser?.uid, let notificationId = notification.id else { return }
        
        db.collection("users").document(userId).collection("notifications").document(notificationId).delete()
        
        DispatchQueue.main.async {
            self.notifications.removeAll { $0.id == notification.id }
            self.updateUnreadCount()
        }
    }
    
    // ✅ NUEVO: Eliminar notificación por criterios (para deshacer acciones)
    func removeNotification(type: NotificationType, senderId: String, recipientId: String, momentId: String? = nil, storyId: String? = nil, commentId: String? = nil, reaction: String? = nil) {
        
        var query = db.collection("users").document(recipientId).collection("notifications")
            .whereField("type", isEqualTo: type.rawValue)
            .whereField("senderId", isEqualTo: senderId)
        
        if let momentId = momentId {
            query = query.whereField("momentId", isEqualTo: momentId)
        }
        
        if let storyId = storyId {
            query = query.whereField("storyId", isEqualTo: storyId)
        }
        
        if let commentId = commentId {
            query = query.whereField("commentId", isEqualTo: commentId)
        }
        
        if let reaction = reaction {
            query = query.whereField("reaction", isEqualTo: reaction)
        }
        
        query.getDocuments { [weak self] snapshot, error in
            guard let self = self else { return }
            
            Task { @MainActor in
                guard let documents = snapshot?.documents else { return }
                
                let batch = self.db.batch()
                
                for doc in documents {
                    batch.deleteDocument(doc.reference)
                }
                
                batch.commit { error in
                    if error == nil {
                        print("✅ Notification removed successfully")
                    }
                }
            }
        }

    }
    
    // MARK: - Utility (One-time fetch)
    func fetchNotificationsOnce(userId: String, completion: @escaping (Result<[Notification], Error>) -> Void) {
        db.collection("users").document(userId).collection("notifications")
            .order(by: "timestamp", descending: true)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                let notifications = snapshot?.documents.compactMap { try? $0.data(as: Notification.self) } ?? []
                completion(.success(notifications))
            }
    }
}

// Modelos auxiliares necesarios para el servicio
extension NotificationService {
    struct User: Codable {
        let id: String
        let username: String
        let profileImagePath: String?
    }
}
