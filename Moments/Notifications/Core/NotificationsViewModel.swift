import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import Kingfisher
import Combine

@MainActor
class NotificationsViewModel: ObservableObject {
    @Published var notifications: [Notification] = []
    @Published var groupedByDate: [String: [NotificationGroup]] = [:]
    @Published var dateKeys: [String] = []
    @Published var groupedNotifications: [NotificationGroup] = []
    @Published var selectedTab: NotificationsView.NotificationTab = .all {
        didSet { groupNotifications() }
    }
    @Published var isLoading = false
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var pendingRequestsCount = 0
    @Published var hasUnreadNotifications = false
    @Published var canLoadMore = true
    @Published var isLoadingMore = false
    @Published var pendingDeletion: NotificationService.PendingNotificationDeletion?
    
    private let firestoreService = FirestoreService()
    private let notificationService = NotificationService.shared
    private var cancellables = Set<AnyCancellable>()
    private var userProfileImageCache: [String: String] = [:]

    init() {
        setupSubscribers()
    }

    private func setupSubscribers() {
        notificationService.$notifications
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newNotifications in
                self?.notifications = newNotifications
                self?.groupNotifications()
                self?.updatePendingCounts()
            }
            .store(in: &cancellables)
            
        notificationService.$isLoading
            .receive(on: DispatchQueue.main)
            .assign(to: \.isLoading, on: self)
            .store(in: &cancellables)

        notificationService.$isLoadingMore
            .receive(on: DispatchQueue.main)
            .assign(to: \.isLoadingMore, on: self)
            .store(in: &cancellables)

        notificationService.$canLoadMore
            .receive(on: DispatchQueue.main)
            .assign(to: \.canLoadMore, on: self)
            .store(in: &cancellables)

