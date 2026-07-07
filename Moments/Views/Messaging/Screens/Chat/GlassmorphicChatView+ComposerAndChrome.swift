import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Kingfisher
import AVKit
import AVFoundation
import CoreLocation
import MapKit

extension GlassmorphicChatView {

    func sharedMedia(from message: EnhancedMessage) -> SharedMedia? {
        guard let mediaUrl = message.mediaUrl else { return nil }
        guard message.type == .image || message.type == .video || message.type == .ephemeral else { return nil }

        return SharedMedia(
            id: message.id,
            type: message.type == .video ? .video : .image,
            thumbnailUrl: message.thumbnailUrl ?? mediaUrl,
            originalUrl: mediaUrl,
            senderId: message.senderId,
            timestamp: message.timestamp,
            sourceMessage: message,
            allowsSaving: message.type != .ephemeral && message.isVanishModeMessage != true
        )
    }

    func sharedMediaItemsForOverlay(selecting message: EnhancedMessage) -> [SharedMedia] {
        if message.type == .ephemeral {
            guard let selected = sharedMedia(from: message) else { return [] }
            return [selected]
        }

        let items = viewModel.messages.compactMap(sharedMedia(from:))
        guard let selected = sharedMedia(from: message) else { return items }

        if items.contains(where: { $0.id == selected.id }) {
            return items
        }

        return items + [selected]
    }

    func sendReplyToSharedMedia(_ media: SharedMedia, text: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        viewModel.sendTextMessage(trimmedText, replyTo: media.id)
        DispatchQueue.main.async {
            completion(.success(()))
        }
    }

