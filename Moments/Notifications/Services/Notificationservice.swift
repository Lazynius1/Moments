import Foundation
import FirebaseFirestore
import FirebaseAuth
import UserNotifications

// MARK: - ✨ Moments Notification Service (Unified Source of Truth)
@MainActor
class NotificationService: ObservableObject {
    static let shared = NotificationService()
    private let db = Firestore.firestore()
    
    @Published var unreadCount: Int = 0
    @Published var notifications: [Notification] = []
    @Published var isLoading: Bool = false
    @Published var isLoadingMore: Bool = false
    @Published var canLoadMore: Bool = true
    @Published var pendingDeletion: PendingNotificationDeletion?

    private var listener: ListenerRegistration?
    private var lastDocument: DocumentSnapshot?
    private let pageSize = 20
    private var profileCache: [String: User] = [:]
    private var pendingDeletionTask: Task<Void, Never>?
    private var hiddenPendingDeletionIds: Set<String> = []
    private let deletionUndoWindow: TimeInterval = 3

    struct PendingNotificationDeletion: Equatable {
        let id = UUID()
        let notifications: [Notification]

        static func == (lhs: PendingNotificationDeletion, rhs: PendingNotificationDeletion) -> Bool {
            lhs.id == rhs.id
        }
    }
    
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
            self.notifications = visibleNotifications(from: cached)
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
                
                let fetched = documents.compactMap { doc in
                    self.decodeNotificationDocument(doc)
                }
                self.notifications = self.visibleNotifications(from: fetched)
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
                    
                    let newNotifications = self.visibleNotifications(from: documents.compactMap { doc in
                        self.decodeNotificationDocument(doc)
                    })
                    
