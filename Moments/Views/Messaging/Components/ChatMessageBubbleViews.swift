import SwiftUI
import FirebaseAuth

// MARK: - Glassmorphic Message Row
struct GlassmorphicMessageRow: View {
    @ObservedObject var message: EnhancedMessage
    let displayReactions: [String: [String]]?
    let isCurrentUser: Bool
    let showAvatar: Bool
    var groupPosition: ChatMessageGroupPosition = .single
    var allowsReplySwipe: Bool = true
    var persistsViewState: Bool = true
    let otherUserId: String?
    let isOtherParticipantUnavailable: Bool
    let otherParticipantName: String
    let repliedMessage: EnhancedMessage?
    var isMenuSelected: Bool = false
    var isBubbleFlashing: Bool = false
    let onReply: () -> Void
    let onReaction: (String) -> Void
    let onAvatarTap: () -> Void
    let onReplyTap: ((String) -> Void)?
    var onDoubleTap: (() -> Void)? = nil
    let onMessageViewed: ((String) -> Void)?
    let onMomentNavigation: ((EnhancedMessage) -> Void)?
    let onStoryNavigation: ((EnhancedMessage) -> Void)?
    var onMentionNavigation: ((String) -> Void)? = nil
    let onOpenMedia: (EnhancedMessage) -> Void
    let onStopLiveLocation: ((String) -> Void)?
    let onHydrateMedia: ((EnhancedMessage) -> Void)?
    let onLongPress: ((ChatMessageLiftSnapshot) -> Void)?
    var onViewOnceOpen: ((EnhancedMessage, Bool) -> Void)? = nil
    var onOpenLocation: ((EnhancedMessage) -> Void)? = nil
    var viewOnceZoomNamespace: Namespace.ID? = nil
    var momentZoomNamespace: Namespace.ID? = nil
    let progress: Double?
    var downloadProgress: Double? = nil
    var isDownloadingMedia: Bool = false
    var showSeenLabel: Bool = false
    @ObservedObject var timestampRevealState: ChatTimestampRevealState

    @Environment(\.colorScheme) var colorScheme
    @Environment(\.chatListContainerWidth) private var chatListContainerWidth
    @Environment(\.chatFailedMessageRetryAction) private var retryAction
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    private var resolvedReactions: [String: [String]]? {
        displayReactions ?? message.reactions
    }

    private var hasReactions: Bool {
        resolvedReactions.map { !$0.isEmpty } ?? false
    }

    private var hasStar: Bool {
        guard let userId = Auth.auth().currentUser?.uid else { return false }
        return message.isStarred(by: userId)
    }

    private var reactionTimestampSpacing: CGFloat {
        hasReactions ? 6 : 4
    }

    private var bottomRowPadding: CGFloat {
        let base = isGroupTail ? 5.0 : 1.0
        guard hasReactions || hasStar else { return base }
        return base + (isGroupTail ? 8 : 4)
    }

    @State private var dragOffset: CGFloat = 0
    @State private var replyHapticStep = 0

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
        let rowWidth = ChatBubbleLayoutWidth.containerWidth(chatListWidth: chatListContainerWidth)

        HStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 0) {
                if isCurrentUser {
                    Spacer(minLength: 48)
                        .contentShape(Rectangle())
                        .chatTimestampRevealGesture(state: timestampRevealState)
                }

                if !isCurrentUser {
                    ChatIncomingAvatarGutter(
                        showAvatar: showAvatar,
                        otherUserId: otherUserId,
                        isUnavailable: isOtherParticipantUnavailable,
                        onTap: onAvatarTap
                    )
                }

                if isCurrentUser,
                   message.status == .failed,
                   let retryAction,
                   retryAction.canRetry(message) {
                    Button {
                        HapticManager.shared.lightImpact()
                        retryAction.retry(message)
                    } label: {
                        Image(systemName: "exclamationmark.arrow.circlepath")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.red)
                            .padding(6)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 2)
                }

                VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: reactionTimestampSpacing) {
                    if let originalMessage = repliedMessage {
                        StackedReplyQuote(
                            repliedMessage: originalMessage,
                            isOutgoingRow: isCurrentUser,
                            otherParticipantName: otherParticipantName,
                            onTap: { onReplyTap?(originalMessage.id) }
                        )
                        // La cita acompaña a la burbuja al deslizar para responder.
                        .offset(x: dragOffset)
                    }

                    VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 0) {
                        incomingTextTranslation { displayedText in
                            messageBubbleWithReactions(
                                displayedText: displayedText,
                                repliedMessage: repliedMessage,
                                otherParticipantId: otherUserId,
                                otherParticipantName: otherParticipantName
                            )
                        }

                        // "Editado" bajo la burbuja para no pisar la cita solapada.
                        if message.editedAt != nil && !message.isDeleted {
                            Text("chat.edited")
                                .font(.system(size: 11))
                                .chatFloatingText(adaptiveColors.timestampColor)
                                .padding(.top, 2)
                                .padding(.horizontal, 12)
                                .offset(x: dragOffset)
                        }
                    }
                }

                if !isCurrentUser {
                    Spacer(minLength: 48)
                }
            }
            .padding(.horizontal, 8)
            .frame(width: rowWidth, alignment: isCurrentUser ? .trailing : .leading)

            MessageTimestamp(
                message: message,
                isCurrentUser: isCurrentUser,
                showSeenLabel: showSeenLabel
            )
            .frame(width: 55)
            .padding(.leading, 12)
            .opacity(Double(min(-timestampRevealState.offset / 40, 1.0)))
        }
        .padding(.trailing, -67)
        .offset(x: timestampRevealState.offset)
        .padding(.top, isGroupHead ? 5 : 1)
        .padding(.bottom, bottomRowPadding)
        .contentShape(Rectangle())
        .chatTimestampRevealGesture(state: timestampRevealState)
    }

    /// Forma real de la burbuja para el flash de "saltar a la cita" (nil = rectángulo redondeado).
    private var flashShape: ChatBubbleShape? {
        let side: ChatBubbleShape.Side = isCurrentUser ? .trailing : .leading
        if message.isDeleted {
            return ChatBubbleShape(side: side, position: groupPosition, cornerRadius: 20)
        }
        switch message.type {
        case .text where message.storyReplyData == nil:
            return ChatBubbleShape(
                side: side,
                position: groupPosition,
                cornerRadius: ChatBubbleAnchorMetrics.scaledTextMetric(ChatTextBubbleMetrics.cornerRadius),
                joinedRadius: ChatBubbleAnchorMetrics.scaledTextMetric(ChatTextBubbleMetrics.joinedRadius)
            )
        case .image, .video, .audio:
            return ChatBubbleShape(
                side: side,
                position: groupPosition,
                cornerRadius: ChatBubbleAnchorMetrics.cornerRadius(for: message)
            )
        default:
            return nil
        }
    }

    /// El flash no debe cubrir el hueco inferior que reservan reacciones/estrella.
    private var flashBottomInset: CGFloat {
        guard !message.isDeleted, hasReactions || hasStar else { return 0 }
        let isCompact = message.type == .text && message.storyReplyData == nil
        return MessageReactionMetrics.reactionRowSpacing(compact: isCompact)
    }

    private var isIncomingTextBubble: Bool {
        !isCurrentUser && !message.isDeleted && message.type == .text && message.storyReplyData == nil
    }

    @ViewBuilder
    private func incomingTextTranslation<Bubble: View>(
        @ViewBuilder bubble: @escaping (String) -> Bubble
    ) -> some View {
        if isIncomingTextBubble, let content = message.content, !content.isEmpty {
            ChatTranslationContainer(text: content, isOutgoing: false, content: bubble)
        } else {
            bubble(message.content ?? "")
        }
    }

    @ViewBuilder
    private func messageBubbleWithReactions(
        displayedText: String,
        repliedMessage: EnhancedMessage?,
        otherParticipantId: String?,
        otherParticipantName: String
    ) -> some View {
        let cornerRadius = ChatBubbleAnchorMetrics.cornerRadius(for: message)
        let isVanishProtected = message.isVanishModeMessage == true
        let bubble = GlassmorphicMessageBubble(
            translatedTextOverride: displayedText,
            message: message,
            reactions: resolvedReactions,
            onReaction: onReaction,
            repliedMessage: repliedMessage,
            otherParticipantId: otherParticipantId,
            otherParticipantName: otherParticipantName,
            isCurrentUser: isCurrentUser,
            groupPosition: groupPosition,
            progress: progress,
            downloadProgress: downloadProgress,
            onReplyTap: onReplyTap,
            onMessageViewed: onMessageViewed,
            onMomentNavigation: onMomentNavigation,
            onStoryNavigation: onStoryNavigation,
            onMentionNavigation: onMentionNavigation,
            onOpenMedia: onOpenMedia,
            onStopLiveLocation: onStopLiveLocation,
            onHydrateMedia: onHydrateMedia,
            isDownloadingMedia: isDownloadingMedia,
            onViewOnceOpen: onViewOnceOpen,
            viewOnceZoomNamespace: viewOnceZoomNamespace,
            momentZoomNamespace: momentZoomNamespace
        )

        ChatBubbleReplySwipeContainer(
            dragOffset: $dragOffset,
            hapticStep: $replyHapticStep,
            isOutgoing: isCurrentUser,
            cornerRadius: cornerRadius,
            isEnabled: allowsReplySwipe && !message.isDeleted,
            onReply: onReply
        ) {
            ChatMessageBubbleChrome(
                isMenuSelected: isMenuSelected,
                isOutgoing: isCurrentUser,
                cornerRadius: cornerRadius,
                colorScheme: colorScheme,
                isFlashing: isBubbleFlashing,
                highlightShape: flashShape,
                highlightBottomInset: flashBottomInset,
                allowsPressScale: !message.isDeleted,
                onTap: ChatMessageBodyOpen.isOpenable(
                    message,
                    isCurrentUser: isCurrentUser,
                    currentUserId: Auth.auth().currentUser?.uid ?? ""
                ) ? { openMessageBody() } : nil,
                onLongPress: onLongPress
            ) {
                if isVanishProtected {
                    ScreenshotProtectedView(isProtected: true, cornerRadius: cornerRadius) {
                        bubble
                    }
                } else {
                    bubble
                }
            }
        }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                onDoubleTap?()
            }
        )
    }

    private func openMessageBody() {
        ChatMessageBodyOpen.open(
            message,
            isCurrentUser: isCurrentUser,
            currentUserId: Auth.auth().currentUser?.uid ?? "",
            onOpenMedia: onOpenMedia,
            onMomentNavigation: onMomentNavigation,
            onStoryNavigation: onStoryNavigation,
            onViewOnceOpen: onViewOnceOpen,
            onOpenLocation: onOpenLocation,
            onHydrateMedia: onHydrateMedia,
            onMessageViewed: onMessageViewed,
            persistsViewState: persistsViewState
        )
    }
}
struct DeletedMessageBubble: View {
    let message: EnhancedMessage
    let isCurrentUser: Bool
    var groupPosition: ChatMessageGroupPosition = .single
    @Environment(\.colorScheme) var colorScheme

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    private var bubbleShape: ChatBubbleShape {
        ChatBubbleShape(
            side: isCurrentUser ? .trailing : .leading,
            position: groupPosition,
            cornerRadius: 20,
            joinedRadius: ChatTextBubbleMetrics.joinedRadius
        )
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: getDeletedIcon())
                .font(.system(size: 16))
                .foregroundStyle(adaptiveColors.messageTextColor.opacity(0.5))

