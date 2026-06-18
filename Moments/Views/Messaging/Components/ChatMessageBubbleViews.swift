import SwiftUI
import FirebaseAuth

// MARK: - Glassmorphic Message Row
struct GlassmorphicMessageRow: View {
    @ObservedObject var message: EnhancedMessage
    let isCurrentUser: Bool
    let showAvatar: Bool
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

    @State private var dragOffset: CGFloat = 0
    @State private var hasTriggeredHaptic = false

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

            HStack(alignment: .bottom, spacing: 8) {
                if !isCurrentUser {
                    if showAvatar {
                        Button(action: onAvatarTap) {
                            if isOtherParticipantUnavailable {
                                ProfileUnavailableAvatar(size: 32)
                            } else {
                                GlassmorphicAvatar(userId: otherUserId ?? "")
                                    .frame(width: 32, height: 32)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    } else {
                        Color.clear.frame(width: 32, height: 32)
                    }
                }

                if isCurrentUser { Spacer(minLength: 50) }

                VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 4) {
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

                    ZStack(alignment: isCurrentUser ? .bottomLeading : .bottomTrailing) {
                        GlassmorphicMessageBubble(
                            message: message,
                            repliedMessage: repliedMessage,
                            otherParticipantId: otherUserId,
                            otherParticipantName: otherParticipantName,
                            isCurrentUser: isCurrentUser,
                            progress: progress,
                            onReplyTap: onReplyTap,
                            onMessageViewed: onMessageViewed,
                            onMomentNavigation: onMomentNavigation,
                            onStoryNavigation: onStoryNavigation,
                            onOpenMedia: onOpenMedia,
                            onStopLiveLocation: onStopLiveLocation,
                            onHydrateMedia: onHydrateMedia
                        )

                        if let reactions = message.reactions, !reactions.isEmpty {
                            GlassmorphicReactionsView(
                                reactions: reactions,
                                onTap: onReaction
                            )
                            .offset(x: isCurrentUser ? -6 : 6, y: 10)
                            .zIndex(2)
                        }
                    }
                    .padding(.bottom, (message.reactions?.isEmpty == false) ? 6 : 0)

                    MessageTimestamp(
                        message: message,
                        isCurrentUser: isCurrentUser,
                        showSeenLabel: showSeenLabel
                    )
                }

                if !isCurrentUser { Spacer(minLength: 50) }
            }
            .offset(x: dragOffset)
            .contentShape(Rectangle())
            .chatReplySwipeGesture(
                dragOffset: $dragOffset,
                hasTriggeredHaptic: $hasTriggeredHaptic,
                onReply: onReply
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
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
    let repliedMessage: EnhancedMessage?
    let otherParticipantId: String?
    let otherParticipantName: String
    let isCurrentUser: Bool
    let progress: Double?
    let onReplyTap: ((String) -> Void)?
    let onMessageViewed: ((String) -> Void)?
    let onMomentNavigation: ((EnhancedMessage) -> Void)?
    let onStoryNavigation: ((EnhancedMessage) -> Void)?
    let onOpenMedia: (EnhancedMessage) -> Void
    let onStopLiveLocation: ((String) -> Void)?
    let onHydrateMedia: ((EnhancedMessage) -> Void)?
    @State private var showEphemeralImage: Bool = false
    @Environment(\.colorScheme) var colorScheme

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
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
                                otherParticipantId: otherParticipantId
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

                                HStack(alignment: .bottom, spacing: 12) {
                                    if isCurrentUser {
                                        Text(content)
                                            .font(.custom("Poppins-Regular", size: 15))
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .foregroundColor(adaptiveColors.messageTextColor)
                                            .background(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .fill(.ultraThinMaterial.opacity(0.3))
                                            )

                                        Capsule()
                                            .fill(adaptiveColors.userAccentColor)
                                            .frame(width: 3, height: 20)
                                            .padding(.bottom, 6)
                                    } else {
                                        Capsule()
                                            .fill(adaptiveColors.receivedAccentColor)
                                            .frame(width: 3, height: 20)
                                            .padding(.bottom, 6)

                                        Text(content)
                                            .font(.custom("Poppins-Regular", size: 15))
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .foregroundColor(adaptiveColors.messageTextColor)
                                            .background(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .fill(.ultraThinMaterial.opacity(0.3))
                                            )
                                    }
                                }
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
                        .onAppear {
                            onHydrateMedia?(message)
                        }

                    case .ephemeral:
                        if message.storyReplyData != nil {
                            StoryReplyMessageBubble(
                                message: message,
                                isCurrentUser: isCurrentUser,
                                otherParticipantId: otherParticipantId
                            )
                        } else {
                            if let mediaUrl = message.mediaUrl, !message.isViewed, isEphemeralValid() {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(adaptiveColors.messageBubbleBackground)
                                        .frame(maxWidth: 250, maxHeight: 300)
                                        .overlay(
                                            VStack(spacing: 8) {
                                                AttachmentIconView(icon: .ephemeral, preset: .chatEphemeralPlaceholder, tintColor: adaptiveColors.messageTextColor.opacity(0.7))

                                                Text("chat.tapToView")
                                                    .font(.custom("Poppins-Medium", size: 14))
                                                    .foregroundColor(adaptiveColors.messageTextColor)

                                                Text("chat.ephemeral.title")
                                                    .font(.custom("Poppins-Regular", size: 12))
                                                    .foregroundColor(adaptiveColors.messageTextColor.opacity(0.7))
                                            }
                                        )

                                    if showEphemeralImage {
                                        GlassmorphicImageMessage(
                                            imageUrl: mediaUrl,
                                            isSending: false,
                                            progress: nil,
                                            onTap: {}
                                        )
                                    }
                                }
                                .onTapGesture {
                                    showEphemeralImage = true
                                    markAsViewed()
                                }
                            } else if let content = message.content {
                                Text(content)
                                    .font(.custom("Poppins-Regular", size: 15))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .foregroundColor(adaptiveColors.messageTextColor.opacity(0.6))
                                    .background(
                                        RoundedRectangle(cornerRadius: 20)
                                            .fill(adaptiveColors.messageBubbleBackground)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 20)
                                                    .stroke(adaptiveColors.messageBubbleStroke, lineWidth: 0.5)
                                            )
                                    )
                            } else {
                                Text("chat.message.expired")
                                    .font(.custom("Poppins-Regular", size: 15))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .foregroundColor(adaptiveColors.messageTextColor.opacity(0.6))
                                    .background(
                                        RoundedRectangle(cornerRadius: 20)
                                            .fill(adaptiveColors.messageBubbleBackground)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 20)
                                                    .stroke(adaptiveColors.messageBubbleStroke, lineWidth: 0.5)
                                            )
                                    )
                            }
                        }
                    case .sharedMoment:
                        HStack(alignment: .bottom, spacing: 12) {
                            if isCurrentUser {
                                SharedMomentMessageBubble(
                                    message: message,
                                    isCurrentUser: isCurrentUser,
                                    onTap: {
                                        onMomentNavigation?(message)
                                    }
                                )

                                Capsule()
                                    .fill(adaptiveColors.userAccentColor)
                                    .frame(width: 3, height: 20)
                                    .padding(.bottom, 6)
                            } else {
                                Capsule()
                                    .fill(adaptiveColors.receivedAccentColor)
                                    .frame(width: 3, height: 20)
                                    .padding(.bottom, 6)

                                SharedMomentMessageBubble(
                                    message: message,
                                    isCurrentUser: isCurrentUser,
                                    onTap: {
                                        onMomentNavigation?(message)
                                    }
                                )
                            }
                        }
                        .onAppear {
                        }

                    case .sharedStory:
                        HStack(alignment: .bottom, spacing: 12) {
                            if isCurrentUser {
                                SharedStoryMessageBubble(
                                    message: message,
                                    isCurrentUser: isCurrentUser,
                                    onTap: {
                                        onStoryNavigation?(message)
                                    }
                                )

                                Capsule()
                                    .fill(adaptiveColors.userAccentColor)
                                    .frame(width: 3, height: 20)
                                    .padding(.bottom, 6)
                            } else {
                                Capsule()
                                    .fill(adaptiveColors.receivedAccentColor)
                                    .frame(width: 3, height: 20)
                                    .padding(.bottom, 6)

                                SharedStoryMessageBubble(
                                    message: message,
                                    isCurrentUser: isCurrentUser,
                                    onTap: {
                                        onStoryNavigation?(message)
                                    }
                                )
                            }
                        }

                    case .gif:
                        ChatGifMessageBubble(
                            message: message,
                            progress: progress
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

    private func isEphemeralValid() -> Bool {
        guard let expirationDate = message.expirationDate else { return true }
        return Date() < expirationDate
    }

    private func markAsViewed() {
        ChatService().markEphemeralAsViewed(conversationId: message.conversationId, messageId: message.id) { _ in
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