                    self.notifications.append(contentsOf: newNotifications)
                    self.isLoadingMore = false
                }
            }

    }
    
    private func updateUnreadCount() {
        self.unreadCount = notifications.filter { $0.isPending }.count
        UNUserNotificationCenter.current().setBadgeCount(self.unreadCount) { _ in }
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
    
    // MARK: - Notification Creation (Simplified — Server handles DND/Mute/Filtering)
    // ⚠️ NOTE: Client-side notification writes should eventually migrate to Cloud Functions.
    // The server pipeline (index.js) already handles DND, mute settings, and all filtering.
    // Client writes are kept for mentions, photo tags, and profile visits only.
    
    private func saveNotification(_ notification: Notification, for userId: String) {
        // Evitar auto-notificaciones
        guard userId != Auth.auth().currentUser?.uid else { return }
        
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
            LocalPersistenceService.shared.saveNotifications([notificationToSave])
        } catch {
            print("❌ Error saving notification: \(error)")
        }
    }
    
    // MARK: - Public Sending Methods
    
    func sendInteractionNotification(
        type: NotificationType,
        to targetUserId: String,
        notificationId: String? = nil,
        momentId: String? = nil,
        storyId: String? = nil,
        storyAuthorId: String? = nil,
        commentId: String? = nil,
        reaction: String? = nil,
        senderUsername: String? = nil,
        echoId: String? = nil,
        mentionContext: String? = nil,
        targetAuthorId: String? = nil,
        targetAuthorUsername: String? = nil
    ) {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        let username = senderUsername ?? UserDefaults.standard.string(forKey: "current_username") ?? "Alguien"
        
        let notification = Notification(
            id: notificationId,
            type: type,
            senderId: currentUserId,
            senderUsername: username,
            timestamp: Date(),
            isPending: true,
            momentId: momentId,
            storyId: storyId,
            storyAuthorId: storyAuthorId,
            mentionContext: mentionContext,
            targetAuthorId: targetAuthorId,
            targetAuthorUsername: targetAuthorUsername,
            reaction: reaction,
            commentId: commentId,
            echoId: echoId
        )
        
        saveNotification(notification, for: targetUserId)
    }
    
    func sendMentionNotification(to userId: String, momentId: String? = nil, storyId: String? = nil) {
        let currentUserId = Auth.auth().currentUser?.uid
        let context = storyId != nil ? "story" : (momentId != nil ? "moment" : nil)
        sendInteractionNotification(
            type: .mention,
            to: userId,
            momentId: momentId,
            storyId: storyId,
            storyAuthorId: storyId != nil ? currentUserId : nil,
            mentionContext: context,
            targetAuthorId: storyId != nil ? currentUserId : nil
        )
    }

    func sendStoryMentionNotification(to userId: String, storyId: String, storyAuthorId: String) {
        sendInteractionNotification(
            type: .mention,
            to: userId,
            storyId: storyId,
            storyAuthorId: storyAuthorId,
            mentionContext: "story",
            targetAuthorId: storyAuthorId
        )
    }

    func sendMomentMentionNotification(to userId: String, momentId: String, momentAuthorId: String? = nil, momentAuthorUsername: String? = nil, commentText: String? = nil, senderUsername: String? = nil) {
        let notificationId: String? = {
            guard let currentUserId = Auth.auth().currentUser?.uid else { return nil }
            return "mention_moment_\(momentId)_\(currentUserId)_\(userId)"
        }()
        sendInteractionNotification(
            type: .mention,
            to: userId,
            notificationId: notificationId,
            momentId: momentId,
            reaction: commentText,
            senderUsername: senderUsername,
            mentionContext: "moment",
            targetAuthorId: momentAuthorId,
            targetAuthorUsername: momentAuthorUsername
        )
    }

    func sendCommentMentionNotification(to userId: String, momentId: String, momentAuthorId: String? = nil, momentAuthorUsername: String? = nil, commentId: String, commentText: String? = nil, senderUsername: String? = nil) {
        sendInteractionNotification(
            type: .mention,
            to: userId,
            momentId: momentId,
            commentId: commentId,
            reaction: commentText,
            senderUsername: senderUsername,
            mentionContext: "comment",
            targetAuthorId: momentAuthorId,
            targetAuthorUsername: momentAuthorUsername
        )
    }

    func sendPhotoTagNotification(
        to userId: String,
        momentId: String,
        momentAuthorId: String,
        momentAuthorUsername: String? = nil,
        momentTitle: String? = nil
    ) {
        sendInteractionNotification(
            type: .photoTag,
            to: userId,
            momentId: momentId,
            reaction: momentTitle,
            mentionContext: "photoTag",
            targetAuthorId: momentAuthorId,
            targetAuthorUsername: momentAuthorUsername
        )
    }
    
    // MARK: - Actions
    
    func markAsRead(_ notification: Notification) {
        guard let userId = Auth.auth().currentUser?.uid, let notificationId = notification.id else { return }
        
        Task {
            await LocalPersistenceService.shared.markNotificationAsRead(notificationId: notificationId, userId: userId)
        }
        
        if let index = notifications.firstIndex(where: { $0.id == notification.id }) {
            notifications[index].isPending = false
            updateUnreadCount()
        }
    }
    
    func markAllAsRead() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        // ✅ Optimista: Limpiar estado local inmediatamente
        let visiblePendingIds = notifications.compactMap { notification in
            notification.isPending ? notification.id : nil
        }
        notifications.indices.forEach { notifications[$0].isPending = false }
        unreadCount = 0
        UNUserNotificationCenter.current().setBadgeCount(0) { _ in }
        
        Task {
            await markSpecificNotificationsAsRead(userId: userId, ids: visiblePendingIds)
            await markAllAsReadBatch(userId: userId)
            await markAllAsReadByScan(userId: userId)
        }
    }
    
    private func markAllAsReadBatch(userId: String) async {
        let db = self.db
        do {
            let snapshot = try await db.collection("users").document(userId).collection("notifications")
                .whereField("isPending", isEqualTo: true)
                .limit(to: 500)
                .getDocuments()
            
            let documents = snapshot.documents
            guard !documents.isEmpty else {
                await markAllAsReadLegacyBatch(userId: userId)
                return
            }
            
            let batch = db.batch()
            for doc in documents {
                batch.updateData([
                    "isPending": false,
                    "isRead": true
                ], forDocument: doc.reference)
            }
            
            try await batch.commit()
            
            if documents.count == 500 {
                await markAllAsReadBatch(userId: userId)
            } else {
                await markAllAsReadLegacyBatch(userId: userId)
            }
        } catch {
            print("❌ Error marking batch as read: \(error)")
        }
    }

    private func markAllAsReadLegacyBatch(userId: String) async {
        let db = self.db
        do {
            let snapshot = try await db.collection("users").document(userId).collection("notifications")
                .whereField("isRead", isEqualTo: false)
                .limit(to: 500)
                .getDocuments()
            
            let documents = snapshot.documents
            guard !documents.isEmpty else { return }
            
            let batch = db.batch()
            for doc in documents {
                batch.updateData([
                    "isPending": false,
                    "isRead": true
                ], forDocument: doc.reference)
            }
            
            try await batch.commit()
            
            if documents.count == 500 {
                await markAllAsReadLegacyBatch(userId: userId)
            }
        } catch {
            print("❌ Error marking legacy batch as read: \(error)")
        }
    }

    private func markSpecificNotificationsAsRead(userId: String, ids: [String]) async {
        guard !ids.isEmpty else { return }
        let uniqueIds = Array(Set(ids))
        let chunks = stride(from: 0, to: uniqueIds.count, by: 400).map {
            Array(uniqueIds[$0..<min($0 + 400, uniqueIds.count)])
        }

        let db = self.db
        for chunk in chunks {
            let batch = db.batch()
            for id in chunk {
                let ref = db.collection("users").document(userId).collection("notifications").document(id)
                batch.setData([
                    "isPending": false,
                    "isRead": true
                ], forDocument: ref, merge: true)
            }
            do {
                try await batch.commit()
            } catch {
                print("❌ Error marking specific notifications as read: \(error)")
            }
        }
    }
    
    private func markAllAsReadByScan(userId: String, startAfter: DocumentSnapshot? = nil) async {
        let db = self.db
        var query = db.collection("users").document(userId).collection("notifications")
            .whereField("isRead", isEqualTo: false)
            .limit(to: 500)
        
        if let startAfter {
            query = query.start(afterDocument: startAfter)
        }
        
        do {
            let snapshot = try await query.getDocuments()
            let documents = snapshot.documents
            guard !documents.isEmpty else { return }
            
            let batch = db.batch()
            for doc in documents {
                let data = doc.data()
                let isPending = data["isPending"] as? Bool
                let isRead = data["isRead"] as? Bool
                
                if isPending != false || isRead != true {
                    batch.setData([
                        "isPending": false,
                        "isRead": true
                    ], forDocument: doc.reference, merge: true)
                }
            }
            
            try await batch.commit()
            
            if documents.count == 500, let last = documents.last {
                await markAllAsReadByScan(userId: userId, startAfter: last)
            }
        } catch {
            print("❌ Error marking scan batch as read: \(error)")
        }
    }
    
    func deleteNotification(_ notification: Notification) {
        stageDeletion([notification])
    }

    func deleteNotifications(_ notificationsToDelete: [Notification]) {
        stageDeletion(notificationsToDelete)
    }

    func stageDeletion(_ notificationsToDelete: [Notification]) {
        guard Auth.auth().currentUser?.uid != nil else { return }

        let valid = notificationsToDelete.filter { $0.id != nil }
        guard !valid.isEmpty else { return }

        if pendingDeletion != nil {
            commitPendingDeletion()
        }

        let ids = Set(valid.compactMap(\.id))
        hiddenPendingDeletionIds.formUnion(ids)
        removeFromLocalState(valid)
        pendingDeletion = PendingNotificationDeletion(notifications: valid)
        schedulePendingDeletionCommit()
    }

    func undoPendingDeletion() {
        guard let pending = pendingDeletion else { return }

        pendingDeletionTask?.cancel()
        pendingDeletionTask = nil

        let ids = Set(pending.notifications.compactMap(\.id))
        hiddenPendingDeletionIds.subtract(ids)

        let existingIds = Set(notifications.compactMap(\.id))
        let restored = pending.notifications.filter { notification in
            guard let id = notification.id else { return false }
            return !existingIds.contains(id)
        }

        notifications.append(contentsOf: restored)
        notifications.sort { $0.timestamp > $1.timestamp }
        LocalPersistenceService.shared.saveNotifications(restored, sync: false)

        pendingDeletion = nil
        updateUnreadCount()
    }

    func commitPendingDeletion() {
        guard let pending = pendingDeletion else { return }

        pendingDeletionTask?.cancel()
        pendingDeletionTask = nil

        commitDeletionToFirestore(pending.notifications)
        hiddenPendingDeletionIds.subtract(Set(pending.notifications.compactMap(\.id)))
        pendingDeletion = nil
    }

    private func schedulePendingDeletionCommit() {
        let pendingId = pendingDeletion?.id
        pendingDeletionTask?.cancel()
        pendingDeletionTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((self?.deletionUndoWindow ?? 3) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.pendingDeletion?.id == pendingId else { return }
                self.commitPendingDeletion()
            }
        }
    }

    private func visibleNotifications(from fetched: [Notification]) -> [Notification] {
        guard !hiddenPendingDeletionIds.isEmpty else { return fetched }
        return fetched.filter { notification in
            guard let id = notification.id else { return true }
            return !hiddenPendingDeletionIds.contains(id)
        }
    }

    private func removeFromLocalState(_ notificationsToDelete: [Notification]) {
        let idSet = Set(notificationsToDelete.compactMap(\.id))
        notifications.removeAll { notification in
            guard let id = notification.id else { return false }
            return idSet.contains(id)
        }
        updateUnreadCount()
        LocalPersistenceService.shared.deleteNotifications(ids: Array(idSet))
    }

    private func commitDeletionToFirestore(_ notificationsToDelete: [Notification]) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let ids = notificationsToDelete.compactMap(\.id)
        guard !ids.isEmpty else { return }

        Task {
            let batch = db.batch()
            for id in ids {
                let ref = db.collection("users").document(userId).collection("notifications").document(id)
                batch.deleteDocument(ref)
            }

            do {
                try await batch.commit()
            } catch {
                print("❌ Error deleting notifications: \(error)")
            }
        }
    }

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
        
        let db = self.db
        Task {
            do {
                let snapshot = try await query.getDocuments()
                let batch = db.batch()
                for doc in snapshot.documents {
                    batch.deleteDocument(doc.reference)
                }
                try await batch.commit()
                print("✅ Notification removed successfully")
            } catch {
                print("❌ Error removing notification: \(error)")
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
