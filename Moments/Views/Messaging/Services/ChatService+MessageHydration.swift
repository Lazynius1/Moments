import Foundation
import FirebaseFirestore
import FirebaseAuth

final class ViewOnceReplaySessionStore {
    struct PendingReplay {
        let conversationId: String
        let messageId: String
        let viewerId: String
    }

    static let shared = ViewOnceReplaySessionStore()

    private let queue = DispatchQueue(label: "com.moments.viewOnceReplaySessionStore")
    private var availableKeys: Set<String> = []
    private var consumedKeys: Set<String> = []

    private init() {}

    func markAvailable(message: EnhancedMessage, viewerId: String) {
        guard let key = key(message: message, viewerId: viewerId) else { return }
        queue.sync {
            availableKeys.insert(key)
            consumedKeys.remove(key)
        }
    }

    func markConsumed(message: EnhancedMessage, viewerId: String) {
        guard let key = key(message: message, viewerId: viewerId) else { return }
        queue.sync {
            availableKeys.remove(key)
            consumedKeys.insert(key)
        }
    }

    func apply(to message: EnhancedMessage, viewerId: String?) {
        guard let viewerId, let key = key(message: message, viewerId: viewerId) else { return }

        let state = queue.sync {
            (available: availableKeys.contains(key), consumed: consumedKeys.contains(key))
        }

        guard state.available || state.consumed else { return }

        if state.available, message.allowReplay == true, !message.hasBeenReplayedBy(userId: viewerId) {
            message.replayAvailableInCurrentChatSession = true
            message.replayConsumedInCurrentChatSession = false
        } else if state.consumed {
            message.replayAvailableInCurrentChatSession = false
            message.replayConsumedInCurrentChatSession = true
        }
    }

    func clear(conversationId: String) {
        _ = drainAvailable(conversationId: conversationId)
    }

    func drainAvailable(conversationId: String) -> [PendingReplay] {
        let prefix = conversationId + "|"
        return queue.sync {
            let pending = availableKeys
                .filter { $0.hasPrefix(prefix) }
                .compactMap(Self.pendingReplay(from:))
            availableKeys = Set(availableKeys.filter { !$0.hasPrefix(prefix) })
            consumedKeys = Set(consumedKeys.filter { !$0.hasPrefix(prefix) })
            return pending
        }
    }

    private func key(message: EnhancedMessage, viewerId: String) -> String? {
        guard message.isViewOnce,
              message.allowReplay == true,
              message.senderId != viewerId,
              !viewerId.isEmpty else {
            return nil
        }
        return "\(message.conversationId)|\(message.id)|\(viewerId)"
    }

    private static func pendingReplay(from key: String) -> PendingReplay? {
        let parts = key.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3 else { return nil }
        return PendingReplay(conversationId: parts[0], messageId: parts[1], viewerId: parts[2])
    }
}

extension ChatService {
    func createBasicMessageData(from message: EnhancedMessage) -> [String: Any] {
        var data: [String: Any] = [
            "id": message.id,
            "conversationId": message.conversationId,
            "senderId": message.senderId,
            "type": message.type.rawValue,
            "timestamp": FieldValue.serverTimestamp(),
            "status": MessageStatus.sent.rawValue,
            "isRead": message.isRead,
            "isDeleted": message.isDeleted,
            "isViewed": message.isViewed
        ]

        if let mediaObjectPath = message.mediaObjectPath {
            data["mediaObjectPath"] = mediaObjectPath
        } else if let mediaUrl = message.mediaUrl {
            data["mediaUrl"] = mediaUrl
        }
        if let thumbnailObjectPath = message.thumbnailObjectPath {
            data["thumbnailObjectPath"] = thumbnailObjectPath
        } else if let thumbnailUrl = message.thumbnailUrl {
            data["thumbnailUrl"] = thumbnailUrl
        }
        if let mediaEncryption = message.mediaEncryption {
            data["mediaEncryption"] = mediaEncryption.firestoreData
        }
        if let thumbnailEncryption = message.thumbnailEncryption {
            data["thumbnailEncryption"] = thumbnailEncryption.firestoreData
        }
        if let duration = message.duration {
            data["duration"] = duration
        }
        if let waveform = message.audioWaveform, !waveform.isEmpty {
            data["audioWaveform"] = waveform.prefix(64).map(Double.init)
        }
        if let fileSize = message.fileSize {
            data["fileSize"] = fileSize
        }
        if let mediaWidth = message.mediaWidth {
            data["mediaWidth"] = mediaWidth
        }
        if let mediaHeight = message.mediaHeight {
            data["mediaHeight"] = mediaHeight
        }
        if let replyTo = message.replyTo {
            data["replyTo"] = replyTo
        }
        if message.isVanishModeMessage == true {
            data["isVanishModeMessage"] = true
        }
        appendOverlayPayload(from: message, to: &data)

        return data
    }

