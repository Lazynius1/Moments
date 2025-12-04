import Foundation
import UIKit
import WidgetKit
import FirebaseAuth
import FirebaseFirestore

class NotificationBadgeService: ObservableObject {
    static let shared = NotificationBadgeService()
    
    @Published var unreadNotificationsCount: Int = 0
    @Published var unreadMessagesCount: Int = 0
    
    // ✅ UserDefaults compartido para el widget (configura este App Group en Xcode)
    // Asegúrate de crear/activar el App Group "group.com.glowsyapp"
    private let widgetUserDefaults = UserDefaults(suiteName: "group.com.glowsyapp")
    
    private var notificationListener: ListenerRegistration?
    private var messageListener: ListenerRegistration?
    
    private init() {
        setupListeners()
    }
    
    // ✅ CONFIGURAR LISTENERS para ambos tipos de notificaciones
    func setupListeners() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        
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
                    return
                }
                
                let count = snapshot?.documents.count ?? 0
                
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.unreadNotificationsCount = count
                    // 🔄 Sincronizar con widget
                    self.widgetUserDefaults?.set(count, forKey: "widget_unread_notifications")
                    self.updateAppBadge()
                    WidgetCenter.shared.reloadTimelines(ofKind: "GlowsyWidgetExtension")
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
                    guard let self = self else { return }
                    self.unreadMessagesCount = unreadConversations
                    
                    // 🔄 Sincronizar con widget
                    self.widgetUserDefaults?.set(unreadConversations, forKey: "widget_unread_messages")
                    
                    self.updateAppBadge()
                    WidgetCenter.shared.reloadTimelines(ofKind: "GlowsyWidgetExtension")
                }
            }
    }

    
    // ✅ ACTUALIZAR badge de la app con el total
    private func updateAppBadge() {
        let totalBadge = unreadNotificationsCount + unreadMessagesCount
        
        
        DispatchQueue.main.async {
            UIApplication.shared.applicationIconBadgeNumber = totalBadge
        }
    }
    
    // ✅ LIMPIAR notificaciones (llamado desde NotificationsView)
    func clearNotificationBadge() {
        unreadNotificationsCount = 0
        widgetUserDefaults?.set(0, forKey: "widget_unread_notifications")
        updateAppBadge()
        WidgetCenter.shared.reloadTimelines(ofKind: "GlowsyWidgetExtension")
    }
    
    // ✅ LIMPIAR mensajes (llamado desde MessagingView)
    func clearMessageBadge() {
        unreadMessagesCount = 0
        widgetUserDefaults?.set(0, forKey: "widget_unread_messages")
        updateAppBadge()
        WidgetCenter.shared.reloadTimelines(ofKind: "GlowsyWidgetExtension")
    }
    
    // ✅ LIMPIAR badge completo de la app
    func clearAppBadge() {
        DispatchQueue.main.async {
            UIApplication.shared.applicationIconBadgeNumber = 0
        }
    }
    
    // ✅ LIMPIAR listeners cuando el usuario se desloguee
    func cleanup() {
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
