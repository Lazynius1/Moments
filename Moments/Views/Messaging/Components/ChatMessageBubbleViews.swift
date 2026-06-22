import SwiftUI
import FirebaseAuth

// MARK: - Glassmorphic Message Row
struct GlassmorphicMessageRow: View {
    @ObservedObject var message: EnhancedMessage
    let displayReactions: [String: [String]]?
    let isCurrentUser: Bool
    let showAvatar: Bool
    var groupPosition: ChatMessageGroupPosition = .single
    let otherUserId: String?
    let isOtherParticipantUnavailable: Bool
    let otherParticipantName: String
    let repliedMessage: EnhancedMessage?
    let onReply: () -> Void
    let onReaction: (String) -> Void
    let onAvatarTap: () -> Void
    let onReplyTap: ((String) -> Void)?
    let onMessageViewed: ((String) -> Void)?
    let onMomentNavigation: ((EnhancedMessage) -> Void)?
    let onStoryNavigation: ((EnhancedMessage) -> Void)?
    let onOpenMedia: (EnhancedMessage) -> Void
    let onStopLiveLocation: ((String) -> Void)?
    let onHydrateMedia: ((EnhancedMessage) -> Void)?
    let progress: Double?
    var showSeenLabel: Bool = false

    @Environment(\.colorScheme) var colorScheme
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    private var resolvedReactions: [String: [String]]? {
        displayReactions ?? message.reactions
    }

    private var hasReactions: Bool {
        resolvedReactions.map { !$0.isEmpty } ?? false
    }

    private var reactionTimestampSpacing: CGFloat {
        hasReactions ? 6 : 4
    }

    private var bottomRowPadding: CGFloat {
        let base = isGroupTail ? 5.0 : 1.0
        guard hasReactions else { return base }
        return base + (isGroupTail ? 8 : 4)
    }

    @State private var dragOffset: CGFloat = 0
    @State private var hasTriggeredHaptic = false

    private var isGroupTail: Bool {
        groupPosition == .last || groupPosition == .single
    }

    private var isGroupHead: Bool {
        groupPosition == .first || groupPosition == .single
    }

    private var timestampLeadingInset: CGFloat {
        isCurrentUser ? 0 : ChatIncomingMessageLayout.gutterInset
    }

    var body: some View {
        ZStack(alignment: .leading) {
            // Background Reply Icon (appears when swiping)
            if dragOffset > 0 {
                Image(systemName: "arrowshape.turn.up.left.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(adaptiveColors.userAccentColor)
                    .opacity(Double(min(dragOffset / 60, 1.0)))
                    .offset(x: min(dragOffset - 30, 0))
                    .padding(.leading, 12)
            }

            VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 2) {
                HStack(alignment: .bottom, spacing: 0) {
                    if isCurrentUser { Spacer(minLength: 50) }

                    if !isCurrentUser {
                        ChatIncomingAvatarGutter(
                            showAvatar: showAvatar,
                            otherUserId: otherUserId,
                            isUnavailable: isOtherParticipantUnavailable,
                            onTap: onAvatarTap
                        )
                    }

                    VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: reactionTimestampSpacing) {
                        if let originalMessage = repliedMessage {
                            GlassmorphicReplyPreview(
                                message: originalMessage,
                                isParentMessageFromCurrentUser: isCurrentUser,
                                otherParticipantName: otherParticipantName,
                                onTap: { onReplyTap?(originalMessage.id) }
                            )
                            .padding(.bottom, -8)
                            .zIndex(1)
                        }

                        messageBubbleWithReactions(
                            repliedMessage: repliedMessage,
                            otherParticipantId: otherUserId,
                            otherParticipantName: otherParticipantName
                        )
                    }

                    if !isCurrentUser { Spacer(minLength: 50) }
                }

                if isGroupTail {
                    MessageTimestamp(
                        message: message,
                        isCurrentUser: isCurrentUser,
                        showSeenLabel: showSeenLabel
                    )
                    .padding(.leading, timestampLeadingInset)
                }
            }
            .offset(x: dragOffset)
            .contentShape(Rectangle())
            .chatReplySwipeGesture(
                dragOffset: $dragOffset,
                hasTriggeredHaptic: $hasTriggeredHaptic,
                onReply: onReply
            )
        }
        .padding(.horizontal, 8)
        .padding(.top, isGroupHead ? 5 : 1)
        .padding(.bottom, bottomRowPadding)
    }

    @ViewBuilder
    private func messageBubbleWithReactions(
        repliedMessage: EnhancedMessage?,
        otherParticipantId: String?,
        otherParticipantName: String
    ) -> some View {
        let bubble = GlassmorphicMessageBubble(
            message: message,
            reactions: resolvedReactions,
            onReaction: onReaction,
            repliedMessage: repliedMessage,
            otherParticipantId: otherParticipantId,
            otherParticipantName: otherParticipantName,
            isCurrentUser: isCurrentUser,
            groupPosition: groupPosition,
            progress: progress,
            onReplyTap: onReplyTap,
            onMessageViewed: onMessageViewed,
            onMomentNavigation: onMomentNavigation,
            onStoryNavigation: onStoryNavigation,
            onOpenMedia: onOpenMedia,
            onStopLiveLocation: onStopLiveLocation,
            onHydrateMedia: onHydrateMedia
        )

        bubble
    }
}