    func buildEnhancedMessage(
        from data: [String: Any],
        docId: String,
        conversationId: String,
        decryptedContentOverride: String? = nil
    ) async -> EnhancedMessage {
        let id = data["id"] as? String ?? docId
        let senderId = data["senderId"] as? String ?? ""
        let typeString = data["type"] as? String ?? MessageType.text.rawValue
        let type = MessageType(rawValue: typeString) ?? .text

        let rawContent = data["content"] as? String
        let decryptedContent: String?
        if type == .chatNotice {
            decryptedContent = rawContent
        } else if let decryptedContentOverride {
            decryptedContent = decryptedContentOverride
        } else if let rawContent {
            decryptedContent = await decryptMessageContent(rawContent, for: conversationId)
        } else {
            decryptedContent = rawContent
        }

        // ✅ Ubicación: las coordenadas viajan cifradas dentro de `content`.
        // Decodificamos el payload y NO exponemos el JSON como texto del mensaje.
        var locationLatitude = data["latitude"] as? Double
        var locationLongitude = data["longitude"] as? Double
        var locationName = data["locationName"] as? String
        var locationAddress = data["locationAddress"] as? String
        let content: String?
        if type == .chatNotice {
            content = rawContent
        } else if type == .location {
            if let decryptedContent, let payload = ChatLocationPayload.decode(decryptedContent) {
                locationLatitude = payload.lat
                locationLongitude = payload.lng
                locationName = payload.name ?? locationName
                locationAddress = payload.address ?? locationAddress
            }
            content = nil
        } else {
            content = decryptedContent
        }

        let mediaObjectPath = data["mediaObjectPath"] as? String
        let thumbnailObjectPath = data["thumbnailObjectPath"] as? String
        let mediaEncryption = (data["mediaEncryption"] as? [String: Any]).flatMap { EncryptedChatMediaMetadata(map: $0) }
        let thumbnailEncryption = (data["thumbnailEncryption"] as? [String: Any]).flatMap { EncryptedChatMediaMetadata(map: $0) }
        let isDeleted = data["isDeleted"] as? Bool ?? false
        let requestContext = data["context"] as? [String: Any] ?? [:]
        let requestContextKind = data["contextKind"] as? String ?? requestContext["kind"] as? String
        var resolvedStoryReplyData = data["storyReplyData"] as? [String: String]
        var resolvedSharedMomentData = data["sharedMomentData"] as? [String: String]
        var resolvedSharedStoryData = data["sharedStoryData"] as? [String: String]
        var resolvedSharedProfileData = data["sharedProfileData"] as? [String: String]
        if resolvedStoryReplyData == nil,
           requestContextKind == MessageRequestInteractionContext.Kind.storyMessage.rawValue {
            resolvedStoryReplyData = [
                "storyId": requestContext["storyId"] as? String ?? "",
                "storyOwnerId": requestContext["storyOwnerId"] as? String ?? ""
            ]
        }
        if resolvedSharedMomentData == nil, requestContextKind == MessageRequestInteractionContext.Kind.shareMoment.rawValue {
            resolvedSharedMomentData = [
                "momentId": requestContext["sharedContentId"] as? String ?? "",
                "momentAuthorId": requestContext["sharedContentOwnerId"] as? String ?? ""
            ]
        }
        if resolvedSharedStoryData == nil, requestContextKind == MessageRequestInteractionContext.Kind.shareStory.rawValue {
            resolvedSharedStoryData = [
                "storyId": requestContext["sharedContentId"] as? String ?? requestContext["storyId"] as? String ?? "",
                "storyAuthorId": requestContext["sharedContentOwnerId"] as? String
                    ?? requestContext["storyOwnerId"] as? String
                    ?? ""
            ]
        }
        if resolvedSharedProfileData == nil, requestContextKind == MessageRequestInteractionContext.Kind.shareProfile.rawValue {
            resolvedSharedProfileData = [
                "profileUserId": requestContext["sharedContentId"] as? String ?? "",
            ]
        }

        let resolvedIsRead = Self.resolvedIncomingIsRead(from: data, senderId: senderId)

        let resolvedMedia: CachedResolvedMedia
        if isDeleted {
            resolvedMedia = CachedResolvedMedia(mediaUrl: nil, thumbnailUrl: nil)
        } else if let mediaObjectPath, !mediaObjectPath.isEmpty, let mediaEncryption {
            resolvedMedia = await resolveEncryptedMediaForDisplay(
                messageId: id,
                conversationId: conversationId,
                mediaObjectPath: mediaObjectPath,
                mediaEncryption: mediaEncryption,
                thumbnailObjectPath: thumbnailObjectPath,
                thumbnailEncryption: thumbnailEncryption
            )
        } else {
            resolvedMedia = CachedResolvedMedia(
                mediaUrl: data["mediaUrl"] as? String,
                thumbnailUrl: data["thumbnailUrl"] as? String
            )
        }

        let parsedMessage = EnhancedMessage(
            id: id,
            conversationId: conversationId,
            senderId: senderId,
            type: type,
            content: content,
            mediaUrl: resolvedMedia.mediaUrl,
            thumbnailUrl: resolvedMedia.thumbnailUrl,
            mediaObjectPath: mediaObjectPath,
            thumbnailObjectPath: thumbnailObjectPath,
            mediaEncryption: mediaEncryption,
            thumbnailEncryption: thumbnailEncryption,
            duration: data["duration"] as? Double,
            audioWaveform: Self.decodeAudioWaveform(from: data["audioWaveform"]),
            fileName: data["fileName"] as? String,
            fileSize: data["fileSize"] as? Int64,
            mediaWidth: data["mediaWidth"] as? Int,
            mediaHeight: data["mediaHeight"] as? Int,
            latitude: locationLatitude,
            longitude: locationLongitude,
            locationName: locationName,
            locationAddress: locationAddress,
            isLiveLocation: data["isLiveLocation"] as? Bool,
            liveLocationExpiresAt: (data["liveLocationExpiresAt"] as? Timestamp)?.dateValue(),
            liveLocationDuration: data["liveLocationDuration"] as? String,
            liveLocationStoppedAt: (data["liveLocationStoppedAt"] as? Timestamp)?.dateValue(),
            liveLocationSessionId: data["liveLocationSessionId"] as? String,
            locationUpdatedAt: (data["locationUpdatedAt"] as? Timestamp)?.dateValue(),
            timestamp: (data["timestamp"] as? Timestamp)?.dateValue() ?? Date(),
            status: MessageStatus(rawValue: data["status"] as? String ?? MessageStatus.sent.rawValue) ?? .sent,
            isRead: resolvedIsRead,
            isDeleted: data["isDeleted"] as? Bool ?? false,
            deletedAt: (data["deletedAt"] as? Timestamp)?.dateValue(),
            editedAt: (data["editedAt"] as? Timestamp)?.dateValue(),
            reactions: data["reactions"] as? [String: [String]],
            replyTo: data["replyTo"] as? String,
            expirationDate: (data["expirationDate"] as? Timestamp)?.dateValue(),
            isViewed: data["isViewed"] as? Bool ?? false,
            storyReplyData: resolvedStoryReplyData,
            sharedMomentData: resolvedSharedMomentData,
            sharedStoryData: resolvedSharedStoryData,
            sharedProfileData: resolvedSharedProfileData,
            mediaBatchId: data["mediaBatchId"] as? String,
            textOverlayLive: data["textOverlayLive"] as? Bool,
            textOverlays: Self.decodeCodableArray(StoryTextOverlayMetadata.self, from: data["textOverlays"]),
            stickers: Self.decodeCodableArray(StickerData.self, from: data["stickers"]),
            drawingData: data["drawingData"] as? Data,
            viewedBy: data["viewedBy"] as? [String],
            readBy: data["readBy"] as? [String],
            readAtBy: (data["readAtBy"] as? [String: Timestamp])?.mapValues { $0.dateValue() },
            starredBy: data["starredBy"] as? [String],
            isForwarded: data["isForwarded"] as? Bool,
            isVanishModeMessage: data["isVanishModeMessage"] as? Bool,
            vanishedFor: data["vanishedFor"] as? [String],
            vanishExpiresAt: (data["vanishExpiresAt"] as? Timestamp)?.dateValue()
        )
        parsedMessage.allowReplay = data["allowReplay"] as? Bool
        parsedMessage.replayedBy = data["replayedBy"] as? [String]
        ViewOnceReplaySessionStore.shared.apply(
            to: parsedMessage,
            viewerId: Auth.auth().currentUser?.uid
        )
        return parsedMessage
    }

