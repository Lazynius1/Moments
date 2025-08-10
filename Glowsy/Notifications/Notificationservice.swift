import Foundation
import FirebaseFirestore
import FirebaseAuth
import UserNotifications

// MARK: - ✨ Enhanced Notification Service (Adaptado a tu estructura)
class NotificationService: ObservableObject {
    static let shared = NotificationService()
    private let db = Firestore.firestore()
    
    @Published var unreadCount: Int = 0
    @Published var notifications: [Notification] = []
    
    private init() {
        // Solicitud de permisos de notificaciones pospuesta hasta interacción del usuario
        observeNotifications()
    }
    
    // MARK: - Permission & Setup
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
    }
    
    // MARK: - Real-time Notification Observation
    private func observeNotifications() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        db.collection("users").document(userId).collection("notifications")
            .order(by: "timestamp", descending: true)
            .limit(to: 50)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let documents = snapshot?.documents else { return }
                
                DispatchQueue.main.async {
                    self?.notifications = documents.compactMap { doc in
                        try? doc.data(as: Notification.self)
                    }
                    
                    self?.unreadCount = self?.notifications.filter { $0.isPending }.count ?? 0
                    
                    // Update app badge
                    UIApplication.shared.applicationIconBadgeNumber = self?.unreadCount ?? 0
                }
            }
    }
    
    // MARK: - Comment Notifications (Adaptadas a tu modelo)
    
    func sendCommentNotification(to userId: String, from fromUserId: String, momentId: String, content: String, momentAuthor: String = "") {
        guard userId != fromUserId else { return }
        
        fetchUserProfile(userId: fromUserId) { [weak self] fromUser in
            let notification = Notification(
                type: .comment,
                senderId: fromUserId,
                senderUsername: fromUser?.username ?? "Usuario",
                timestamp: Date(),
                isPending: true,
                momentId: momentId
            )
            
            self?.saveNotification(notification, for: userId)
            self?.sendPushNotification(notification, to: userId)
            
            // Enviar analítica si tienes AnalyticsService
            print("📊 Comment notification sent from \(fromUserId) to \(userId)")
        }
    }
    
    func sendCommentReplyNotification(to userId: String, from fromUserId: String, momentId: String, content: String, parentCommentId: String) {
        guard userId != fromUserId else { return }
        
        fetchUserProfile(userId: fromUserId) { [weak self] fromUser in
            let notification = Notification(
                type: .comment, // Usar el tipo existente
                senderId: fromUserId,
                senderUsername: fromUser?.username ?? "Usuario",
                timestamp: Date(),
                isPending: true,
                momentId: momentId
            )
            
            self?.saveNotification(notification, for: userId)
            self?.sendPushNotification(notification, to: userId)
            
            print("📊 Comment reply notification sent from \(fromUserId) to \(userId)")
        }
    }
    
    func sendCommentLikeNotification(to userId: String, from fromUserId: String, momentId: String, commentId: String) {
        guard userId != fromUserId else { return }
        
        fetchUserProfile(userId: fromUserId) { [weak self] fromUser in
            let notification = Notification(
                type: .like, // Usar el tipo existente para likes
                senderId: fromUserId,
                senderUsername: fromUser?.username ?? "Usuario",
                timestamp: Date(),
                isPending: true,
                momentId: momentId
            )
            
            self?.saveNotification(notification, for: userId)
            self?.sendPushNotification(notification, to: userId)
            
            print("📊 Comment like notification sent from \(fromUserId) to \(userId)")
        }
    }
    
    // ✅ FUNCIÓN UNIFICADA para menciones (cualquier contenido)
    func sendMentionNotification(to userId: String, from fromUserId: String, contentId: String, contentType: String, content: String = "") {
        guard userId != fromUserId else { return }
        
        fetchUserProfile(userId: fromUserId) { [weak self] fromUser in
            // ✅ Crear la notificación con los parámetros correctos desde el inicio
            let notification: Notification
            
            switch contentType {
            case "moment":
                notification = Notification(
                    type: .mention,
                    senderId: fromUserId,
                    senderUsername: fromUser?.username ?? "Usuario",
                    timestamp: Date(),
                    isPending: true,
                    momentId: contentId
                )
            case "story":
                notification = Notification(
                    type: .mention,
                    senderId: fromUserId,
                    senderUsername: fromUser?.username ?? "Usuario",
                    timestamp: Date(),
                    isPending: true,
                    storyId: contentId
                )
            case "comment":
                notification = Notification(
                    type: .mention,
                    senderId: fromUserId,
                    senderUsername: fromUser?.username ?? "Usuario",
                    timestamp: Date(),
                    isPending: true,
                    momentId: contentId // Los comentarios están en momentos
                )
            default:
                notification = Notification(
                    type: .mention,
                    senderId: fromUserId,
                    senderUsername: fromUser?.username ?? "Usuario",
                    timestamp: Date(),
                    isPending: true,
                    momentId: contentId // Por defecto
                )
            }
            
            self?.saveNotification(notification, for: userId)
            self?.sendPushNotification(notification, to: userId)
            
            print("📧 Mention notification sent from \(fromUserId) to \(userId) in \(contentType)")
        }
    }
    
    // MARK: - Batch Mention Notifications
    func sendBatchMentionNotifications(mentionedUserIds: [String], from fromUserId: String, contentId: String, contentType: String, content: String = "") {
        for userId in mentionedUserIds {
            sendMentionNotification(to: userId, from: fromUserId, contentId: contentId, contentType: contentType, content: content)
        }
    }
    
    // MARK: - Mark as Read
    func markAsRead(_ notification: Notification) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        db.collection("users").document(userId).collection("notifications").document(notification.id).updateData([
            "isPending": false,
            "readAt": Timestamp(date: Date())
        ])
        
        // Update local state
        if let index = notifications.firstIndex(where: { $0.id == notification.id }) {
            notifications[index].isPending = false
            unreadCount = notifications.filter { $0.isPending }.count
            UIApplication.shared.applicationIconBadgeNumber = unreadCount
        }
    }
    
    func markAllAsRead() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let batch = db.batch()
        let unreadNotifications = notifications.filter { $0.isPending }
        
        for notification in unreadNotifications {
            let ref = db.collection("users").document(userId).collection("notifications").document(notification.id)
            batch.updateData([
                "isPending": false,
                "readAt": Timestamp(date: Date())
            ], forDocument: ref)
        }
        
        batch.commit { [weak self] error in
            if error == nil {
                DispatchQueue.main.async {
                    self?.notifications = self?.notifications.map { notification in
                        var updated = notification
                        updated.isPending = false
                        return updated
                    } ?? []
                    
                    self?.unreadCount = 0
                    UIApplication.shared.applicationIconBadgeNumber = 0
                }
            }
        }
    }
    
    // MARK: - Private Helper Methods
    private func saveNotification(_ notification: Notification, for userId: String) {
        let data: [String: Any] = [
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
        
        db.collection("users").document(userId).collection("notifications").document(notification.id).setData(data)
    }
    
    private func sendPushNotification(_ notification: Notification, to userId: String) {
        // ✅ Cloud Functions maneja automáticamente las notificaciones push FCM
        // Solo guardamos en Firestore y Cloud Functions se encarga del resto
        print("📧 Notificación guardada en Firestore - Cloud Functions enviará FCM automáticamente")
    }
    
    private func fetchUserProfile(userId: String, completion: @escaping (User?) -> Void) {
        db.collection("users").document(userId).getDocument { snapshot, error in
            guard let data = snapshot?.data() else {
                completion(nil)
                return
            }
            
            // Crear un User temporal con los datos necesarios
            let user = User(
                id: userId,
                username: data["username"] as? String ?? "Usuario",
                email: data["email"] as? String ?? "",
                profileImagePath: data["profileImagePath"] as? String,
                isVerified: data["isVerified"] as? Bool ?? false,
                bio: data["bio"] as? String
            )
            completion(user)
        }
    }
    
    // MARK: - Notification Message Helpers
    private func getNotificationTitle(for notification: Notification) -> String {
        switch notification.type {
        case .comment:
            return "💬 Nuevo comentario"
        case .mention:
            return "📧 Te mencionaron"
        case .like:
            return "❤️ Le gustó tu contenido"
        case .newFollower:
            return "👥 Nuevo seguidor"
        case .followRequest:
            return "📩 Solicitud de seguimiento"
        case .mutualConnection:
            return "🤝 Conexión mutua"
        case .profileVisit:
            return "👁️ Visita al perfil"
        case .storyReaction:
            return "😊 Reacción a historia"
        }
    }
    
    private func getNotificationBody(for notification: Notification) -> String {
        switch notification.type {
        case .comment:
            return "\(notification.senderUsername) comentó en tu momento"
        case .mention:
            return "\(notification.senderUsername) te mencionó"
        case .like:
            return "\(notification.senderUsername) le dio me gusta a tu momento"
        case .newFollower:
            return "\(notification.senderUsername) comenzó a seguirte"
        case .followRequest:
            return "\(notification.senderUsername) quiere seguirte"
        case .mutualConnection:
            return "Ahora tienes una conexión mutua con \(notification.senderUsername)"
        case .profileVisit:
            return "\(notification.visitCount ?? 1) visitas a tu perfil"
        case .storyReaction:
            return "\(notification.senderUsername) reaccionó a tu historia"
        }
    }
    
    private func getNotificationData(for notification: Notification) -> [String: Any] {
        var data: [String: Any] = [
            "type": notification.type.rawValue,
            "senderId": notification.senderId,
            "notificationId": notification.id
        ]
        
        if let momentId = notification.momentId {
            data["momentId"] = momentId
        }
        
        if let storyId = notification.storyId {
            data["storyId"] = storyId
        }
        
        return data
    }
}

