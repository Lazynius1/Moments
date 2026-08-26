import UIKit

enum ChatRowHeightEstimator {
    private static let maxBubbleWidthFraction: CGFloat = ChatTextBubbleMetrics.maxWidthScreenFraction
    private static let textHorizontalPadding: CGFloat = ChatTextBubbleMetrics.horizontalPadding * 2
    private static let textVerticalPadding: CGFloat = ChatTextBubbleMetrics.verticalPadding * 2
    private static let baseFontSize: CGFloat = 15
    private static let replyBlockHeight: CGFloat = 46
    private static let reactionsRowHeight: CGFloat = 28

    private static let mediaDefaultAspect: CGFloat = 4.0 / 5.0
    private static let mediaMinHeight: CGFloat = 140
    private static let mediaMaxHeight: CGFloat = 420
    private static let gifDefaultAspect: CGFloat = 200.0 / 150.0

    private static let voiceNoteHeight: CGFloat = 68
    private static let locationHeight: CGFloat = 205
    private static let liveLocationExtraHeight: CGFloat = 40
    private static let fileHeight: CGFloat = 72
    private static let viewOncePillHeight: CGFloat = 50
    private static let viewOnceRowVerticalPadding: CGFloat = 10
    private static let ephemeralHeight: CGFloat = 150
    private static let sharedMomentPreviewHeight: CGFloat = 320
    /// Story share = reply thumb × ~1.85 (140×217) + padding.
    private static let sharedStoryPreviewHeight: CGFloat = 232
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

    static func estimatedHeight(for row: ChatRenderRow, containerWidth: CGFloat) -> CGFloat {
        let bubbleWidth = max(120, containerWidth * maxBubbleWidthFraction)
        switch row {
        case .conversationIntro:
            return conversationIntroHeight
        case .requestDisclaimer:
            return requestDisclaimerHeight
        case .pendingRequestMessage(let message):
            if message.hasStoryReplyContext {
                return 190
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
            return estimatedClusterHeight(count: messages.count)
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
        switch message.type {
        case .text:
            return textHeight(for: message, bubbleWidth: bubbleWidth)
        case .image, .video:
            return mediaHeight(for: message, bubbleWidth: bubbleWidth, fallbackAspect: mediaDefaultAspect)
        case .gif, .sticker:
            return mediaHeight(for: message, bubbleWidth: bubbleWidth, fallbackAspect: gifDefaultAspect)
        case .audio:
            return voiceNoteHeight
        case .location:
            return message.isLiveLocation == true ? locationHeight + liveLocationExtraHeight : locationHeight
        case .file:
            return fileHeight
        case .viewOnceImage, .viewOnceVideo:
            return viewOnceHeight(for: message)
        case .ephemeral:
            return ephemeralHeight
        case .sharedMoment:
            return sharedMomentPreviewHeight
        case .sharedStory:
            return sharedStoryPreviewHeight
        case .chatNotice:
            return chatNoticeHeight
        }
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

    private static func mediaHeight(for message: EnhancedMessage, bubbleWidth: CGFloat, fallbackAspect: CGFloat) -> CGFloat {
        let aspect: CGFloat
        if let width = message.mediaWidth, let height = message.mediaHeight, width > 0, height > 0 {
            aspect = CGFloat(width) / CGFloat(height)
        } else {
            aspect = fallbackAspect
        }

        var height = bubbleWidth / max(aspect, 0.35)
        height = min(max(height, mediaMinHeight), mediaMaxHeight)

        if let caption = message.content, !caption.isEmpty {
            height += textHeight(for: message, bubbleWidth: bubbleWidth) - textVerticalPadding
        }
        if let reactions = message.reactions, !reactions.isEmpty {
            height += reactionsRowHeight
        }
        return height
    }

    private static func viewOnceHeight(for message: EnhancedMessage) -> CGFloat {
        var height = viewOncePillHeight + viewOnceRowVerticalPadding
        if let reactions = message.reactions, !reactions.isEmpty {
            height += reactionsRowHeight
        }
        return height
    }
}
