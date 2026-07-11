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
    func startVoiceRecording(interactionId: UUID, startsLocked: Bool) {
        if let currentId = voiceRecordingInteractionId, currentId != interactionId {
            finishVoiceRecording(interactionId: currentId, action: .cancel)
        }

        voiceRecordingDraft = nil
        recordingTime = 0
        beginVoiceRecordingSegment(interactionId: interactionId, startsLocked: startsLocked)
    }

    func resumeVoiceRecording() {
        guard
            let interactionId = voiceRecordingInteractionId,
            let draft = voiceRecordingDraft
        else { return }

        guard draft.normalizedTrimRange != nil else {
            beginVoiceRecordingSegment(interactionId: interactionId, startsLocked: true)
            return
        }

        isPreparingVoiceRecordingPreview = true
        Task { @MainActor in
            guard let segment = await materializedVoiceRecordingSegment(from: draft) else {
                guard voiceRecordingInteractionId == interactionId else { return }
                isPreparingVoiceRecordingPreview = false
                HapticManager.shared.error()
                return
            }
            guard voiceRecordingInteractionId == interactionId else { return }
            voiceRecordingDraft = VoiceRecordingDraft(
                segments: [segment],
                recording: segment.recording
            )
            recordingTime = segment.duration
            beginVoiceRecordingSegment(interactionId: interactionId, startsLocked: true)
        }
    }

    func updateVoiceRecordingTrimRange(_ range: Range<TimeInterval>) {
        guard var draft = voiceRecordingDraft, !isRecordingVoice else { return }
        draft.trimRange = range
        voiceRecordingDraft = draft
        recordingTime = draft.duration
    }

    private func beginVoiceRecordingSegment(interactionId: UUID, startsLocked: Bool) {
        voiceRecordingInteractionId = interactionId
        isVoiceRecordingLocked = startsLocked
        isPreparingVoiceRecordingPreview = false

        AudioRecordingManager.shared.startRecording { started in
            guard voiceRecordingInteractionId == interactionId else {
                if started {
                    AudioRecordingManager.shared.stopRecording { _ in }
                }
                return
            }

            guard started else {
                clearVoiceRecordingState()
                viewModel.error = NSLocalizedString(
                    "chat.error.microphonePermission",
                    comment: "Microphone permission required for voice messages"
                )
                return
            }

            isRecordingVoice = true
            HapticManager.shared.playVoiceRecordStartSound()
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                recordingTime += 0.1
                if recordingTime >= 60.0 {
                    finishVoiceRecording(interactionId: interactionId, action: .send)
                }
            }
        }
    }

    func pauseVoiceRecording() {
        guard
            let interactionId = voiceRecordingInteractionId,
            isRecordingVoice,
            isVoiceRecordingLocked
        else { return }

        recordingTimer?.invalidate()
        recordingTimer = nil
        isRecordingVoice = false
        isVoiceRecordingLocked = false
        isPreparingVoiceRecordingPreview = true
        HapticManager.shared.playVoiceRecordEndSound()

        let previousDuration = voiceRecordingDraft?.duration ?? 0
        let segmentDuration = max(0.1, recordingTime - previousDuration)
        AudioRecordingManager.shared.stopRecording { recording in
            guard voiceRecordingInteractionId == interactionId else { return }
            guard let recording else {
                clearVoiceRecordingState()
                return
            }

            var draft = voiceRecordingDraft ?? VoiceRecordingDraft(segments: [], recording: nil)
            draft.segments.append(VoiceRecordingSegment(recording: recording, duration: segmentDuration))
            voiceRecordingDraft = draft

            Task { @MainActor in
                let composed = await VoiceRecordingComposer.compose(draft.segments)
                guard voiceRecordingInteractionId == interactionId else { return }
                voiceRecordingDraft?.recording = composed
                isPreparingVoiceRecordingPreview = false
                HapticManager.shared.selection()
            }
        }
    }

    func finishVoiceRecording(
        interactionId: UUID,
        action: VoiceRecordingFinishAction
    ) {
        guard voiceRecordingInteractionId == interactionId else { return }

        if action == .cancel {
            clearVoiceRecordingState()
            AudioRecordingManager.shared.stopRecording { _ in }
            return
        }

        if isRecordingVoice {
            recordingTimer?.invalidate()
            recordingTimer = nil
            isRecordingVoice = false
            isVoiceRecordingLocked = false
            isPreparingVoiceRecordingPreview = true
            HapticManager.shared.playVoiceRecordEndSound()

            let previousDuration = voiceRecordingDraft?.duration ?? 0
            let segmentDuration = max(0.1, recordingTime - previousDuration)
            AudioRecordingManager.shared.stopRecording { recording in
                guard voiceRecordingInteractionId == interactionId else { return }
                guard let recording else {
                    clearVoiceRecordingState()
                    return
                }

                var segments = voiceRecordingDraft?.segments ?? []
                segments.append(VoiceRecordingSegment(recording: recording, duration: segmentDuration))
                sendVoiceRecordingSegments(segments, interactionId: interactionId)
            }
        } else if let draft = voiceRecordingDraft {
            sendVoiceRecordingDraft(draft, interactionId: interactionId)
        }
    }

    private func sendVoiceRecordingDraft(
        _ draft: VoiceRecordingDraft,
        interactionId: UUID
    ) {
        isPreparingVoiceRecordingPreview = true
        Task { @MainActor in
            let segment = await materializedVoiceRecordingSegment(from: draft)
            guard voiceRecordingInteractionId == interactionId else { return }
            if let segment {
                sendComposedVoiceRecording(segment.recording, duration: segment.duration)
            } else {
                HapticManager.shared.error()
            }
            clearVoiceRecordingState()
        }
    }

    private func materializedVoiceRecordingSegment(
        from draft: VoiceRecordingDraft
    ) async -> VoiceRecordingSegment? {
        let recording: RecordedVoiceNote
        if let composed = draft.recording {
            recording = composed
        } else if let composed = await VoiceRecordingComposer.compose(draft.segments) {
            recording = composed
        } else {
            return nil
        }

        return await VoiceRecordingComposer.trim(
            recording,
            fullDuration: draft.fullDuration,
            to: draft.normalizedTrimRange
        )
    }

    private func sendVoiceRecordingSegments(
        _ segments: [VoiceRecordingSegment],
        interactionId: UUID
    ) {
        Task { @MainActor in
            let recording = await VoiceRecordingComposer.compose(segments)
            guard voiceRecordingInteractionId == interactionId else { return }
            let duration = segments.reduce(0) { $0 + $1.duration }
            if let recording {
                sendComposedVoiceRecording(recording, duration: duration)
            }
            clearVoiceRecordingState()
        }
    }

    private func sendComposedVoiceRecording(_ recording: RecordedVoiceNote, duration: TimeInterval) {
        guard duration >= 0.5 else {
            HapticManager.shared.error()
            viewModel.error = NSLocalizedString(
                "chat.voice.record.tooShort",
                comment: "Voice recording was too short"
            )
            return
        }
        viewModel.sendAudioMessage(
            recording.data,
            duration: duration,
            waveform: recording.waveform
        )
    }

    private func clearVoiceRecordingState() {
        voiceRecordingInteractionId = nil
        voiceRecordingDraft = nil
        isRecordingVoice = false
        isVoiceRecordingLocked = false
        isPreparingVoiceRecordingPreview = false
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingTime = 0
    }

    func resetVoiceRecordingInteraction() {
        if let interactionId = voiceRecordingInteractionId {
            finishVoiceRecording(interactionId: interactionId, action: .cancel)
        } else {
            clearVoiceRecordingState()
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