            Text(getDeletedText())
                .font(.system(size: legacyPoppinsSize(14)))
                .foregroundStyle(adaptiveColors.messageTextColor.opacity(0.6))
                .italic()
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .fixedSize(horizontal: true, vertical: true)
        .background(adaptiveColors.messageBubbleBackground, in: bubbleShape)
        .overlay(
            bubbleShape
                .stroke(adaptiveColors.messageBubbleStroke, lineWidth: 0.5)
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
    var translatedTextOverride: String? = nil
    @ObservedObject var message: EnhancedMessage
    let reactions: [String: [String]]?
    let onReaction: (String) -> Void
    let repliedMessage: EnhancedMessage?
    let otherParticipantId: String?
    let otherParticipantName: String
    let isCurrentUser: Bool
    var groupPosition: ChatMessageGroupPosition = .single
    let progress: Double?
    var downloadProgress: Double? = nil
    let onReplyTap: ((String) -> Void)?
    let onMessageViewed: ((String) -> Void)?
    let onMomentNavigation: ((EnhancedMessage) -> Void)?
    let onStoryNavigation: ((EnhancedMessage) -> Void)?
    var onMentionNavigation: ((String) -> Void)? = nil
    let onOpenMedia: (EnhancedMessage) -> Void
    let onStopLiveLocation: ((String) -> Void)?
    let onHydrateMedia: ((EnhancedMessage) -> Void)?
    var isDownloadingMedia: Bool = false
    var onViewOnceOpen: ((EnhancedMessage, Bool) -> Void)? = nil
    var viewOnceZoomNamespace: Namespace.ID? = nil
    var momentZoomNamespace: Namespace.ID? = nil
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.chatListContainerWidth) private var chatListContainerWidth

    @State private var localMediaDimensions: CGSize?

