import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - Conversation Model
struct Conversation: Identifiable, Codable, Hashable {
    @DocumentID var id: String?
    let participants: [String]
    let lastMessage: String?
    let timestamp: Date
    var readStatus: [String: Bool]
    let otherParticipantId: String
    let otherParticipantUsername: String?
    let otherParticipantProfileImagePath: String?
    let isPinned: Bool?
    let pinnedByUserIds: [String]?
    let pinnedBy: String?
    let isMuted: Bool?
    let mutedByUserIds: [String]?
    let mutedBy: String?
    let encryptionVersion: String?
    let conversationKeyVersion: Int?
    let wrappedKeys: [String: WrappedConversationKey]?

    // ✅ Privacy: Preferencias explícitas de lectura por usuario en este chat
    var readReceiptPreferences: [String: Bool]?
    /// Si `false`, los demás no pueden reenviar los mensajes de texto de ese usuario en este chat.
    var forwardingPreferences: [String: Bool]?

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Conversation, rhs: Conversation) -> Bool {
        return lhs.id == rhs.id
    }

    enum CodingKeys: String, CodingKey {
        case id
        case participants
        case lastMessage
        case timestamp
        case readStatus
        case otherParticipantId
        case otherParticipantUsername
        case otherParticipantProfileImagePath
        case isPinned
        case pinnedByUserIds
        case pinnedBy
        case isMuted
        case mutedByUserIds
        case mutedBy
        case encryptionVersion
        case conversationKeyVersion
        case wrappedKeys
        case readReceiptPreferences
        case forwardingPreferences
    }

    init(
        id: String?,
        participants: [String],
        lastMessage: String?,
        timestamp: Date,
        readStatus: [String: Bool],
        otherParticipantId: String,
        otherParticipantUsername: String?,
        otherParticipantProfileImagePath: String?,
        isPinned: Bool? = false,
        pinnedByUserIds: [String]? = nil,
        pinnedBy: String? = nil,
        isMuted: Bool? = false,
        mutedByUserIds: [String]? = nil,
        mutedBy: String? = nil,
        encryptionVersion: String? = nil,
        conversationKeyVersion: Int? = nil,
        wrappedKeys: [String: WrappedConversationKey]? = nil
    ) {
        self.id = id
        self.participants = participants
        self.lastMessage = lastMessage
        self.timestamp = timestamp
        self.readStatus = readStatus
        self.otherParticipantId = otherParticipantId
        self.otherParticipantUsername = otherParticipantUsername
        self.otherParticipantProfileImagePath = otherParticipantProfileImagePath
        self.isPinned = isPinned
        self.pinnedByUserIds = pinnedByUserIds
        self.pinnedBy = pinnedBy
        self.isMuted = isMuted
        self.mutedByUserIds = mutedByUserIds
        self.mutedBy = mutedBy
        self.encryptionVersion = encryptionVersion
        self.conversationKeyVersion = conversationKeyVersion
        self.wrappedKeys = wrappedKeys
        self.readReceiptPreferences = [:]
        self.forwardingPreferences = [:]
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id)
        self.participants = try container.decode([String].self, forKey: .participants)
        self.lastMessage = try container.decodeIfPresent(String.self, forKey: .lastMessage)
        let timestamp = try container.decode(Timestamp.self, forKey: .timestamp)
        self.timestamp = timestamp.dateValue()
        self.readStatus = try container.decodeIfPresent([String: Bool].self, forKey: .readStatus) ?? [:]
        self.otherParticipantId = try container.decodeIfPresent(String.self, forKey: .otherParticipantId) ?? ""
        self.otherParticipantUsername = try container.decodeIfPresent(String.self, forKey: .otherParticipantUsername)
        self.otherParticipantProfileImagePath = try container.decodeIfPresent(String.self, forKey: .otherParticipantProfileImagePath)
        self.isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        self.pinnedByUserIds = try container.decodeIfPresent([String].self, forKey: .pinnedByUserIds)
        self.pinnedBy = try container.decodeIfPresent(String.self, forKey: .pinnedBy)
        self.isMuted = try container.decodeIfPresent(Bool.self, forKey: .isMuted) ?? false
        self.mutedByUserIds = try container.decodeIfPresent([String].self, forKey: .mutedByUserIds)
        self.mutedBy = try container.decodeIfPresent(String.self, forKey: .mutedBy)
        self.encryptionVersion = try container.decodeIfPresent(String.self, forKey: .encryptionVersion)
        self.conversationKeyVersion = try container.decodeIfPresent(Int.self, forKey: .conversationKeyVersion)
        self.wrappedKeys = try container.decodeIfPresent([String: WrappedConversationKey].self, forKey: .wrappedKeys)
        self.readReceiptPreferences = try container.decodeIfPresent([String: Bool].self, forKey: .readReceiptPreferences) ?? [:]
        self.forwardingPreferences = try container.decodeIfPresent([String: Bool].self, forKey: .forwardingPreferences) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(participants, forKey: .participants)
        try container.encodeIfPresent(lastMessage, forKey: .lastMessage)
        try container.encode(Timestamp(date: timestamp), forKey: .timestamp)
        try container.encode(readStatus, forKey: .readStatus)
        try container.encode(otherParticipantId, forKey: .otherParticipantId)
        try container.encodeIfPresent(otherParticipantUsername, forKey: .otherParticipantUsername)
        try container.encodeIfPresent(otherParticipantProfileImagePath, forKey: .otherParticipantProfileImagePath)
        try container.encodeIfPresent(isPinned, forKey: .isPinned)
        try container.encodeIfPresent(pinnedByUserIds, forKey: .pinnedByUserIds)
        try container.encodeIfPresent(pinnedBy, forKey: .pinnedBy)
        try container.encodeIfPresent(isMuted, forKey: .isMuted)
        try container.encodeIfPresent(mutedByUserIds, forKey: .mutedByUserIds)
        try container.encodeIfPresent(mutedBy, forKey: .mutedBy)
        try container.encodeIfPresent(encryptionVersion, forKey: .encryptionVersion)
        try container.encodeIfPresent(conversationKeyVersion, forKey: .conversationKeyVersion)
        try container.encodeIfPresent(wrappedKeys, forKey: .wrappedKeys)
        try container.encodeIfPresent(readReceiptPreferences, forKey: .readReceiptPreferences)
        try container.encodeIfPresent(forwardingPreferences, forKey: .forwardingPreferences)
    }

    func allowsForwarding(ofMessagesFrom senderId: String) -> Bool {
        forwardingPreferences?[senderId] ?? true
    }

    func isMuted(for userId: String?) -> Bool {
        guard let userId, !userId.isEmpty else {
            return isMuted ?? false
        }

        if mutedByUserIds?.contains(userId) == true {
            return true
        }

        if isMuted == true, let mutedBy {
            return mutedBy == userId
        }

        return false
    }

    func isPinned(for userId: String?) -> Bool {
        guard let userId, !userId.isEmpty else {
            return isPinned ?? false
        }

        if pinnedByUserIds?.contains(userId) == true {
            return true
        }

        if isPinned == true, let pinnedBy {
            return pinnedBy == userId
        }

        return false
    }

    // Propiedad calculada para obtener el número de mensajes no leídos
    var unreadCount: Int {
        guard let currentUserId = Auth.auth().currentUser?.uid,
              let isRead = readStatus[currentUserId] else { return 0 }
        return isRead ? 0 : 1 // Simplificado, en producción sería más complejo
    }

    // Verificar si la conversación está activa
    var isActive: Bool {
        // Aquí podrías verificar que ningún participante haya bloqueado al otro
        return true // Por ahora retornamos true
    }

    // Obtener preview del último mensaje para notificaciones
    var messagePreview: String {
        if let lastMessage {
            if lastMessage.starts(with: "📎") {
                return lastMessage
            } else if lastMessage.count > 50 {
                return String(lastMessage.prefix(47)) + "..."
            }
            return lastMessage
        }
        return NSLocalizedString("chat.preview.newConversation", comment: "")
    }
}

