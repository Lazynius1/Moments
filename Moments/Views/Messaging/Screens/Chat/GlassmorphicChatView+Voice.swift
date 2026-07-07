import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Kingfisher
import AVKit
import AVFoundation
import CoreLocation
import MapKit

extension GlassmorphicChatView {
    // MARK: - Voice Recording Functions
    func startVoiceRecording() {
        recordingTime = 0

        AudioRecordingManager.shared.startRecording { started in
            guard started else {
                viewModel.error = NSLocalizedString(
                    "chat.error.microphonePermission",
                    comment: "Microphone permission required for voice messages"
                )
                return
            }

            isRecordingVoice = true
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                recordingTime += 0.1
                if recordingTime >= 60.0 {
                    stopVoiceRecording(shouldSend: true)
                }
            }
        }
    }

    func stopVoiceRecording(shouldSend: Bool) {
        isRecordingVoice = false
        recordingTimer?.invalidate()
        recordingTimer = nil

        let capturedDuration = max(recordingTime, 0.1)
        recordingTime = 0

        AudioRecordingManager.shared.stopRecording { [weak viewModel] audioData in
            guard shouldSend,
                  let audioData,
                  !audioData.isEmpty,
                  let viewModel else { return }
            viewModel.sendAudioMessage(audioData, duration: capturedDuration)
        }
    }
}

// ✅ NUEVO: Función para manejar navegación al momento desde el chat
extension GlassmorphicChatView {
    func preferredReactionHighlightMessageId() -> String? {
        reloadNotificationOpenIntent()
        return notificationOpenIntent?.highlightMessageIds.first
    }

    func hasExplicitReactionHighlightIntent() -> Bool {
        reloadNotificationOpenIntent()
        return notificationOpenIntent?.highlightMessageIds.isEmpty == false
    }

    func hasUnreadIncomingMessages() -> Bool {
        unreadIncomingMessageCount() > 0
    }

    func unreadIncomingMessageCount() -> Int {
        viewModel.unreadIncomingCount
    }

    func clearUnreadDividerUI() {
        let previousDividerId = unreadDividerMessageId
        unreadDividerMessageId = nil
        unreadDividerInitialized = true
        unreadDividerCount = 0
        reconfigureUnreadDividerRow(for: previousDividerId)
    }

    func refreshPendingIncomingState() {
        let unreadCount = unreadIncomingMessageCount()
        unreadDividerCount = unreadCount
        if unreadCount == 0 {
            pendingIncomingMessages = 0
            clearUnreadDividerUI()
            return
        }

        if isPinnedToBottom {
            pendingIncomingMessages = 0
            clearUnreadDividerUI()
            return
        }

        pendingIncomingMessages = unreadCount
        if unreadDividerMessageId == nil {
            unreadDividerInitialized = false
            initializeUnreadDividerIfNeeded()
        }
    }

    func syncPendingIncomingMessagesOnOpen() {
        refreshPendingIncomingState()
    }

    func reconcileScrollStateForCurrentConversation() {
        guard !hasCompletedInitialScroll else { return }
        reloadNotificationOpenIntent()
        let hasHighlightIntent = preferredReactionHighlightMessageId() != nil
        if hasHighlightIntent { return }

        if !hasUnreadIncomingMessages() {
            clearUnreadDividerUI()
            if case .firstUnread = frozenInitialScrollTarget {
                frozenInitialScrollTarget = viewModel.messages.last.map { .bottom(messageId: $0.id) }
                isPinnedToBottom = true
            }
            if case .highlightedMessage = frozenInitialScrollTarget {
                frozenInitialScrollTarget = viewModel.messages.last.map { .bottom(messageId: $0.id) }
                isPinnedToBottom = true
            }
            if shouldOpenAtBottom(), !hasCompletedInitialScroll {
                pendingInitialScrollRoute = true
            }
        }
    }

    func refreshFrozenScrollTargetForReactionHighlight() {
        guard let highlightId = preferredReactionHighlightMessageId() else { return }
        frozenInitialScrollTarget = .highlightedMessage(messageId: highlightId)
    }

    func messageRowIsLaidOut(_ messageId: String) -> Bool {
        for row in viewModel.chatRenderRows {
            guard case .message(let item) = row else { continue }
            switch item {
            case .single(let message) where message.id == messageId:
                return true
            case .mediaCluster(let messages) where messages.contains(where: { $0.id == messageId }):
                return true
            default:
                continue
            }
        }
        return false
    }

    func messageIsReadyForScroll(_ messageId: String) -> Bool {
        guard viewModel.messages.contains(where: { $0.id == messageId }) else { return false }
        guard let rowId = messageRowId(containingMessageId: messageId) else { return false }
        return chatListController.containsRow(id: rowId)
    }

    func resolveInitialScrollTarget() -> ChatScrollTarget? {
        reloadNotificationOpenIntent()

        if let highlightId = preferredReactionHighlightMessageId() {
            return .highlightedMessage(messageId: highlightId)
        }

        if shouldOpenAtBottom() {
            if let lastId = viewModel.messages.last?.id {
                return .bottom(messageId: lastId)
            }
            return nil
        }

        // No se guarda posición arbitraria, pero los no leídos tienen prioridad:
        // abrir en el primer no leído; si no hay, al último mensaje.
        if let unreadId = viewModel.messages.first(where: {
            !$0.isRead && $0.senderId != viewModel.currentUserId
        })?.id {
            return .firstUnread(messageId: unreadId)
        }

        if let lastId = viewModel.messages.last?.id {
            return .bottom(messageId: lastId)
        }
        return nil
    }