    private var photoVideoSize: CGSize {
        ChatMediaCardLayout.standaloneSize(
            width: message.mediaWidth ?? localMediaDimensions.map { Int($0.width) },
            height: message.mediaHeight ?? localMediaDimensions.map { Int($0.height) },
            bubbleMaxWidth: ChatBubbleLayoutWidth.capped(
                ChatBubbleLayoutWidth.maxTextBubbleWidth(chatListWidth: chatListContainerWidth),
                chatListWidth: chatListContainerWidth,
                gutter: isCurrentUser ? 64 : 88
            )
        )
    }

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    private var isStarredByCurrentUser: Bool {
        guard let userId = Auth.auth().currentUser?.uid else { return false }
        return message.isStarred(by: userId)
    }

    /// Forma de burbuja para media/audio que une esquinas en ráfagas (igual que el texto).
    private func mediaBubbleShape(cornerRadius: CGFloat) -> ChatBubbleShape {
        ChatBubbleShape(
            side: isCurrentUser ? .trailing : .leading,
            position: groupPosition,
            cornerRadius: cornerRadius,
            joinedRadius: ChatTextBubbleMetrics.joinedRadius
        )
    }

    @ViewBuilder
    private func attachBubbleBadges<Content: View>(
        to content: Content,
        compact: Bool = false,
        anchoredInsideBounds: Bool = false
    ) -> some View {
        content.messageReactionOverlay(
            isOutgoing: isCurrentUser,
            reactions: reactions,
            isStarred: isStarredByCurrentUser,
            compact: compact,
            anchoredInsideBounds: anchoredInsideBounds,
            onTap: onReaction
        )
    }

    @ViewBuilder
    private func textMessageBody(_ content: String) -> some View {
        // El reply ya se muestra apilado encima de la burbuja, no embebido dentro.
        ChatTextBubbleView(
            text: translatedTextOverride ?? content,
            isOutgoing: isCurrentUser,
            messageId: message.id,
            groupPosition: groupPosition,
            reactions: reactions,
            isStarred: isStarredByCurrentUser,
            repliedMessage: nil,
            otherParticipantName: otherParticipantName,
            onReplyTap: nil,
            onMentionTap: onMentionNavigation,
            onReaction: onReaction
        )
    }