// MARK: - Legacy Message Model (mantener compatibilidad)
struct Message: Identifiable, Codable {
    @DocumentID var id: String?
    let conversationId: String
    let senderId: String
    let content: String
    let timestamp: Date
    var isRead: Bool
    var reaction: String?
    var expirationDate: Date?
    var isViewed: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case conversationId
        case senderId
        case content
        case timestamp
        case isRead
        case reaction
        case expirationDate
        case isViewed
    }

    init(id: String?, conversationId: String, senderId: String, content: String, timestamp: Date, isRead: Bool, reaction: String?, expirationDate: Date? = nil, isViewed: Bool = false) {
        self.id = id
        self.conversationId = conversationId
        self.senderId = senderId
        self.content = content
        self.timestamp = timestamp
        self.isRead = isRead
        self.reaction = reaction
        self.expirationDate = expirationDate
        self.isViewed = isViewed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id)
        self.conversationId = try container.decode(String.self, forKey: .conversationId)
        self.senderId = try container.decode(String.self, forKey: .senderId)
        self.content = try container.decode(String.self, forKey: .content)
        let timestamp = try container.decode(Timestamp.self, forKey: .timestamp)
        self.timestamp = timestamp.dateValue()
        self.isRead = try container.decode(Bool.self, forKey: .isRead)
        self.reaction = try container.decodeIfPresent(String.self, forKey: .reaction)
        self.expirationDate = try container.decodeIfPresent(Timestamp.self, forKey: .expirationDate)?.dateValue()
        self.isViewed = try container.decodeIfPresent(Bool.self, forKey: .isViewed) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(conversationId, forKey: .conversationId)
        try container.encode(senderId, forKey: .senderId)
        try container.encode(content, forKey: .content)
        try container.encode(Timestamp(date: timestamp), forKey: .timestamp)
        try container.encode(isRead, forKey: .isRead)
        try container.encodeIfPresent(reaction, forKey: .reaction)
        if let expirationDate = expirationDate {
            try container.encode(Timestamp(date: expirationDate), forKey: .expirationDate)
        }
        try container.encode(isViewed, forKey: .isViewed)
    }
}

extension Message: Equatable {
    static func == (lhs: Message, rhs: Message) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - Message Types
enum MessageType: String, CaseIterable, Codable {
    case text = "text"
    case image = "image"
    case video = "video"
    case audio = "audio"
    case gif = "gif"
    case sticker = "sticker"
    case location = "location"
    case file = "file"
    case ephemeral = "ephemeral"
    case sharedMoment = "sharedMoment"
    case sharedStory = "sharedStory"
    // ✅ NUEVOS: Tipos para view-once
    case viewOnceImage = "viewOnceImage"
    case viewOnceVideo = "viewOnceVideo"

    var displayName: String {
        switch self {
        case .text: return NSLocalizedString("common.text", comment: "")
        case .image: return NSLocalizedString("common.photo", comment: "")
        case .video: return NSLocalizedString("common.video", comment: "")
        case .audio: return NSLocalizedString("common.audio", comment: "")
        case .gif: return "GIF"
        case .sticker: return "Sticker"
        case .location: return NSLocalizedString("common.location", comment: "")
        case .file: return NSLocalizedString("common.file", comment: "")
        case .ephemeral: return NSLocalizedString("chat.viewOnce.viewOnce", comment: "")
        case .sharedMoment: return NSLocalizedString("chat.preview.sharedMoment", comment: "")
        case .sharedStory: return NSLocalizedString("chat.preview.sharedStory", comment: "")
        case .viewOnceImage: return NSLocalizedString("chat.viewOnce.photo", comment: "") + " (" + NSLocalizedString("chat.viewOnce.viewOnce", comment: "") + ")"
        case .viewOnceVideo: return NSLocalizedString("chat.viewOnce.video", comment: "") + " (" + NSLocalizedString("chat.viewOnce.viewOnce", comment: "") + ")"
        }
    }

    var iconName: String {
        switch self {
        case .text: return "text.bubble"
        case .image: return "photo"
        case .video: return "video"
        case .audio: return "mic"
        case .gif: return "photo.on.rectangle.angled"
        case .sticker: return "face.smiling"
        case .location: return "location"
        case .file: return "doc"
        case .ephemeral: return "timer"
        case .sharedMoment: return "square.and.arrow.up"
        case .sharedStory: return "paperplane.fill"
        case .viewOnceImage: return "camera.circle"
        case .viewOnceVideo: return "video.circle"
        }
    }

    // ✅ NUEVA: Propiedad para identificar view-once
    var isViewOnce: Bool {
        return self == .viewOnceImage || self == .viewOnceVideo
    }

    // ✅ NUEVA: Preview para lista de conversaciones
    var conversationPreview: String {
        switch self {
        case .text: return NSLocalizedString("chat.preview.text", comment: "")
        case .image: return NSLocalizedString("chat.preview.photo", comment: "")
        case .video: return NSLocalizedString("chat.preview.video", comment: "")
        case .audio: return NSLocalizedString("chat.preview.audio", comment: "")
        case .gif: return NSLocalizedString("chat.preview.gif", comment: "")
        case .sticker: return NSLocalizedString("chat.preview.sticker", comment: "")
        case .location: return NSLocalizedString("chat.preview.location", comment: "")
        case .file: return NSLocalizedString("chat.preview.file", comment: "")
        case .ephemeral: return NSLocalizedString("chat.preview.ephemeral", comment: "")
        case .sharedMoment: return NSLocalizedString("chat.preview.sharedMoment", comment: "")
        case .sharedStory: return NSLocalizedString("chat.preview.sharedStory", comment: "")
        case .viewOnceImage: return NSLocalizedString("chat.preview.viewOncePhoto", comment: "")
        case .viewOnceVideo: return NSLocalizedString("chat.preview.viewOnceVideo", comment: "")
        }
    }
}

private let neutralConversationPreviewPrefixes = ["💬", "📷", "🎥", "🎵", "🎞", "😊", "📍", "📎", "📸", "⏱"]

func sanitizedConversationPreview(_ rawPreview: String?, encryptionVersion: String?) -> String {
    let trimmedPreview = rawPreview?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

    guard encryptionVersion?.hasPrefix("3") == true else {
        return trimmedPreview
    }

    guard !trimmedPreview.isEmpty else {
        return MessageType.text.conversationPreview
    }

    if neutralConversationPreviewPrefixes.contains(where: { trimmedPreview.hasPrefix($0) }) {
        return trimmedPreview
    }

    return MessageType.text.conversationPreview
}

// MARK: - Message Status
enum MessageStatus: String, Codable {
    case pending = "pending"
    case sending = "sending"
    case sent = "sent"
    case delivered = "delivered"
    case read = "read"
    case failed = "failed"