    private func appendOverlayPayload(from message: EnhancedMessage, to data: inout [String: Any]) {
        if let textOverlayLive = message.textOverlayLive {
            data["textOverlayLive"] = textOverlayLive
        }
        if let textOverlays = message.textOverlays,
           let encoded = Self.encodeCodableArray(textOverlays),
           !encoded.isEmpty {
            data["textOverlays"] = encoded
        }
        if let stickers = message.stickers,
           let encoded = Self.encodeCodableArray(stickers),
           !encoded.isEmpty {
            data["stickers"] = encoded
        }
        if let drawingData = message.drawingData {
            data["drawingData"] = drawingData
        }
    }

    static func encodeCodableArray<T: Encodable>(_ values: [T]) -> [[String: Any]]? {
        do {
            let data = try JSONEncoder().encode(values)
            return try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        } catch {
            return nil
        }
    }

    static func decodeCodableArray<T: Decodable>(_ type: T.Type, from value: Any?) -> [T]? {
        guard let value else { return nil }
        do {
            let data = try JSONSerialization.data(withJSONObject: value)
            return try JSONDecoder().decode([T].self, from: data)
        } catch {
            return nil
        }
    }

    private static func decodeAudioWaveform(from value: Any?) -> [Float]? {
        guard let values = value as? [Any] else { return nil }
        let samples = values.prefix(64).compactMap { value -> Float? in
            guard let number = value as? NSNumber else { return nil }
            return min(1, max(0, number.floatValue))
        }
        return samples.isEmpty ? nil : samples
    }

