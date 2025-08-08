import Foundation
import UIKit
import FirebaseAuth
import FirebaseFirestore

class NotificationBadgeService: ObservableObject {
    static let shared = NotificationBadgeService()
    
    @Published var unreadNotificationsCount: Int = 0
    @Published var unreadMessagesCount: Int = 0
    
    private var notificationListener: ListenerRegistration?
    private var messageListener: ListenerRegistration?
    
    private init() {
        setupListeners()
    }
    
    // ✅ CONFIGURAR LISTENERS para ambos tipos de notificaciones
    func setupListeners() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        print("🔔 BadgeService: Configurando listeners para: \(userId)")
        
        // 1. Listener para notificaciones generales
        setupNotificationListener(userId: userId)
        
        // 2. Listener para mensajes no leídos
        setupMessageListener(userId: userId)
    }
    
    private func setupNotificationListener(userId: String) {
        notificationListener?.remove()
        
        notificationListener = Firestore.firestore()
            .collection("users")
            .document(userId)
            .collection("notifications")
            .whereField("isPending", isEqualTo: true)
            .addSnapshotListener { [weak self] snapshot, error in
                if let error = error {
                    print("❌ BadgeService: Error listener notificaciones: \(error)")
                    return
                }
                
                let count = snapshot?.documents.count ?? 0
                print("🔔 BadgeService: Notificaciones no leídas: \(count)")
                
                DispatchQueue.main.async {
                    self?.unreadNotificationsCount = count
                    self?.updateAppBadge()
                }
            }
    }
    
    // ✅ ACTUALIZAR setupMessageListener para contar CONVERSACIONES
    private func setupMessageListener(userId: String) {
        messageListener?.remove()
        
        messageListener = Firestore.firestore()
            .collection("conversations")
            .whereField("participants", arrayContains: userId)
            .addSnapshotListener { [weak self] snapshot, error in
                if let error = error {
                    return
                }
                
                guard let documents = snapshot?.documents else { return }
                
                var unreadConversations = 0
                let group = DispatchGroup()
                
                for document in documents {
                    group.enter()
                    let conversationId = document.documentID
                    
                    Firestore.firestore()
                        .collection("conversations")
                        .document(conversationId)
                        .collection("messages")
                        .whereField("isRead", isEqualTo: false)
                        .limit(to: 1)
                        .getDocuments { messagesSnapshot, messagesError in
                            defer { group.leave() }
                            
                            if messagesError != nil { return }
                            
                            let hasUnreadFromOthers = messagesSnapshot?.documents.contains { doc in
                                let data = doc.data()
                                let senderId = data["senderId"] as? String ?? ""
                                return senderId != userId
                            } ?? false
                            
                            if hasUnreadFromOthers {
                                unreadConversations += 1
                            }
                        }
                }
                
                group.notify(queue: .main) {
                    self?.unreadMessagesCount = unreadConversations
                    self?.updateAppBadge()
                }
            }
    }

    
    // ✅ ACTUALIZAR badge de la app con el total
    private func updateAppBadge() {
        let totalBadge = unreadNotificationsCount + unreadMessagesCount
        
        print("🔔 BadgeService: Actualizando badge app: \(totalBadge)")
        print("  - Notificaciones: \(unreadNotificationsCount)")
        print("  - Mensajes: \(unreadMessagesCount)")
        
        DispatchQueue.main.async {
            UIApplication.shared.applicationIconBadgeNumber = totalBadge
        }
    }
    
    // ✅ LIMPIAR notificaciones (llamado desde NotificationsView)
    func clearNotificationBadge() {
        print("🔔 BadgeService: Limpiando badge de notificaciones")
        unreadNotificationsCount = 0
        updateAppBadge()
    }
    
    // ✅ LIMPIAR mensajes (llamado desde MessagingView)
    func clearMessageBadge() {
        print("📨 BadgeService: Limpiando badge de mensajes")
        unreadMessagesCount = 0
        updateAppBadge()
    }
    
    // ✅ LIMPIAR badge completo de la app
    func clearAppBadge() {
        print("🧹 BadgeService: Limpiando badge completo de la app")
        DispatchQueue.main.async {
            UIApplication.shared.applicationIconBadgeNumber = 0
        }
    }
    
    // ✅ LIMPIAR listeners cuando el usuario se desloguee
    func cleanup() {
        print("🧹 BadgeService: Limpiando listeners")
        notificationListener?.remove()
        messageListener?.remove()
        notificationListener = nil
        messageListener = nil
        unreadNotificationsCount = 0
        unreadMessagesCount = 0
        clearAppBadge()
    }
    
    deinit {
        cleanup()
    }
}