    var displayName: String {
        switch self {
        case .pending: return NSLocalizedString("chat.status.pending", comment: "")
        case .sending: return NSLocalizedString("chat.status.sending", comment: "")
        case .sent: return NSLocalizedString("chat.status.sent", comment: "")
        case .delivered: return NSLocalizedString("chat.status.delivered", comment: "")
        case .read: return NSLocalizedString("chat.status.read", comment: "")
        case .failed: return NSLocalizedString("chat.status.failed", comment: "")
        }
    }

    var iconName: String {
        switch self {
        case .pending, .sending: return "clock"
        case .sent: return "checkmark"
        case .delivered: return "checkmark.circle"
        case .read: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle"
        }
    }
}

enum ChatMediaPurpose: String, Codable {
    case primary
    case thumbnail
}

struct EncryptedChatMediaMetadata: Codable, Hashable {
    let version: String
    let algorithm: String
    let purpose: ChatMediaPurpose
    let mediaId: String
    let contentType: String
    let fileExtension: String
    let plaintextSize: Int64

    init(
        version: String = "1.0",
        algorithm: String = "AES.GCM+HKDF-SHA256",
        purpose: ChatMediaPurpose,
        mediaId: String,
        contentType: String,
        fileExtension: String,
        plaintextSize: Int64
    ) {
        self.version = version
        self.algorithm = algorithm
        self.purpose = purpose
        self.mediaId = mediaId
        self.contentType = contentType
        self.fileExtension = fileExtension
        self.plaintextSize = plaintextSize
    }

    init?(map: [String: Any]) {
        guard
            let version = map["version"] as? String,
            let algorithm = map["algorithm"] as? String,
            let purposeRaw = map["purpose"] as? String,
            let purpose = ChatMediaPurpose(rawValue: purposeRaw),
            let mediaId = map["mediaId"] as? String,
            let contentType = map["contentType"] as? String,
            let fileExtension = map["fileExtension"] as? String
        else {
            return nil
        }

        let plaintextSize: Int64
        if let size = map["plaintextSize"] as? Int64 {
            plaintextSize = size
        } else if let size = map["plaintextSize"] as? Int {
            plaintextSize = Int64(size)
        } else if let size = map["plaintextSize"] as? Double {
            plaintextSize = Int64(size)
        } else {
            return nil
        }

        self.init(
            version: version,
            algorithm: algorithm,
            purpose: purpose,
            mediaId: mediaId,
            contentType: contentType,
            fileExtension: fileExtension,
            plaintextSize: plaintextSize
        )
    }

    var firestoreData: [String: Any] {
        [
            "version": version,
            "algorithm": algorithm,
            "purpose": purpose.rawValue,
            "mediaId": mediaId,
            "contentType": contentType,
            "fileExtension": fileExtension,
            "plaintextSize": plaintextSize
        ]
    }
}

// MARK: - Enhanced Message Model with View-Once Support
class EnhancedMessage: Codable, Identifiable, ObservableObject {
    let id: String
    let conversationId: String
    let senderId: String
    let type: MessageType
    let content: String?
    var mediaUrl: String? {
        didSet { objectWillChange.send() }
    }
    var thumbnailUrl: String? {
        didSet { objectWillChange.send() }
    }
    let mediaObjectPath: String?
    let thumbnailObjectPath: String?
    let mediaEncryption: EncryptedChatMediaMetadata?
    let thumbnailEncryption: EncryptedChatMediaMetadata?
    let duration: Double?
    let fileName: String?
    let fileSize: Int64?
    let latitude: Double?
    let longitude: Double?
    // ✅ NUEVO: Ubicación (fija + en vivo)
    let locationName: String?
    let locationAddress: String?
    let isLiveLocation: Bool?
    let liveLocationExpiresAt: Date?
    let liveLocationDuration: String?
    var liveLocationStoppedAt: Date?
    let liveLocationSessionId: String?
    let locationUpdatedAt: Date?
    let timestamp: Date
    @Published var status: MessageStatus
    @Published var isRead: Bool
    @Published var isDeleted: Bool
    var deletedAt: Date?
    var editedAt: Date?
    var reactions: [String: [String]]? {
        didSet { objectWillChange.send() }
    }
    var replyTo: String?
    var expirationDate: Date?
    @Published var isViewed: Bool
    let storyReplyData: [String: String]?
    let sharedMomentData: [String: String]?
    let sharedStoryData: [String: String]?
    let mediaBatchId: String?

    // ✅ NUEVOS: Campos para view-once
    var viewedBy: [String]? // IDs de usuarios que han visto el mensaje view-once
    var starredBy: [String]?
    var isForwarded: Bool?
    /// Dimensiones originales de GIF/sticker (p. ej. Giphy `fixed_height`).
    let mediaWidth: Int?
    let mediaHeight: Int?

    enum CodingKeys: String, CodingKey {
        case id, conversationId, senderId, type, content, mediaUrl, thumbnailUrl
        case mediaObjectPath, thumbnailObjectPath, mediaEncryption, thumbnailEncryption
        case duration, fileName, fileSize, mediaWidth, mediaHeight, latitude, longitude, timestamp
        case status, isRead, isDeleted, deletedAt, editedAt, reactions
        case replyTo, expirationDate, isViewed, storyReplyData, sharedMomentData, sharedStoryData
        case mediaBatchId
        case viewedBy
        case starredBy, isForwarded
        // ✅ NUEVO: Ubicación (fija + en vivo)
        case locationName, locationAddress
        case isLiveLocation, liveLocationExpiresAt, liveLocationDuration
        case liveLocationStoppedAt, liveLocationSessionId, locationUpdatedAt
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.id = try container.decode(String.self, forKey: .id)
        self.conversationId = try container.decode(String.self, forKey: .conversationId)
        self.senderId = try container.decode(String.self, forKey: .senderId)

        if let typeString = try container.decodeIfPresent(String.self, forKey: .type),
           let type = MessageType(rawValue: typeString) {
            self.type = type
        } else {
            self.type = .text
        }

