import Foundation
import FirebaseAuth
import SwiftUI

typealias ConversationChatSession = MomentsChatViewModel

@MainActor
final class ChatSessionEngine: ObservableObject {
    static let shared = ChatSessionEngine()

    private var sessions: [String: ConversationChatSession] = [:]
    private var conversationById: [String: Conversation] = [:]
    private let maxWarmSessions = 3
    private var ownerUserId: String?

    private(set) var activeConversationId: String?

    private init() {}

    func session(for conversation: Conversation) -> ConversationChatSession {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            return MomentsChatViewModel(conversation: conversation)
        }
        reconcileCurrentUser()
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
        reconcileCurrentUser()
        activeConversationId = conversationId
        guard let session = sessions[conversationId] else {
            syncInAppFallbackListeners()
            return
        }
        session.activateChatSession()
        enforceWarmSessionLimit(excluding: conversationId)
        syncInAppFallbackListeners()
    }

    func deactivate(conversationId: String) {
        reconcileCurrentUser()
        if activeConversationId == conversationId {
            activeConversationId = nil
        }
        sessions[conversationId]?.deactivateChatSession()
        syncInAppFallbackListeners()
    }

    func warm(conversationIds: [String]) {
        reconcileCurrentUser()
        let ids = Array(conversationIds.prefix(maxWarmSessions))
        for conversationId in ids where !conversationId.isEmpty {
            guard let conversation = conversationById[conversationId] ?? sessions[conversationId]?.conversation else { continue }
            let session = session(for: conversation)
            if session.chatSessionMode != .active {
                session.warmChatSession()
            }
        }
        enforceWarmSessionLimit(excluding: nil)
        syncInAppFallbackListeners()
    }

    func invalidateAll() {
        activeConversationId = nil
        for session in sessions.values {
            session.stopListening()
        }
        sessions.removeAll()
        conversationById.removeAll()
        ChatScrollStateStore.clearAll()
        ownerUserId = Auth.auth().currentUser?.uid
        syncInAppFallbackListeners()
    }

    func warmConversationIdsForNotifications() -> [String] {
        var ids = Set<String>()
        if let activeConversationId {
            ids.insert(activeConversationId)
        }
        for (conversationId, session) in sessions where session.chatSessionMode == .warm || session.chatSessionMode == .active {
            ids.insert(conversationId)
        }
        return Array(ids.prefix(5))
    }

    private func syncInAppFallbackListeners() {
        InAppNotificationService.shared.syncFallbackListeners(
            conversationIds: warmConversationIdsForNotifications()
        )
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

    private func reconcileCurrentUser() {
        let currentUserId = Auth.auth().currentUser?.uid
        guard ownerUserId != currentUserId else { return }
        if ownerUserId == nil {
            ownerUserId = currentUserId
            return
        }
        activeConversationId = nil
        for session in sessions.values {
            session.stopListening()
        }
        sessions.removeAll()
        conversationById.removeAll()
        ChatScrollStateStore.clearAll()
        ChatAccessCoordinator.shared.invalidateAll()
        ownerUserId = currentUserId
        syncInAppFallbackListeners()
    }
}
