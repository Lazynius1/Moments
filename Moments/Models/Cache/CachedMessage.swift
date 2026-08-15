import Foundation
import SwiftData

@Model
final class CachedMessage {
    @Attribute(.unique) var id: String
    var conversationId: String
    var senderId: String
    var typeString: String // Raw value of MessageType
    var content: String?
    var mediaUrl: String?
    var thumbnailUrl: String?
    /// Ruta cifrada en Storage — imprescindible para re-descargar si iOS purga Caches.
    var mediaObjectPath: String?
    var thumbnailObjectPath: String?
    var mediaEncryptionData: Data?
    var thumbnailEncryptionData: Data?
    var mediaBatchId: String?
    var duration: Double?
    var audioWaveformData: Data?
    var fileName: String?
    var fileSize: Int64?
    var mediaWidth: Int?
    var mediaHeight: Int?
    var latitude: Double?
    var longitude: Double?
    /// Ubicación (fija + en vivo). Sin estos campos el snapshot local-first
    /// reutiliza el cache y la bubble pierde el texto live / detenido / countdown.
    var locationName: String?
    var locationAddress: String?
    var isLiveLocation: Bool?
    var liveLocationExpiresAt: Date?
    var liveLocationDuration: String?
    var liveLocationStoppedAt: Date?
    var liveLocationSessionId: String?
    var locationUpdatedAt: Date?
    var timestamp: Date
    var statusString: String // Raw value of MessageStatus
    var isRead: Bool
    var isDeleted: Bool
    var deletedAt: Date?
    var editedAt: Date?
    var reactionsData: Data? // [String: [String]] encoded
    var replyTo: String?
    var expirationDate: Date?
    var isViewed: Bool
    var storyReplyDataEncoded: Data? // [String: String] encoded
    var sharedMomentDataEncoded: Data? // [String: String] encoded
    var sharedStoryDataEncoded: Data? // [String: String] encoded
    var textOverlayLive: Bool?
    var textOverlaysData: Data?
    var stickersData: Data?
    var drawingData: Data?
    var viewedBy: [String]?
    var readBy: [String]?
    var readAtByData: Data?
    var lastSyncedAt: Date
    var isVanishModeMessage: Bool
    var vanishedFor: [String]
    var vanishExpiresAt: Date?

    init(id: String,
         conversationId: String,
         senderId: String,
         typeString: String,
         content: String?,
         mediaUrl: String?,
         thumbnailUrl: String?,
         mediaObjectPath: String? = nil,
         thumbnailObjectPath: String? = nil,
         mediaEncryptionData: Data? = nil,
         thumbnailEncryptionData: Data? = nil,
         mediaBatchId: String? = nil,
         duration: Double?,
         audioWaveformData: Data? = nil,
         fileName: String?,
         fileSize: Int64?,
         mediaWidth: Int? = nil,
         mediaHeight: Int? = nil,
         latitude: Double?,
         longitude: Double?,
         locationName: String? = nil,
         locationAddress: String? = nil,
         isLiveLocation: Bool? = nil,
         liveLocationExpiresAt: Date? = nil,
         liveLocationDuration: String? = nil,
         liveLocationStoppedAt: Date? = nil,
         liveLocationSessionId: String? = nil,
         locationUpdatedAt: Date? = nil,
         timestamp: Date,
         statusString: String,
         isRead: Bool,
         isDeleted: Bool,
         deletedAt: Date?,
         editedAt: Date?,
         reactionsData: Data?,
         replyTo: String?,
         expirationDate: Date?,
         isViewed: Bool,
         storyReplyDataEncoded: Data?,
         sharedMomentDataEncoded: Data?,
         sharedStoryDataEncoded: Data? = nil,
         textOverlayLive: Bool? = nil,
         textOverlaysData: Data? = nil,
         stickersData: Data? = nil,
         drawingData: Data? = nil,
         viewedBy: [String]?,
         readBy: [String]? = nil,
         readAtByData: Data? = nil,
         lastSyncedAt: Date = Date(),
         isVanishModeMessage: Bool = false,
         vanishedFor: [String] = [],
         vanishExpiresAt: Date? = nil) {
        self.id = id
        self.conversationId = conversationId
        self.senderId = senderId
        self.typeString = typeString
        self.content = content
        self.mediaUrl = mediaUrl
        self.thumbnailUrl = thumbnailUrl
        self.mediaObjectPath = mediaObjectPath
        self.thumbnailObjectPath = thumbnailObjectPath
        self.mediaEncryptionData = mediaEncryptionData
        self.thumbnailEncryptionData = thumbnailEncryptionData
        self.mediaBatchId = mediaBatchId
        self.duration = duration
        self.audioWaveformData = audioWaveformData
        self.fileName = fileName
        self.fileSize = fileSize
        self.mediaWidth = mediaWidth
        self.mediaHeight = mediaHeight
        self.latitude = latitude
        self.longitude = longitude
        self.locationName = locationName
        self.locationAddress = locationAddress
        self.isLiveLocation = isLiveLocation
        self.liveLocationExpiresAt = liveLocationExpiresAt
        self.liveLocationDuration = liveLocationDuration
        self.liveLocationStoppedAt = liveLocationStoppedAt
        self.liveLocationSessionId = liveLocationSessionId
        self.locationUpdatedAt = locationUpdatedAt
        self.timestamp = timestamp
        self.statusString = statusString
        self.isRead = isRead
        self.isDeleted = isDeleted
        self.deletedAt = deletedAt
        self.editedAt = editedAt
        self.reactionsData = reactionsData
        self.replyTo = replyTo
        self.expirationDate = expirationDate
        self.isViewed = isViewed
        self.storyReplyDataEncoded = storyReplyDataEncoded
        self.sharedMomentDataEncoded = sharedMomentDataEncoded
        self.sharedStoryDataEncoded = sharedStoryDataEncoded
        self.textOverlayLive = textOverlayLive
        self.textOverlaysData = textOverlaysData
        self.stickersData = stickersData
        self.drawingData = drawingData
        self.viewedBy = viewedBy
        self.readBy = readBy
        self.readAtByData = readAtByData
        self.lastSyncedAt = lastSyncedAt
        self.isVanishModeMessage = isVanishModeMessage
        self.vanishedFor = vanishedFor
        self.vanishExpiresAt = vanishExpiresAt
    }
}

