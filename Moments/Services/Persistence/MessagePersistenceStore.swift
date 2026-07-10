import Foundation
import SwiftData

/// Contexto SwiftData dedicado a mensajes. Nunca comparte `mainContext` con la UI.
/// Los mensajes cruzan el límite del actor codificados para no enviar instancias
/// `@Model` ni `ObservableObject` entre ejecutores.
@ModelActor
actor MessagePersistenceStore {
    private let maxMessagesPerConversation = 2_000

    func save(
        encodedMessages: Data,
        conversationId: String,
        sync: Bool
    ) throws {
        let messages = try JSONDecoder().decode([EnhancedMessage].self, from: encodedMessages)
        guard !messages.isEmpty || sync else { return }

        if sync {
            let predicate = #Predicate<CachedMessage> { $0.conversationId == conversationId }
            try modelContext.delete(model: CachedMessage.self, where: predicate)
        }

        let messageIds = messages.map(\.id)
        let predicate = #Predicate<CachedMessage> { messageIds.contains($0.id) }
        let existing = try modelContext.fetch(FetchDescriptor<CachedMessage>(predicate: predicate))
        let existingById = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })

        for message in messages {
            let cached = CachedMessage.from(message)
            if let current = existingById[message.id] {
                merge(cached, into: current)
            } else {
                modelContext.insert(cached)
            }
        }

        try modelContext.save()
        try trimMessages(for: conversationId)
    }

    func reconcile(encodedMessages: Data, conversationId: String) throws {
        let messages = try JSONDecoder().decode([EnhancedMessage].self, from: encodedMessages)
        guard !messages.isEmpty else { return }
        try save(encodedMessages: encodedMessages, conversationId: conversationId, sync: false)

        guard let oldestRemoteTimestamp = messages.map(\.timestamp).min() else { return }
        let remoteIds = Set(messages.map(\.id))
        let predicate = #Predicate<CachedMessage> {
            $0.conversationId == conversationId && $0.timestamp >= oldestRemoteTimestamp
        }
        let cachedWindow = try modelContext.fetch(FetchDescriptor<CachedMessage>(predicate: predicate))
        for cached in cachedWindow where !remoteIds.contains(cached.id) {
            modelContext.delete(cached)
        }
        if modelContext.hasChanges {
            try modelContext.save()
        }
    }

    func recentMessages(
        conversationId: String,
        limit: Int,
        cutoffDate: Date?
    ) throws -> Data {
        guard limit > 0 else { return Data() }

        let predicate = #Predicate<CachedMessage> { $0.conversationId == conversationId }
        var descriptor = FetchDescriptor<CachedMessage>(
            predicate: predicate,
            sortBy: [
                SortDescriptor(\.timestamp, order: .reverse),
                SortDescriptor(\.id, order: .reverse)
            ]
        )
        descriptor.fetchLimit = limit

        var cached = try modelContext.fetch(descriptor)
        if let cutoffDate {
            cached.removeAll { $0.timestamp <= cutoffDate }
        }
        let messages = cached.reversed().map { $0.toEnhancedMessage() }
        return try JSONEncoder().encode(messages)
    }

    func messagesBefore(
        conversationId: String,
        cursor: MessageSyncCursor,
        cutoffDate: Date?,
        limit: Int
    ) throws -> Data {
        guard limit > 0 else { return Data() }

        let cutoff = cutoffDate
        let predicate = #Predicate<CachedMessage> {
            $0.conversationId == conversationId
                && (cutoff == nil || $0.timestamp > cutoff!)
                && (
                    $0.timestamp < cursor.timestamp
                        || ($0.timestamp == cursor.timestamp && $0.id < cursor.messageId)
                )
        }
        var descriptor = FetchDescriptor<CachedMessage>(
            predicate: predicate,
            sortBy: [
                SortDescriptor(\.timestamp, order: .reverse),
                SortDescriptor(\.id, order: .reverse)
            ]
        )
        descriptor.fetchLimit = limit

        let messages = try modelContext.fetch(descriptor).reversed().map { $0.toEnhancedMessage() }
        return try JSONEncoder().encode(messages)
    }

    func messagesAfter(
        conversationId: String,
        cursor: MessageSyncCursor,
        cutoffDate: Date?,
        limit: Int
    ) throws -> Data {
        guard limit > 0 else { return Data() }

        let cutoff = cutoffDate
        let predicate = #Predicate<CachedMessage> {
            $0.conversationId == conversationId
                && (cutoff == nil || $0.timestamp > cutoff!)
                && (
                    $0.timestamp > cursor.timestamp
                        || ($0.timestamp == cursor.timestamp && $0.id >= cursor.messageId)
                )
        }
        var descriptor = FetchDescriptor<CachedMessage>(
            predicate: predicate,
            sortBy: [
                SortDescriptor(\.timestamp, order: .forward),
                SortDescriptor(\.id, order: .forward)
            ]
        )
        descriptor.fetchLimit = limit

        let messages = try modelContext.fetch(descriptor).map { $0.toEnhancedMessage() }
        return try JSONEncoder().encode(messages)
    }

    func allMessages(conversationId: String) throws -> Data {
        let predicate = #Predicate<CachedMessage> { $0.conversationId == conversationId }
        let descriptor = FetchDescriptor<CachedMessage>(
            predicate: predicate,
            sortBy: [
                SortDescriptor(\.timestamp, order: .forward),
                SortDescriptor(\.id, order: .forward)
            ]
        )
        let messages = try modelContext.fetch(descriptor).map { $0.toEnhancedMessage() }
        return try JSONEncoder().encode(messages)
    }

    func containsMessage(conversationId: String, messageId: String) throws -> Bool {
        let predicate = #Predicate<CachedMessage> {
            $0.conversationId == conversationId && $0.id == messageId
        }
        var descriptor = FetchDescriptor<CachedMessage>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try modelContext.fetchCount(descriptor) > 0
    }

    func lastCursor(conversationId: String) throws -> MessageSyncCursor? {
        let predicate = #Predicate<CachedMessage> { $0.conversationId == conversationId }
        var descriptor = FetchDescriptor<CachedMessage>(
            predicate: predicate,
            sortBy: [
                SortDescriptor(\.timestamp, order: .reverse),
                SortDescriptor(\.id, order: .reverse)
            ]
        )
        descriptor.fetchLimit = 1
        guard let message = try modelContext.fetch(descriptor).first else { return nil }
        return MessageSyncCursor(timestamp: message.timestamp, messageId: message.id)
    }

    private func trimMessages(for conversationId: String) throws {
        let predicate = #Predicate<CachedMessage> { $0.conversationId == conversationId }
        var descriptor = FetchDescriptor<CachedMessage>(
            predicate: predicate,
            sortBy: [
                SortDescriptor(\.timestamp, order: .reverse),
                SortDescriptor(\.id, order: .reverse)
            ]
        )
        descriptor.fetchOffset = maxMessagesPerConversation

        let overflow = try modelContext.fetch(descriptor)
        guard !overflow.isEmpty else { return }
        let evictedIds = overflow.map(\.id)
        for message in overflow {
            modelContext.delete(message)
        }
        try modelContext.save()

        Task.detached(priority: .utility) {
            for messageId in evictedIds {
                ChatCacheStore.deleteMessageFiles(
                    conversationId: conversationId,
                    messageId: messageId
                )
            }
        }
    }

    private func merge(_ new: CachedMessage, into existing: CachedMessage) {
        existing.typeString = new.typeString
        existing.isDeleted = new.isDeleted
        existing.deletedAt = new.deletedAt

        if new.isDeleted {
            existing.content = nil
            existing.mediaUrl = nil
            existing.thumbnailUrl = nil
            existing.mediaObjectPath = nil
            existing.thumbnailObjectPath = nil
            existing.mediaEncryptionData = nil
            existing.thumbnailEncryptionData = nil
            existing.audioWaveformData = nil
        } else {
            existing.content = new.content
            if !shouldPreserveLocalMediaURL(existing.mediaUrl) {
                existing.mediaUrl = new.mediaUrl
            }
            if !shouldPreserveLocalMediaURL(existing.thumbnailUrl) {
                existing.thumbnailUrl = new.thumbnailUrl
            }
            existing.mediaObjectPath = new.mediaObjectPath
            existing.thumbnailObjectPath = new.thumbnailObjectPath
            existing.mediaEncryptionData = new.mediaEncryptionData
            existing.thumbnailEncryptionData = new.thumbnailEncryptionData
            existing.audioWaveformData = new.audioWaveformData
        }

        existing.mediaBatchId = new.mediaBatchId
        existing.duration = new.duration
        existing.fileName = new.fileName
        existing.fileSize = new.fileSize
        existing.mediaWidth = new.mediaWidth
        existing.mediaHeight = new.mediaHeight
        existing.latitude = new.latitude
        existing.longitude = new.longitude
        existing.statusString = new.statusString
        existing.isRead = existing.isRead || new.isRead
        existing.editedAt = new.editedAt
        existing.reactionsData = new.reactionsData
        existing.replyTo = new.replyTo
        existing.expirationDate = new.expirationDate
        existing.isViewed = new.isViewed
        existing.storyReplyDataEncoded = new.storyReplyDataEncoded
        existing.sharedMomentDataEncoded = new.sharedMomentDataEncoded
        existing.sharedStoryDataEncoded = new.sharedStoryDataEncoded
        existing.textOverlayLive = new.textOverlayLive
        existing.textOverlaysData = new.textOverlaysData
        existing.stickersData = new.stickersData
        existing.drawingData = new.drawingData
        existing.viewedBy = new.viewedBy
        existing.isVanishModeMessage = new.isVanishModeMessage
        existing.vanishedFor = Array(Set(existing.vanishedFor + new.vanishedFor))
        existing.vanishExpiresAt = new.vanishExpiresAt ?? existing.vanishExpiresAt
        existing.lastSyncedAt = Date()
    }

    private func shouldPreserveLocalMediaURL(_ value: String?) -> Bool {
        guard let value,
              let url = URL(string: value),
              url.isFileURL else {
            return false
        }
        return FileManager.default.fileExists(atPath: url.path)
    }
}