    func resolveEncryptedMediaForMessage(_ message: EnhancedMessage, forceDownload: Bool = false) async -> (mediaUrl: String?, thumbnailUrl: String?)? {
        await encryptedMediaResolver.resolveForMessage(message, forceDownload: forceDownload)
    }

    /// Resuelve solo la miniatura del vídeo (cifrada o no) sin descargar el vídeo completo.
    func resolveVideoThumbnail(for message: EnhancedMessage, forceDownload: Bool = false) async -> String? {
        await encryptedMediaResolver.resolveThumbnailURL(for: message, forceDownload: forceDownload)
    }

    /// URLs locales ya descifradas en disco (sin red).
    func warmMessageURLsFromDiskCache(_ message: EnhancedMessage) -> (mediaUrl: String?, thumbnailUrl: String?) {
        encryptedMediaResolver.warmMessageURLsFromDiskCache(message)
    }

    func resolveEncryptedMediaForDisplay(
        messageId: String,
        conversationId: String,
        mediaObjectPath: String,
        mediaEncryption: EncryptedChatMediaMetadata,
        thumbnailObjectPath: String?,
        thumbnailEncryption: EncryptedChatMediaMetadata?
    ) async -> CachedResolvedMedia {
        await encryptedMediaResolver.resolveForDisplay(
            messageId: messageId,
            conversationId: conversationId,
            mediaObjectPath: mediaObjectPath,
            mediaEncryption: mediaEncryption,
            thumbnailObjectPath: thumbnailObjectPath,
            thumbnailEncryption: thumbnailEncryption
        )
    }
}