extension CachedMessage {
    /// No persistir rutas `file://` muertas ni cache local de GIF/sticker.
    private static func sanitizedMediaURL(_ url: String?, type: MessageType) -> String? {
        guard let url, !url.isEmpty else { return nil }
        if type == .gif || type == .sticker,
           let parsed = URL(string: url), parsed.isFileURL {
            return nil
        }
        if let parsed = URL(string: url), parsed.isFileURL,
           !FileManager.default.fileExists(atPath: parsed.path) {
            return nil
        }
        return url
    }

    static func from(_ message: EnhancedMessage) -> CachedMessage {
        let encoder = JSONEncoder()
        let reactionsData = try? encoder.encode(message.reactions)
        let storyReplyDataEncoded = try? encoder.encode(message.storyReplyData)
        let sharedMomentDataEncoded = try? encoder.encode(message.sharedMomentData)
        let sharedStoryDataEncoded = try? encoder.encode(message.sharedStoryData)
        let textOverlaysData = try? encoder.encode(message.textOverlays)
        let stickersData = try? encoder.encode(message.stickers)
        let mediaEncryptionData = try? encoder.encode(message.mediaEncryption)
        let thumbnailEncryptionData = try? encoder.encode(message.thumbnailEncryption)
        let audioWaveformData = try? encoder.encode(message.audioWaveform)
        let readAtByData = try? encoder.encode(message.readAtBy)
        
        return CachedMessage(
            id: message.id,
            conversationId: message.conversationId,
            senderId: message.senderId,
            typeString: message.type.rawValue,
            content: message.content,
            mediaUrl: sanitizedMediaURL(message.mediaUrl, type: message.type),
            thumbnailUrl: sanitizedMediaURL(message.thumbnailUrl, type: message.type),
            mediaObjectPath: message.mediaObjectPath,
            thumbnailObjectPath: message.thumbnailObjectPath,
            mediaEncryptionData: mediaEncryptionData,
            thumbnailEncryptionData: thumbnailEncryptionData,
            mediaBatchId: message.mediaBatchId,
            duration: message.duration,
            audioWaveformData: audioWaveformData,
            fileName: message.fileName,
            fileSize: message.fileSize,
            mediaWidth: message.mediaWidth,
            mediaHeight: message.mediaHeight,
            latitude: message.latitude,
            longitude: message.longitude,
            locationName: message.locationName,
            locationAddress: message.locationAddress,
            isLiveLocation: message.isLiveLocation,
            liveLocationExpiresAt: message.liveLocationExpiresAt,
            liveLocationDuration: message.liveLocationDuration,
            liveLocationStoppedAt: message.liveLocationStoppedAt,
            liveLocationSessionId: message.liveLocationSessionId,
            locationUpdatedAt: message.locationUpdatedAt,
            timestamp: message.timestamp,
            statusString: message.status.rawValue,
            isRead: message.isRead,
            isDeleted: message.isDeleted,
            deletedAt: message.deletedAt,
            editedAt: message.editedAt,
            reactionsData: reactionsData,
            replyTo: message.replyTo,
            expirationDate: message.expirationDate,
            isViewed: message.isViewed,
            storyReplyDataEncoded: storyReplyDataEncoded,
            sharedMomentDataEncoded: sharedMomentDataEncoded,
            sharedStoryDataEncoded: sharedStoryDataEncoded,
            textOverlayLive: message.textOverlayLive,
            textOverlaysData: textOverlaysData,
            stickersData: stickersData,
            drawingData: message.drawingData,
            viewedBy: message.viewedBy,
            readBy: message.readBy,
            readAtByData: readAtByData,
            lastSyncedAt: Date(),
            isVanishModeMessage: message.isVanishModeMessage == true,
            vanishedFor: message.vanishedFor ?? [],
            vanishExpiresAt: message.vanishExpiresAt
        )
    }
    