    var body: some View {
        Group {
            if message.isDeleted {
                DeletedMessageBubble(
                    message: message,
                    isCurrentUser: isCurrentUser,
                    groupPosition: groupPosition
                )
            } else {
                if message.type == .viewOnceImage || message.type == .viewOnceVideo {
                    attachBubbleBadges(
                        to: ViewOnceMessageBubble(
                            message: message,
                            isCurrentUser: isCurrentUser,
                            otherParticipantName: otherParticipantName,
                            progress: progress,
                            zoomNamespace: viewOnceZoomNamespace,
                            zoomSourceID: "view-once-\(message.id)"
                        )
                    )
                    .onAppear {
                    }
                } else {
                    switch message.type {
                    case .text:
                        if message.storyReplyData != nil {
                            attachBubbleBadges(
                                to: StoryReplyMessageBubble(
                                    message: message,
                                    isCurrentUser: isCurrentUser,
                                    otherParticipantId: otherParticipantId,
                                    onHydrateMedia: onHydrateMedia,
                                    onOpenMedia: onOpenMedia
                                )
                            )
                        } else if let content = message.content {
                            VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 4) {
                                if message.isForwarded == true {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrowshape.turn.up.right")
                                            .font(.system(size: 10, weight: .semibold))
                                        Text("chat.forwarded")
                                    }
                                    .font(.system(size: legacyPoppinsSize(11)))
                                    .foregroundStyle(adaptiveColors.messageTextColor.opacity(0.55))
                                }

                                textMessageBody(content)
                            }
                        }

                    case .image:
                        attachBubbleBadges(
                            to: GlassmorphicImageMessage(
                                imageUrl: message.mediaUrl,
                                previewThumbnailUrl: message.previewThumbnailURLForDisplay,
                                isSending: message.status == .sending,
                                isResolvingMedia: message.isMediaPendingResolution

                                    && !isDownloadingMedia,
                                isDownloadingMedia: isDownloadingMedia,
                                downloadProgress: downloadProgress,
                                downsamplingSize: photoVideoSize,
                                progress: progress,
                                bubbleShape: mediaBubbleShape(cornerRadius: 16)
                            )
                            .frame(width: photoVideoSize.width, height: photoVideoSize.height)
                            .task(id: "\(message.mediaUrl ?? "")|\(message.thumbnailUrl ?? "")") {
                                if message.mediaWidth == nil || message.mediaHeight == nil {
                                    let primary = await ChatMediaFileDimensions.read(localURL: message.mediaUrl)
                                    let thumbnail = primary == nil ? await ChatMediaFileDimensions.read(localURL: message.thumbnailUrl) : nil
                                    localMediaDimensions = primary ?? thumbnail
                                }
                            }
                            .overlay { ChatMessageStaticOverlay(message: message) }
                            .clipShape(mediaBubbleShape(cornerRadius: 16))
                        )
                        .onAppear {
                            onHydrateMedia?(message)
                        }

                    case .audio:
                        attachBubbleBadges(
                            to: GlassmorphicAudioMessage(
                                messageId: message.id,
                                audioUrl: message.mediaUrl,
                                duration: message.duration ?? 0,
                                waveformSamples: message.audioWaveform,
                                isCurrentUser: isCurrentUser,
                                isSending: message.status == .sending,
                                progress: progress,
                                adaptiveColors: adaptiveColors,
                                groupPosition: groupPosition
                            )
                        )
                        .onAppear {
                            onHydrateMedia?(message)
                        }

                    case .video:
                        attachBubbleBadges(
                            to: GlassmorphicVideoMessage(
                                videoUrl: message.mediaUrl,
                                thumbnailUrl: message.thumbnailUrl,
                                isSending: message.status == .sending,
                                isResolvingMedia: (message.isMediaPendingResolution || message.needsVideoThumbnailForDisplay)

                                    && !isDownloadingMedia,
                                isDownloadingMedia: isDownloadingMedia,
                                downloadProgress: downloadProgress,
                                downsamplingSize: photoVideoSize,
                                progress: progress,
                                bubbleShape: mediaBubbleShape(cornerRadius: 16)
                            )
                            .frame(width: photoVideoSize.width, height: photoVideoSize.height)
                            .task(id: "\(message.mediaUrl ?? "")|\(message.thumbnailUrl ?? "")") {
                                if message.mediaWidth == nil || message.mediaHeight == nil {
                                    let primary = await ChatMediaFileDimensions.read(localURL: message.mediaUrl)
                                    let thumbnail = primary == nil ? await ChatMediaFileDimensions.read(localURL: message.thumbnailUrl) : nil
                                    localMediaDimensions = primary ?? thumbnail
                                }
                            }
                            .overlay { ChatMessageStaticOverlay(message: message) }
                            .clipShape(mediaBubbleShape(cornerRadius: 16))
                        )
                        .onAppear {
                            onHydrateMedia?(message)
                        }

                    case .ephemeral:
                        if message.storyReplyData != nil {
                            attachBubbleBadges(
                                to: StoryReplyMessageBubble(
                                    message: message,
                                    isCurrentUser: isCurrentUser,
                                    otherParticipantId: otherParticipantId,
                                    onHydrateMedia: onHydrateMedia,
                                    onOpenMedia: onOpenMedia
                                )
                            )
                        } else {
                            attachBubbleBadges(
                                to: ChatEphemeralMessageContent(
                                    message: message,
                                    layout: .standard,
                                    onHydrateMedia: onHydrateMedia,
                                    onOpenMedia: onOpenMedia
                                )
                            )
                        }
                    case .sharedMoment:
                        attachBubbleBadges(
                            to: SharedMomentMessageBubble(
                                message: message,
                                isCurrentUser: isCurrentUser,
                                zoomNamespace: momentZoomNamespace,
                                zoomSourceID: "chat-moment-\(message.id)"
                            )
                        )

                    case .sharedStory:
                        attachBubbleBadges(
                            to: SharedStoryMessageBubble(
                                message: message,
                                isCurrentUser: isCurrentUser
                            )
                        )

                    case .sharedProfile:
                        attachBubbleBadges(
                            to: SharedProfileMessageBubble(
                                message: message,
                                isCurrentUser: isCurrentUser
                            )
                        )

                    case .gif:
                        attachBubbleBadges(
                            to: ChatGifMessageBubble(
                                message: message,
                                progress: progress
                            )
                        )
                        .onAppear {
                            onHydrateMedia?(message)
                        }

                    case .sticker:
                        attachBubbleBadges(
                            to: ChatStickerMessageBubble(
                                message: message,
                                isSending: message.status == .sending,
                                progress: progress
                            )
                        )
                        .onAppear {
                            onHydrateMedia?(message)
                        }

                    case .location:
                        attachBubbleBadges(
                            to: ChatLocationMessageBubble(
                                message: message,
                                isCurrentUser: isCurrentUser,
                                accentColor: adaptiveColors.userAccentColor,
                                accentColorRed: adaptiveColors.accentColorRed,
                                onStopLive: {
                                    onStopLiveLocation?(message.id)
                                }
                            )
                        )

                    default:
                        attachBubbleBadges(
                            to: Text("chat.message.unsupported")
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .foregroundStyle(adaptiveColors.messageTextColor.opacity(0.6))
                                .glassmorphicChat()
                                .clipShape(RoundedRectangle(cornerRadius: 20))
                        )
                    }
                }
            }
        }
        .onAppear {
            if !isCurrentUser && !message.isDeleted {
            }
        }
    }
}