        self.content = try container.decodeIfPresent(String.self, forKey: .content)
        self.mediaUrl = try container.decodeIfPresent(String.self, forKey: .mediaUrl)
        self.thumbnailUrl = try container.decodeIfPresent(String.self, forKey: .thumbnailUrl)
        self.mediaObjectPath = try container.decodeIfPresent(String.self, forKey: .mediaObjectPath)
        self.thumbnailObjectPath = try container.decodeIfPresent(String.self, forKey: .thumbnailObjectPath)
        self.mediaEncryption = try container.decodeIfPresent(EncryptedChatMediaMetadata.self, forKey: .mediaEncryption)
        self.thumbnailEncryption = try container.decodeIfPresent(EncryptedChatMediaMetadata.self, forKey: .thumbnailEncryption)
        self.duration = try container.decodeIfPresent(Double.self, forKey: .duration)
        self.fileName = try container.decodeIfPresent(String.self, forKey: .fileName)
        self.fileSize = try container.decodeIfPresent(Int64.self, forKey: .fileSize)
        self.mediaWidth = try container.decodeIfPresent(Int.self, forKey: .mediaWidth)
        self.mediaHeight = try container.decodeIfPresent(Int.self, forKey: .mediaHeight)
        self.latitude = try container.decodeIfPresent(Double.self, forKey: .latitude)
        self.longitude = try container.decodeIfPresent(Double.self, forKey: .longitude)

        // ✅ NUEVO: Ubicación (fija + en vivo)
        self.locationName = try container.decodeIfPresent(String.self, forKey: .locationName)
        self.locationAddress = try container.decodeIfPresent(String.self, forKey: .locationAddress)
        self.isLiveLocation = try container.decodeIfPresent(Bool.self, forKey: .isLiveLocation)
        self.liveLocationDuration = try container.decodeIfPresent(String.self, forKey: .liveLocationDuration)
        self.liveLocationSessionId = try container.decodeIfPresent(String.self, forKey: .liveLocationSessionId)
        if let expiresAt = try container.decodeIfPresent(Timestamp.self, forKey: .liveLocationExpiresAt) {
            self.liveLocationExpiresAt = expiresAt.dateValue()
        } else {
            self.liveLocationExpiresAt = nil
        }
        if let stoppedAt = try container.decodeIfPresent(Timestamp.self, forKey: .liveLocationStoppedAt) {
            self.liveLocationStoppedAt = stoppedAt.dateValue()
        } else {
            self.liveLocationStoppedAt = nil
        }
        if let updatedAt = try container.decodeIfPresent(Timestamp.self, forKey: .locationUpdatedAt) {
            self.locationUpdatedAt = updatedAt.dateValue()
        } else {
            self.locationUpdatedAt = nil
        }

        if let timestamp = try container.decodeIfPresent(Timestamp.self, forKey: .timestamp) {
            self.timestamp = timestamp.dateValue()
        } else {
            self.timestamp = Date()
        }

        let statusString = try container.decodeIfPresent(String.self, forKey: .status) ?? MessageStatus.sent.rawValue
        let status = MessageStatus(rawValue: statusString) ?? .sent
        self.status = status

        let isRead = try container.decodeIfPresent(Bool.self, forKey: .isRead) ?? false
        self.isRead = isRead

        let isDeleted = try container.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
        self.isDeleted = isDeleted

        if let deletedAt = try container.decodeIfPresent(Timestamp.self, forKey: .deletedAt) {
            self.deletedAt = deletedAt.dateValue()
        } else {
            self.deletedAt = nil
        }

        if let editedAt = try container.decodeIfPresent(Timestamp.self, forKey: .editedAt) {
            self.editedAt = editedAt.dateValue()
        } else {
            self.editedAt = nil
        }

        self.reactions = try container.decodeIfPresent([String: [String]].self, forKey: .reactions)
        self.replyTo = try container.decodeIfPresent(String.self, forKey: .replyTo)

        if let expirationDate = try container.decodeIfPresent(Timestamp.self, forKey: .expirationDate) {
            self.expirationDate = expirationDate.dateValue()
        } else {
            self.expirationDate = nil
        }

        let isViewed = try container.decodeIfPresent(Bool.self, forKey: .isViewed) ?? false
        self.isViewed = isViewed

        self.storyReplyData = try container.decodeIfPresent([String: String].self, forKey: .storyReplyData)
        self.sharedMomentData = try container.decodeIfPresent([String: String].self, forKey: .sharedMomentData)
        self.sharedStoryData = try container.decodeIfPresent([String: String].self, forKey: .sharedStoryData)
        self.mediaBatchId = try container.decodeIfPresent(String.self, forKey: .mediaBatchId)

        // ✅ NUEVO: Decodificar viewedBy
        self.viewedBy = try container.decodeIfPresent([String].self, forKey: .viewedBy)
        self.starredBy = try container.decodeIfPresent([String].self, forKey: .starredBy)
        self.isForwarded = try container.decodeIfPresent(Bool.self, forKey: .isForwarded)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(conversationId, forKey: .conversationId)
        try container.encode(senderId, forKey: .senderId)
        try container.encode(type.rawValue, forKey: .type)
        try container.encodeIfPresent(content, forKey: .content)
        try container.encodeIfPresent(mediaUrl, forKey: .mediaUrl)
        try container.encodeIfPresent(thumbnailUrl, forKey: .thumbnailUrl)
        try container.encodeIfPresent(mediaObjectPath, forKey: .mediaObjectPath)
        try container.encodeIfPresent(thumbnailObjectPath, forKey: .thumbnailObjectPath)
        try container.encodeIfPresent(mediaEncryption, forKey: .mediaEncryption)
        try container.encodeIfPresent(thumbnailEncryption, forKey: .thumbnailEncryption)
        try container.encodeIfPresent(duration, forKey: .duration)
        try container.encodeIfPresent(fileName, forKey: .fileName)
        try container.encodeIfPresent(fileSize, forKey: .fileSize)
        try container.encodeIfPresent(mediaWidth, forKey: .mediaWidth)
        try container.encodeIfPresent(mediaHeight, forKey: .mediaHeight)
        try container.encodeIfPresent(latitude, forKey: .latitude)
        try container.encodeIfPresent(longitude, forKey: .longitude)
        // ✅ NUEVO: Ubicación (fija + en vivo)
        try container.encodeIfPresent(locationName, forKey: .locationName)
        try container.encodeIfPresent(locationAddress, forKey: .locationAddress)
        try container.encodeIfPresent(isLiveLocation, forKey: .isLiveLocation)
        try container.encodeIfPresent(liveLocationDuration, forKey: .liveLocationDuration)
        try container.encodeIfPresent(liveLocationSessionId, forKey: .liveLocationSessionId)
        if let liveLocationExpiresAt {
            try container.encode(Timestamp(date: liveLocationExpiresAt), forKey: .liveLocationExpiresAt)
        }
        if let liveLocationStoppedAt {
            try container.encode(Timestamp(date: liveLocationStoppedAt), forKey: .liveLocationStoppedAt)
        }
        if let locationUpdatedAt {
            try container.encode(Timestamp(date: locationUpdatedAt), forKey: .locationUpdatedAt)
        }
        try container.encode(Timestamp(date: timestamp), forKey: .timestamp)
        try container.encode(status.rawValue, forKey: .status)
        try container.encode(isRead, forKey: .isRead)
        try container.encode(isDeleted, forKey: .isDeleted)

