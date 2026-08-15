import Foundation
import FirebaseFirestore
import FirebaseAuth

extension ChatService {
    /// Para mensajes entrantes, el estado real de lectura incluye estar en `readBy`
    /// (el campo `isRead` del doc solo refleja read receipts cuando están activos).
    static func resolvedIncomingIsRead(from data: [String: Any], senderId: String) -> Bool {
        let readBy = data["readBy"] as? [String] ?? []
        let docIsRead = data["isRead"] as? Bool ?? false
        if let currentUid = Auth.auth().currentUser?.uid, senderId != currentUid {
            return docIsRead || readBy.contains(currentUid)
        }
        return docIsRead
    }

    /// Local-first: reutiliza mensajes de SwiftData y solo hidrata docs nuevos o con cambio material.
    func buildMessagesFromSnapshotUsingLocalCache(
        documents: [QueryDocumentSnapshot],
        conversationId: String,
        cutoffDate: Date?
    ) async -> [EnhancedMessage] {
        let cached = await MainActor.run {
            LocalPersistenceService.shared.loadMessagesFast(conversationId: conversationId)
        }
        let cachedById = Dictionary(uniqueKeysWithValues: cached.map { ($0.id, $0) })
        let hasLocalCache = !cached.isEmpty
        let currentUserId = Auth.auth().currentUser?.uid

        var indexedMessages: [Int: EnhancedMessage] = [:]
        var indicesNeedingHydration: [(index: Int, doc: QueryDocumentSnapshot, data: [String: Any])] = []
        var orderedIndices: [Int] = []

        for (index, doc) in documents.enumerated() {
            let data = doc.data()

            if let deletedFor = data["deletedFor"] as? [String],
               let currentUserId,
               deletedFor.contains(currentUserId) {
                continue
            }

            if let vanishedFor = data["vanishedFor"] as? [String],
               let currentUserId,
               vanishedFor.contains(currentUserId) {
                continue
            }

            if let cutoff = cutoffDate,
               let msgTimestamp = (data["timestamp"] as? Timestamp)?.dateValue(),
               msgTimestamp <= cutoff {
                continue
            }

            orderedIndices.append(index)
            let messageId = data["id"] as? String ?? doc.documentID

            if hasLocalCache,
               let existing = cachedById[messageId],
               !Self.snapshotNeedsFullHydrate(data: data, cached: existing) {
                var message = existing
                Self.applySnapshotMetadata(to: &message, from: data)
                indexedMessages[index] = message
            } else {
                indicesNeedingHydration.append((index, doc, data))
            }
        }

        if !indicesNeedingHydration.isEmpty {
            await withTaskGroup(of: (Int, EnhancedMessage).self) { group in
                for item in indicesNeedingHydration {
                    group.addTask {
                        let message = await self.buildEnhancedMessage(
                            from: item.data,
                            docId: item.doc.documentID,
                            conversationId: conversationId
                        )
                        return (item.index, message)
                    }
                }
                for await (index, message) in group {
                    indexedMessages[index] = message
                }
            }
        }

        return orderedIndices.compactMap { indexedMessages[$0] }
    }

