import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine
import SwiftUI

struct InAppActionToast: Identifiable {
    let id = UUID()
    let systemImage: String
    let prefix: String
    let emphasis: String?
    let suffix: String
    let subtitle: String?
    let duration: TimeInterval
    let undo: (@MainActor () -> Void)?
    /// Se queda hasta que llegue el resultado o se descarte.
    let holds: Bool
    let showsProgress: Bool
    /// Tras el toast, el chrome hace morph a la pill Incognito.
    let bridgesToIncognitoPill: Bool
    /// Toast de pausa: morph desde la pill.
    let isIncognitoPaused: Bool
    /// Se ejecuta al acabar el timer / dismiss sin deshacer (p. ej. commit de unfollow diferido).
    let onExpire: (@MainActor () -> Void)?

    static let standardDuration: TimeInterval = 2
    static let undoDuration: TimeInterval = 3.5
    static let incognitoBridgeDuration: TimeInterval = 1.55

    init(
        systemImage: String,
        prefix: String,
        emphasis: String? = nil,
        suffix: String = "",
        subtitle: String? = nil,
        duration: TimeInterval = InAppActionToast.standardDuration,
        undo: (@MainActor () -> Void)? = nil,
        holds: Bool = false,
        showsProgress: Bool = false,
        bridgesToIncognitoPill: Bool = false,
        isIncognitoPaused: Bool = false,
        onExpire: (@MainActor () -> Void)? = nil
    ) {
        self.systemImage = systemImage
        self.prefix = prefix
        self.emphasis = emphasis
        self.suffix = suffix
        self.subtitle = subtitle
        self.duration = undo == nil ? duration : max(duration, Self.undoDuration)
        self.undo = undo
        self.holds = holds
        self.showsProgress = showsProgress
        self.bridgesToIncognitoPill = bridgesToIncognitoPill
        self.isIncognitoPaused = isIncognitoPaused
        self.onExpire = onExpire
    }

    static func activityProgress(titleKey: String) -> InAppActionToast {
        InAppActionToast(
            systemImage: "ellipsis",
            prefix: NSLocalizedString(titleKey, comment: ""),
            subtitle: NSLocalizedString("userActivity.simple.recentlyDeleted.processing.subtitle", comment: ""),
            holds: true,
            showsProgress: true
        )
    }

    static func activityDone(_ key: String) -> InAppActionToast {
        .plain(key, fallback: "", icon: "checkmark.circle.fill")
    }

    static var commentPosted: InAppActionToast {
        InAppActionToast(
            systemImage: "bubble.right.fill",
            prefix: NSLocalizedString("toast.action.commentPosted", value: "Comentario publicado", comment: "")
        )
    }

    static var momentSaved: InAppActionToast {
        InAppActionToast(
            systemImage: "bookmark.fill",
            prefix: NSLocalizedString("toast.action.momentSaved", value: "Momento guardado", comment: "")
        )
    }

    static var momentDeleted: InAppActionToast {
        InAppActionToast(
            systemImage: "trash.fill",
            prefix: NSLocalizedString("toast.action.momentDeleted", value: "Momento eliminado", comment: "")
        )
    }

    static func momentArchived(
        undo: (@MainActor () -> Void)? = nil,
        onExpire: (@MainActor () -> Void)? = nil
    ) -> InAppActionToast {
        InAppActionToast(
            systemImage: "archivebox.fill",
            prefix: NSLocalizedString("toast.action.momentArchived", value: "Momento archivado", comment: ""),
            undo: undo,
            onExpire: onExpire
        )
    }

    static var storyDeleted: InAppActionToast {
        InAppActionToast(
            systemImage: "trash.fill",
            prefix: NSLocalizedString("toast.action.storyDeleted", value: "Historia eliminada", comment: "")
        )
    }

    static var echoLeft: InAppActionToast {
        InAppActionToast(
            systemImage: "rectangle.portrait.and.arrow.right",
            prefix: NSLocalizedString("toast.action.echoLeft", value: "Has salido del Echo", comment: "")
        )
    }

    static var echoDeleted: InAppActionToast {
        InAppActionToast(
            systemImage: "trash.fill",
            prefix: NSLocalizedString("toast.action.echoDeleted", value: "Echo eliminado", comment: "")
        )
    }

    static func followed(_ username: String) -> InAppActionToast {
        personToast(icon: "person.fill.checkmark", prefixKey: "toast.action.followed", fallback: "Sigues a ", username: username)
    }

    static func followRequested(_ username: String) -> InAppActionToast {
        personToast(icon: "person.fill.badge.plus", prefixKey: "toast.action.followRequested", fallback: "Solicitud enviada a ", username: username)
    }

