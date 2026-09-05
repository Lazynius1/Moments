import UIKit

enum ChatRowHeightEstimator {
    private static let maxBubbleWidthFraction: CGFloat = ChatTextBubbleMetrics.maxWidthScreenFraction
    private static let textHorizontalPadding: CGFloat = ChatTextBubbleMetrics.horizontalPadding * 2
    private static let textVerticalPadding: CGFloat = ChatTextBubbleMetrics.verticalPadding * 2
    private static let baseFontSize: CGFloat = 15
    private static let replyBlockHeight: CGFloat = 46
    private static let reactionsRowHeight: CGFloat = 28

    private static let photoVideoHeight: CGFloat = 272
    private static let stickerSize: CGFloat = 140
    private static let voiceNoteHeight: CGFloat = 68
    private static let locationHeight: CGFloat = 217
    private static let liveLocationExtraHeight: CGFloat = 40
    private static let fileHeight: CGFloat = 72
    private static let viewOncePillHeight: CGFloat = 50
    private static let viewOnceRowVerticalPadding: CGFloat = 10
    /// `DeletedMessageBubble`: icono 16 + padding vertical 10×2.
    private static let deletedRowHeight: CGFloat = 50
    /// Story share 180×320 más el padding vertical de la burbuja (como HEAD).
    private static let sharedStoryPreviewHeight: CGFloat = 336
    private static let storyReplyTextHeight: CGFloat = 244
    private static let storyReplyEphemeralHeight: CGFloat = 368
    private static let chatNoticeHeight: CGFloat = 36

    private static let headerHeight: CGFloat = 32
    private static let buzzHeight: CGFloat = 44
    private static let typingHeight: CGFloat = 40
    private static let historyStartHeight: CGFloat = 50
    private static let conversationIntroHeight: CGFloat = 190
    private static let requestDisclaimerHeight: CGFloat = 58
    private static let incomingRequestActionsHeight: CGFloat = 190
    private static let outgoingRequestControlsHeight: CGFloat = 76

    static let fallbackHeight: CGFloat = 60

    /// Hueco fijo para cards/media que aún no han medido (evita apelotonar).
    /// Borrados y texto se autoajustan: la píldora no hereda la altura del audio/card.
    static func usesReservedHeight(_ row: ChatRenderRow) -> Bool {
        switch row {
        case .message(let item):
            switch item {
            case .mediaCluster(let messages):
                return !messages.allSatisfy(\.isDeleted)
            case .single(let message):
                if message.isDeleted { return false }
                if message.storyReplyData != nil { return true }
                switch message.type {
                case .text, .chatNotice:
                    return false
                case .image, .video, .audio, .gif, .sticker, .location, .file,
                     .ephemeral, .sharedMoment, .sharedStory, .sharedProfile,
                     .viewOnceImage, .viewOnceVideo:
                    return true
                }
            }
        case .pendingRequestMessage(let message):
            if message.hasStoryReplyContext { return true }
            return message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .conversationIntro, .requestDisclaimer, .incomingRequestActions,
             .outgoingRequestControls, .header, .buzz, .typing, .historyStart:
            return true
        }
    }

