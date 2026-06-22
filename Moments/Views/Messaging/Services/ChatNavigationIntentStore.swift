import Foundation

/// Intenciones de navegación al abrir un chat (p. ej. resaltar mensajes tras una push de reacción).
enum ChatNavigationIntentStore {
    private static let lock = NSLock()
    private static var pendingHighlights: [String: Set<String>] = [:]

    static func enqueueHighlight(conversationId: String, messageId: String) {
        guard !conversationId.isEmpty, !messageId.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        var set = pendingHighlights[conversationId] ?? []
        set.insert(messageId)
        pendingHighlights[conversationId] = set
    }

    static func consumeHighlights(for conversationId: String) -> Set<String> {
        guard !conversationId.isEmpty else { return [] }
        lock.lock()
        defer { lock.unlock() }
        let highlights = pendingHighlights[conversationId] ?? []
        pendingHighlights.removeValue(forKey: conversationId)
        return highlights
    }
}

extension Foundation.Notification.Name {
    static let chatMessageReactionHighlight = Foundation.Notification.Name("ChatMessageReactionHighlight")
}