    func toEnhancedMessage() -> EnhancedMessage {
        let decoder = JSONDecoder()
        
        let type = MessageType(rawValue: typeString) ?? .text
        let status = MessageStatus(rawValue: statusString) ?? .sent
        
        let reactions: [String: [String]]? = {
            guard let data = reactionsData else { return nil }
            return try? decoder.decode([String: [String]].self, from: data)
        }()
        
        let storyReplyData: [String: String]? = {
            guard let data = storyReplyDataEncoded else { return nil }
            return try? decoder.decode([String: String].self, from: data)
        }()
        
        let sharedMomentData: [String: String]? = {
            guard let data = sharedMomentDataEncoded else { return nil }
            return try? decoder.decode([String: String].self, from: data)
        }()

        let sharedStoryData: [String: String]? = {
            guard let data = sharedStoryDataEncoded else { return nil }
            return try? decoder.decode([String: String].self, from: data)
        }()

        let textOverlays: [StoryTextOverlayMetadata]? = {
            guard let data = textOverlaysData else { return nil }
            return try? decoder.decode([StoryTextOverlayMetadata].self, from: data)
        }()

        let stickers: [StickerData]? = {
            guard let data = stickersData else { return nil }
            return try? decoder.decode([StickerData].self, from: data)
        }()

        let mediaEncryption: EncryptedChatMediaMetadata? = {
            guard let data = mediaEncryptionData else { return nil }
            return try? decoder.decode(EncryptedChatMediaMetadata.self, from: data)
        }()

        let thumbnailEncryption: EncryptedChatMediaMetadata? = {
            guard let data = thumbnailEncryptionData else { return nil }
            return try? decoder.decode(EncryptedChatMediaMetadata.self, from: data)
        }()

        let audioWaveform: [Float]? = {
            guard let data = audioWaveformData else { return nil }
            return try? decoder.decode([Float].self, from: data)
        }()

        let readAtBy: [String: Date]? = {
            guard let data = readAtByData else { return nil }
            return try? decoder.decode([String: Date].self, from: data)
        }()
        
        return EnhancedMessage(
            id: id,
            conversationId: conversationId,
            senderId: senderId,
            type: type,
            content: content,
            mediaUrl: Self.sanitizedMediaURL(mediaUrl, type: type),
            thumbnailUrl: Self.sanitizedMediaURL(thumbnailUrl, type: type),
            mediaObjectPath: mediaObjectPath,
            thumbnailObjectPath: thumbnailObjectPath,
            mediaEncryption: mediaEncryption,
            thumbnailEncryption: thumbnailEncryption,
            duration: duration,
            audioWaveform: audioWaveform,
            fileName: fileName,
            fileSize: fileSize,
            mediaWidth: mediaWidth,
            mediaHeight: mediaHeight,
            latitude: latitude,
            longitude: longitude,
            locationName: locationName,
            locationAddress: locationAddress,
            isLiveLocation: isLiveLocation,
            liveLocationExpiresAt: liveLocationExpiresAt,
            liveLocationDuration: liveLocationDuration,
            liveLocationStoppedAt: liveLocationStoppedAt,
            liveLocationSessionId: liveLocationSessionId,
            locationUpdatedAt: locationUpdatedAt,
            timestamp: timestamp,
            status: status,
            isRead: isRead,
            isDeleted: isDeleted,
            deletedAt: deletedAt,
            editedAt: editedAt,
            reactions: reactions,
            replyTo: replyTo,
            expirationDate: expirationDate,
            isViewed: isViewed,
            storyReplyData: storyReplyData,
            sharedMomentData: sharedMomentData,
            sharedStoryData: sharedStoryData,
            mediaBatchId: mediaBatchId,
            textOverlayLive: textOverlayLive,
            textOverlays: textOverlays,
            stickers: stickers,
            drawingData: drawingData,
            viewedBy: viewedBy,
            readBy: readBy,
            readAtBy: readAtBy,
            isVanishModeMessage: isVanishModeMessage ? true : nil,
            vanishedFor: vanishedFor.isEmpty ? nil : vanishedFor,
            vanishExpiresAt: vanishExpiresAt
        )
    }
}
