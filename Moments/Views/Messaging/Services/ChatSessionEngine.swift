import Foundation
import SwiftUI

typealias ConversationChatSession = MomentsChatViewModel

@MainActor
final class ChatSessionEngine: ObservableObject {
    static let shared = ChatSessionEngine()

    private var sessions: [String: ConversationChatSession] = [:]
    private var conversationById: [String: Conversation] = [:]
    private let maxWarmSessions = 3

    private init() {}

    func session(for conversation: Conversation) -> ConversationChatSession {
        let conversationId = conversation.id ?? UUID().uuidString
        conversationById[conversationId] = conversation

        if let existing = sessions[conversationId] {
            return existing
        }

        let session = MomentsChatViewModel(conversation: conversation)
        sessions[conversationId] = session
        session.loadCachedMessagesIfNeeded()
        return session
    }

    func activate(conversationId: String) {
        guard let session = sessions[conversationId] else { return }
        session.activateChatSession()
        enforceWarmSessionLimit(excluding: conversationId)
    }

    func deactivate(conversationId: String) {
        sessions[conversationId]?.deactivateChatSession()
    }

    func warm(conversationIds: [String]) {
        let ids = Array(conversationIds.prefix(maxWarmSessions))
        for conversationId in ids where !conversationId.isEmpty {
            guard let conversation = conversationById[conversationId] ?? sessions[conversationId]?.conversation else { continue }
            let session = session(for: conversation)
            if session.chatSessionMode != .active {
                session.warmChatSession()
            }
        }
        enforceWarmSessionLimit(excluding: nil)
    }

    func invalidateAll() {
        for session in sessions.values {
            session.stopListening()
        }
        sessions.removeAll()
        conversationById.removeAll()
        ChatScrollStateStore.clearAll()
    }

    private func enforceWarmSessionLimit(excluding activeId: String?) {
        let warmSessions = sessions.values
            .filter { $0.chatSessionMode == .warm }
            .sorted { lhs, rhs in
                (lhs.conversation.timestamp ?? .distantPast) > (rhs.conversation.timestamp ?? .distantPast)
            }

        if warmSessions.count <= maxWarmSessions { return }

        for session in warmSessions.dropFirst(maxWarmSessions) {
            let id = session.conversation.id ?? ""
            if id == activeId { continue }
            session.pauseChatListenersImmediately()
        }
    }
}
