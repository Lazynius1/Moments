import Foundation
import FirebaseAuth
import SwiftUI

typealias ConversationChatSession = MomentsChatViewModel

@MainActor
final class ChatSessionEngine: ObservableObject {
    static let shared = ChatSessionEngine()

    private var sessions: [String: ConversationChatSession] = [:]
    private var conversationById: [String: Conversation] = [:]
    private let maxCachedSessions = 10
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
            existing.mergeConversationReadMetadata(from: conversation)
            return existing
        }

        trimSessionCache(excluding: conversationId)

        let session = MomentsChatViewModel(conversation: conversation)
        sessions[conversationId] = session
        session.loadCachedMessagesIfNeeded()
        return session
    }

    /// Registra en el cache una sesión que se abrió como borrador (sin id) una vez que
    /// se ha materializado su conversación en Firestore, para que las siguientes aperturas
    /// reutilicen la misma sesión en lugar de crear una nueva.
    func registerMaterializedSession(_ session: ConversationChatSession, conversationId: String) {
        guard !conversationId.isEmpty else { return }
        reconcileCurrentUser()
        conversationById[conversationId] = session.conversation
        if sessions[conversationId] == nil {
            trimSessionCache(excluding: conversationId)
            sessions[conversationId] = session
        }
    }

    func preloadRecentSessions(from conversations: [Conversation], limit: Int = 5) {
        reconcileCurrentUser()
        for conversation in conversations.prefix(limit) {
            guard let conversationId = conversation.id, !conversationId.isEmpty else { continue }
            conversationById[conversationId] = conversation
            if sessions[conversationId] != nil { continue }
            trimSessionCache(excluding: conversationId)
            let session = MomentsChatViewModel(conversation: conversation)
            sessions[conversationId] = session
            session.loadCachedMessagesIfNeeded()
        }
    }

    func activate(conversationId: String) {
        reconcileCurrentUser()
        activeConversationId = conversationId
        guard let session = sessions[conversationId] else {
            syncInAppFallbackListeners()
            return
        }
        session.activateChatSession()
        syncInAppFallbackListeners()

        if LocalFirstMessagingSettings.isEnabled {
            Task {
                await MessageCatchUpService.shared.sync(conversationId: conversationId)
            }
        }
    }

    func deactivate(conversationId: String) {
        reconcileCurrentUser()
        if activeConversationId == conversationId {
            activeConversationId = nil
        }
        sessions[conversationId]?.deactivateChatSession()
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

    /// Descarta la sesión en memoria de una conversación (p. ej. tras borrarla del inbox).
    func invalidateSession(conversationId: String) {
        guard !conversationId.isEmpty else { return }
        if activeConversationId == conversationId {
            activeConversationId = nil
        }
        sessions[conversationId]?.stopListening()
        sessions.removeValue(forKey: conversationId)
        conversationById.removeValue(forKey: conversationId)
        syncInAppFallbackListeners()
    }

    func notificationConversationIdsForFallback() -> [String] {
        var ids = Set<String>()
        if let activeConversationId {
            ids.insert(activeConversationId)
        }

        let currentUserId = Auth.auth().currentUser?.uid ?? ""
        let cachedConversations = LocalPersistenceService.shared.loadConversations()
        for conversation in cachedConversations where !(conversation.readStatus[currentUserId] ?? true) {
            if let conversationId = conversation.id {
                ids.insert(conversationId)
            }
        }

        if ids.isEmpty {
            for conversation in cachedConversations.prefix(5) {
                if let conversationId = conversation.id {
                    ids.insert(conversationId)
                }
            }
        }

        return Array(ids.prefix(5))
    }

    private func syncInAppFallbackListeners() {
        InAppNotificationService.shared.syncFallbackListeners(
            conversationIds: notificationConversationIdsForFallback()
        )
    }

    private func trimSessionCache(excluding conversationId: String) {
        guard sessions.count >= maxCachedSessions else { return }

        let evictionCandidates = sessions.values
            .filter { $0.conversation.id != conversationId && $0.conversation.id != activeConversationId }
            .sorted { lhs, rhs in
                (lhs.conversation.timestamp ?? .distantPast) < (rhs.conversation.timestamp ?? .distantPast)
            }

        for session in evictionCandidates.prefix(max(0, sessions.count - maxCachedSessions + 1)) {
            guard let id = session.conversation.id else { continue }
            session.stopListening()
            sessions.removeValue(forKey: id)
            conversationById.removeValue(forKey: id)
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
        MessageIngestService.shared.resetOnSignOut()
        MessageCatchUpService.shared.resetOnSignOut()
        ownerUserId = currentUserId
        syncInAppFallbackListeners()
    }
}
