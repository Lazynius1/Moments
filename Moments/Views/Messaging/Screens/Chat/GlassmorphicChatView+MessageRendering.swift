import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Kingfisher
import AVKit
import AVFoundation
import CoreLocation
import MapKit

extension GlassmorphicChatView {
    @ViewBuilder
    func chatRenderRow(_ row: ChatRenderRow, index: Int, proxy: ScrollViewProxy?) -> some View {
        switch row {
        case .conversationIntro(let context):
            ChatConversationIntroRow(
                context: context,
                fallbackName: otherParticipantDisplayName,
                fallbackUserId: viewModel.conversation.otherParticipantId,
                adaptiveColors: adaptiveColors
            )
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 8)
            .chatMenuDimmedWhenOpen(messageMenuSelection != nil)
        case .requestDisclaimer(let context):
            ChatRequestDisclaimerRow(
                textKey: context == nil ? "chat.intro.disclaimer.normal" : pendingChatDisclaimerKey,
                adaptiveColors: adaptiveColors
            )
            .padding(.horizontal, 18)
            .padding(.vertical, 6)
            .chatMenuDimmedWhenOpen(messageMenuSelection != nil)
        case .pendingRequestMessage(let message):
            ChatMessageRowChrome(
                isOutgoing: message.isOutgoing,
                colorScheme: colorScheme
            ) {
                PendingRequestNormalMessageRow(
                    pendingMessage: message,
                    conversationId: pendingRequestThreadId
                        ?? pendingChatContext?.request?.id
                        ?? "pending:\(pendingChatContext?.otherUserId ?? "unknown")",
                    currentUserId: viewModel.currentUserId,
                    otherParticipantId: pendingChatContext?.otherUserId,
                    otherParticipantName: pendingChatContext?.otherUsername ?? otherParticipantDisplayName,
                    isOtherParticipantUnavailable: isOtherParticipantUnavailable,
                    showAvatar: shouldShowPendingRequestAvatar(for: message),
                    groupPosition: pendingRequestGroupPosition(for: message),
                    timestampRevealState: chatListController.timestampRevealState,
                    onAvatarTap: { openOtherParticipantProfile() },
                    onOpenMedia: { _ in openPendingRequestMedia(message) },
                    onMomentNavigation: { handleMomentNavigationFromChat(message: $0) },
                    onStoryNavigation: { handleStoryNavigationFromChat(message: $0) },
                    momentZoomNamespace: momentZoomNamespace
                )
            }
            .chatMenuDimmedWhenOpen(messageMenuSelection != nil)
        case .incomingRequestActions(let isLoading):
            IncomingRequestBottomDock(
                disclaimerTextKey: pendingChatDisclaimerKey,
                adaptiveColors: adaptiveColors,
                isLoading: isLoading,
                onAccept: { acceptPendingMessageRequest() },
                onDelete: deletePendingMessageRequest,
                onBlock: blockPendingMessageRequest,
                onReport: { showingReportSheet = true }
            )
            .padding(.bottom, 8)
            .chatMenuDimmedWhenOpen(messageMenuSelection != nil)
        case .outgoingRequestControls(let messageCount, let limitReached):
            if limitReached {
                PendingRequestSentInputBar(
                    limitReached: true,
                    onCancel: cancelPendingMessageRequest
                )
                .chatMenuDimmedWhenOpen(messageMenuSelection != nil)
            } else if let context = pendingChatContext {
                ChatRequestInviteNotice(
                    displayName: context.otherUsername,
                    username: context.otherUsername,
                    messageCount: messageCount,
                    adaptiveColors: adaptiveColors
                )
                .chatMenuDimmedWhenOpen(messageMenuSelection != nil)
            }
        case .header(let date):
            GlassmorphicDateHeader(date: date)
                .padding(.vertical, 10)
                .chatMenuDimmedWhenOpen(messageMenuSelection != nil)
                .transition(.identity)
        case .message(let item):
            if shouldShowUnreadDivider(before: item) {
                GlassmorphicUnreadDivider(unreadCount: unreadDividerCount)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 6)
                    .chatMenuDimmedWhenOpen(messageMenuSelection != nil)
                    .transition(.identity)
            }

