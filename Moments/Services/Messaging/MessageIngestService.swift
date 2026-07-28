import Foundation
import FirebaseAuth

enum MessageIngestSource: String {
    case push
    case notificationExtension
    case catchUp
    case manual
}

@MainActor
final class MessageIngestService {
    static let shared = MessageIngestService()

    private var inFlightKeys = Set<String>()
    private var recentlyIngestedKeys = Set<String>()

    private init() {}

    func resetOnSignOut() {
        inFlightKeys.removeAll()
        recentlyIngestedKeys.removeAll()
        MessageIngestQueue.clear()
        MessageSyncCursorStore.clearAll()
        LocalPersistenceService.shared.clearAllChatCache()
    }

    /// Purga el caché local tras restaurar la identidad de chat.
    ///
    /// El descifrado ocurre al ingerir y, cuando falla, el contenido se guarda tal cual en cifrado
    /// (`decryptChatMessage(...) ?? content`). Los mensajes que entraron por push o catch-up
    /// mientras la identidad no estaba disponible quedaron persistidos ilegibles: sin tirar el
    /// caché seguirían mostrándose así aunque ya haya clave buena. Al vaciarlo se vuelven a bajar
    /// de Firestore y se descifran con la identidad restaurada.
    func resetAfterIdentityRestore() {
        inFlightKeys.removeAll()
        recentlyIngestedKeys.removeAll()
        MessageSyncCursorStore.clearAll()
        LocalPersistenceService.shared.clearAllChatCache()
    }

    func drainPendingQueue() async {
        guard LocalFirstMessagingSettings.isEnabled else { return }
        guard Auth.auth().currentUser != nil else { return }

        let pending = MessageIngestQueue.drainAll()
        guard !pending.isEmpty else { return }

        var processed: [PendingMessageIngest] = []
        for item in pending {
            let didIngest = await ingest(
                conversationId: item.conversationId,
                messageId: item.messageId,
                source: .notificationExtension
            )
            if didIngest {
                processed.append(item)
            }
        }

        if processed.count != pending.count {
            let unprocessed = pending.filter { item in
                !processed.contains(where: { $0.conversationId == item.conversationId && $0.messageId == item.messageId })
            }
            for item in unprocessed {
                MessageIngestQueue.enqueue(conversationId: item.conversationId, messageId: item.messageId)
            }
        }
    }

