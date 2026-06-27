import Foundation

struct PendingMessageIngest: Codable, Equatable {
    let conversationId: String
    let messageId: String
    let enqueuedAt: Date
}

enum MessageIngestQueue {
    static let appGroupID = "group.com.glowsyapp"
    private static let fileName = "pending_message_ingest.json"
    private static let lock = NSLock()

    static func enqueue(conversationId: String, messageId: String) {
        let conversationId = conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
        let messageId = messageId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !conversationId.isEmpty, !messageId.isEmpty else { return }

        lock.lock()
        defer { lock.unlock() }

        var pending = readPendingUnsafe()
        let item = PendingMessageIngest(
            conversationId: conversationId,
            messageId: messageId,
            enqueuedAt: Date()
        )
        guard !pending.contains(where: { $0.conversationId == item.conversationId && $0.messageId == item.messageId }) else {
            return
        }
        pending.append(item)
        writePendingUnsafe(pending)
    }

    static func drainAll() -> [PendingMessageIngest] {
        lock.lock()
        defer { lock.unlock() }
        let pending = readPendingUnsafe()
        writePendingUnsafe([])
        return pending
    }

    static func remove(processed: [PendingMessageIngest]) {
        guard !processed.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }

        let processedKeys = Set(processed.map { "\($0.conversationId):\($0.messageId)" })
        let remaining = readPendingUnsafe().filter {
            !processedKeys.contains("\($0.conversationId):\($0.messageId)")
        }
        writePendingUnsafe(remaining)
    }

    static func clear() {
        lock.lock()
        defer { lock.unlock() }
        writePendingUnsafe([])
    }

    private static func queueFileURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(fileName)
    }

    private static func readPendingUnsafe() -> [PendingMessageIngest] {
        guard let url = queueFileURL(),
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return []
        }
        return (try? JSONDecoder().decode([PendingMessageIngest].self, from: data)) ?? []
    }

    private static func writePendingUnsafe(_ pending: [PendingMessageIngest]) {
        guard let url = queueFileURL() else { return }
        guard let data = try? JSONEncoder().encode(pending) else { return }
        try? data.write(to: url, options: [.atomic])
    }
}

enum MessageSyncCursorStore {
    private static let appGroupID = MessageIngestQueue.appGroupID
    private static let prefix = "messageSyncCursor_"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    static func cursor(for conversationId: String) -> Date? {
        let key = prefix + conversationId
        let timestamp = defaults?.double(forKey: key) ?? 0
        guard timestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }

    static func updateCursor(for conversationId: String, timestamp: Date) {
        defaults?.set(timestamp.timeIntervalSince1970, forKey: prefix + conversationId)
    }

    static func clearAll() {
        guard let defaults else { return }
        defaults.dictionaryRepresentation().keys
            .filter { $0.hasPrefix(prefix) }
            .forEach { defaults.removeObject(forKey: $0) }
    }
}