    static func requestAccepted(_ username: String) -> InAppActionToast {
        personToast(icon: "person.fill.checkmark", prefixKey: "toast.action.requestAccepted", fallback: "Aceptaste la solicitud de seguimiento de ", username: username)
    }

    static func requestRejected(_ username: String) -> InAppActionToast {
        personToast(icon: "person.fill.xmark", prefixKey: "toast.action.requestRejected", fallback: "Rechazaste la solicitud de seguimiento de ", username: username)
    }

    static func unfollowed(
        _ username: String,
        undo: (@MainActor () -> Void)? = nil,
        onExpire: (@MainActor () -> Void)? = nil
    ) -> InAppActionToast {
        personToast(
            icon: "person.fill.xmark",
            prefixKey: "toast.action.unfollowed",
            fallback: "Dejaste de seguir a ",
            username: username,
            undo: undo,
            onExpire: onExpire
        )
    }

    static func blocked(_ username: String) -> InAppActionToast {
        personToast(icon: "hand.raised.fill", prefixKey: "toast.action.blocked", fallback: "Bloqueaste a ", username: username)
    }

    static func muted(
        _ username: String,
        undo: @escaping @MainActor () -> Void,
        onExpire: (@MainActor () -> Void)? = nil
    ) -> InAppActionToast {
        personToast(
            icon: "speaker.slash.fill",
            prefixKey: "toast.action.muted",
            fallback: "Silenciaste a ",
            username: username,
            undo: undo,
            onExpire: onExpire
        )
    }

    static func momentUnsaved(
        undo: @escaping @MainActor () -> Void,
        onExpire: (@MainActor () -> Void)? = nil
    ) -> InAppActionToast {
        InAppActionToast(
            systemImage: "bookmark.slash.fill",
            prefix: NSLocalizedString("toast.action.momentUnsaved", value: "Quitado de guardados", comment: ""),
            undo: undo,
            onExpire: onExpire
        )
    }

    static func commentDeleted(username: String?) -> InAppActionToast {
        if let username, !username.isEmpty {
            return personToast(icon: "trash.fill", prefixKey: "toast.action.commentDeleted.prefix", fallback: "Eliminaste el comentario de ", username: username)
        }
        return InAppActionToast(
            systemImage: "trash.fill",
            prefix: NSLocalizedString("toast.action.commentDeleted", value: "Comentario eliminado", comment: "")
        )
    }

    static func messageCopied(text: String) -> InAppActionToast {
        InAppActionToast(
            systemImage: "doc.on.doc.fill",
            prefix: NSLocalizedString("toast.action.messageCopied", value: "Mensaje copiado al portapapeles", comment: ""),
            subtitle: text
        )
    }

    static var linkCopied: InAppActionToast {
        InAppActionToast(
            systemImage: "link",
            prefix: NSLocalizedString("toast.action.linkCopied", value: "Enlace copiado", comment: "")
        )
    }

    static var momentUpdated: InAppActionToast {
        InAppActionToast(
            systemImage: "pencil",
            prefix: NSLocalizedString("toast.action.momentUpdated", value: "Momento actualizado", comment: "")
        )
    }

    static func leftGroup(_ name: String) -> InAppActionToast {
        InAppActionToast(
            systemImage: "rectangle.portrait.and.arrow.right",
            prefix: NSLocalizedString("toast.action.leftGroup.prefix", value: "Saliste del grupo ", comment: ""),
            emphasis: name,
            suffix: localizedSuffix("toast.action.leftGroup.suffix")
        )
    }

    static func pinnedMoment(
        undo: @escaping @MainActor () -> Void,
        onExpire: (@MainActor () -> Void)? = nil
    ) -> InAppActionToast {
        InAppActionToast(
            systemImage: "pin.fill",
            prefix: NSLocalizedString("contextMenu.pinMoment.toast.pinned", value: "Momento fijado", comment: ""),
            undo: undo,
            onExpire: onExpire
        )
    }

    static func unpinnedMoment(
        undo: @escaping @MainActor () -> Void,
        onExpire: (@MainActor () -> Void)? = nil
    ) -> InAppActionToast {
        InAppActionToast(
            systemImage: "pin.slash.fill",
            prefix: NSLocalizedString("contextMenu.pinMoment.toast.unpinned", value: "Momento desfijado", comment: ""),
            undo: undo,
            onExpire: onExpire
        )
    }

