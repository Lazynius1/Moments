import Foundation
import UIKit
import WidgetKit
import FirebaseAuth
import FirebaseFirestore

class NotificationBadgeService: ObservableObject {
    static let shared = NotificationBadgeService()
    
    @Published var unreadNotificationsCount: Int = 0
    @Published var unreadMessagesCount: Int = 0
    @Published var unreadEchoesCount: Int = 0   // ✅ TRACKING: Echoes
    @Published var unreadTagsCount: Int = 0     // ✅ TRACKING: Tags
    
    // ✅ UserDefaults compartido para el widget (configura este App Group en Xcode)
    // Asegúrate de crear/activar el App Group "group.com.glowsyapp"
    private let widgetUserDefaults = UserDefaults(suiteName: "group.com.glowsyapp")
    
    private var notificationListener: ListenerRegistration?
    private var messageListener: ListenerRegistration?
    private var widgetReloadWorkItem: DispatchWorkItem?
    
    private init() {
        setupListeners()
    }
    
    // ✅ CONFIGURAR LISTENERS para ambos tipos de notificaciones
    func setupListeners() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        // 1. Listener para notificaciones generales (incluye Echoes y Tags)
        setupNotificationListener(userId: userId)
        
        // 2. Listener para mensajes no leídos
        setupMessageListener(userId: userId)
    }
    
    // ✅ NUEVO: Refresco manual (para background updates desde AppDelegate)
    func refreshAllCounts(completion: (() -> Void)? = nil) {
        guard let userId = Auth.auth().currentUser?.uid else { 
            completion?()
            return 
        }
        
        let group = DispatchGroup()
        
        // Refrescar Notificaciones/Echoes/Tags
        group.enter()
        Firestore.firestore()
            .collection("users")
            .document(userId)
            .collection("notifications")
            .whereField("isPending", isEqualTo: true)
            .getDocuments { [weak self] snapshot, _ in
                defer { group.leave() }
                if let docs = snapshot?.documents {
                    self?.processNotificationDocuments(docs)
                }
            }
        
        // Refrescar Mensajes
        group.enter()
        Firestore.firestore()
            .collection("conversations")
            .whereField("participants", arrayContains: userId)
            .getDocuments { [weak self] snapshot, _ in
                defer { group.leave() }
                guard let self = self, let docs = snapshot?.documents else { return }
                
                let count = self.countUnreadMessages(in: docs, userId: userId)
                DispatchQueue.main.async {
                    self.unreadMessagesCount = count
                    self.widgetUserDefaults?.set(count, forKey: "widget_unread_messages")
                }
            }
        
        group.notify(queue: .main) {
            self.updateAppBadge()
            self.scheduleWidgetReload()
            completion?()
        }
    }
    
    private func setupNotificationListener(userId: String) {
        notificationListener?.remove()
        notificationListener = Firestore.firestore()
            .collection("users")
            .document(userId)
            .collection("notifications")
            .whereField("isPending", isEqualTo: true)
            .addSnapshotListener { [weak self] snapshot, error in
                if let docs = snapshot?.documents {
                    self?.processNotificationDocuments(docs)
                }
            }
    }
    
    private func processNotificationDocuments(_ documents: [QueryDocumentSnapshot]) {
        let totalCount = documents.count
        let echoes = documents.filter { ($0.data()["type"] as? String) == "echoSuggestion" }.count
        let tags = documents.filter { ($0.data()["type"] as? String) == "photoTag" }.count
        
        DispatchQueue.main.async {
            self.unreadNotificationsCount = totalCount
            self.unreadEchoesCount = echoes
            self.unreadTagsCount = tags
            
            self.widgetUserDefaults?.set(totalCount, forKey: "widget_unread_notifications")
            self.widgetUserDefaults?.set(echoes, forKey: "widget_unread_echoes")
            self.widgetUserDefaults?.set(tags, forKey: "widget_unread_tags")
            
            self.updateAppBadge()
            self.scheduleWidgetReload()
        }
    }
    
    private func setupMessageListener(userId: String) {
        messageListener?.remove()
        messageListener = Firestore.firestore()
            .collection("conversations")
            .whereField("participants", arrayContains: userId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self, let docs = snapshot?.documents else { return }
                
                let count = self.countUnreadMessages(in: docs, userId: userId)
                DispatchQueue.main.async {
                    self.unreadMessagesCount = count
                    self.widgetUserDefaults?.set(count, forKey: "widget_unread_messages")
                    self.updateAppBadge()
                    self.scheduleWidgetReload()
                }
            }
    }
    
    private func countUnreadMessages(in documents: [QueryDocumentSnapshot], userId: String) -> Int {
        var unreadConversations = 0
        
        for document in documents {
            let data = document.data()
            let readStatus = data["readStatus"] as? [String: Bool] ?? [:]
            
            // Si el estado de lectura para el usuario actual es 'false', significa que hay mensajes nuevos
            if let isRead = readStatus[userId], !isRead {
                unreadConversations += 1
            }
        }
        
        return unreadConversations
    }

    
    // ✅ ACTUALIZAR badge de la app con el total
    private func updateAppBadge() {
        let totalBadge = unreadNotificationsCount + unreadMessagesCount
        
        DispatchQueue.main.async {
            // Método clásico (App Icon)
            UIApplication.shared.applicationIconBadgeNumber = totalBadge
            
            // Método moderno para iOS 16+ (Sincronización más fiable)
            if #available(iOS 16.0, *) {
                UNUserNotificationCenter.current().setBadgeCount(totalBadge)
            }
        }
    }
    
    // ✅ LIMPIAR notificaciones (llamado desde NotificationsView)
    func clearNotificationBadge() {
        unreadNotificationsCount = 0
        unreadEchoesCount = 0
        unreadTagsCount = 0
        widgetUserDefaults?.set(0, forKey: "widget_unread_notifications")
        widgetUserDefaults?.set(0, forKey: "widget_unread_echoes")
        widgetUserDefaults?.set(0, forKey: "widget_unread_tags")
        updateAppBadge()
        scheduleWidgetReload()
    }
    
    // ✅ LIMPIAR mensajes (llamado desde MessagingView)
    func clearMessageBadge() {
        unreadMessagesCount = 0
        widgetUserDefaults?.set(0, forKey: "widget_unread_messages")
        updateAppBadge()
        scheduleWidgetReload()
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
        
        // Resetear contadores locales
        unreadNotificationsCount = 0
        unreadMessagesCount = 0
        unreadEchoesCount = 0
        unreadTagsCount = 0
        
        // Resetear UserDefaults para el widget
        widgetUserDefaults?.set(0, forKey: "widget_unread_notifications")
        widgetUserDefaults?.set(0, forKey: "widget_unread_messages")
        widgetUserDefaults?.set(0, forKey: "widget_unread_echoes")
        widgetUserDefaults?.set(0, forKey: "widget_unread_tags")
        
        // Limpiar el badge de la app
        clearAppBadge()
        
        // Recargar widget para reflejar estado vacío/login
        scheduleWidgetReload()
    }
    
    deinit {
        cleanup()
    }
    
    private func scheduleWidgetReload(delay: TimeInterval = 2.0) {
        widgetReloadWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            WidgetCenter.shared.reloadTimelines(ofKind: "GlowsyWidgetExtension")
        }
        widgetReloadWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
}