// MARK: - Componente para Mensajes Eliminados
struct DeletedMessageBubble: View {
    let message: EnhancedMessage
    let isCurrentUser: Bool
    @Environment(\.colorScheme) var colorScheme

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: getDeletedIcon())
                .font(.system(size: 16))
                .foregroundColor(adaptiveColors.messageTextColor.opacity(0.5))

            Text(getDeletedText())
                .font(.custom("Poppins-Regular", size: 14))
                .foregroundColor(adaptiveColors.messageTextColor.opacity(0.6))
                .italic()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(adaptiveColors.messageBubbleBackground.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(adaptiveColors.messageBubbleStroke, lineWidth: 0.5)
                )
        )
    }

    private func getDeletedIcon() -> String {
        switch message.type {
        case .audio:
            return "mic.slash"
        case .image:
            return "photo"
        case .video:
            return "video.slash"
        case .text:
            return "text.quote"
        case .file:
            return "doc.slash"
        case .location:
            return "location.slash"
        default:
            return "trash"
        }
    }

    private func getDeletedText() -> String {
        switch message.type {
        case .audio:
            return NSLocalizedString("chat.deleted.audio", comment: "Deleted audio message")
        case .image:
            return NSLocalizedString("chat.deleted.image", comment: "Deleted image message")
        case .video:
            return NSLocalizedString("chat.deleted.video", comment: "Deleted video message")
        case .text:
            return NSLocalizedString("chat.deleted.text", comment: "Deleted text message")
        case .file:
            return NSLocalizedString("chat.deleted.file", comment: "Deleted file message")
        case .location:
            return NSLocalizedString("chat.deleted.location", comment: "Deleted location message")
        case .ephemeral:
            return NSLocalizedString("chat.deleted.ephemeral", comment: "Deleted ephemeral moment")
        default:
            return NSLocalizedString("chat.deleted.text", comment: "Deleted text message")
        }
    }
}

// MARK: - Updated Glassmorphic Message Bubble
struct GlassmorphicMessageBubble: View {
    @ObservedObject var message: EnhancedMessage
    let reactions: [String: [String]]?
    let onReaction: (String) -> Void
    let repliedMessage: EnhancedMessage?
    let otherParticipantId: String?
    let otherParticipantName: String
    let isCurrentUser: Bool
    var groupPosition: ChatMessageGroupPosition = .single
    let progress: Double?
    let onReplyTap: ((String) -> Void)?
    let onMessageViewed: ((String) -> Void)?
    let onMomentNavigation: ((EnhancedMessage) -> Void)?
    let onStoryNavigation: ((EnhancedMessage) -> Void)?
    let onOpenMedia: (EnhancedMessage) -> Void
    let onStopLiveLocation: ((String) -> Void)?
    let onHydrateMedia: ((EnhancedMessage) -> Void)?
    @Environment(\.colorScheme) var colorScheme

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    @ViewBuilder
    private func textMessageBody(_ content: String) -> some View {
        ChatTextBubbleView(
            text: content,
            isOutgoing: isCurrentUser,
            groupPosition: groupPosition,
            reactions: reactions,
            onReaction: onReaction
        )
    }