        if let deletedAt = deletedAt {
            try container.encode(Timestamp(date: deletedAt), forKey: .deletedAt)
        }

        if let editedAt = editedAt {
            try container.encode(Timestamp(date: editedAt), forKey: .editedAt)
        }

        try container.encodeIfPresent(reactions, forKey: .reactions)
        try container.encodeIfPresent(replyTo, forKey: .replyTo)

        if let expirationDate = expirationDate {
            try container.encode(Timestamp(date: expirationDate), forKey: .expirationDate)
        }

        try container.encode(isViewed, forKey: .isViewed)
        try container.encodeIfPresent(storyReplyData, forKey: .storyReplyData)
        try container.encodeIfPresent(sharedMomentData, forKey: .sharedMomentData)
        try container.encodeIfPresent(sharedStoryData, forKey: .sharedStoryData)
        try container.encodeIfPresent(mediaBatchId, forKey: .mediaBatchId)

        // ✅ NUEVO: Codificar viewedBy
        try container.encodeIfPresent(viewedBy, forKey: .viewedBy)
        try container.encodeIfPresent(starredBy, forKey: .starredBy)
        try container.encodeIfPresent(isForwarded, forKey: .isForwarded)
    }

    required init(id: String? = nil,
         conversationId: String,
         senderId: String,
         type: MessageType,
         content: String? = nil,
         mediaUrl: String? = nil,
         thumbnailUrl: String? = nil,
         mediaObjectPath: String? = nil,
         thumbnailObjectPath: String? = nil,
         mediaEncryption: EncryptedChatMediaMetadata? = nil,
         thumbnailEncryption: EncryptedChatMediaMetadata? = nil,
         duration: Double? = nil,
         fileName: String? = nil,
         fileSize: Int64? = nil,
         mediaWidth: Int? = nil,
         mediaHeight: Int? = nil,
         latitude: Double? = nil,
         longitude: Double? = nil,
         locationName: String? = nil,
         locationAddress: String? = nil,
         isLiveLocation: Bool? = nil,
         liveLocationExpiresAt: Date? = nil,
         liveLocationDuration: String? = nil,
         liveLocationStoppedAt: Date? = nil,
         liveLocationSessionId: String? = nil,
         locationUpdatedAt: Date? = nil,
         timestamp: Date = Date(),
         status: MessageStatus = .sending,
         isRead: Bool = false,
         isDeleted: Bool = false,
         deletedAt: Date? = nil,
         editedAt: Date? = nil,
         reactions: [String: [String]]? = nil,
         replyTo: String? = nil,
         expirationDate: Date? = nil,
         isViewed: Bool = false,
         storyReplyData: [String: String]? = nil,
         sharedMomentData: [String: String]? = nil,
         sharedStoryData: [String: String]? = nil,
         mediaBatchId: String? = nil,
         viewedBy: [String]? = nil,
         starredBy: [String]? = nil,
         isForwarded: Bool? = nil) {

        self.id = id ?? UUID().uuidString
        self.conversationId = conversationId
        self.senderId = senderId
        self.type = type
        self.content = content
        self.mediaUrl = mediaUrl
        self.thumbnailUrl = thumbnailUrl
        self.mediaObjectPath = mediaObjectPath
        self.thumbnailObjectPath = thumbnailObjectPath
        self.mediaEncryption = mediaEncryption
        self.thumbnailEncryption = thumbnailEncryption
        self.duration = duration
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
        self.status = status
        self.isRead = isRead
        self.isDeleted = isDeleted
        self.deletedAt = deletedAt
        self.editedAt = editedAt
        self.reactions = reactions
        self.replyTo = replyTo
        self.expirationDate = expirationDate
        self.isViewed = isViewed
        self.storyReplyData = storyReplyData
        self.sharedMomentData = sharedMomentData
        self.sharedStoryData = sharedStoryData
        self.mediaBatchId = mediaBatchId
        self.viewedBy = viewedBy
        self.starredBy = starredBy
        self.isForwarded = isForwarded
    }

    func isStarred(by userId: String) -> Bool {
        starredBy?.contains(userId) ?? false
    }

    var isExpired: Bool {
        guard let expirationDate = expirationDate else { return false }
        return Date() > expirationDate
    }

    /// `true` si el mensaje es una sesión de ubicación en vivo (independiente de si sigue activa).
    var isLiveLocationMessage: Bool {
        type == .location && (isLiveLocation ?? false)
    }

    /// `true` si la sesión live sigue activa (no parada manualmente y no expirada).
    var isLiveLocationActive: Bool {
        guard isLiveLocationMessage else { return false }
        if liveLocationStoppedAt != nil { return false }
        if let expiresAt = liveLocationExpiresAt, Date() >= expiresAt { return false }
        return true
    }

    // ✅ ACTUALIZADA: Preview mejorado con support para view-once
    var preview: String {
        switch type {
        case .text:
            return content ?? ""
        case .image:
            return NSLocalizedString("chat.preview.image", comment: "")
        case .video:
            return NSLocalizedString("chat.preview.video", comment: "")
        case .audio:
            return NSLocalizedString("chat.preview.audio", comment: "")
        case .gif:
            return NSLocalizedString("chat.preview.gif", comment: "")
        case .sticker:
            return NSLocalizedString("chat.preview.sticker", comment: "")
        case .location:
            return NSLocalizedString("chat.preview.location", comment: "")
        case .file:
            return "📎 \(fileName ?? NSLocalizedString("common.file", comment: ""))"
        case .ephemeral:
            return NSLocalizedString("chat.preview.ephemeral_long", comment: "")
        case .sharedMoment:
            return NSLocalizedString("chat.preview.sharedMoment", comment: "")
        case .sharedStory:
            return NSLocalizedString("chat.preview.sharedStory", comment: "")
        case .viewOnceImage:
            return NSLocalizedString("chat.preview.viewOncePhoto", comment: "")
        case .viewOnceVideo:
            return NSLocalizedString("chat.preview.viewOnceVideo", comment: "")
        }
    }

    // ✅ NUEVAS: Propiedades y funciones para view-once

    /// Determina si este mensaje es view-once
    var isViewOnce: Bool {
        return type.isViewOnce
    }

    /// Determina si el usuario actual ya vio este mensaje view-once
    func hasBeenViewedBy(userId: String) -> Bool {
        guard isViewOnce else { return false }
        return viewedBy?.contains(userId) ?? false
    }

