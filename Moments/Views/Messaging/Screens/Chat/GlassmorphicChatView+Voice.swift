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

    func syncPendingIncomingMessagesOnOpen() {
        if isPinnedToBottom || shouldOpenAtBottom() {
            pendingIncomingMessages = 0
            if !hasUnreadIncomingMessages() {
                unreadDividerMessageId = nil
                unreadDividerInitialized = true
            }
        } else {
            pendingIncomingMessages = unreadIncomingMessageCount()
        }
    }

    func reconcileScrollStateForCurrentConversation() {
        guard !hasCompletedInitialScroll else { return }
        reloadNotificationOpenIntent()
        let hasHighlightIntent = preferredReactionHighlightMessageId() != nil
        if hasHighlightIntent { return }

        if !hasUnreadIncomingMessages() {
            unreadDividerMessageId = nil
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
        viewModel.messages.contains(where: { $0.id == messageId })
            && messageRowIsLaidOut(messageId)
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

        // No se guarda posición arbitraria, pero los no leídos tienen prioridad (estilo Telegram):
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
        for row in viewModel.chatRenderRows {
            guard case .message(let item) = row else { continue }
            switch item {
            case .single(let message) where message.id == messageId:
                return item.id
            case .mediaCluster(let messages) where messages.contains(where: { $0.id == messageId }):
                return item.id
            default:
                continue
            }
        }
        return messageId
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
        guard !viewModel.messages.isEmpty else { return }

        unreadDividerMessageId = viewModel.messages.first {
            !$0.isRead && $0.senderId != viewModel.currentUserId
        }?.id
        unreadDividerCount = unreadIncomingMessageCount()
        unreadDividerInitialized = true
    }

    func shouldShowUnreadDivider(before item: MessageItem) -> Bool {
        guard let dividerId = unreadDividerMessageId else { return false }
        let rowId = messageRowId(containingMessageId: dividerId) ?? dividerId
        return item.id == rowId
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
