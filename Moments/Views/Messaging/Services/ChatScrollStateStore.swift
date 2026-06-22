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

/// Estado de scroll por conversación — sobrevive a salir y volver a entrar al chat.
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

    private static let lock = NSLock()
    private static var states: [String: State] = [:]

    static func state(for conversationId: String) -> State {
        guard !conversationId.isEmpty else { return State() }
        lock.lock()
        defer { lock.unlock() }
        return states[conversationId] ?? State()
    }

    static func update(for conversationId: String, _ update: (inout State) -> Void) {
        guard !conversationId.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        var current = states[conversationId] ?? State()
        update(&current)
        states[conversationId] = current
    }

    static func shouldRunInitialScroll(for conversationId: String, hasHighlightIntent: Bool) -> Bool {
        let stored = state(for: conversationId)
        if hasHighlightIntent { return true }
        return !stored.hasCompletedInitialScroll
    }

    static func clearAll() {
        lock.lock()
        defer { lock.unlock() }
        states.removeAll()
    }
}