            renderMessageItem(item, in: viewModel.messages, proxy: proxy)
                .transition(.identity)
        case .buzz(let event):
            ChatBuzzTimelineEventRow(
                text: buzzTimelineText(for: event),
                isOutgoing: event.senderId == viewModel.currentUserId
            )
            .id("buzz-\(event.id)")
            .chatMenuDimmedWhenOpen(messageMenuSelection != nil)
            .transition(.identity)
        case .typing:
            ChatIncomingTypingIndicatorRow()
                .chatMenuDimmedWhenOpen(messageMenuSelection != nil)
        case .historyStart:
            ChatHistoryStartHeader(adaptiveColors: adaptiveColors)
                .chatMenuDimmedWhenOpen(messageMenuSelection != nil)
        }
    }

    func isOutgoingItem(_ item: MessageItem) -> Bool {
        switch item {
        case .single(let message):
            return message.senderId == viewModel.currentUserId
        case .mediaCluster(let messages):
            return messages.first?.senderId == viewModel.currentUserId
        }
    }

    func pendingRequestGroupPosition(for message: PendingChatTimelineMessage) -> ChatMessageGroupPosition {
        let messages = pendingChatTimelineMessages
        guard let index = messages.firstIndex(where: { $0.id == message.id }) else { return .single }
        let previousMatches = index > 0 && messages[index - 1].isOutgoing == message.isOutgoing
        let nextMatches = index < messages.count - 1 && messages[index + 1].isOutgoing == message.isOutgoing

        switch (previousMatches, nextMatches) {
        case (false, false): return .single
        case (false, true): return .first
        case (true, true): return .middle
        case (true, false): return .last
        }
    }

    func shouldShowPendingRequestAvatar(for message: PendingChatTimelineMessage) -> Bool {
        guard !message.isOutgoing else { return false }
        let messages = pendingChatTimelineMessages
        guard let index = messages.firstIndex(where: { $0.id == message.id }) else { return true }
        return index == messages.count - 1 || messages[index + 1].isOutgoing != message.isOutgoing
    }

    var chatRootContent: some View {
        GeometryReader { proxy in
            ZStack {
                adaptiveColors.chatBackground[0]
                    .ignoresSafeArea()
                ChatGlassmorphicBackground(adaptiveColors: adaptiveColors)
                mainChatStack()
                    .modifier(ChatBuzzShakeEffect(
                        progress: buzzShakeProgress,
                        amplitude: reduceMotion ? 0 : buzzShakeAmplitude
                    ))

                if let buzzToastText {
                    VStack {
                        ChatBuzzToast(text: buzzToastText)
                            .padding(.top, 10)
                        Spacer()
                    }
                    .padding(.horizontal, 18)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(45)
                }

                ChatMessageContextMenuOverlay(
                    selection: $messageMenuSelection,
                    containerSize: proxy.size,
                    containerFrameInGlobal: proxy.frame(in: .global),
                    safeAreaInsets: proxy.safeAreaInsets,
                    colorScheme: colorScheme,
                    currentUserId: viewModel.currentUserId,
                    forwardingPreferences: viewModel.forwardingPreferences,
                    onDeleteForEveryone: { message in
                        viewModel.deleteMessageForEveryone(message)
                    },
                    onDeleteForMe: { message in
                        viewModel.deleteMessageForMe(message)
                    },
                    onEdit: { message in
                        replyingTo = nil
                        editingMessage = message
                        messageText = message.content ?? ""
                        isTextFieldFocused = true
                    },
                    onReply: { message in
                        activateReply(to: message)
                    },
                    onCopy: { message in
                        UIPasteboard.general.string = message.content
                    },
                    onForward: { message in
                        forwardingMessage = message
                    },
                    onToggleStar: { message in
                        viewModel.toggleStar(for: message)
                    },
                    onReaction: { message, emoji in
                        viewModel.addReaction(to: message, emoji: emoji)
                        pulseBubbleHighlight(message.id)
                    },
                    onMoreReactions: { message in
                        reactionPickerMessage = message
                        showingReactionEmojiPicker = true
                    },
                    onOpenMessage: { message, cluster in
                        openChatMessageBody(message, cluster: cluster)
                    }
                )
                .allowsHitTesting(messageMenuSelection != nil)
                .zIndex(50)
            }
        }
        .ignoresSafeArea(.container, edges: .bottom)
    }

    func mainChatStack() -> some View {
        let composerBottomInset = ChatComposerChromeMetrics.panelBottomGap(
            keyboardVisible: keyboardScrollCoordinator.isVisible
        )

        return messagesListSection
            .environment(\.chatFailedMessageRetryAction, ChatFailedMessageRetryAction(
                canRetry: { viewModel.canRetryMessage($0) },
                retry: { viewModel.retryFailedMessage($0) }
            ))
            .chatBottomScrollEdgeHidden()
            .ignoresSafeArea(.container, edges: .bottom)
            .overlay(alignment: .bottom) {
                ChatBottomWallpaperEdgeFade(
                    color: adaptiveColors.chatBackground[0],
                    composerChromeHeight: max(lastComposerHeight, 0)
                )
            }
            .chatBottomBarInset {
                inputBarSection
                    .chatMenuDimmedWhenOpen(messageMenuSelection != nil)
                .padding(.bottom, composerBottomInset)
                .opacity(isSearchVisible ? 0 : 1)
                .allowsHitTesting(!isSearchVisible)
                .accessibilityHidden(isSearchVisible)
                .chatComposerHeightReporting()
                .onChatComposerHeightChange { height in
                    handleComposerHeightChangeInList(height)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                ZStack(alignment: .bottomTrailing) {
                    if floatingNavigationState.isVisible {
                        ChatFloatingNavigationOverlay(
                            state: floatingNavigationState,
                            counterText: searchCounterText,
                            isSearching: viewModel.isSearchingHistory,
                            canSearchGoUp: canSearchGoUp,
                            canSearchGoDown: canSearchGoDown,
                            pendingIncomingCount: pendingIncomingMessages,
                            accentColor: scrollToBottomAccentColor,
                            badgeTextColor: scrollToBottomBadgeTextColor,
                            colorScheme: colorScheme,
                            reduceMotion: reduceMotion,
                            onSearchPrevious: { moveSearchSelection(by: -1) },
                            onSearchNext: advanceSearchSelection,
                            onScrollToBottom: { scrollToBottomFromUserAction(animated: true) }
                        )
                        .padding(.trailing, 8)
                        .padding(.bottom, floatingNavigationBottomInset + 20)
                    }

                    VoiceRecordingFloatingControlHost(
                        isRecording: isRecordingVoice,
                        isLocked: isVoiceRecordingLocked,
                        isPreparing: isPreparingVoiceRecordingPreview,
                        hasDraft: voiceRecordingDraft != nil,
                        hasActiveInteraction: voiceRecordingInteractionId != nil,
                        gestureState: voiceRecordingGestureState,
                        primaryTint: adaptiveColors.primary,
                        accentTint: adaptiveColors.accent,
                        onPause: pauseVoiceRecording,
                        onResume: resumeVoiceRecording
                    )
                    .padding(.trailing, 16)
                    .padding(.bottom, ChatComposerChromeMetrics.floatingControlBottomInset(composerChromeHeight: lastComposerHeight) + 20)
                    .zIndex(100)
                }
            }
    }
}
