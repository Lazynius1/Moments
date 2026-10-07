import Foundation
import FirebaseAuth

@MainActor
final class MessageCatchUpService {
    static let shared = MessageCatchUpService()

    private var lastFullSyncAt: Date?
    private var inFlightConversationIds = Set<String>()
    /// `conversation.timestamp` ya cubierto por una pasada completa: si el doc no ha
    /// avanzado desde entonces no hay mensajes nuevos que traer.
    private var syncedConversationTimestamps: [String: Date] = [:]
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

        let batch = prioritized
            .filter { conversation in
                guard let conversationId = conversation.id,
                      let synced = syncedConversationTimestamps[conversationId] else { return true }
                return conversation.timestamp > synced
            }
            .prefix(maxConversationsPerSync)
        guard !batch.isEmpty else { return }

        Task {
            await preloadKeys(for: batch.compactMap(\.id))
            await withTaskGroup(of: Void.self) { group in
                for conversation in batch {
                    guard let conversationId = conversation.id else { continue }
                    let timestamp = conversation.timestamp
                    group.addTask {
                        await self.syncAndRecord(conversationId: conversationId, conversationTimestamp: timestamp)
                    }
                }
            }
        }
    }

    private func syncAndRecord(conversationId: String, conversationTimestamp: Date) async {
        // Solo se recuerda si la pasada terminó sin errores de red.
        if await sync(conversationId: conversationId) {
            syncedConversationTimestamps[conversationId] = conversationTimestamp
        }
    }

    /// Devuelve false si alguna página falló (o no se pudo ejecutar la pasada).
    @discardableResult
    func sync(conversationId: String) async -> Bool {
        guard LocalFirstMessagingSettings.isEnabled else { return false }
        guard Auth.auth().currentUser != nil else { return false }
        guard !conversationId.isEmpty else { return false }
        guard !inFlightConversationIds.contains(conversationId) else { return false }

        inFlightConversationIds.insert(conversationId)
        defer { inFlightConversationIds.remove(conversationId) }

        var ingestedCount = 0
        let maxPages = maxCatchUpMessagesPerSync / catchUpPageSize

        for _ in 0..<maxPages {
            guard ingestedCount < maxCatchUpMessagesPerSync else { break }

            let cursor = await resolveCatchUpCursor(for: conversationId)

            let pageLimit = min(catchUpPageSize, maxCatchUpMessagesPerSync - ingestedCount)
            guard let messages = await fetchCatchUpPage(
                conversationId: conversationId,
                cursor: cursor,
                limit: pageLimit
            ) else {
                return false
            }
            guard !messages.isEmpty else { break }

            _ = await MessageIngestService.shared.ingestBatch(
                messages,
                conversationId: conversationId,
                source: .catchUp
            )
            ingestedCount += messages.count

            if messages.count < pageLimit { break }
        }
        return true
    }

    private func resolveCatchUpCursor(for conversationId: String) async -> MessageSyncCursor? {
        if let stored = MessageSyncCursorStore.cursor(for: conversationId),
           !stored.messageId.isEmpty {
            return stored
        }
        if let local = await LocalPersistenceService.shared.lastMessageSyncCursorInBackground(for: conversationId) {
            return local
        }
        return MessageSyncCursorStore.cursor(for: conversationId)
    }

    private func fetchCatchUpPage(
        conversationId: String,
        cursor: MessageSyncCursor?,
        limit: Int
    ) async -> [EnhancedMessage]? {
        if let cursor {
            return await fetchMessagesAfter(conversationId: conversationId, after: cursor, limit: limit)
        }
        return await fetchRecentMessages(conversationId: conversationId, limit: limit)
    }

    private func fetchRecentMessages(conversationId: String, limit: Int) async -> [EnhancedMessage]? {
        await withCheckedContinuation { continuation in
            ChatService.shared.fetchRecentMessages(conversationId: conversationId, limit: limit) { result in
                switch result {
                case .success(let messages):
                    continuation.resume(returning: messages)
                case .failure:
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func fetchMessagesAfter(
        conversationId: String,
        after cursor: MessageSyncCursor,
        limit: Int
    ) async -> [EnhancedMessage]? {
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
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    /// Tras vaciar la caché local hay que volver a traer todo aunque el doc no cambie.
    func forgetSyncedConversationTimestamps() {
        syncedConversationTimestamps.removeAll()
        lastFullSyncAt = nil
    }

    func resetOnSignOut() {
        lastFullSyncAt = nil
        inFlightConversationIds.removeAll()
        syncedConversationTimestamps.removeAll()
    }

    private func preloadKeys(for conversationIds: [String]) async {
        guard !conversationIds.isEmpty else { return }
        await EncryptionService.shared.preloadConversationKeys(for: conversationIds)
    }
}