    /// Obtiene el estado del view-once para un usuario específico
    func viewOnceStatus(for currentUserId: String) -> String {
        guard isViewOnce else { return "" }

        if senderId == currentUserId {
            // Usuario que envió el mensaje
            return isViewed ? NSLocalizedString("chat.viewOnce.viewed", comment: "") : NSLocalizedString("chat.viewOnce.sent", comment: "")
        } else {
            // Usuario que recibe el mensaje
            let hasViewed = hasBeenViewedBy(userId: currentUserId)
            return hasViewed ? NSLocalizedString("chat.viewOnce.viewed", comment: "") : NSLocalizedString("chat.viewOnce.tapToView", comment: "")
        }
    }

    /// Determina si debe mostrar el contenido del view-once
    func shouldShowViewOnceContent(for currentUserId: String) -> Bool {
        guard isViewOnce else { return true }

        if senderId == currentUserId {
            // El remitente siempre puede ver un preview
            return true
        } else {
            // El receptor solo puede ver si no ha sido visto aún
            return !hasBeenViewedBy(userId: currentUserId)
        }
    }

    /// Obtiene el ícono apropiado para el tipo de mensaje
    var typeIcon: String {
        return type.iconName
    }

    /// Determina si el mensaje puede ser eliminado automáticamente (view-once visto)
    var canBeAutoDeleted: Bool {
        return isViewOnce && isViewed && !isDeleted
    }

    /// Preview para mostrar en la lista de conversaciones
    var conversationPreview: String {
        if let content = content, type == .text {
            return content.count > 50 ? String(content.prefix(47)) + "..." : content
        }
        return type.conversationPreview
    }
}

// MARK: - ✅ NUEVAS: Extensiones para View-Once
extension EnhancedMessage: Equatable {
    static func == (lhs: EnhancedMessage, rhs: EnhancedMessage) -> Bool {
        return lhs.id == rhs.id
    }
}

extension EnhancedMessage: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - ✅ NUEVA: Extension para crear mensajes view-once fácilmente
extension EnhancedMessage {

    /// Crea un mensaje view-once de imagen
    static func createViewOnceImage(
        conversationId: String,
        senderId: String,
        mediaUrl: String,
        fileSize: Int64? = nil
    ) -> EnhancedMessage {
        return EnhancedMessage(
            conversationId: conversationId,
            senderId: senderId,
            type: .viewOnceImage,
            mediaUrl: mediaUrl,
            fileSize: fileSize,
            viewedBy: []
        )
    }

    /// Crea un mensaje view-once de video
    static func createViewOnceVideo(
        conversationId: String,
        senderId: String,
        mediaUrl: String,
        thumbnailUrl: String? = nil,
        duration: Double? = nil,
        fileSize: Int64? = nil
    ) -> EnhancedMessage {
        return EnhancedMessage(
            conversationId: conversationId,
            senderId: senderId,
            type: .viewOnceVideo,
            mediaUrl: mediaUrl,
            thumbnailUrl: thumbnailUrl,
            duration: duration,
            fileSize: fileSize,
            viewedBy: []
        )
    }
}

// MARK: - ✅ NUEVA: Helper para conversión de tipos de media
enum ViewOnceMediaType {
    case image
    case video

    var messageType: MessageType {
        switch self {
        case .image: return .viewOnceImage
        case .video: return .viewOnceVideo
        }
    }

    var preview: String {
        switch self {
        case .image: return NSLocalizedString("chat.preview.viewOncePhoto", comment: "")
        case .video: return NSLocalizedString("chat.preview.viewOnceVideo", comment: "")
        }
    }

    var iconName: String {
        switch self {
        case .image: return "camera.circle"
        case .video: return "video.circle"
        }
    }
}

// MARK: - ✅ NUEVA: Extension para compatibilidad con EnhancedCameraPickerView
extension ViewOnceMediaType {
    init(from cameraMediaType: EnhancedCameraPickerView.MediaType) {
        switch cameraMediaType {
        case .image: self = .image
        case .video: self = .video
        }
    }
}

// MARK: - ================== MODELOS AUXILIARES ==================

// MARK: - Typing Indicator Model
struct TypingIndicator: Codable {
    let userId: String
    let conversationId: String
    let timestamp: Date

    init(userId: String, conversationId: String, timestamp: Date = Date()) {
        self.userId = userId
        self.conversationId = conversationId
        self.timestamp = timestamp
    }

    enum CodingKeys: String, CodingKey {
        case userId, conversationId, timestamp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.userId = try container.decode(String.self, forKey: .userId)
        self.conversationId = try container.decode(String.self, forKey: .conversationId)
        let timestamp = try container.decode(Timestamp.self, forKey: .timestamp)
        self.timestamp = timestamp.dateValue()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userId, forKey: .userId)
        try container.encode(conversationId, forKey: .conversationId)
        try container.encode(Timestamp(date: timestamp), forKey: .timestamp)
    }
}

// MARK: - Message Notification Model
struct MessageNotification {
    let conversationId: String
    let messageId: String
    let senderId: String
    let senderName: String
    let messagePreview: String
    let timestamp: Date
    let isViewOnce: Bool // ✅ NUEVO: Indicar si es view-once

    var title: String {
        return senderName
    }

    var body: String {
        return isViewOnce ? NSLocalizedString("chat.notification.viewOncePrompt", comment: "") : messagePreview
    }

    init(conversationId: String, messageId: String, senderId: String, senderName: String, messagePreview: String, timestamp: Date = Date(), isViewOnce: Bool = false) {
        self.conversationId = conversationId
        self.messageId = messageId
        self.senderId = senderId
        self.senderName = senderName
        self.messagePreview = messagePreview
        self.timestamp = timestamp
        self.isViewOnce = isViewOnce
    }
}

// MARK: - ✅ NUEVO: View-Once Metadata Model
struct ViewOnceMetadata: Codable {
    let messageId: String
    let conversationId: String
    let senderId: String
    let createdAt: Date
    var viewedBy: [String]
    var isExpired: Bool

    init(messageId: String, conversationId: String, senderId: String, createdAt: Date = Date()) {
        self.messageId = messageId
        self.conversationId = conversationId
        self.senderId = senderId
        self.createdAt = createdAt
        self.viewedBy = []
        self.isExpired = false
    }

    mutating func markAsViewedBy(userId: String) {
        if !viewedBy.contains(userId) {
            viewedBy.append(userId)
        }
    }

    var canBeDeleted: Bool {
        return !viewedBy.isEmpty && !isExpired
    }
}

// MARK: - ================== PROTOCOLOS Y EXTENSIONES ==================

// MARK: - Helper Protocol for Message Compatibility
protocol MessageProtocol {
    var senderId: String { get }
    var timestamp: Date { get }
    var isRead: Bool { get }
}

extension Message: MessageProtocol {}
extension EnhancedMessage: MessageProtocol {}

// MARK: - ✅ NUEVA: Extension para analytics y tracking
extension EnhancedMessage {