    static func chatArchived(
        undo: @escaping @MainActor () -> Void,
        onExpire: (@MainActor () -> Void)? = nil
    ) -> InAppActionToast {
        InAppActionToast(
            systemImage: "archivebox.fill",
            prefix: NSLocalizedString("messaging.toast.archived", value: "Chat archivado", comment: ""),
            undo: undo,
            onExpire: onExpire
        )
    }

    static var chatUnarchived: InAppActionToast {
        InAppActionToast(
            systemImage: "archivebox",
            prefix: NSLocalizedString("messaging.toast.unarchived", value: "Chat desarchivado", comment: "")
        )
    }

    static func chatMuted(
        undo: @escaping @MainActor () -> Void,
        onExpire: (@MainActor () -> Void)? = nil
    ) -> InAppActionToast {
        InAppActionToast(
            systemImage: "bell.slash.fill",
            prefix: NSLocalizedString("messaging.toast.muted", value: "Chat silenciado", comment: ""),
            undo: undo,
            onExpire: onExpire
        )
    }

    static var chatUnmuted: InAppActionToast {
        InAppActionToast(
            systemImage: "bell.fill",
            prefix: NSLocalizedString("messaging.toast.unmuted", value: "Notificaciones reactivadas", comment: "")
        )
    }

    static func chatPinned(
        undo: @escaping @MainActor () -> Void,
        onExpire: (@MainActor () -> Void)? = nil
    ) -> InAppActionToast {
        InAppActionToast(
            systemImage: "pin.fill",
            prefix: NSLocalizedString("messaging.toast.pinned", value: "Chat fijado", comment: ""),
            undo: undo,
            onExpire: onExpire
        )
    }

    static var chatUnpinned: InAppActionToast {
        InAppActionToast(
            systemImage: "pin.slash.fill",
            prefix: NSLocalizedString("messaging.toast.unpinned", value: "Chat desfijado", comment: "")
        )
    }

    static var chatDeleted: InAppActionToast {
        InAppActionToast(
            systemImage: "trash.fill",
            prefix: NSLocalizedString("messaging.toast.deleted", value: "Conversación eliminada", comment: "")
        )
    }

    static func notificationDeleted(
        count: Int,
        undo: @escaping @MainActor () -> Void,
        onExpire: (@MainActor () -> Void)? = nil
    ) -> InAppActionToast {
        let prefix = count > 1
            ? NSLocalizedString("notifications.deleted.toast.plural", value: "Notificaciones eliminadas", comment: "")
            : NSLocalizedString("notifications.deleted.toast", value: "Notificación eliminada", comment: "")
        return InAppActionToast(systemImage: "trash.fill", prefix: prefix, undo: undo, onExpire: onExpire)
    }

    static func plain(_ key: String, fallback: String, icon: String, subtitle: String? = nil) -> InAppActionToast {
        InAppActionToast(
            systemImage: icon,
            prefix: NSLocalizedString(key, value: fallback, comment: ""),
            subtitle: subtitle
        )
    }

    /// Activar/reanudar: toast con copy → morph a la pill del timer.
    static func incognitoActivated() -> InAppActionToast {
        InAppActionToast(
            systemImage: "eye.slash.fill",
            prefix: NSLocalizedString("toast.action.incognito.activated", value: "Incognito activated", comment: ""),
            subtitle: NSLocalizedString("toast.action.incognito.activated.subtitle", value: "Tap to pause", comment: ""),
            duration: incognitoBridgeDuration,
            bridgesToIncognitoPill: true
        )
    }

    /// Pausar: la pill hace morph al toast y se descarta (sin subtítulo).
    static func incognitoPaused() -> InAppActionToast {
        InAppActionToast(
            systemImage: "eye.slash",
            prefix: NSLocalizedString("toast.action.incognito.paused", value: "Incognito paused", comment: ""),
            duration: 1.8,
            bridgesToIncognitoPill: false,
            isIncognitoPaused: true
        )
    }

    private static func personToast(
        icon: String,
        prefixKey: String,
        fallback: String,
        username: String,
        undo: (@MainActor () -> Void)? = nil,
        onExpire: (@MainActor () -> Void)? = nil
    ) -> InAppActionToast {
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            let stripped = fallback.trimmingCharacters(in: .whitespaces)
            let prefix = stripped.hasSuffix(" a") ? String(stripped.dropLast(2)) : stripped
            return InAppActionToast(
                systemImage: icon,
                prefix: NSLocalizedString(prefixKey, value: prefix, comment: ""),
                undo: undo,
                onExpire: onExpire
            )
        }
        return InAppActionToast(
            systemImage: icon,
            prefix: NSLocalizedString(prefixKey, value: fallback, comment: ""),
            emphasis: name,
            suffix: localizedSuffix(prefixKey + ".suffix"),
            undo: undo,
            onExpire: onExpire
        )
    }

    private static func localizedSuffix(_ key: String) -> String {
        // Si la clave no existe, Bundle.main.localizedString devuelve la propia key
        // (p. ej. "toast.action.followed.suffix") y se veía en el banner.
        let resolved = Bundle.main.localizedString(forKey: key, value: nil, table: nil)
        return resolved == key ? "" : resolved
    }
}