    static func estimatedHeight(for row: ChatRenderRow, containerWidth: CGFloat) -> CGFloat {
        let bubbleWidth = max(120, containerWidth * maxBubbleWidthFraction)
        switch row {
        case .conversationIntro:
            return conversationIntroHeight
        case .requestDisclaimer:
            return requestDisclaimerHeight
        case .pendingRequestMessage(let message):
            if message.hasStoryReplyContext {
                return message.messageType == .ephemeral ? storyReplyEphemeralHeight : storyReplyTextHeight
            }
            let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return viewOncePillHeight + viewOnceRowVerticalPadding }
            return max(46, textHeight(for: text, bubbleWidth: bubbleWidth) + 6)
        case .incomingRequestActions:
            return incomingRequestActionsHeight
        case .outgoingRequestControls:
            return outgoingRequestControlsHeight
        case .header:
            return headerHeight
        case .buzz:
            return buzzHeight
        case .typing:
            return typingHeight
        case .historyStart:
            return historyStartHeight
        case .message(let item):
            return estimatedHeight(for: item, bubbleWidth: bubbleWidth)
        }
    }

    private static func textHeight(for text: String, bubbleWidth: CGFloat) -> CGFloat {
        let availableWidth = max(80, bubbleWidth - textHorizontalPadding)
        let bounding = NSString(string: text).boundingRect(
            with: CGSize(width: availableWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: UIFont.systemFont(ofSize: baseFontSize)],
            context: nil
        )
        return ceil(bounding.height) + textVerticalPadding
    }

    private static func estimatedHeight(for item: MessageItem, bubbleWidth: CGFloat) -> CGFloat {
        switch item {
        case .single(let message):
            return estimatedHeight(for: message, bubbleWidth: bubbleWidth)
        case .mediaCluster(let messages):
            if messages.allSatisfy(\.isDeleted) {
                return deletedRowHeight
            }
            return estimatedClusterHeight(count: messages.filter { !$0.isDeleted }.count)
        }
    }

    private static func estimatedClusterHeight(count: Int) -> CGFloat {
        let visible = min(max(count, 1), ClusterMediaLayout.maxVisible)
        return ClusterMediaLayout.frontHeight
            + ClusterMediaLayout.fanTopPadding(for: visible)
            + ClusterMediaLayout.fanBottomPadding
            + 6
    }

    private static func estimatedHeight(for message: EnhancedMessage, bubbleWidth: CGFloat) -> CGFloat {
        if message.isDeleted {
            return deletedRowHeight
        }
        if message.storyReplyData != nil {
            return message.type == .ephemeral ? storyReplyEphemeralHeight : storyReplyTextHeight
        }
        switch message.type {
        case .text:
            return textHeight(for: message, bubbleWidth: bubbleWidth)
        case .image, .video:
            var height = photoVideoHeight
            if let caption = message.content, !caption.isEmpty {
                height += textHeight(for: message, bubbleWidth: bubbleWidth) - textVerticalPadding
            }
            if let reactions = message.reactions, !reactions.isEmpty {
                height += reactionsRowHeight
            }
            return height
        case .gif:
            return ChatGifLayout.displaySize(width: message.mediaWidth, height: message.mediaHeight).height
        case .sticker:
            return stickerSize
        case .audio:
            return voiceNoteHeight
        case .location:
            return message.isLiveLocation == true ? locationHeight + liveLocationExtraHeight : locationHeight
        case .file:
            return fileHeight
        case .viewOnceImage, .viewOnceVideo:
            return viewOnceHeight(for: message)
        case .ephemeral:
            return ChatEphemeralLayout.standard.height
        case .sharedMoment:
            return sharedMomentRowHeight(for: message)
        case .sharedStory:
            return sharedStoryPreviewHeight
        case .sharedProfile:
            return SharedProfileDMCardMetrics.cardHeight
        case .chatNotice:
            return chatNoticeHeight
        }
    }

    private static func sharedMomentRowHeight(for message: EnhancedMessage) -> CGFloat {
        let data = message.sharedMomentData ?? [:]
        let aspect = parseSharedAspectRatio(data["momentAspectRatio"])
        let isVideo = !(data["momentVideoUrl"] ?? "").isEmpty
        if sharedMomentLooksLikeReel(isVideo: isVideo, aspectRatio: aspect) {
            return sharedStoryPreviewHeight
        }
        let hasCaption = !(data["momentContent"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
        return SharedDMPostCardMetrics.cardHeight(aspectRatio: aspect, hasCaption: hasCaption)
    }

    private static func textHeight(for message: EnhancedMessage, bubbleWidth: CGFloat) -> CGFloat {
        let text = message.content ?? ""
        guard !text.isEmpty else { return fallbackHeight }

        let maxTextWidth = bubbleWidth - textHorizontalPadding
        let font = UIFont.systemFont(ofSize: baseFontSize, weight: .regular)
        let attributed = NSAttributedString(string: text, attributes: [.font: font])
        let bounds = attributed.boundingRect(
            with: CGSize(width: max(40, maxTextWidth), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )

        var height = bounds.height.rounded(.up) + textVerticalPadding
        if message.replyTo != nil { height += replyBlockHeight }
        if let reactions = message.reactions, !reactions.isEmpty { height += reactionsRowHeight }
        return max(height, fallbackHeight * 0.7)
    }

    private static func viewOnceHeight(for message: EnhancedMessage) -> CGFloat {
        var height = viewOncePillHeight + viewOnceRowVerticalPadding
        if let reactions = message.reactions, !reactions.isEmpty {
            height += reactionsRowHeight
        }
        return height
    }
}