    /// Propiedades para analytics
    var analyticsData: [String: Any] {
        var data: [String: Any] = [
            "messageType": type.rawValue,
            "hasMedia": mediaUrl != nil,
            "isViewOnce": isViewOnce,
            "messageLength": content?.count ?? 0
        ]

        if isViewOnce {
            data["viewOnceType"] = type.rawValue
            data["hasBeenViewed"] = isViewed
            data["viewerCount"] = viewedBy?.count ?? 0
        }

        if let duration = duration {
            data["mediaDuration"] = duration
        }

        if let fileSize = fileSize {
            data["fileSize"] = fileSize
        }

        return data
    }

    /// Evento de analytics para tracking
    var analyticsEvent: String {
        if isViewOnce {
            return isViewed ? "view_once_message_viewed" : "view_once_message_sent"
        } else {
            return "message_sent"
        }
    }

    /// Media cifrada pendiente de resolver a URL local/remota.
    var isMediaPendingResolution: Bool {
        guard status != .sending else { return false }
        switch type {
        case .image:
            guard mediaUrl == nil else { return false }
            return mediaObjectPath != nil && mediaEncryption != nil
        case .ephemeral:
            guard mediaUrl == nil else { return false }
            return mediaObjectPath != nil && mediaEncryption != nil
        case .video:
            guard thumbnailUrl == nil && mediaUrl == nil else { return false }
            return mediaObjectPath != nil && mediaEncryption != nil
        case .gif, .sticker:
            if mediaUrl == nil {
                return mediaObjectPath != nil && mediaEncryption != nil
            }
            if let urlString = mediaUrl,
               let url = URL(string: urlString),
               url.isFileURL {
                return !FileManager.default.fileExists(atPath: url.path)
            }
            return false
        default:
            return false
        }
    }
}

// MARK: - ✅ NUEVA: Utility para manejo de estados de view-once
struct ViewOnceStateManager {

    /// Determina si un mensaje view-once debe ser eliminado
    static func shouldDeleteViewOnceMessage(_ message: EnhancedMessage, for userId: String) -> Bool {
        guard message.isViewOnce else { return false }

        // Si el usuario no es el remitente y ya vio el mensaje
        if message.senderId != userId && message.hasBeenViewedBy(userId: userId) {
            return true
        }

        return false
    }

    /// Obtiene el texto apropiado para el estado del view-once
    static func getViewOnceStatusText(_ message: EnhancedMessage, for userId: String) -> String {
        guard message.isViewOnce else { return "" }

        if message.isDeleted {
            return "Mensaje eliminado"
        }

        if message.senderId == userId {
            // Remitente
            return message.isViewed ? "Visto" : "Enviado"
        } else {
            // Receptor
            return message.hasBeenViewedBy(userId: userId) ? "Visto" : "Toca para ver"
        }
    }

    /// Obtiene el color apropiado para el estado del view-once
    static func getViewOnceStatusColor(_ message: EnhancedMessage, for userId: String) -> String {
        guard message.isViewOnce else { return "primary" }

        if message.isDeleted {
            return "secondary"
        }

        if message.senderId == userId {
            return message.isViewed ? "success" : "warning"
        } else {
            return message.hasBeenViewedBy(userId: userId) ? "secondary" : "primary"
        }
    }
}

// MARK: - ✅ NUEVA: Extension para formateo y display
extension EnhancedMessage {

    /// Formato de tiempo relativo
    var relativeTimeString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.locale = Locale(identifier: "es_ES")
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }

    /// Formato de tiempo absoluto
    var absoluteTimeString: String {
        let formatter = DateFormatter()

        if Calendar.current.isDateInToday(timestamp) {
            formatter.timeStyle = .short
        } else if Calendar.current.isDate(timestamp, equalTo: Date(), toGranularity: .weekOfYear) {
            formatter.dateFormat = "EEEE HH:mm"
        } else {
            formatter.dateFormat = "dd/MM/yyyy HH:mm"
        }

        formatter.locale = Locale(identifier: "es_ES")
        return formatter.string(from: timestamp)
    }

    /// Tamaño del archivo formateado
    var formattedFileSize: String? {
        guard let fileSize = fileSize else { return nil }

        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }

    /// Duración formateada para audio/video
    var formattedDuration: String? {
        guard let duration = duration else { return nil }

        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60

        if minutes > 0 {
            return String(format: "%d:%02d", minutes, seconds)
        } else {
            return String(format: "0:%02d", seconds)
        }
    }
}

// MARK: - ✅ NUEVA: Constants para view-once (Moments Style)
struct ViewOnceConstants {
    // ✅ Se borra al cerrar vista, no con timers
    static let autoDeleteDelay: TimeInterval = 0.5 // Delay antes de auto-eliminar (al cerrar vista)
    static let maxFileSize: Int64 = 50 * 1024 * 1024 // 50MB máximo
    static let supportedImageTypes = ["image/jpeg", "image/png", "image/heic"]
    static let supportedVideoTypes = ["video/mp4", "video/mov", "video/quicktime"]

    struct Analytics {
        static let viewOnceCreated = "view_once_created"
        static let viewOnceOpened = "view_once_opened"
        static let viewOnceClosed = "view_once_closed" // ✅ Se triggea al cerrar vista
        static let viewOnceDeleted = "view_once_deleted" // ✅ Se triggea después de cerrar
        static let viewOnceExpired = "view_once_expired" // ✅ Por si acaso, pero no se usa
    }

    struct Notifications {
        static let viewOnceViewed = "ViewOnceMessageViewed"
        static let viewOnceDeleted = "ViewOnceMessageDeleted"
        static let viewOnceReceived = "ViewOnceMessageReceived"
        static let viewOnceClosed = "ViewOnceMessageClosed" // ✅ NUEVO: Cuando se cierra la vista
    }

    // ✅ NUEVAS: Constantes específicas para Moments-style
    struct MomentsStyle {
        static let deleteOnViewClose = true // Se borra al cerrar vista
        static let allowScreenshots = false // Prevenir screenshots (si es posible)
        static let showCloseWarning = true // Mostrar "Se borrará al cerrar"
        static let enableHapticFeedback = true // Feedback al abrir/cerrar
    }
}

// MARK: - ✅ NUEVA: Error handling para view-once
enum ViewOnceError: Error, LocalizedError {
    case messageNotFound
    case alreadyViewed
    case notViewOnceMessage
    case deletionFailed
    case uploadFailed
    case invalidMediaType
    case fileTooLarge
    case networkError

    var errorDescription: String? {
        switch self {
        case .messageNotFound:
            return "Mensaje no encontrado"
        case .alreadyViewed:
            return "Este mensaje ya fue visto"
        case .notViewOnceMessage:
            return "No es un mensaje de ver una vez"
        case .deletionFailed:
            return "No se pudo eliminar el mensaje"
        case .uploadFailed:
            return "Error al subir el archivo"
        case .invalidMediaType:
            return "Tipo de archivo no soportado"
        case .fileTooLarge:
            return "El archivo es demasiado grande"
        case .networkError:
            return "Error de conexión"
        }
    }
}