// MARK: - User Model Extension (temporal para compatibilidad)
extension NotificationService {
    struct User {
        let id: String
        let username: String
        let email: String
        let profileImagePath: String?
        let isVerified: Bool
        let bio: String?
    }
}

extension NotificationService {
    func sendModerationNotification(to userId: String, title: String, message: String, contentType: String, contentId: String) {
        // Implementar envío de notificación push
        // Esta función debería conectar con tu servicio de notificaciones push
        print("📱 Enviando notificación de moderación: \(title) - \(message)")
        
        // Guardar notificación en Firestore para mostrar en la app
        let notificationData: [String: Any] = [
            "title": title,
            "message": message,
            "type": "moderation",
            "contentType": contentType,
            "contentId": contentId,
            "timestamp": Timestamp(date: Date()),
            "read": false
        ]
        
        Firestore.firestore()
            .collection("users").document(userId)
            .collection("notifications")
            .addDocument(data: notificationData) { error in
                if let error = error {
                    print("❌ Error guardando notificación: \(error)")
                } else {
                    print("✅ Notificación de moderación guardada")
                }
            }
    }
}

extension NotificationService {
    // Solo enviar notificaciones a usuarios que pueden ver el contenido
    func sendNotificationToAudience(
        type: NotificationType,
        contentId: String,
        contentType: String,
        authorId: String,
        audience: ContentAudience,
        customUsers: [String]? = nil,
        customListId: String? = nil  // ⭐ NUEVO PARÁMETRO
    ) {
        // Obtener lista de usuarios que pueden ver el contenido
        let privacyService = PrivacyService()
        
        switch audience {
        case .everyone:
            // Notificar a todos los seguidores
            FirestoreService().fetchFollowers(userId: authorId) { result in
                if case .success(let followers) = result {
                    for follower in followers {
                        self.sendNotificationIfAllowed(
                            to: follower.id,
                            from: authorId,
                            type: type,
                            contentId: contentId
                        )
                    }
                }
            }
            
        case .connections:
            // Solo conexiones mutuas
            FirestoreService().fetchMutualConnections(userId: authorId) { result in
                if case .success(let connections) = result {
                    for connection in connections {
                        self.sendNotificationIfAllowed(
                            to: connection.id,
                            from: authorId,
                            type: type,
                            contentId: contentId
                        )
                    }
                }
            }
            
        case .bestFriends:
            // Solo mejores amigos
            FirestoreService().fetchUser(userId: authorId) { result in
                if case .success(let user) = result {
                    for friendId in user.bestFriends {
                        self.sendNotificationIfAllowed(
                            to: friendId,
                            from: authorId,
                            type: type,
                            contentId: contentId
                        )
                    }
                }
            }
            
        case .custom:
            // Lista personalizada simple
            if let customUsers = customUsers {
                for userId in customUsers {
                    self.sendNotificationIfAllowed(
                        to: userId,
                        from: authorId,
                        type: type,
                        contentId: contentId
                    )
                }
            }
            
        case .customList:
            // ⭐ NUEVO CASO: Lista personalizada reutilizable
            if let listId = customListId {
                privacyService.getCustomListViewers(
                    listId: listId,
                    ownerId: authorId
                ) { memberIds in
                    for memberId in memberIds {
                        self.sendNotificationIfAllowed(
                            to: memberId,
                            from: authorId,
                            type: type,
                            contentId: contentId
                        )
                    }
                }
            }
            
        case .onlyMe:
            // No enviar notificaciones
            break
        }
    }

    
    private func sendNotificationIfAllowed(
        to userId: String,
        from authorId: String,
        type: NotificationType,
        contentId: String
    ) {
        // Verificar preferencias de notificación del usuario
        FirestoreService().fetchUser(userId: userId) { result in
            if case .success(let user) = result,
               user.notificationPreferences?[type.rawValue] ?? true {
                // Enviar notificación
                // ... código de envío ...
            }
        }
    }
}
