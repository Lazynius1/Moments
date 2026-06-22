import Foundation

/// Intenciones al abrir un chat desde una push (scroll, zumbido, resaltar mensaje…).
/// Se hace peek al entrar y clear solo cuando se procesa — nunca consume en el init de la vista.
enum ChatNavigationIntentStore {
    struct OpenIntent: Equatable {
        var playBuzzOnOpen = false
        var buzzEventId: String?
        var highlightMessageIds: Set<String> = []
    }

    private static let lock = NSLock()
    private static var pending: [String: OpenIntent] = [:]

    private static func updateIntent(
        conversationId: String,
        _ update: (inout OpenIntent) -> Void
    ) {
        guard !conversationId.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        var intent = pending[conversationId] ?? OpenIntent()
        update(&intent)
        pending[conversationId] = intent
    }

    static func enqueueHighlight(conversationId: String, messageId: String) {
        guard !messageId.isEmpty else { return }
        updateIntent(conversationId: conversationId) { $0.highlightMessageIds.insert(messageId) }
    }

    static func enqueueBuzz(conversationId: String, buzzEventId: String? = nil) {
        updateIntent(conversationId: conversationId) {
            $0.playBuzzOnOpen = true
            if let buzzEventId, !buzzEventId.isEmpty {
                $0.buzzEventId = buzzEventId
            }
        }
    }

    static func clearHighlights(for conversationId: String) {
        updateIntent(conversationId: conversationId) { $0.highlightMessageIds.removeAll() }
    }

    static func peek(for conversationId: String) -> OpenIntent? {
        guard !conversationId.isEmpty else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return pending[conversationId]
    }

    static func clear(for conversationId: String) {
        guard !conversationId.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        pending.removeValue(forKey: conversationId)
    }
}

extension Foundation.Notification.Name {
    static let chatMessageReactionHighlight = Foundation.Notification.Name("ChatMessageReactionHighlight")
    static let chatBuzzHighlight = Foundation.Notification.Name("ChatBuzzHighlight")
}