    private static func snapshotNeedsFullHydrate(data: [String: Any], cached: EnhancedMessage) -> Bool {
        let typeString = data["type"] as? String ?? MessageType.text.rawValue
        if typeString != cached.type.rawValue { return true }

        let remoteEditedAt = (data["editedAt"] as? Timestamp)?.dateValue()
        if remoteEditedAt != cached.editedAt { return true }

        let remoteDeleted = data["isDeleted"] as? Bool ?? false
        if remoteDeleted != cached.isDeleted { return true }

        if typeString == MessageType.chatNotice.rawValue {
            let remoteContent = data["content"] as? String
            if remoteContent != cached.content { return true }
        }

        let remoteMediaPath = data["mediaObjectPath"] as? String
        if remoteMediaPath != cached.mediaObjectPath { return true }

        let remoteThumbPath = data["thumbnailObjectPath"] as? String
        if remoteThumbPath != cached.thumbnailObjectPath { return true }

        if let remoteEncryption = data["mediaEncryption"] as? [String: Any],
           let cachedEncryption = cached.mediaEncryption {
            let remoteMediaId = remoteEncryption["mediaId"] as? String
            if remoteMediaId != cachedEncryption.mediaId { return true }
        } else if (data["mediaEncryption"] != nil) != (cached.mediaEncryption != nil) {
            return true
        }

        if data["content"] != nil, remoteEditedAt != nil { return true }

        // Ubicación en vivo: el cache antiguo no tenía estos campos; sin rehidratar,
        // la bubble se queda como ubicación fija hasta reiniciar / forzar hydrate.
        let remoteIsLive = data["isLiveLocation"] as? Bool
        if remoteIsLive != cached.isLiveLocation { return true }

        let remoteLiveExpiresAt = (data["liveLocationExpiresAt"] as? Timestamp)?.dateValue()
        if remoteLiveExpiresAt != cached.liveLocationExpiresAt { return true }

        let remoteLiveStoppedAt = (data["liveLocationStoppedAt"] as? Timestamp)?.dateValue()
        if remoteLiveStoppedAt != cached.liveLocationStoppedAt { return true }

        let remoteLiveDuration = data["liveLocationDuration"] as? String
        if remoteLiveDuration != cached.liveLocationDuration { return true }

        let remoteLiveSessionId = data["liveLocationSessionId"] as? String
        if remoteLiveSessionId != cached.liveLocationSessionId { return true }

        let remoteLocationUpdatedAt = (data["locationUpdatedAt"] as? Timestamp)?.dateValue()
        if remoteLocationUpdatedAt != cached.locationUpdatedAt { return true }

        let remoteLocationName = data["locationName"] as? String
        if remoteLocationName != cached.locationName { return true }

        let remoteLocationAddress = data["locationAddress"] as? String
        if remoteLocationAddress != cached.locationAddress { return true }

        return false
    }

    private static func applySnapshotMetadata(to message: inout EnhancedMessage, from data: [String: Any]) {
        message.isRead = Self.resolvedIncomingIsRead(from: data, senderId: message.senderId)
        if let statusRaw = data["status"] as? String,
           let status = MessageStatus(rawValue: statusRaw) {
            message.status = status
        }
        if let isDeleted = data["isDeleted"] as? Bool {
            message.isDeleted = isDeleted
        }
        if let deletedAt = (data["deletedAt"] as? Timestamp)?.dateValue() {
            message.deletedAt = deletedAt
        }
        if let isViewed = data["isViewed"] as? Bool {
            message.isViewed = isViewed
        }
        if let viewedBy = data["viewedBy"] as? [String] {
            message.viewedBy = viewedBy
        }
        if let allowReplay = data["allowReplay"] as? Bool {
            message.allowReplay = allowReplay
        }
        if let replayedBy = data["replayedBy"] as? [String] {
            message.replayedBy = replayedBy
        }
        ViewOnceReplaySessionStore.shared.apply(
            to: message,
            viewerId: Auth.auth().currentUser?.uid
        )
        if let readBy = data["readBy"] as? [String] {
            message.readBy = readBy
        }
        if let readAtBy = data["readAtBy"] as? [String: Timestamp] {
            message.readAtBy = readAtBy.mapValues { $0.dateValue() }
        }
        if let starredBy = data["starredBy"] as? [String] {
            message.starredBy = starredBy
        }
        if let isForwarded = data["isForwarded"] as? Bool {
            message.isForwarded = isForwarded
        }
        if let vanishedFor = data["vanishedFor"] as? [String] {
            message.vanishedFor = vanishedFor
        }
        if let vanishExpiresAt = (data["vanishExpiresAt"] as? Timestamp)?.dateValue() {
            message.vanishExpiresAt = vanishExpiresAt
        }
        message.textOverlayLive = data["textOverlayLive"] as? Bool
        message.textOverlays = ChatService.decodeCodableArray(StoryTextOverlayMetadata.self, from: data["textOverlays"])
        message.stickers = ChatService.decodeCodableArray(StickerData.self, from: data["stickers"])
        message.drawingData = data["drawingData"] as? Data

        if message.isDeleted {
            message.mediaUrl = nil
            message.thumbnailUrl = nil
            message.textOverlayLive = nil
            message.textOverlays = nil
            message.stickers = nil
            message.drawingData = nil
        }
    }
}
