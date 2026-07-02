import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine
import SwiftUI

@MainActor
class InAppNotificationService: ObservableObject {
    static let shared = InAppNotificationService()

    @Published var currentNotification: Notification?
    @Published var showBanner: Bool = false

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private let displayDuration: TimeInterval = 4.0
    private var dismissTimer: AnyCancellable?
    private var reactionListeners: [String: ListenerRegistration] = [:]
    private var buzzListeners: [String: ListenerRegistration] = [:]
    private var listenerStartTime = Date()

    private init() {}

    func startListing() {
        guard Auth.auth().currentUser?.uid != nil else { return }

        listener?.remove()
        listener = nil
        clearFallbackListeners()

        listenerStartTime = Date()

        // El banner in-app en foreground lo cubre AppDelegate (push → coordinador).
        // El listener de users/notifications duplicaba el banner: primero genérico (push),
        // luego el doc Firestore con el copy completo.
        syncFallbackListeners(conversationIds: ChatSessionEngine.shared.notificationConversationIdsForFallback())
    }

    func stopListening() {
        listener?.remove()
        listener = nil

        clearFallbackListeners()
        dismissManually()
        currentNotification = nil
    }

    func syncFallbackListeners(conversationIds: [String]) {
        let targetIds = Set(conversationIds.filter { !$0.isEmpty }.prefix(5))

        for (conversationId, registration) in reactionListeners where !targetIds.contains(conversationId) {
            registration.remove()
            reactionListeners.removeValue(forKey: conversationId)
        }

        for (conversationId, registration) in buzzListeners where !targetIds.contains(conversationId) {
            registration.remove()
            buzzListeners.removeValue(forKey: conversationId)
        }

        for conversationId in targetIds {
            attachReactionFallbackListener(conversationId: conversationId)
            attachBuzzFallbackListener(conversationId: conversationId)
        }
    }

    func handleNewNotification(_ notification: Notification) {
        NotificationPresentationCoordinator.shared.present(notification, source: .local)
    }

    func display(_ notification: Notification) {
        currentNotification = notification
        showBanner = true

        HapticManager.shared.notification(.success)
        startDismissTimer()
    }

    private func startDismissTimer() {
        dismissTimer?.cancel()
        dismissTimer = Just(())
            .delay(for: .seconds(displayDuration), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                withAnimation {
                    self?.showBanner = false
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self?.currentNotification = nil
                }
            }
    }

    func dismissManually() {
        withAnimation {
            showBanner = false
        }
        dismissTimer?.cancel()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, !self.showBanner else { return }
            self.currentNotification = nil
        }
    }

    func pauseDismissTimer() {
        dismissTimer?.cancel()
    }

    func resumeDismissTimerIfNeeded() {
        guard showBanner else { return }
        startDismissTimer()
    }

    private func clearFallbackListeners() {
        reactionListeners.values.forEach { $0.remove() }
        buzzListeners.values.forEach { $0.remove() }
        reactionListeners.removeAll()
        buzzListeners.removeAll()
    }

    private func attachReactionFallbackListener(conversationId: String) {
        guard reactionListeners[conversationId] == nil,
              let currentUserId = Auth.auth().currentUser?.uid else { return }

        let registration = db.collectionGroup("messageReactions")
            .whereField("conversationId", isEqualTo: conversationId)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self else { return }

                snapshot?.documentChanges.forEach { change in
                    guard change.type == .added else { return }
                    let data = change.document.data()
                    let reactorId = data["userId"] as? String ?? change.document.documentID
                    guard reactorId != currentUserId else { return }

                    let messageId = data["messageId"] as? String ?? ""
                    let emoji = data["emoji"] as? String ?? ""
                    guard !messageId.isEmpty, !emoji.isEmpty else { return }

                    if let timestamp = (data["timestamp"] as? Timestamp)?.dateValue(),
                       timestamp <= self.listenerStartTime {
                        return
                    }

                    Task { @MainActor in
                        let isOwnMessage = await NotificationPresentationCoordinator.shared.isMessageAuthoredByCurrentUser(
                            conversationId: conversationId,
                            messageId: messageId
                        )
                        guard isOwnMessage else { return }

                        let username = await NotificationPresentationCoordinator.shared.fetchSenderUsername(userId: reactorId)
                        NotificationPresentationCoordinator.shared.presentMessageReactionFallback(
                            conversationId: conversationId,
                            messageId: messageId,
                            senderId: reactorId,
                            senderUsername: username,
                            emoji: emoji,
                            messageType: nil
                        )
                    }
                }
            }

        reactionListeners[conversationId] = registration
    }

    private func attachBuzzFallbackListener(conversationId: String) {
        guard buzzListeners[conversationId] == nil,
              let currentUserId = Auth.auth().currentUser?.uid else { return }

        let registration = db.collection("conversations")
            .document(conversationId)
            .collection("buzzEvents")
            .order(by: "createdAt", descending: true)
            .limit(to: 20)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self else { return }

                snapshot?.documentChanges.forEach { change in
                    guard change.type == .added else { return }
                    let data = change.document.data()
                    guard data["type"] as? String == "buzz",
                          let senderId = data["senderId"] as? String,
                          senderId != currentUserId else { return }

                    if let createdAt = (data["createdAt"] as? Timestamp)?.dateValue(),
                       createdAt <= self.listenerStartTime {
                        return
                    }

                    Task { @MainActor in
                        let username = await NotificationPresentationCoordinator.shared.fetchSenderUsername(userId: senderId)
                        NotificationPresentationCoordinator.shared.presentChatBuzzFallback(
                            conversationId: conversationId,
                            buzzEventId: change.document.documentID,
                            senderId: senderId,
                            senderUsername: username
                        )
                    }
                }
            }

        buzzListeners[conversationId] = registration
    }
}