// MARK: - Link opening

enum ChatLinkOpener {
    private static let mentionScheme = "moments-mention"

    static func firstURL(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let searchable = linkSearchableText(from: text)
        let range = NSRange(searchable.startIndex..., in: searchable)
        return detector.firstMatch(in: searchable, options: [], range: range)?.url
    }

    static func containsLink(in text: String) -> Bool {
        firstURL(in: text) != nil
    }

    /// Texto plano para detectar URLs (quita delimitadores de spoiler `||`).
    private static func linkSearchableText(from text: String) -> String {
        text.replacingOccurrences(of: "||", with: "")
    }

    static func open(_ url: URL) {
        UIApplication.shared.open(url)
    }

    static func openFirstLink(in text: String) {
        guard let url = firstURL(in: text) else { return }
        open(url)
    }

    static func applyDetectedLinks(
        to attributed: inout AttributedString,
        in plainText: String,
        linkColor: Color,
        underline: Bool = true
    ) {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return
        }
        let range = NSRange(plainText.startIndex..., in: plainText)
        for match in detector.matches(in: plainText, options: [], range: range) {
            guard let url = match.url,
                  let swiftRange = Range(match.range, in: plainText),
                  let attrRange = swiftRange.toAttributedStringRange(in: attributed) else {
                continue
            }
            attributed[attrRange].link = url
            attributed[attrRange].foregroundColor = linkColor
            if underline {
                attributed[attrRange].underlineStyle = .single
            }
        }
    }

    static func applyDetectedMentions(
        to attributed: inout AttributedString,
        mentionColor: Color
    ) {
        let plainText = String(attributed.characters)
        guard let regex = try? NSRegularExpression(
            pattern: #"(?<![\p{L}\p{N}_])@([\p{L}\p{N}_]{1,30})"#
        ) else { return }

        let fullRange = NSRange(plainText.startIndex..., in: plainText)
        for match in regex.matches(in: plainText, range: fullRange) {
            guard let swiftRange = Range(match.range, in: plainText),
                  let usernameRange = Range(match.range(at: 1), in: plainText),
                  let attrRange = swiftRange.toAttributedStringRange(in: attributed),
                  let url = mentionURL(for: String(plainText[usernameRange])) else {
                continue
            }
            attributed[attrRange].link = url
            attributed[attrRange].foregroundColor = mentionColor
            attributed[attrRange].inlinePresentationIntent = .stronglyEmphasized
        }
    }

    static func openMentionIfNeeded(_ url: URL, onOpen: ((String) -> Void)? = nil) -> Bool {
        guard url.scheme == mentionScheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let username = components.queryItems?.first(where: { $0.name == "username" })?.value,
              !username.isEmpty else {
            return false
        }
        if let onOpen {
            onOpen(username)
        } else {
            MomentMentionNavigation.openProfile(forUsername: username)
        }
        return true
    }

    private static func mentionURL(for username: String) -> URL? {
        var components = URLComponents()
        components.scheme = mentionScheme
        components.host = "profile"
        components.queryItems = [URLQueryItem(name: "username", value: username)]
        return components.url
    }
}

// MARK: - Link Preview Helper & View
import LinkPresentation

extension Foundation.Notification.Name {
    /// userInfo["messageId"]: el contenido de esa fila cambió de tamaño tras cargar algo asíncrono.
    static let chatRowContentSizeDidChange = Foundation.Notification.Name("ChatRowContentSizeDidChange")
}

class LinkMetadataCache {
    static let shared = LinkMetadataCache()
    private var cache: [URL: LPLinkMetadata] = [:]
    private var images: [URL: UIImage] = [:]

    /// Lectura síncrona (hilo principal) para pintar la tarjeta ya en su tamaño final.
    func cachedMetadata(for url: URL) -> (metadata: LPLinkMetadata, image: UIImage?)? {
        cache[url].map { ($0, images[url]) }
    }