    func sendBuzzFromAttachmentMenu() {
        let now = Date()
        if let lastBuzzSentAt, now.timeIntervalSince(lastBuzzSentAt) < 45 {
            showBuzzToast(NSLocalizedString("chat.buzz.cooldown", comment: "Buzz cooldown"))
            return
        }

        lastBuzzSentAt = now
        viewModel.sendBuzz { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    HapticManager.shared.playBuzzSentSound()
                    triggerBuzzEffect(
                        text: NSLocalizedString("chat.buzz.sent", comment: "Sent buzz toast"),
                        isLocal: true,
                        showsToast: false
                    )
                case .failure(let error):
                    lastBuzzSentAt = nil
                    showBuzzToast(error.localizedDescription)
                }
            }
        }
    }

    func buzzTimelineText(for event: ChatBuzzEvent) -> String {
        if event.senderId == viewModel.currentUserId {
            return NSLocalizedString("chat.buzz.sent", comment: "Sent buzz timeline event")
        }

        return String(
            format: NSLocalizedString("chat.buzz.received", comment: "Incoming buzz timeline event"),
            otherParticipantDisplayName
        )
    }

    func triggerBuzzEffect(text: String, isLocal: Bool, showsToast: Bool = true) {
        if showsToast {
            showBuzzToast(text)
        }
        guard !isLocal else { return }

        buzzShakeAmplitude = 24
        HapticManager.shared.chatBuzzReceived(reduceMotion: reduceMotion)
        HapticManager.shared.playBuzzReceivedSound()
        guard !reduceMotion else { return }
        buzzShakeProgress = 0
        withAnimation(.linear(duration: 1.12)) {
            buzzShakeProgress = 1
        }
    }

    func showBuzzToast(_ text: String) {
        buzzToastDismissTask?.cancel()
        withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86)) {
            buzzToastText = text
        }

        buzzToastDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_900_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.9)) {
                buzzToastText = nil
            }
        }
    }

    // ✅ REFACTORIZADO: Sección de barra de entrada
    var inputBarSection: some View {
        Group {
            if isOtherParticipantBlockedByCurrentUser {
                BlockedByMeChatInputBar(onUnblock: unblockOtherParticipantFromChat)
            } else if isOtherParticipantUnavailable {
                UnavailableChatInputBar()
            } else {
                GlassmorphicInputBar(
                    text: $messageText,
                    isTyping: $session.isTyping,
                    isRecordingVoice: $isRecordingVoice,
                    activeAttachmentSheet: $activeAttachmentSheet,
                    isVanishModeActive: viewModel.vanishModeActive,
                    recordingTime: recordingTime,
                    onSend: {
                        let messageToSend = messageText

                        guard !messageToSend.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                            return
                        }

                        if let editingMessage = editingMessage {
                            // Save edit
                            viewModel.editMessage(editingMessage, newContent: messageToSend)
                            self.editingMessage = nil
                        } else {
                            // Send new message
                            let replyToMessageId = replyingTo?.id
                            viewModel.sendTextMessage(messageToSend, replyTo: replyToMessageId)
                            replyingTo = nil
                            ChatDraftStore.shared.clearDraft(for: conversationId)
                        }

                        messageText = ""
                    },
                    onStartVoiceRecording: {
                        startVoiceRecording()
                    },
                    onStopVoiceRecording: { shouldSend in
                        stopVoiceRecording(shouldSend: shouldSend)
                    }
                )
                .focused($isTextFieldFocused)
                .onPreferenceChange(ChatPlusButtonAnchorKey.self) { frame in
                    plusButtonAnchorFrame = frame
                }
            }
        }
    }

    struct UnavailableChatInputBar: View {
        @Environment(\.colorScheme) var colorScheme

        var body: some View {
            HStack(spacing: 10) {
                Image(systemName: "person.slash")
                    .font(.system(size: 15, weight: .semibold))

                Text("chat.input.unavailable")
                    .font(.system(size: legacyPoppinsSize(14), weight: .medium))
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .foregroundColor(colorScheme == .dark ? .white.opacity(0.62) : .black.opacity(0.54))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .momentsChromeGlass(in: Capsule(), interactive: false)
        }
    }

    struct BlockedByMeChatInputBar: View {
        let onUnblock: () -> Void
        @Environment(\.colorScheme) var colorScheme

        var body: some View {
            HStack(spacing: 10) {
                Text("chat.blockedByMe.input")
                    .font(.system(size: legacyPoppinsSize(13), weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.66) : .black.opacity(0.58))
                    .lineLimit(2)

                Spacer(minLength: 6)

                Button(action: onUnblock) {
                    Text("chat.blockedByMe.unblock")
                        .font(.system(size: legacyPoppinsSize(13), weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .momentsChromeGlass(in: Capsule(), interactive: true)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .momentsChromeGlass(in: Capsule(), interactive: false)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    // ✅ REFACTORIZADO: Acciones al aparecer

    // ✅ REFACTORIZADO: Renderizar cada item del chat por separado para evitar errores del compilador
    @ViewBuilder
    func renderMessageItem(_ item: MessageItem, in messages: [EnhancedMessage], proxy: ScrollViewProxy?) -> some View {
        let rowId = ChatRenderRow.message(item).id
        let isMenuSelected = messageMenuSelection?.rowId == rowId
        let isBubbleHighlighted = isMessageItemHighlighted(item)

        ChatMessageRowChrome(
            isOutgoing: isOutgoingItem(item),
            colorScheme: colorScheme
        ) {
            Group {
                switch item {
                case .single(let message):
                    let liveMessage = viewModel.messagesById[message.id] ?? message
                    if liveMessage.type == .chatNotice {
                        ChatNoticeTimelineRow(
                            noticeKey: liveMessage.content ?? "",
                            actorUserId: liveMessage.senderId,
                            currentUserId: viewModel.currentUserId,
                            otherParticipantName: otherParticipantDisplayName,
                            onChangeTimer: { showVanishTimerSheet = true },
                            onTurnOn: { viewModel.toggleVanishMode() }
                        )
                        .id(rowId)
                    } else {
                    let displayReactions = shouldRenderReactionChrome(rowId: rowId, messageIds: [liveMessage.id])
                        ? viewModel.displayReactions(for: liveMessage.id)
                        : nil
                    GlassmorphicMessageRow(
                    message: liveMessage,
                    displayReactions: displayReactions,
                    isCurrentUser: liveMessage.senderId == viewModel.currentUserId,
                    showAvatar: shouldShowAvatar(for: liveMessage, in: messages),
                    groupPosition: messageGroupPosition(for: liveMessage, in: messages),
                    otherUserId: viewModel.conversation.otherParticipantId,
                    isOtherParticipantUnavailable: isOtherParticipantUnavailable,
                    otherParticipantName: otherParticipantDisplayName,
                    repliedMessage: liveMessage.replyTo.flatMap { viewModel.messagesById[$0] },
                    isMenuSelected: isMenuSelected,
                    isBubbleFlashing: isBubbleFlashing(liveMessage.id),
                    onReply: { activateReply(to: liveMessage) },
                    onReaction: { emoji in
                        viewModel.addReaction(to: liveMessage, emoji: emoji)
                        pulseBubbleHighlight(liveMessage.id)
                    },
                    onAvatarTap: {
                        showingUserProfile = true
                    },
                    onReplyTap: { targetId in
                        jumpTo(targetId, proxy: proxy)
                    },
                    onMessageViewed: { messageId in
                        if let index = viewModel.messageIndexById[messageId] {
                            viewModel.messages[index].isViewed = true
                        }
                    },
                    onMomentNavigation: { message in
                        handleMomentNavigationFromChat(message: message)
                    },
                    onStoryNavigation: { message in
                        handleStoryNavigationFromChat(message: message)
                    },
                    onOpenMedia: { message in
                        if message.needsDownloadForPlayback {
                            viewModel.openMediaForViewing(message) { _ in }
                            return
                        }
                        guard let media = sharedMedia(from: message) else { return }
                        selectedChatMediaItems = sharedMediaItemsForOverlay(selecting: message)
                        selectedChatMedia = media
                    },
                    onStopLiveLocation: { messageId in
                        viewModel.stopLiveLocation(messageId: messageId)
                    },
                    onHydrateMedia: { message in
                        viewModel.hydrateMediaIfNeeded(for: message)
                    },
                    onLongPress: { frame, cornerRadius in
                        let resolvedFrame = chatListController.frameInWindow(forRowId: rowId) ?? frame
                        presentMessageOptions(
                            liveMessage,
                            rowId: rowId,
                            cluster: nil,
                            anchorFrame: resolvedFrame,
                            anchorCornerRadius: cornerRadius
                        )
                    },
                    onViewOnceOpen: { targetMessage, isReplaySession in
                        presentViewOnceViewer(message: targetMessage, isReplaySession: isReplaySession)
                    },
                    viewOnceZoomNamespace: viewOnceZoomNamespace,
                    progress: viewModel.uploadProgress[liveMessage.id],
                    downloadProgress: viewModel.downloadProgress[liveMessage.id],
                    isDownloadingMedia: viewModel.isDownloadingMedia(liveMessage.id),
                    showSeenLabel: shouldShowSeenLabel(for: liveMessage.id, status: liveMessage.status),
                    timestampRevealOffset: $timestampRevealOffset
                )
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded {
                        addQuickReaction(to: liveMessage)
                    }
                )
                    }

                case .mediaCluster(let clusterMessages):
                    let liveCluster = clusterMessages.map { clusterMessage in
                        viewModel.messagesById[clusterMessage.id] ?? clusterMessage
                    }
                    GlassmorphicClusterRow(
                    messages: liveCluster,
                    repliedMessage: liveCluster.first?.replyTo.flatMap { viewModel.messagesById[$0] },
                    otherParticipantName: otherParticipantDisplayName,
                    isCurrentUser: liveCluster.first?.senderId == viewModel.currentUserId,
                    showAvatar: shouldShowAvatar(for: liveCluster.first!, in: messages),
                    otherUserId: viewModel.conversation.otherParticipantId,
                    isOtherParticipantUnavailable: isOtherParticipantUnavailable,
                    onAvatarTap: { showingUserProfile = true },
                    onMessageViewed: { messageId in
                        if let index = viewModel.messageIndexById[messageId] {
                            viewModel.messages[index].isViewed = true
                        }
                    },
                    onMomentNavigation: { message in
                        handleMomentNavigationFromChat(message: message)
                    },
                    onOpenCluster: { clusterMessages in
                        let ids = clusterMessages.map(\.id)
                        guard let anchorId = ids.first else { return }
                        clusterGallerySelection = ClusterGallerySelection(
                            anchorMessageId: anchorId,
                            messageIds: ids
                        )
                    },
                    onLongPress: { message, frame, cornerRadius in
                        let resolvedFrame = chatListController.frameInWindow(forRowId: rowId) ?? frame
                        presentMessageOptions(
                            message,
                            rowId: rowId,
                            cluster: liveCluster.count > 1 ? liveCluster : nil,
                            anchorFrame: resolvedFrame,
                            anchorCornerRadius: cornerRadius
                        )
                    },
                    onHydrateMedia: { message in
                        viewModel.hydrateMediaIfNeeded(for: message)
                    },
                    onReply: { messages in
                        self.clusterForReply = messages
                    },
                    onReplyTap: { id in
                        jumpTo(id, proxy: proxy)
                    },
                    displayReactions: { messageId in
                        shouldRenderReactionChrome(rowId: rowId, messageIds: liveCluster.map(\.id))
                            ? viewModel.displayReactions(for: messageId)
                            : nil
                    },
                    onReaction: { message, emoji in
                        viewModel.addReaction(to: message, emoji: emoji)
                        pulseBubbleHighlight(message.id)
                    },
                    uploadProgress: viewModel.uploadProgress,
                    showSeenLabel: {
                        let status = ClusterMessageStatusAggregator.aggregate(liveCluster)
                        guard let anchorId = liveCluster.last?.id else { return false }
                        return shouldShowSeenLabel(for: anchorId, status: status)
                    }(),
                    isMenuSelected: isMenuSelected,
                    isBubbleFlashing: liveCluster.contains { isBubbleFlashing($0.id) },
                    timestampRevealOffset: $timestampRevealOffset
                )
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded {
                        if let frontMessage = liveCluster.first {
                            addQuickReaction(to: frontMessage)
                        }
                    }
                )

                }
            }
        }
        .chatMenuDimmedUnlessSelected(isSelected: isMenuSelected, menuOpen: messageMenuSelection != nil)
        .zIndex(isMenuSelected || isBubbleHighlighted ? 100 : 0)
        .id(item.id)
    }

    func isMessageItemHighlighted(_ item: MessageItem) -> Bool {
        switch item {
        case .single(let message):
            return flashingMessageIds.contains(message.id)
        case .mediaCluster(let messages):
            return messages.contains { flashingMessageIds.contains($0.id) }
        }
    }

    var chatMediaLayoutSignature: String {
        viewModel.messages.suffix(6).map { message in
            "\(message.id)|\(message.mediaUrl ?? "")|\(message.thumbnailUrl ?? "")|\(message.type.rawValue)"
        }.joined(separator: ";")
    }

    var lastOutgoingMessageId: String? {
        viewModel.messages.last(where: { $0.senderId == viewModel.currentUserId })?.id
    }

    func shouldShowSeenLabel(for messageId: String, status: MessageStatus) -> Bool {
        status == .read && messageId == lastOutgoingMessageId
    }

    func reactionIdentitySuffix(for item: MessageItem) -> String {
        switch item {
        case .single(let message):
            return reactionToken(for: message.id)
        case .mediaCluster(let clusterMessages):
            return clusterMessages.map { reactionToken(for: $0.id) }.joined(separator: "|")
        }
    }

    func reactionToken(for messageId: String) -> String {
        guard let reactions = viewModel.displayReactions(for: messageId), !reactions.isEmpty else { return "" }
        return reactions
            .map { "\($0.key):\($0.value.count)" }
            .sorted()
            .joined(separator: ",")
    }

    func shouldRenderReactionChrome(rowId: String, messageIds: [String]) -> Bool {
        messageMenuSelection?.rowId != rowId
    }

    func isBubbleFlashing(_ messageId: String) -> Bool {
        flashingMessageIds.contains(messageId)
    }

    func activateReply(to message: EnhancedMessage) {
        replyingTo = message
        pulseBubbleHighlight(message.id)
        guard hasCompletedInitialScroll else { return }
        if isPinnedToBottom {
            pendingPinnedBottomSnap = true
        } else if !isReplyTargetLikelyVisible(messageId: message.id) {
            pendingReplyScrollMessageId = message.id
        }
    }

    func isReplyTargetLikelyVisible(messageId: String) -> Bool {
        guard let rowId = messageRowId(containingMessageId: messageId) else { return false }
        return chatListController.topVisibleRowId == rowId
    }

    func pulseBubbleHighlight(_ messageId: String, duration: TimeInterval = ChatBubbleAnchorMetrics.highlightDuration) {
        let insertAnimation: Animation? = reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.7)
        let removeAnimation: Animation? = reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.82)
        withAnimation(insertAnimation) {
            flashingMessageIds.insert(messageId)
        }
        let id = messageId
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            withAnimation(removeAnimation) {
                _ = flashingMessageIds.remove(id)
            }
        }
    }

    func addQuickReaction(to message: EnhancedMessage) {
        viewModel.addReaction(to: message, emoji: quickReactionEmoji)
        pulseBubbleHighlight(message.id)
        HapticManager.shared.lightImpact()
    }

    func presentMessageOptions(
        _ message: EnhancedMessage,
        rowId: String,
        cluster: [EnhancedMessage]?,
        anchorFrame: CGRect,
        anchorCornerRadius: CGFloat
    ) {
        guard anchorFrame.width > 0, anchorFrame.height > 0 else { return }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            messageMenuSelection = ChatMessageMenuSelection(
                rowId: rowId,
                message: message,
                anchorFrame: anchorFrame,
                anchorCornerRadius: anchorCornerRadius,
                isOutgoing: message.senderId == viewModel.currentUserId,
                clusterMessages: cluster
            )
        }
    }

    func restoreScrollUIState() {
        // Apertura fresca: al fondo (o al primer no leído), sin restaurar offset de sesiones anteriores.
        // `didHydrateScrollStateOnce` evita que un segundo `onAppear` (p. ej. cerrar un sheet) relance el routing.
        guard !didHydrateScrollStateOnce else { return }
        didHydrateScrollStateOnce = true
        hasCompletedInitialScroll = false
        didReapplyFrozenScrollPosition = false
        frozenInitialScrollTarget = nil
        pendingInitialScrollRoute = false
        unreadDividerMessageId = nil
        unreadDividerCount = 0
        unreadDividerInitialized = false
        isPinnedToBottom = true
        listIsAtBottom = true
    }

    /// Al activar vanish con el swipe por primera vez en esta conversación, abre el selector de
    /// duración para que el usuario elija (en vez de quedarse en el default silencioso de 24h).
    func presentVanishTimerPickerIfFirstActivation() {
        guard !conversationId.isEmpty else { return }
        let key = "chat.vanish.timerPicker.shown.\(conversationId)"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            showVanishTimerSheet = true
        }
    }

    func clearUnreadDividerAndMarkReadIfNeeded(sealsVanish: Bool = true) {
        pendingIncomingMessages = 0
        clearUnreadDividerUI()
        viewModel.markVisibleConversationAsRead(sealsVanish: sealsVanish)
    }

    /// Estilo WhatsApp: el divisor desaparece al responder, no al llegar al fondo.
    func dismissUnreadDividerOnUserReply() {
        guard unreadDividerMessageId != nil || hasUnreadIncomingMessages() else { return }
        ChatScrollDebug.log("unread divider dismissed — user replied")
        clearUnreadDividerAndMarkReadIfNeeded(sealsVanish: false)
    }

    /// Marca leído al salir del hilo (estilo WhatsApp: no depende de llegar al fondo).
    func markConversationReadOnExit(sealsVanish: Bool = false) {
        ChatScrollDebug.log("markConversationReadOnExit sealsVanish=\(sealsVanish)")
        clearUnreadDividerAndMarkReadIfNeeded(sealsVanish: sealsVanish)
    }

    func shouldOpenAtBottom() -> Bool {
        preferredReactionHighlightMessageId() == nil && !hasUnreadIncomingMessages()
    }

    func onAppearActions() {
        restoreScrollUIState()
        reloadNotificationOpenIntent()
        reconcileScrollStateForCurrentConversation()
        consumeDeferredJumpToMessageIfNeeded()

        if let intent = notificationOpenIntent, !intent.highlightMessageIds.isEmpty {
            hasCompletedInitialScroll = false
            didReapplyFrozenScrollPosition = false
            frozenInitialScrollTarget = nil
            pendingInitialScrollRoute = true
            initialScrollTask?.cancel()
            initialScrollTask = nil
            highlightScrollTask?.cancel()
            highlightScrollTask = nil
            listBottomSnapTask?.cancel()
            listBottomSnapTask = nil
        }

        if !conversationId.isEmpty {
            ChatSessionEngine.shared.activate(conversationId: conversationId)
            cleanupConsumedViewOnceMessagesIfNeeded()
        }

        configureListInitialScrollPolicy()
        syncPendingIncomingMessagesOnOpen()

        setupOnlineStatusObserver()
        refreshOtherParticipantUsername()
        refreshOtherParticipantAvailability()
        checkUserStories()
        installScreenshotObserverIfNeeded()
    }

    func cleanupConsumedViewOnceMessagesIfNeeded() {
        guard !didRunConsumedViewOnceCleanup else { return }
        didRunConsumedViewOnceCleanup = true

        ChatService.shared.cleanupConsumedViewOnceMessages(conversationId: conversationId)
    }

    // ✅ REFACTORIZADO: Acciones al desaparecer
    func onDisappearActions() {
        // Empujar Settings/Perfil no es salir del chat: conservar scroll y sesión activa.
        if showingConversationSettings || showingUserProfile {
            return
        }

        // Al salir del hilo marcamos leído (estilo WhatsApp); no al llegar al fondo.
        markConversationReadOnExit(sealsVanish: false)
        initialScrollTask?.cancel()
        initialScrollTask = nil
        highlightScrollTask?.cancel()
        highlightScrollTask = nil
        listBottomSnapTask?.cancel()
        listBottomSnapTask = nil
        composerSnapTask?.cancel()
        composerSnapTask = nil
        didHydrateScrollStateOnce = false
        hasCompletedInitialScroll = false
        didReapplyFrozenScrollPosition = false
        buzzToastDismissTask?.cancel()
        buzzToastDismissTask = nil
        buzzToastText = nil

        if !conversationId.isEmpty {
            let pendingReplays = ViewOnceReplaySessionStore.shared.drainAvailable(conversationId: conversationId)
            pendingReplays.forEach { pending in
                ViewOnceConsumptionService.shared.consume(
                    conversationId: pending.conversationId,
                    messageId: pending.messageId,
                    reason: .abandonReplay
                ) { error in
                    if let error {
                        LogConfig.log("Pending replay consume failed: \(error.localizedDescription)", category: "Chat")
                    }
                }
            }
            ChatSessionEngine.shared.deactivate(conversationId: conversationId)
        }

        viewModel.handleChatDismissedForVanishMode()
        removeScreenshotObserverIfNeeded()

        statusListener?.remove()
    }

    // ✅ ACTUALIZADO: Función para verificar historias del usuario (con filtrado de privacidad como en reels)
    func checkUserStories() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        let otherUserId = viewModel.conversation.otherParticipantId
        guard !otherUserId.isEmpty else { return }

        StoryRingResolverService.shared.resolve(
            viewerId: currentUserId,
            authorId: otherUserId,
            privacyService: privacyService
        ) { snapshot in
            self.hasStory = snapshot.hasStory
            self.hasUnseenStory = snapshot.hasUnseenStory
            self.storyCount = snapshot.storyCount
            self.storyViewedStatus = snapshot.storyViewedStatus
            self.storyAudiences = snapshot.storyAudiences
        }
    }

}