// MARK: - Message Request Model
struct MessageRequest: Identifiable, Codable, Hashable {
    @DocumentID var id: String?
    let senderId: String
    let senderUsername: String?
    let senderProfileImagePath: String?
    let receiverId: String
    let message: String
    let timestamp: Date
    let status: RequestStatus
    let messageType: MessageType
    let mediaUrl: String?
    let thumbnailUrl: String?

    enum RequestStatus: String, Codable, CaseIterable {
        case pending = "pending"
        case accepted = "accepted"
        case rejected = "rejected"
        case blocked = "blocked"

        var displayName: String {
            switch self {
            case .pending: return "Pendiente"
            case .accepted: return "Aceptada"
            case .rejected: return "Rechazada"
            case .blocked: return "Bloqueada"
            }
        }

        var color: String {
            switch self {
            case .pending: return "FF9500" // Naranja
            case .accepted: return "34C759" // Verde
            case .rejected: return "FF3B30" // Rojo
            case .blocked: return "8E8E93" // Gris
            }
        }
    }

    init(id: String?, senderId: String, senderUsername: String?, senderProfileImagePath: String?, receiverId: String, message: String, timestamp: Date, status: RequestStatus, messageType: MessageType, mediaUrl: String?, thumbnailUrl: String?) {
        self.id = id
        self.senderId = senderId
        self.senderUsername = senderUsername
        self.senderProfileImagePath = senderProfileImagePath
        self.receiverId = receiverId
        self.message = message
        self.timestamp = timestamp
        self.status = status
        self.messageType = messageType
        self.mediaUrl = mediaUrl
        self.thumbnailUrl = thumbnailUrl
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id)
        self.senderId = try container.decode(String.self, forKey: .senderId)
        self.senderUsername = try container.decodeIfPresent(String.self, forKey: .senderUsername)
        self.senderProfileImagePath = try container.decodeIfPresent(String.self, forKey: .senderProfileImagePath)
        self.receiverId = try container.decode(String.self, forKey: .receiverId)
        self.message = try container.decode(String.self, forKey: .message)

        // Manejar timestamp de Firestore
        do {
            let timestamp = try container.decode(Timestamp.self, forKey: .timestamp)
            self.timestamp = timestamp.dateValue()
        } catch {
            // Si falla la decodificación de Timestamp, usar fecha actual como fallback
            self.timestamp = Date()
        }

        self.status = try container.decode(RequestStatus.self, forKey: .status)
        self.messageType = try container.decode(MessageType.self, forKey: .messageType)
        self.mediaUrl = try container.decodeIfPresent(String.self, forKey: .mediaUrl)
        self.thumbnailUrl = try container.decodeIfPresent(String.self, forKey: .thumbnailUrl)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(senderId, forKey: .senderId)
        try container.encodeIfPresent(senderUsername, forKey: .senderUsername)
        try container.encodeIfPresent(senderProfileImagePath, forKey: .senderProfileImagePath)
        try container.encode(receiverId, forKey: .receiverId)
        try container.encode(message, forKey: .message)
        try container.encode(Timestamp(date: timestamp), forKey: .timestamp)
        try container.encode(status, forKey: .status)
        try container.encode(messageType, forKey: .messageType)
        try container.encodeIfPresent(mediaUrl, forKey: .mediaUrl)
        try container.encodeIfPresent(thumbnailUrl, forKey: .thumbnailUrl)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case senderId
        case senderUsername
        case senderProfileImagePath
        case receiverId
        case message
        case timestamp
        case status
        case messageType
        case mediaUrl
        case thumbnailUrl
    }

    // Propiedad calculada para mostrar preview del mensaje
    var messagePreview: String {
        switch messageType {
        case .text:
            if message.count > 50 {
                return String(message.prefix(47)) + "..."
            }
            return message
        case .image:
            return "📷 Imagen"
        case .video:
            return "🎥 Video"
        case .audio:
            return "🎵 Audio"
        case .gif:
            return "🎞️ GIF"
        case .file:
            return "📎 Archivo"
        case .location:
            return "📍 Ubicación"
        case .sticker:
            return "😊 Sticker"
        case .ephemeral:
            return "📸 Momento efímero"
        case .sharedMoment:
            return "📷 Momento compartido"
        case .sharedStory:
            return NSLocalizedString("chat.preview.sharedStory", comment: "")
        case .viewOnceImage:
            return "📷 Foto (ver una vez)"
        case .viewOnceVideo:
            return "🎥 Video (ver una vez)"
        }
    }

    // Verificar si la solicitud está pendiente
    var isPending: Bool {
        return status == .pending
    }

    // Verificar si el usuario puede enviar más solicitudes
    var canSendMoreRequests: Bool {
        return status != .blocked
    }
}

// MARK: - Reacciones (una por usuario, estilo IG)

enum MessageReactionMutation {
    /// Sustituye la reacción previa del usuario o la quita si repite el mismo emoji.
    static func apply(
        to reactions: [String: [String]]?,
        emoji: String,
        userId: String
    ) -> [String: [String]]? {
        var reactions = reactions ?? [:]
        let alreadyHasThisEmoji = reactions[emoji]?.contains(userId) ?? false

        if alreadyHasThisEmoji {
            var userIds = reactions[emoji] ?? []
            userIds.removeAll { $0 == userId }
            if userIds.isEmpty {
                reactions.removeValue(forKey: emoji)
            } else {
                reactions[emoji] = userIds
            }
        } else {
            for key in Array(reactions.keys) {
                var userIds = reactions[key] ?? []
                userIds.removeAll { $0 == userId }
                if userIds.isEmpty {
                    reactions.removeValue(forKey: key)
                } else {
                    reactions[key] = userIds
                }
            }
            var userIds = reactions[emoji] ?? []
            userIds.append(userId)
            reactions[emoji] = userIds
        }

        return reactions.isEmpty ? nil : reactions
    }
}

// MARK: - Políticas de mensaje (edición, reenvío)

enum ChatMessagePolicy {
    static let editWindow: TimeInterval = 10 * 60

    static func canEdit(_ message: EnhancedMessage, userId: String) -> Bool {
        guard message.senderId == userId, message.type == .text, !message.isDeleted else { return false }
        return Date().timeIntervalSince(message.timestamp) < editWindow
    }

    /// Solo texto plano; el cifrado E2E obliga a descifrar y recifrar por destino.
    static func canForward(
        _ message: EnhancedMessage,
        currentUserId: String,
        forwardingPreferences: [String: Bool]? = nil
    ) -> Bool {
        guard message.type == .text, !message.isDeleted else { return false }
        let trimmed = message.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return false }
        if message.senderId == currentUserId { return true }
        return forwardingPreferences?[message.senderId] ?? true
    }

    static func canCopy(
        _ message: EnhancedMessage,
        currentUserId: String,
        forwardingPreferences: [String: Bool]? = nil
    ) -> Bool {
        canForward(message, currentUserId: currentUserId, forwardingPreferences: forwardingPreferences)
    }
}