    func messageRowId(containingMessageId messageId: String) -> String? {
        if chatListController.containsRow(id: messageId) {
            return chatListController.resolvedRowId(forMessageId: messageId) ?? messageId
        }
        for row in viewModel.chatRenderRows {
            guard case .message(let item) = row else { continue }
            switch item {
            case .single(let message) where message.id == messageId:
                return row.id
            case .mediaCluster(let messages) where messages.contains(where: { $0.id == messageId }):
                return row.id
            default:
                continue
            }
        }
        return nil
    }

    func pendingBuzzReplayNeedsRetry() -> Bool {
        guard let conversationId = viewModel.conversation.id else { return false }

        if let intent = notificationOpenIntent, intent.playBuzzOnOpen {
            if let event = resolvePendingBuzzEvent(for: intent),
               !ChatBuzzProcessedStore.isProcessed(eventId: event.id, conversationId: conversationId) {
                return true
            }
            if let buzzEventId = intent.buzzEventId, !buzzEventId.isEmpty {
                return viewModel.buzzEvents.first(where: { $0.id == buzzEventId }) == nil
            }
        }

        if let event = viewModel.pendingReplayBuzzEvent(),
           !ChatBuzzProcessedStore.isProcessed(eventId: event.id, conversationId: conversationId) {
            return true
        }

        return false
    }

    func reloadNotificationOpenIntent() {
        guard let conversationId = viewModel.conversation.id else { return }
        notificationOpenIntent = ChatNavigationIntentStore.peek(for: conversationId)
    }

    func clearNotificationOpenIntentIfFinished() {
        guard let conversationId = viewModel.conversation.id else { return }
        guard let intent = notificationOpenIntent else { return }

        let highlightsPending = !intent.highlightMessageIds.isEmpty
        let buzzPending = pendingBuzzReplayNeedsRetry()
        guard !highlightsPending, !buzzPending else { return }

        ChatNavigationIntentStore.clear(for: conversationId)
        notificationOpenIntent = nil
    }

    func initializeUnreadDividerIfNeeded() {
        guard !unreadDividerInitialized else { return }
        guard hasUnreadIncomingMessages() else { return }
        guard !viewModel.messages.isEmpty else { return }

        guard let firstUnreadId = viewModel.messages.first(where: {
            !$0.isRead && $0.senderId != viewModel.currentUserId
        })?.id else { return }

        unreadDividerMessageId = firstUnreadId
        unreadDividerCount = unreadIncomingMessageCount()
        unreadDividerInitialized = true
        ChatScrollDebug.log("unread divider frozen id=\(firstUnreadId) count=\(unreadDividerCount)")
        reconfigureUnreadDividerRow(for: firstUnreadId)
    }

    /// Las celdas hostean su propio árbol SwiftUI: cambiar `unreadDividerMessageId` después de que
    /// la fila ya esté construida no la re-renderiza (updates in-place), así que el divisor no
    /// aparecía hasta que el scroll reciclaba la celda. Forzar reconfigure de la fila afectada.
    func reconfigureUnreadDividerRow(for messageId: String?) {
        guard let messageId else { return }
        // Un salto de runloop para que el reconfigure se encole después del re-render de SwiftUI
        // (la celda debe reconstruirse con el closure de contenido ya actualizado).
        DispatchQueue.main.async {
            chatListController.reconfigure(messageIds: [messageId])
        }
    }

    func shouldShowUnreadDivider(before item: MessageItem) -> Bool {
        guard let dividerId = unreadDividerMessageId else { return false }
        guard hasUnreadIncomingMessages() else { return false }
        let rowId = messageRowId(containingMessageId: dividerId) ?? dividerId
        guard ChatRenderRow.message(item).id == rowId else { return false }

        guard let dividerIndex = viewModel.messages.firstIndex(where: { $0.id == dividerId }) else {
            return false
        }
        // Hace falta historial leído antes del primer no leído; si la ventana cargada
        // empieza justo en el no leído, el historial puede estar en páginas sin cargar.
        if dividerIndex > 0,
           viewModel.messages[..<dividerIndex].contains(where: {
               $0.isRead || $0.senderId == viewModel.currentUserId
           }) {
            return true
        }
        return viewModel.canLoadMore
    }

    func installScreenshotObserverIfNeeded() {
        removeScreenshotObserverIfNeeded()
        screenshotObserver = NotificationCenter.default.addObserver(
            forName: UIScreen.capturedDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            if UIScreen.main.isCaptured {
                viewModel.reportVanishScreenRecordingIfNeeded()
            }
        }
        screenshotTakenObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.userDidTakeScreenshotNotification,
            object: nil,
            queue: .main
        ) { _ in
            viewModel.reportVanishScreenshotIfNeeded()
        }
    }

    func removeScreenshotObserverIfNeeded() {
        if let screenshotObserver {
            NotificationCenter.default.removeObserver(screenshotObserver)
            self.screenshotObserver = nil
        }
        if let screenshotTakenObserver {
            NotificationCenter.default.removeObserver(screenshotTakenObserver)
            self.screenshotTakenObserver = nil
        }
    }

}