    @discardableResult
    func ingest(userInfo: [AnyHashable: Any]) async -> Bool {
        guard LocalFirstMessagingSettings.isEnabled else { return false }

        let type = (userInfo["type"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard type == "message" || type == "new_message" else { return false }

        guard let conversationId = userInfo["conversationId"] as? String,
              let messageId = userInfo["messageId"] as? String else {
            return false
        }

        return await ingest(conversationId: conversationId, messageId: messageId, source: .push)
    }

    @discardableResult
    func ingestBatch(
        _ messages: [EnhancedMessage],
        conversationId: String,
        source: MessageIngestSource
    ) async -> Int {
        guard LocalFirstMessagingSettings.isEnabled else { return 0 }
        guard !messages.isEmpty else { return 0 }

        let sorted = messages.sorted {
            if $0.timestamp != $1.timestamp {
                return $0.timestamp < $1.timestamp
            }
            return $0.id < $1.id
        }
        await LocalPersistenceService.shared.saveMessagesInBackground(
            sorted,
            conversationId: conversationId,
            sync: false
        )

        if let latestCursor = latestSyncCursor(in: sorted) {
            let stored = MessageSyncCursorStore.cursor(for: conversationId)
            let next: MessageSyncCursor
            if let stored {
                next = latestCursor.isAfter(stored) ? latestCursor : stored
            } else {
                next = latestCursor
            }
            MessageSyncCursorStore.updateCursor(for: conversationId, cursor: next)
            if let latest = sorted.last {
                LocalPersistenceService.shared.upsertConversationPreview(from: latest)
            }
        }

        for message in sorted {
            rememberIngestedKey(dedupKey(conversationId: conversationId, messageId: message.id))
        }

        // Doble check fiable: delivered se marca al ingerir por cualquier canal,
        // no solo cuando iOS entrega el push.
        if let currentUserId = Auth.auth().currentUser?.uid {
            ChatService.shared.markMessagesAsDelivered(
                messages: sorted,
                conversationId: conversationId,
                currentUserId: currentUserId
            )
        }

        // Precarga proactiva de media según la política de auto-descarga.
        ChatMediaPrefetcher.shared.prefetchIfNeeded(sorted)

        NotificationCenter.default.post(
            name: .messagesIngested,
            object: nil,
            userInfo: [
                "conversationId": conversationId,
                "messageIds": sorted.map(\.id),
                "source": source.rawValue
            ]
        )

        return sorted.count
    }

    @discardableResult
    func ingest(
        conversationId: String,
        messageId: String,
        source: MessageIngestSource
    ) async -> Bool {
        guard LocalFirstMessagingSettings.isEnabled else { return false }
        guard Auth.auth().currentUser != nil else { return false }

        let conversationId = conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
        let messageId = messageId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !conversationId.isEmpty, !messageId.isEmpty else { return false }

        let key = dedupKey(conversationId: conversationId, messageId: messageId)
        if recentlyIngestedKeys.contains(key) {
            return true
        }
        if inFlightKeys.contains(key) {
            return false
        }
        if await LocalPersistenceService.shared.messageExistsInBackground(
            conversationId: conversationId,
            messageId: messageId
        ) {
            rememberIngestedKey(key)
            return true
        }

        inFlightKeys.insert(key)
        defer { inFlightKeys.remove(key) }

        let message: EnhancedMessage? = await withCheckedContinuation { continuation in
            ChatService.shared.fetchMessage(conversationId: conversationId, messageId: messageId) { result in
                switch result {
                case .success(let message):
                    continuation.resume(returning: message)
                case .failure:
                    continuation.resume(returning: nil)
                }
            }
        }

        guard let message else {
            return false
        }

        await LocalPersistenceService.shared.saveMessagesInBackground(
            [message],
            conversationId: conversationId,
            sync: false
        )
        LocalPersistenceService.shared.upsertConversationPreview(from: message)
        ChatMediaPrefetcher.shared.prefetchIfNeeded([message])

        if let currentUserId = Auth.auth().currentUser?.uid {
            ChatService.shared.markMessagesAsDelivered(
                messages: [message],
                conversationId: conversationId,
                currentUserId: currentUserId
            )
        }

        // El cursor NO avanza aquí: APNs colapsa/descarta pushes, y saltar hasta este
        // mensaje dejaría fuera para siempre a los intermedios que nunca llegaron.
        // El catch-up pagina contiguo desde el cursor almacenado y lo avanza él.
        Task {
            await MessageCatchUpService.shared.sync(conversationId: conversationId)
        }

        rememberIngestedKey(key)

        ChatCommunicationNotificationService.donateFromPush(
            userInfo: [
                "type": "new_message",
                "conversationId": conversationId,
                "messageId": messageId,
                "senderId": message.senderId
            ],
            previewBody: message.content
        )

        NotificationCenter.default.post(
            name: .messagesIngested,
            object: nil,
            userInfo: [
                "conversationId": conversationId,
                "messageIds": [messageId],
                "source": source.rawValue
            ]
        )

        return true
    }

    private func dedupKey(conversationId: String, messageId: String) -> String {
        "\(conversationId):\(messageId)"
    }

    /// El set de dedup no puede crecer sin límite en sesiones largas; al superar el
    /// tope se vacía y el dedup cae al check de existencia en SwiftData (barato).
    private func rememberIngestedKey(_ key: String) {
        if recentlyIngestedKeys.count > 4000 {
            recentlyIngestedKeys.removeAll(keepingCapacity: true)
        }
        recentlyIngestedKeys.insert(key)
    }

    private func latestSyncCursor(in messages: [EnhancedMessage]) -> MessageSyncCursor? {
        messages.reduce(into: Optional<MessageSyncCursor>.none) { latest, message in
            let candidate = MessageSyncCursor(timestamp: message.timestamp, messageId: message.id)
            guard let current = latest else {
                latest = candidate
                return
            }
            if candidate.isAfter(current) {
                latest = candidate
            }
        }
    }
}
