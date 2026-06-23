import Foundation

enum ChatScrollTarget: Equatable {
    case bottom(messageId: String)
    case firstUnread(messageId: String)
    case highlightedMessage(messageId: String)

    var isFirstUnread: Bool {
        if case .firstUnread = self { return true }
        return false
    }

    var isHighlightedMessage: Bool {
        if case .highlightedMessage = self { return true }
        return false
    }

    var pinsToBottom: Bool {
        if case .bottom = self { return true }
        return false
    }
}

enum ChatScrollStateStore {
    struct State: Equatable {
        var hasCompletedInitialScroll = false
        var frozenInitialScrollTarget: ChatScrollTarget?
        var isPinnedToBottom = true
        var unreadDividerMessageId: String?
        var unreadDividerInitialized = false
        var didProcessNotificationBuzz = false
        var scrollAnchorId: String?
        var scrollOffsetY: CGFloat?
    }

    static func state(for conversationId: String) -> State {
        State()
    }

    static func update(for conversationId: String, _ update: (inout State) -> Void) {}

    static func shouldRunInitialScroll(for conversationId: String, hasHighlightIntent: Bool) -> Bool {
        true
    }

    static func clearAll() {}
}