        notificationService.$pendingDeletion
            .receive(on: DispatchQueue.main)
            .assign(to: \.pendingDeletion, on: self)
            .store(in: &cancellables)
    }

    func refreshNotifications() async {
        notificationService.startObserving()
    }

    func loadMoreNotifications() {
        notificationService.loadMore()
    }

    private func updatePendingCounts() {
        self.hasUnreadNotifications = notificationService.unreadCount > 0
        self.pendingRequestsCount = notifications.filter {
            $0.type == .followRequest && $0.isPending
        }.count
    }

    func markAsRead(_ notification: Notification) {
        notificationService.markAsRead(notification)
    }

    func markAllAsRead() {
        notificationService.markAllAsRead()
    }

    // ✅ Agrupación eficiente por periodos de tiempo
    private func groupNotifications() {
        // ✅ 1. Filtrar notificaciones según la pestaña seleccionada
        let filtered = notifications.filter { notification in
            switch selectedTab {
            case .all:
                return true
            case .reactions:
                return notification.type == .reaction
            case .follows:
                return notification.type == .newFollower || notification.type == .mutualConnection || notification.type == .requestAccepted
            case .comments:
                return notification.type == .comment || notification.type == .like || isMomentOrCommentMention(notification)
            case .storyReactions:
                return notification.type == .storyReaction || notification.type == .storyChainContinued || isStoryMention(notification)
            case .requests:
                return notification.type == .followRequest
            }
        }
        
        // ✅ 2. Agrupar las notificaciones filtradas
        var groupedDict: [String: [Notification]] = [:]
        
        for notification in filtered {
            let key: String
            if notification.type == .newFollower || notification.type == .mutualConnection {
                // Agrupar seguidores nuevos y conexiones mutuas recientes
                // en una fila "X y N más", separados por sección temporal.
                // Offline-safe: opera sobre la caché local.
                key = "\(notification.type.rawValue)_agg_\(getSectionKey(for: notification.timestamp))"
            } else if isPerActorSocialNotification(notification.type) {
                // requestAccepted / followRequest: una fila por sender (evento o acción individual)
                key = "\(notification.type.rawValue)_\(notification.senderId)"
            } else if notification.type == .storyChainContinued {
                // Agrupar por cadena: el evento trae chainId, no commentId/storyId.
                let chain = notification.chainId ?? notification.storyId ?? "general"
                key = "storyChainContinued_\(chain)"
            } else {
                let contentId = notification.commentId ?? notification.storyId ?? notification.momentId ?? "general"
                let context = notification.mentionContext ?? inferredMentionContext(notification)
                key = "\(notification.type.rawValue)_\(context)_\(contentId)"
            }
            
            if groupedDict[key] == nil {
                groupedDict[key] = []
            }
            groupedDict[key]?.append(notification)
        }
        
        let groups = groupedDict.map { key, notifications -> NotificationGroup in
            let sorted = notifications.sorted { $0.timestamp > $1.timestamp }
            // Seguidores / mutuas agregados: contar una sola vez por persona (evita inflar "y N más" con duplicados legacy)
            if key.contains("_agg_") {
                var seenSenders = Set<String>()
                let dedupedBySender = sorted.filter { seenSenders.insert($0.senderId).inserted }
                return NotificationGroup(id: key, notifications: dedupedBySender)
            }
            return NotificationGroup(id: key, notifications: sorted)
        }
        
        var tempSections: [String: [NotificationGroup]] = [:]
        for group in groups {
            let section = getSectionKey(for: group.notifications.first!.timestamp)
            if tempSections[section] == nil { tempSections[section] = [] }
            tempSections[section]?.append(group)
        }
        
        for key in tempSections.keys {
            tempSections[key]?.sort { $0.notifications.first!.timestamp > $1.notifications.first!.timestamp }
        }
        
        self.groupedByDate = tempSections
        self.dateKeys = ["New", "This Week", "This Month", "Earlier"].filter { tempSections[$0] != nil }
        self.groupedNotifications = groups.sorted { $0.notifications.first!.timestamp > $1.notifications.first!.timestamp }
        
        // ✅ #5: Batch preload sender profiles to avoid N+1 queries
        preloadSenderProfiles(for: filtered)
    }
    
    // ✅ #5: Pre-cargar perfiles de senders en batch (evita N+1 queries por fila)
    private func preloadSenderProfiles(for notifications: [Notification]) {
        let senderIds = Set(notifications.map { $0.senderId }.filter { !$0.isEmpty })
        let uncachedIds = senderIds.filter { userProfileImageCache[$0] == nil }
        
        guard !uncachedIds.isEmpty else { return }
        
        // Firestore 'in' queries support max 30 items
        let chunks = Array(uncachedIds).chunked(into: 30)
        
        for chunk in chunks {
            Firestore.firestore().collection("users")
                .whereField(FieldPath.documentID(), in: chunk)
                .getDocuments { [weak self] snapshot, error in
                    guard let self = self, let docs = snapshot?.documents else { return }
                    
                    DispatchQueue.main.async {
                        for doc in docs {
                            let data = doc.data()
                            if let imagePath = data["profileImagePath"] as? String, !imagePath.isEmpty {
                                self.userProfileImageCache[doc.documentID] = imagePath
                            }
                        }
                    }
                }
        }
    }

    private func isStoryMention(_ notification: Notification) -> Bool {
        notification.type == .mention && (notification.mentionContext == "story" || notification.storyId != nil)
    }

    private func isMomentOrCommentMention(_ notification: Notification) -> Bool {
        notification.type == .mention && !isStoryMention(notification)
    }

    private func inferredMentionContext(_ notification: Notification) -> String {
        guard notification.type == .mention else { return "default" }
        if notification.storyId != nil { return "story" }
        if notification.commentId != nil { return "comment" }
        if notification.momentId != nil { return "moment" }
        return "mention"
    }

    private func getSectionKey(for date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        if calendar.isDateInToday(date) || calendar.isDateInYesterday(date) {
            return "New"
        } else if let weekAgo = calendar.date(byAdding: .day, value: -7, to: now), date > weekAgo {
            return "This Week"
        } else if let monthAgo = calendar.date(byAdding: .month, value: -1, to: now), date > monthAgo {
            return "This Month"
        } else {
            return "Earlier"
        }
    }

    func deleteNotification(_ notification: Notification) {
        notificationService.deleteNotification(notification)
    }

    func deleteNotificationGroup(_ group: NotificationGroup) {
        notificationService.stageDeletion(group.notifications)
    }

    func undoPendingDeletion() {
        notificationService.undoPendingDeletion()
    }

    func commitPendingDeletion() {
        notificationService.commitPendingDeletion()
    }

    // ✅ Acciones de solicitudes de seguimiento simplificadas (OFFLINE AWARE)
    func acceptFollowRequest(group: NotificationGroup) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        guard let notification = group.notifications.first(where: { $0.type == .followRequest }),
              let notificationId = notification.id else { return }
        // 1. Delegar a LocalPersistence (Optimistic UI + Sync)
        Task {
            await LocalPersistenceService.shared.acceptFollowRequest(
                notificationId: notificationId,
                senderId: notification.senderId,
                recipientId: userId
            )
            
            // 2. Actualizar estado local del view model para reflejar cambio inmediato
            DispatchQueue.main.async {
                if let index = self.notifications.firstIndex(where: { $0.id == notificationId }) {
                    self.notifications[index].isPending = false
                    self.groupNotifications() // Reagrupar para actualizar UI
                    self.updatePendingCounts()
                }
            }
        }
    }

    func rejectFollowRequest(group: NotificationGroup) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        for notification in group.notifications where notification.type == .followRequest {
            guard let notificationId = notification.id else { continue }
            
            // 1. Delegar a LocalPersistence (Optimistic UI + Sync)
            Task {
                await LocalPersistenceService.shared.rejectFollowRequest(
                    notificationId: notificationId,
                    senderId: notification.senderId,
                    recipientId: userId
                )
                
                // 2. Actualizar estado local del view model para reflejar cambio inmediato
                DispatchQueue.main.async {
                    self.notifications.removeAll { $0.id == notificationId }
                    self.groupNotifications() // Reagrupar para actualizar UI
                    self.updatePendingCounts()
                }
            }
        }
    }

    func checkIfFollowing(currentUserId: String, targetUserId: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        // ✅ OFFLINE-FIRST: Verificar en caché local
        let isFollowingCached = LocalPersistenceService.shared.isFollowing(targetUserId: targetUserId)
        completion(.success(isFollowingCached))
        
        // 🔄 Actualizar en background para consistencia estricta
        firestoreService.isFollowing(currentUserId: currentUserId, targetUserId: targetUserId) { isFollowingNetwork in
            // Si el estado de red difiere del caché local, notificamos de nuevo
            if isFollowingNetwork != isFollowingCached {
                completion(.success(isFollowingNetwork))
            }
        }
    }

    func followUser(currentUserId: String, targetUserId: String, completion: @escaping (Error?) -> Void) {
        firestoreService.followUser(currentUserId: currentUserId, targetUserId: targetUserId) { error in
            DispatchQueue.main.async { completion(error) }
        }
    }

    func unfollowUser(currentUserId: String, targetUserId: String, completion: @escaping (Error?) -> Void) {
        firestoreService.unfollowUser(currentUserId: currentUserId, targetUserId: targetUserId) { error in
            DispatchQueue.main.async { completion(error) }
        }
    }

    func cancelFollowRequest(currentUserId: String, targetUserId: String, completion: @escaping (Error?) -> Void) {
        firestoreService.cancelFollowRequest(currentUserId: currentUserId, targetUserId: targetUserId) { error in
            DispatchQueue.main.async { completion(error) }
        }
    }
    
    func getProfileImagePath(for userId: String) -> String? {
        return userProfileImageCache[userId]
    }

    func updateProfileImageCache(for userId: String, imagePath: String?) {
        userProfileImageCache[userId] = imagePath
    }
}