    func fetchMetadata(for url: URL, completion: @escaping (LPLinkMetadata?, UIImage?) -> Void) {
        if let cachedMeta = cache[url] {
            completion(cachedMeta, images[url])
            return
        }

        let provider = LPMetadataProvider()
        provider.startFetchingMetadata(for: url) { [weak self] metadata, error in
            guard let metadata = metadata else {
                DispatchQueue.main.async {
                    completion(nil, nil)
                }
                return
            }

            DispatchQueue.main.async {
                self?.cache[url] = metadata
            }

            if let imageProvider = metadata.imageProvider {
                imageProvider.loadObject(ofClass: UIImage.self) { image, error in
                    DispatchQueue.main.async {
                        let loadedImage = image as? UIImage
                        if let loadedImage = loadedImage {
                            self?.images[url] = loadedImage
                        }
                        completion(metadata, loadedImage)
                    }
                }
            } else {
                DispatchQueue.main.async {
                    completion(metadata, nil)
                }
            }
        }
    }
}

struct LinkPreviewCard: View {
    let url: URL
    /// Integrado dentro de la burbuja: ancho completo y colores que combinan con la burbuja.
    var embedded: Bool = false
    var isOutgoing: Bool = false
    /// Fila a re-medir cuando la tarjeta cambia de tamaño al cargar (compacta → imagen grande).
    var messageId: String? = nil
    @State private var title: String?
    @State private var host: String?
    @State private var image: UIImage?
    @State private var isLoading: Bool

