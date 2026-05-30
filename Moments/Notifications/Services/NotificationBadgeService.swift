import Foundation
import UIKit
import WidgetKit
import Combine
import FirebaseAuth
import FirebaseFirestore

class NotificationBadgeService: ObservableObject {
    static let shared = NotificationBadgeService()
    
    @Published var unreadNotificationsCount: Int = 0
    @Published var unreadMessagesCount: Int = 0
    @Published var unreadEchoesCount: Int = 0
    @Published var unreadTagsCount: Int = 0
    
    private let widgetUserDefaults = UserDefaults(suiteName: "group.com.glowsyapp")
    
    private var messageListener: ListenerRegistration?
    private var widgetReloadWorkItem: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()
    private var currentUserId: String?
    
    private init() {
        setupListeners()
    }
    
    // ✅ CONFIGURAR LISTENERS — Notificaciones via Combine, mensajes via Firestore
    func setupListeners() {
        guard let userId = Auth.auth().currentUser?.uid else {
            cleanup()
            return
        }
        
        if currentUserId == userId, messageListener != nil, !cancellables.isEmpty {
            return
        }
        
        if currentUserId != userId {
            messageListener?.remove()
            messageListener = nil
            cancellables.removeAll()
            currentUserId = userId
        }
        
        // 1. ✅ OPTIMIZADO: Suscribirse a NotificationService.shared en vez de listener propio
        // Esto elimina el listener duplicado de Firestore (-50% reads en tiempo real)
        if cancellables.isEmpty {
            setupNotificationSubscription()
        }
        
        // 2. Listener para mensajes no leídos (colección diferente, necesita su propio listener)
        setupMessageListener(userId: userId)
    }
    
    // ✅ Suscripción via Combine al singleton de NotificationService
    private func setupNotificationSubscription() {
        Task { @MainActor in
            NotificationService.shared.$notifications
                .receive(on: DispatchQueue.main)
                .sink { [weak self] notifications in
                    guard let self = self else { return }
                    
                    let pendingNotifications = notifications.filter { $0.isPending }
                    let totalCount = pendingNotifications.count
                    let echoes = pendingNotifications.filter { $0.type == .echoSuggestion }.count
                    let tags = pendingNotifications.filter { $0.type == .photoTag }.count
                    
                    self.unreadNotificationsCount = totalCount
                    self.unreadEchoesCount = echoes
                    self.unreadTagsCount = tags
                    
                    self.widgetUserDefaults?.set(totalCount, forKey: "widget_unread_notifications")
                    self.widgetUserDefaults?.set(echoes, forKey: "widget_unread_echoes")
                    self.widgetUserDefaults?.set(tags, forKey: "widget_unread_tags")
                    
                    self.updateAppBadge()
                    self.scheduleWidgetReload()
                }
                .store(in: &cancellables)
        }
    }
    
    // ✅ Refresco manual (para background updates desde AppDelegate)
    func refreshAllCounts(completion: (() -> Void)? = nil) {
        guard let userId = Auth.auth().currentUser?.uid else { 
            completion?()
            return 
        }
        
        let group = DispatchGroup()
        
        // Refrescar Notificaciones via NotificationService
        group.enter()
        Task { @MainActor in
            NotificationService.shared.fetchNotificationsOnce(userId: userId) { [weak self] result in
                defer { group.leave() }
                if case .success(let notifications) = result {
                    let pending = notifications.filter { $0.isPending }
                    DispatchQueue.main.async {
                        self?.unreadNotificationsCount = pending.count
                        self?.unreadEchoesCount = pending.filter { $0.type == .echoSuggestion }.count
                        self?.unreadTagsCount = pending.filter { $0.type == .photoTag }.count
                        self?.widgetUserDefaults?.set(pending.count, forKey: "widget_unread_notifications")
                        self?.widgetUserDefaults?.set(pending.filter { $0.type == .echoSuggestion }.count, forKey: "widget_unread_echoes")
                        self?.widgetUserDefaults?.set(pending.filter { $0.type == .photoTag }.count, forKey: "widget_unread_tags")
                    }
                }
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
            if let isRead = readStatus[userId], !isRead {
                unreadConversations += 1
            }
        }
        return unreadConversations
    }
    
    private func updateAppBadge() {
        let totalBadge = unreadNotificationsCount + unreadMessagesCount
        
        DispatchQueue.main.async {
            UNUserNotificationCenter.current().setBadgeCount(totalBadge) { _ in }
        }
    }
    
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
    
    func clearMessageBadge() {
        unreadMessagesCount = 0
        widgetUserDefaults?.set(0, forKey: "widget_unread_messages")
        updateAppBadge()
        scheduleWidgetReload()
    }
    
    func clearAppBadge() {
        DispatchQueue.main.async {
            UNUserNotificationCenter.current().setBadgeCount(0) { _ in }
        }
    }
    
    func cleanup() {
        messageListener?.remove()
        messageListener = nil
        cancellables.removeAll()
        currentUserId = nil
        
        unreadNotificationsCount = 0
        unreadMessagesCount = 0
        unreadEchoesCount = 0
        unreadTagsCount = 0
        
        widgetUserDefaults?.set(0, forKey: "widget_unread_notifications")
        widgetUserDefaults?.set(0, forKey: "widget_unread_messages")
        widgetUserDefaults?.set(0, forKey: "widget_unread_echoes")
        widgetUserDefaults?.set(0, forKey: "widget_unread_tags")
        
        clearAppBadge()
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
