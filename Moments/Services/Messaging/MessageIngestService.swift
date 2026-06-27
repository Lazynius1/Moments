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
    func ingestBatch(_ messages: [EnhancedMessage], conversationId: String, source: MessageIngestSource) -> Int {
        guard LocalFirstMessagingSettings.isEnabled else { return 0 }
        guard !messages.isEmpty else { return 0 }

        let sorted = messages.sorted { $0.timestamp < $1.timestamp }
        LocalPersistenceService.shared.saveMessages(sorted, conversationId: conversationId, sync: false)

        if let latest = sorted.last {
            LocalPersistenceService.shared.upsertConversationPreview(from: latest)
            MessageSyncCursorStore.updateCursor(for: conversationId, timestamp: latest.timestamp)
        }

        for message in sorted {
            recentlyIngestedKeys.insert(dedupKey(conversationId: conversationId, messageId: message.id))
        }

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
        if LocalPersistenceService.shared.messageExists(conversationId: conversationId, messageId: messageId) {
            recentlyIngestedKeys.insert(key)
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

        LocalPersistenceService.shared.saveMessages([message], conversationId: conversationId, sync: false)
        LocalPersistenceService.shared.upsertConversationPreview(from: message)
        MessageSyncCursorStore.updateCursor(for: conversationId, timestamp: message.timestamp)

        recentlyIngestedKeys.insert(key)

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
}