@MainActor
class InAppNotificationService: ObservableObject {
    static let shared = InAppNotificationService()

    @Published var currentNotification: Notification?
    @Published var actionToast: InAppActionToast?
    @Published var showBanner: Bool = false
    /// Rect real del chrome visible. La ventana flotante solo intercepta toques aquí.
    @Published var interactiveFrame: CGRect = .null

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private let displayDuration: TimeInterval = InAppActionToast.standardDuration
    private var activeDuration: TimeInterval = InAppActionToast.standardDuration
    private var dismissTimer: AnyCancellable?
    private var pendingExpireAction: (@MainActor () -> Void)?
    private var reactionListeners: [String: ListenerRegistration] = [:]
    private var buzzListeners: [String: ListenerRegistration] = [:]
    private var listenerStartTime = Date()
    /// Cola FIFO: no sustituir ni perder banners mientras uno está en pantalla.
    private var bannerQueue: [BannerQueueItem] = []
    /// Entre hide y clear (0.5s): nuevos items van a la cola.
    private var isClearing = false

    private enum BannerQueueItem {
        case notification(Notification)
        case toast(InAppActionToast)
    }

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
        bannerQueue.removeAll()
        dismissManually(consumeExpire: false)
        currentNotification = nil
        actionToast = nil
        pendingExpireAction = nil
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
        enqueue(.notification(notification))
    }

    func showActionToast(_ toast: InAppActionToast) {
        enqueue(.toast(toast))
    }

    func dismissHeldActionToast() {
        guard actionToast?.holds == true else { return }
        dismissManually(consumeExpire: false)
    }

    /// Deshacer del toast: cancela el commit diferido y cierra sin `onExpire`.
    func performUndoFromActionToast() {
        guard let undo = actionToast?.undo else { return }
        pendingExpireAction = nil
        undo()
        dismissManually(consumeExpire: false)
    }

    private func enqueue(_ item: BannerQueueItem) {
        // Progress held → el done / siguiente toast lo sustituye (flujo activity).
        if showBanner, actionToast?.holds == true, case .toast = item {
            present(item)
            return
        }
        if showBanner || isClearing {
            bannerQueue.append(item)
            return
        }
        present(item)
    }

    private func present(_ item: BannerQueueItem) {
        switch item {
        case .notification(let notification):
            actionToast = nil
            currentNotification = notification
            pendingExpireAction = nil
            HapticManager.shared.notification(.success)
            activeDuration = displayDuration
            showBanner = true
            startDismissTimer()
        case .toast(let toast):
            currentNotification = nil
            actionToast = toast
            pendingExpireAction = toast.onExpire
            showBanner = true
            if toast.showsProgress {
                dismissTimer?.cancel()
            } else {
                HapticManager.shared.notification(.success)
                activeDuration = toast.duration
                startDismissTimer()
            }
        }
    }

    private func startDismissTimer() {
        dismissTimer?.cancel()
        dismissTimer = Just(())
            .delay(for: .seconds(activeDuration), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.dismissManually(consumeExpire: true)
            }
    }

    func dismissManually(consumeExpire: Bool = true) {
        guard showBanner || actionToast != nil || currentNotification != nil else {
            presentNextIfNeeded()
            return
        }
        isClearing = true
        withAnimation {
            showBanner = false
        }
        dismissTimer?.cancel()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            if consumeExpire {
                self.consumePendingExpire()
            } else {
                self.pendingExpireAction = nil
            }
            self.currentNotification = nil
            self.actionToast = nil
            self.isClearing = false
            self.presentNextIfNeeded()
        }
    }

    private func presentNextIfNeeded() {
        guard !showBanner, !isClearing, !bannerQueue.isEmpty else { return }
        present(bannerQueue.removeFirst())
    }

    private func consumePendingExpire() {
        let action = pendingExpireAction
        pendingExpireAction = nil
        action?()
    }

    func pauseDismissTimer() {
        dismissTimer?.cancel()
    }

    func resumeDismissTimerIfNeeded() {
        guard showBanner, actionToast?.showsProgress != true else { return }
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