    var body: some View {
        Group {
            if message.isDeleted {
                DeletedMessageBubble(message: message, isCurrentUser: isCurrentUser)
            } else {
                if message.type == .viewOnceImage || message.type == .viewOnceVideo {
                    ViewOnceMessageBubble(
                        message: message,
                        isCurrentUser: isCurrentUser,
                        otherParticipantName: otherParticipantName,
                        progress: progress,
                        onViewed: {
                            markViewOnceAsViewed()
                        }
                    )
                    .onAppear {
                    }
                } else {
                    switch message.type {
                    case .text:
                        if message.storyReplyData != nil {
                            StoryReplyMessageBubble(
                                message: message,
                                isCurrentUser: isCurrentUser,
                                otherParticipantId: otherParticipantId,
                                onHydrateMedia: onHydrateMedia,
                                onOpenMedia: onOpenMedia
                            )
                        } else if let content = message.content {
                            VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 4) {
                                if message.isForwarded == true {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrowshape.turn.up.right")
                                            .font(.system(size: 10, weight: .semibold))
                                        Text("chat.forwarded")
                                    }
                                    .font(.custom("Poppins-Regular", size: 11))
                                    .foregroundColor(adaptiveColors.messageTextColor.opacity(0.55))
                                }

                                textMessageBody(content)
                            }
                            .overlay(alignment: isCurrentUser ? .topLeading : .topTrailing) {
                                if let userId = Auth.auth().currentUser?.uid, message.isStarred(by: userId) {
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(Color(hex: "FFD60A"))
                                        .offset(x: isCurrentUser ? -6 : 6, y: -6)
                                }
                            }
                        }

                    case .image:
                        GlassmorphicImageMessage(
                            imageUrl: message.mediaUrl,
                            isSending: message.status == .sending,
                            isResolvingMedia: message.isMediaPendingResolution,
                            downsamplingSize: CGSize(width: 208, height: 272),
                            progress: progress,
                            onTap: {
                                onOpenMedia(message)
                            }
                        )
                        .frame(width: 208, height: 272)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .messageReactionOverlay(
                            isOutgoing: isCurrentUser,
                            reactions: reactions,
                            onTap: onReaction
                        )
                        .onAppear {
                            onHydrateMedia?(message)
                        }

                    case .audio:
                        GlassmorphicAudioMessage(
                            audioUrl: message.mediaUrl,
                            duration: message.duration ?? 0,
                            isCurrentUser: isCurrentUser,
                            isSending: message.status == .sending,
                            progress: progress,
                            adaptiveColors: adaptiveColors
                        )
                        .onAppear {
                        }

                    case .video:
                        GlassmorphicVideoMessage(
                            videoUrl: message.mediaUrl,
                            thumbnailUrl: message.thumbnailUrl,
                            isSending: message.status == .sending,
                            isResolvingMedia: message.isMediaPendingResolution,
                            downsamplingSize: CGSize(width: 208, height: 272),
                            progress: progress,
                            onTap: {
                                onOpenMedia(message)
                            }
                        )
                        .frame(width: 208, height: 272)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .messageReactionOverlay(
                            isOutgoing: isCurrentUser,
                            reactions: reactions,
                            onTap: onReaction
                        )
                        .onAppear {
                            onHydrateMedia?(message)
                        }

                    case .ephemeral:
                        if message.storyReplyData != nil {
                            StoryReplyMessageBubble(
                                message: message,
                                isCurrentUser: isCurrentUser,
                                otherParticipantId: otherParticipantId,
                                onHydrateMedia: onHydrateMedia,
                                onOpenMedia: onOpenMedia
                            )
                        } else {
                            ChatEphemeralMessageContent(
                                message: message,
                                layout: .standard,
                                onHydrateMedia: onHydrateMedia,
                                onOpenMedia: onOpenMedia
                            )
                            .messageReactionOverlay(
                                isOutgoing: isCurrentUser,
                                reactions: reactions,
                                onTap: onReaction
                            )
                        }
                    case .sharedMoment:
                        SharedMomentMessageBubble(
                            message: message,
                            isCurrentUser: isCurrentUser,
                            onTap: {
                                onMomentNavigation?(message)
                            }
                        )
                        .onAppear {
                        }

                    case .sharedStory:
                        SharedStoryMessageBubble(
                            message: message,
                            isCurrentUser: isCurrentUser,
                            onTap: {
                                onStoryNavigation?(message)
                            }
                        )

                    case .gif:
                        ChatGifMessageBubble(
                            message: message,
                            progress: progress
                        )
                        .messageReactionOverlay(
                            isOutgoing: isCurrentUser,
                            reactions: reactions,
                            onTap: onReaction
                        )
                        .onAppear {
                            onHydrateMedia?(message)
                        }

                    case .sticker:
                        ChatStickerMessageBubble(
                            message: message,
                            isSending: message.status == .sending,
                            progress: progress
                        )
                        .onAppear {
                            onHydrateMedia?(message)
                        }

                    case .location:
                        ChatLocationMessageBubble(
                            message: message,
                            isCurrentUser: isCurrentUser,
                            accentColor: adaptiveColors.userAccentColor,
                            accentColorRed: adaptiveColors.accentColorRed,
                            onStopLive: {
                                onStopLiveLocation?(message.id)
                            }
                        )
                        .messageReactionOverlay(
                            isOutgoing: isCurrentUser,
                            reactions: reactions,
                            onTap: onReaction
                        )

                    default:
                        Text("chat.message.unsupported")
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .foregroundColor(adaptiveColors.messageTextColor.opacity(0.6))
                            .glassmorphicChat()
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                    }
                }
            }
        }
        .onAppear {
            if !isCurrentUser && !message.isDeleted {
            }
        }
    }

    private func markViewOnceAsViewed() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }

        let messageId = message.id
        let conversationId = message.conversationId
        let callback = onMessageViewed

        ChatService().markViewOnceAsViewed(
            conversationId: conversationId,
            messageId: messageId,
            viewerId: currentUserId
        ) { error in
            if error == nil {
                DispatchQueue.main.async {
                    callback?(messageId)
                }
            }
        }
    }
}
