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
            PendingRequestMessageRow(
                message: message,
                adaptiveColors: adaptiveColors
            )
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .chatMenuDimmedWhenOpen(messageMenuSelection != nil)
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
            GlassmorphicTypingIndicator()
                .padding(.horizontal)
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity, alignment: .center)
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

    // ✅ REFACTORIZADO: Sección de barra de respuesta o edición
    var replyBarSection: some View {
        VStack(spacing: 0) {
            if let replyingTo = replyingTo {
                GlassmorphicReplyBar(
                    message: replyingTo,
                    otherParticipantName: otherParticipantDisplayName
                ) {
                    self.replyingTo = nil
                }
            }

            if editingMessage != nil {
                HStack {
                    Image(systemName: "pencil")
                        .foregroundStyle(adaptiveColors.primary)
                    Text("chat.editing.title")
                        .font(.system(size: legacyPoppinsSize(14), weight: .medium))
                        .foregroundStyle(adaptiveColors.primary)
                    Spacer()
                    Button(action: {
                        self.editingMessage = nil
                        self.messageText = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(adaptiveColors.primary.opacity(0.6))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial.opacity(0.5))
            }
        }
    }

    var chatRootContent: some View {
        ZStack {
            ChatGlassmorphicBackground(adaptiveColors: adaptiveColors)
            mainChatStack
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

            GeometryReader { proxy in
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
                        editingMessage = message
                        messageText = message.content ?? ""
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
                    }
                )
            }
            .allowsHitTesting(messageMenuSelection != nil)
            .zIndex(50)
        }
    }

    var mainChatStack: some View {
        messagesListSection
            .chatScrollEdgeEffect(hardBottomEdge: true)
            .environment(\.chatFailedMessageRetryAction, ChatFailedMessageRetryAction(
                canRetry: { viewModel.canRetryMessage($0) },
                retry: { viewModel.retryFailedMessage($0) }
            ))
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
                        .padding(.trailing, 14)
                        .padding(.bottom, floatingNavigationBottomInset)
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
                    .padding(.bottom, max(lastComposerHeight, 0) + 40)
                    .zIndex(100)
                }
            }
            .chatBottomBarInset {
                VStack(spacing: 0) {
                    replyBarSection
                        .chatMenuDimmedWhenOpen(messageMenuSelection != nil)
                    inputBarSection
                        .chatMenuDimmedWhenOpen(messageMenuSelection != nil)
                }
                .opacity(isSearchVisible ? 0 : 1)
                .allowsHitTesting(!isSearchVisible)
                .accessibilityHidden(isSearchVisible)
                .chatComposerHeightReporting()
                .onChatComposerHeightChange { height in
                    handleComposerHeightChangeInList(height)
                }
                .background {
                    adaptiveColors.chatBackground[0]
                        .ignoresSafeArea(edges: .bottom)
                }
            }
    }
}