    init(url: URL, embedded: Bool = false, isOutgoing: Bool = false, messageId: String? = nil) {
        self.url = url
        self.embedded = embedded
        self.isOutgoing = isOutgoing
        self.messageId = messageId
        // Con caché se pinta directamente en su tamaño final (sin salto ni recorte al reciclar celda).
        let cached = LinkMetadataCache.shared.cachedMetadata(for: url)
        _title = State(initialValue: cached.map { $0.metadata.title ?? url.host ?? url.absoluteString })
        _host = State(initialValue: url.host)
        _image = State(initialValue: cached?.image)
        _isLoading = State(initialValue: cached == nil)
    }
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.chatOutgoingBubbleColor) private var chatOutgoingBubbleColor

    @Environment(\.chatListContainerWidth) private var chatListContainerWidth

    private var standaloneCardWidth: CGFloat {
        ChatBubbleLayoutWidth.capped(240, chatListWidth: chatListContainerWidth)
    }

    private var maxCardWidth: CGFloat? { embedded ? nil : standaloneCardWidth }
    private var imageMaxHeight: CGFloat { embedded ? 150 : 120 }
    private var cornerRadius: CGFloat { embedded ? 13 : 10 }

    /// En salientes sigue el contraste del color de burbuja elegido (claro u oscuro).
    private var outgoingTextColor: Color {
        chatBubbleTextColor(for: chatOutgoingBubbleColor)
    }

    private var titleColor: Color {
        if embedded && isOutgoing { return outgoingTextColor }
        return colorScheme == .dark ? .white : .black
    }

    private var hostColor: Color {
        if embedded && isOutgoing { return outgoingTextColor.opacity(0.85) }
        return AdaptiveColors(colorScheme: colorScheme).receivedAccent(from: chatOutgoingBubbleColor)
    }

    private var panelBackground: Color {
        if embedded {
            return isOutgoing
                ? Color.white.opacity(0.16)
                : Color.white.opacity(colorScheme == .dark ? 0.08 : 0.55)
        }
        return Color.white.opacity(colorScheme == .dark ? 0.08 : 0.6)
    }

    private var strokeColor: Color {
        if embedded { return .clear }
        return Color.white.opacity(colorScheme == .dark ? 0.1 : 0.3)
    }

    @ViewBuilder
    private func frameWrap<V: View>(_ view: V) -> some View {
        if embedded {
            view.frame(maxWidth: .infinity, alignment: .leading)
        } else {
            view.frame(maxWidth: standaloneCardWidth, alignment: .leading)
        }
    }

    /// Tarjeta integrada: margen hasta el borde de la burbuja y ancho máximo de la burbuja con enlace.
    static let embeddedInset: CGFloat = 4
    static let embeddedMaxWidth: CGFloat = 260
    private static let compactThumbSize: CGFloat = 52
    private static let largeImageAspect: CGFloat = 1.91
    private static let largeImageMaxHeight: CGFloat = 140

    /// Imagen grande solo si es horizontal y con resolución suficiente; si no, fila compacta.
    private var showsLargeImage: Bool {
        guard let image else { return false }
        let pixelWidth = image.size.width * image.scale
        return pixelWidth >= 300 && image.size.width / max(image.size.height, 1) >= 1.3
    }

    private var embeddedTitleFont: Font { .system(size: 13, weight: .semibold) }
    private var embeddedHostFont: Font { .system(size: 11, weight: .regular) }

    @ViewBuilder
    private var embeddedBody: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        Group {
            if !isLoading, showsLargeImage, let image {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear
                        .aspectRatio(Self.largeImageAspect, contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: Self.largeImageMaxHeight)
                        .overlay {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        }
                        .clipped()
                    embeddedText
                        .padding(.horizontal, 9)
                        .padding(.top, 7)
                        .padding(.bottom, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                HStack(spacing: 9) {
                    compactThumb
                    embeddedText
                    Spacer(minLength: 0)
                }
                .padding(6)
            }
        }
        .background(panelBackground)
        .clipShape(shape)
    }

    @ViewBuilder
    private var compactThumb: some View {
        let thumbShape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        if let image, !isLoading {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: Self.compactThumbSize, height: Self.compactThumbSize)
                .clipShape(thumbShape)
        } else {
            ZStack {
                thumbShape.fill(titleColor.opacity(0.1))
                if isLoading {
                    ProgressView().scaleEffect(0.7)
                } else {
                    Image(systemName: "link")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(titleColor.opacity(0.7))
                }
            }
            .frame(width: Self.compactThumbSize, height: Self.compactThumbSize)
        }
    }

    private var embeddedText: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(isLoading ? (url.host ?? url.absoluteString) : (title ?? url.host ?? url.absoluteString))
                .font(embeddedTitleFont)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .foregroundStyle(titleColor)
            Text(host ?? url.host ?? "")
                .font(embeddedHostFont)
                .lineLimit(1)
                .foregroundStyle(isOutgoing ? outgoingTextColor.opacity(0.75) : titleColor.opacity(0.55))
        }
    }

    var body: some View {
        if embedded {
            Button {
                HapticManager.shared.lightImpact()
                ChatLinkOpener.open(url)
            } label: {
                embeddedBody
            }
            .buttonStyle(.plain)
            .onAppear(perform: loadMetadata)
        } else {
            standaloneBody
        }
    }

    private func loadMetadata() {
        host = url.host
        let wasLarge = !isLoading && showsLargeImage
        let hadImage = image != nil
        LinkMetadataCache.shared.fetchMetadata(for: url) { metadata, img in
            self.title = metadata?.title ?? url.host ?? url.absoluteString
            self.image = img
            self.isLoading = false
            // La celda de la lista no siempre se re-mide sola al crecer: pedir reconfigurarla.
            if let messageId, showsLargeImage != wasLarge || (img != nil) != hadImage {
                NotificationCenter.default.post(name: .chatRowContentSizeDidChange, object: nil, userInfo: ["messageId": messageId])
            }
        }
    }

    private var standaloneBody: some View {
        Button {
            HapticManager.shared.lightImpact()
            ChatLinkOpener.open(url)
        } label: {
            Group {
                if isLoading {
                    frameWrap(
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text(url.host ?? url.absoluteString)
                                .font(.system(size: 11))
                                .foregroundStyle(embedded && isOutgoing ? outgoingTextColor.opacity(0.8) : .gray)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    )
                    .background(panelBackground)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                } else if let title = title {
                    VStack(alignment: .leading, spacing: 0) {
                        if let image = image {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(maxWidth: maxCardWidth ?? .infinity, maxHeight: imageMaxHeight)
                                .clipped()
                        }

                        frameWrap(
                            VStack(alignment: .leading, spacing: 4) {
                                Text(title)
                                    .font(.system(size: 12, weight: .bold))
                                    .lineLimit(2)
                                    .foregroundStyle(titleColor)

                                Text(host ?? "")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(hostColor)
                            }
                            .padding(8)
                        )
                        .background(panelBackground)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(strokeColor, lineWidth: embedded ? 0 : 1)
                    )
                } else {
                    frameWrap(
                        HStack(spacing: 8) {
                            Image(systemName: "link")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(hostColor)
                            Text(url.host ?? url.absoluteString)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(titleColor)
                                .lineLimit(2)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                    )
                    .background(panelBackground)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(strokeColor, lineWidth: embedded ? 0 : 1)
                    )
                }
            }
        }
        .frame(width: embedded ? nil : standaloneCardWidth, alignment: .leading)
        .frame(minHeight: embedded ? nil : imageMaxHeight + 56)
        .buttonStyle(.plain)
        .onAppear {
            self.host = url.host
            LinkMetadataCache.shared.fetchMetadata(for: url) { metadata, img in
                self.title = metadata?.title ?? url.host ?? url.absoluteString
                self.image = img
                self.isLoading = false
            }
        }
    }
}
