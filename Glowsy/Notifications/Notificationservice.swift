import Foundation
import FirebaseFirestore
import FirebaseAuth
import UserNotifications

// MARK: - ✨ Glowsy Notification Service (Unified Source of Truth)
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
        
        listener = query.addSnapshotListener { [weak self] snapshot, error in
            guard let self = self, let documents = snapshot?.documents else { 
                self?.isLoading = false
                return 
            }
            
            self.lastDocument = documents.last
            self.canLoadMore = documents.count >= self.pageSize
            
            DispatchQueue.main.async {
                self.notifications = documents.compactMap { doc in
                    try? doc.data(as: Notification.self)
                }
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
                guard let self = self, let documents = snapshot?.documents else {
                    self?.isLoadingMore = false
                    return
                }
                
                self.lastDocument = documents.last
                self.canLoadMore = documents.count >= self.pageSize
                
                let newNotifications = documents.compactMap { doc in
                    try? doc.data(as: Notification.self)
                }
                
                DispatchQueue.main.async {
                    self.notifications.append(contentsOf: newNotifications)
                    self.isLoadingMore = false
                }
            }
    }
    
    private func updateUnreadCount() {
        self.unreadCount = notifications.filter { $0.isPending }.count
        UIApplication.shared.applicationIconBadgeNumber = self.unreadCount
    }
    
    // MARK: - Notification Creation Engine (Internal)
    
    private func triggerNotification(_ notification: Notification, to targetUserId: String) {
        // 1. Evitar auto-notificaciones
        guard targetUserId != Auth.auth().currentUser?.uid else { return }
        
        // 2. Verificar preferencias del destinatario
        db.collection("users").document(targetUserId).getDocument { [weak self] snapshot, error in
            if let data = snapshot?.data(),
               let preferences = data["notificationPreferences"] as? [String: Bool] {
                let isAllowed = preferences[notification.type.rawValue] ?? true
                if !isAllowed { return }
            }
            
            // 3. Guardar en Firestore (Cloud Functions se encarga del Push)
            self?.saveNotification(notification, for: targetUserId)
        }
    }
    
    private func saveNotification(_ notification: Notification, for userId: String) {
        guard let notificationId = notification.id else { return }
        do {
            try db.collection("users").document(userId).collection("notifications").document(notificationId).setData(from: notification)
        } catch {
            print("❌ Error saving notification: \(error)")
        }
    }
    
    // MARK: - Public Sending Methods
    
    func sendInteractionNotification(type: NotificationType, to targetUserId: String, momentId: String? = nil, storyId: String? = nil, commentId: String? = nil, reaction: String? = nil, senderUsername: String? = nil) {
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
            commentId: commentId
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
        
        db.collection("users").document(userId).collection("notifications").document(notificationId).updateData([
            "isPending": false
        ])
        
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
                guard let self = self, let documents = snapshot?.documents, !documents.isEmpty else { return }
                
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
            guard let documents = snapshot?.documents else { return }
            
            let batch = self?.db.batch()
            
            for doc in documents {
                batch?.deleteDocument(doc.reference)
            }
            
            batch?.commit { error in
                if error == nil {
                    print("✅ Notification removed successfully")
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
