import Foundation
import FirebaseAuth

@MainActor
final class MessageCatchUpService {
    static let shared = MessageCatchUpService()

    private var lastFullSyncAt: Date?
    private var inFlightConversationIds = Set<String>()
    private let fullSyncInterval: TimeInterval = 30
    private let maxConversationsPerSync = 20
    private let catchUpPageSize = 50
    /// Máximo de mensajes ingeridos por conversación y pasada de sync.
    private let maxCatchUpMessagesPerSync = 500

    private init() {}

    func syncRecent(conversations: [Conversation]) {
        guard LocalFirstMessagingSettings.isEnabled else { return }
        guard Auth.auth().currentUser != nil else { return }

        let now = Date()
        if let lastFullSyncAt, now.timeIntervalSince(lastFullSyncAt) < fullSyncInterval {
            return
        }
        lastFullSyncAt = now

        let userId = Auth.auth().currentUser?.uid ?? ""
        let prioritized = conversations.sorted { lhs, rhs in
            let lhsUnread = !(lhs.readStatus[userId] ?? true)
            let rhsUnread = !(rhs.readStatus[userId] ?? true)
            if lhsUnread != rhsUnread { return lhsUnread && !rhsUnread }
            return lhs.timestamp > rhs.timestamp
        }

        let batch = prioritized.prefix(maxConversationsPerSync)

        Task {
            await preloadKeys(for: batch.compactMap(\.id))
            for conversation in batch {
                guard let conversationId = conversation.id else { continue }
                await sync(conversationId: conversationId)
            }
        }
    }

    func sync(conversationId: String) async {
        guard LocalFirstMessagingSettings.isEnabled else { return }
        guard Auth.auth().currentUser != nil else { return }
        guard !conversationId.isEmpty else { return }
        guard !inFlightConversationIds.contains(conversationId) else { return }

        inFlightConversationIds.insert(conversationId)
        defer { inFlightConversationIds.remove(conversationId) }

        var ingestedCount = 0
        let maxPages = maxCatchUpMessagesPerSync / catchUpPageSize

        for _ in 0..<maxPages {
            guard ingestedCount < maxCatchUpMessagesPerSync else { break }

            let cursor = resolveCatchUpCursor(for: conversationId)

            let pageLimit = min(catchUpPageSize, maxCatchUpMessagesPerSync - ingestedCount)
            let messages = await fetchCatchUpPage(
                conversationId: conversationId,
                cursor: cursor,
                limit: pageLimit
            )
            guard !messages.isEmpty else { break }

            _ = MessageIngestService.shared.ingestBatch(messages, conversationId: conversationId, source: .catchUp)
            ingestedCount += messages.count

            if messages.count < pageLimit { break }
        }
    }

    private func resolveCatchUpCursor(for conversationId: String) -> MessageSyncCursor? {
        if let stored = MessageSyncCursorStore.cursor(for: conversationId),
           !stored.messageId.isEmpty {
            return stored
        }
        if let local = LocalPersistenceService.shared.lastMessageSyncCursor(for: conversationId) {
            return local
        }
        return MessageSyncCursorStore.cursor(for: conversationId)
    }

    private func fetchCatchUpPage(
        conversationId: String,
        cursor: MessageSyncCursor?,
        limit: Int
    ) async -> [EnhancedMessage] {
        if let cursor {
            return await fetchMessagesAfter(conversationId: conversationId, after: cursor, limit: limit)
        }
        return await fetchRecentMessages(conversationId: conversationId, limit: limit)
    }

    private func fetchRecentMessages(conversationId: String, limit: Int) async -> [EnhancedMessage] {
        await withCheckedContinuation { continuation in
            ChatService.shared.fetchRecentMessages(conversationId: conversationId, limit: limit) { result in
                switch result {
                case .success(let messages):
                    continuation.resume(returning: messages)
                case .failure:
                    continuation.resume(returning: [])
                }
            }
        }
    }

    private func fetchMessagesAfter(
        conversationId: String,
        after cursor: MessageSyncCursor,
        limit: Int
    ) async -> [EnhancedMessage] {
        await withCheckedContinuation { continuation in
            ChatService.shared.fetchMessagesAfter(
                conversationId: conversationId,
                after: cursor,
                limit: limit
            ) { result in
                switch result {
                case .success(let messages):
                    continuation.resume(returning: messages)
                case .failure:
                    continuation.resume(returning: [])
                }
            }
        }
    }

    func resetOnSignOut() {
        lastFullSyncAt = nil
        inFlightConversationIds.removeAll()
    }

    private func preloadKeys(for conversationIds: [String]) async {
        guard !conversationIds.isEmpty else { return }
        await EncryptionService.shared.preloadConversationKeys(for: conversationIds)
    }
}
