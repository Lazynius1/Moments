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
    let isMuted: Bool?

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
        case isMuted
    }

    init(id: String?, participants: [String], lastMessage: String?, timestamp: Date, readStatus: [String: Bool], otherParticipantId: String, otherParticipantUsername: String?, otherParticipantProfileImagePath: String?, isPinned: Bool? = false, isMuted: Bool? = false) {
        self.id = id
        self.participants = participants
        self.lastMessage = lastMessage
        self.timestamp = timestamp
        self.readStatus = readStatus
        self.otherParticipantId = otherParticipantId
        self.otherParticipantUsername = otherParticipantUsername
        self.otherParticipantProfileImagePath = otherParticipantProfileImagePath
        self.isPinned = isPinned
        self.isMuted = isMuted
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id)
        self.participants = try container.decode([String].self, forKey: .participants)
        self.lastMessage = try container.decodeIfPresent(String.self, forKey: .lastMessage)
        let timestamp = try container.decode(Timestamp.self, forKey: .timestamp)
        self.timestamp = timestamp.dateValue()
        self.readStatus = try container.decodeIfPresent([String: Bool].self, forKey: .readStatus) ?? [:]
        self.otherParticipantId = try container.decode(String.self, forKey: .otherParticipantId)
        self.otherParticipantUsername = try container.decodeIfPresent(String.self, forKey: .otherParticipantUsername)
        self.otherParticipantProfileImagePath = try container.decodeIfPresent(String.self, forKey: .otherParticipantProfileImagePath)
        self.isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        self.isMuted = try container.decodeIfPresent(Bool.self, forKey: .isMuted) ?? false
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
        try container.encodeIfPresent(isMuted, forKey: .isMuted)
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
        if let lastMessage = lastMessage {
            if lastMessage.starts(with: "📎") {
                return lastMessage // Ya tiene formato de archivo adjunto
            } else if lastMessage.count > 50 {
                return String(lastMessage.prefix(47)) + "..."
            }
            return lastMessage
        }
        return "Nueva conversación"
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
    // ✅ NUEVOS: Tipos para view-once
    case viewOnceImage = "viewOnceImage"
    case viewOnceVideo = "viewOnceVideo"
    
    var displayName: String {
        switch self {
        case .text: return "Texto"
        case .image: return "Imagen"
        case .video: return "Video"
        case .audio: return "Audio"
        case .gif: return "GIF"
        case .sticker: return "Sticker"
        case .location: return "Ubicación"
        case .file: return "Archivo"
        case .ephemeral: return "Temporal"
        case .sharedMoment: return "Momento Compartido"
        case .viewOnceImage: return "Foto (Ver una vez)"
        case .viewOnceVideo: return "Video (Ver una vez)"
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
        case .text: return ""
        case .image: return "📷 Foto"
        case .video: return "🎥 Video"
        case .audio: return "🎵 Audio"
        case .gif: return "🎞️ GIF"
        case .sticker: return "😊 Sticker"
        case .location: return "📍 Ubicación"
        case .file: return "📎 Archivo"
        case .ephemeral: return "📸 Momento efímero"
        case .sharedMoment: return "📷 Momento compartido"
        case .viewOnceImage: return "📷 Foto (ver una vez)"
        case .viewOnceVideo: return "🎥 Video (ver una vez)"
        }
    }
}

// MARK: - Message Status
enum MessageStatus: String, Codable {
    case sending = "sending"
    case sent = "sent"
    case delivered = "delivered"
    case read = "read"
    case failed = "failed"
    
    var displayName: String {
        switch self {
        case .sending: return "Enviando"
        case .sent: return "Enviado"
        case .delivered: return "Entregado"
        case .read: return "Leído"
        case .failed: return "Falló"
        }
    }
    
    var iconName: String {
        switch self {
        case .sending: return "clock"
        case .sent: return "checkmark"
        case .delivered: return "checkmark.circle"
        case .read: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle"
        }
    }
}

// MARK: - Enhanced Message Model with View-Once Support
class EnhancedMessage: Codable, Identifiable, ObservableObject {
    let id: String
    let conversationId: String
    let senderId: String
    let type: MessageType
    let content: String?
    let mediaUrl: String?
    let thumbnailUrl: String?
    let duration: Double?
    let fileName: String?
    let fileSize: Int64?
    let latitude: Double?
    let longitude: Double?
    let timestamp: Date
    @Published var status: MessageStatus
    @Published var isRead: Bool
    @Published var isDeleted: Bool
    var deletedAt: Date?
    var editedAt: Date?
    var reactions: [String: [String]]?
    var replyTo: String?
    var expirationDate: Date?
    @Published var isViewed: Bool
    let storyReplyData: [String: String]?
    let sharedMomentData: [String: String]?
    
    // ✅ NUEVOS: Campos para view-once
    var viewedBy: [String]? // IDs de usuarios que han visto el mensaje view-once
    
    enum CodingKeys: String, CodingKey {
        case id, conversationId, senderId, type, content, mediaUrl, thumbnailUrl
        case duration, fileName, fileSize, latitude, longitude, timestamp
        case status, isRead, isDeleted, deletedAt, editedAt, reactions
        case replyTo, expirationDate, isViewed, storyReplyData, sharedMomentData
        case viewedBy // ✅ NUEVO
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
        self.duration = try container.decodeIfPresent(Double.self, forKey: .duration)
        self.fileName = try container.decodeIfPresent(String.self, forKey: .fileName)
        self.fileSize = try container.decodeIfPresent(Int64.self, forKey: .fileSize)
        self.latitude = try container.decodeIfPresent(Double.self, forKey: .latitude)
        self.longitude = try container.decodeIfPresent(Double.self, forKey: .longitude)
        
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
        
        // ✅ NUEVO: Decodificar viewedBy
        self.viewedBy = try container.decodeIfPresent([String].self, forKey: .viewedBy)
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
        try container.encodeIfPresent(duration, forKey: .duration)
        try container.encodeIfPresent(fileName, forKey: .fileName)
        try container.encodeIfPresent(fileSize, forKey: .fileSize)
        try container.encodeIfPresent(latitude, forKey: .latitude)
        try container.encodeIfPresent(longitude, forKey: .longitude)
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
        
        // ✅ NUEVO: Codificar viewedBy
        try container.encodeIfPresent(viewedBy, forKey: .viewedBy)
    }
    
    required init(id: String? = nil,
         conversationId: String,
         senderId: String,
         type: MessageType,
         content: String? = nil,
         mediaUrl: String? = nil,
         thumbnailUrl: String? = nil,
         duration: Double? = nil,
         fileName: String? = nil,
         fileSize: Int64? = nil,
         latitude: Double? = nil,
         longitude: Double? = nil,
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
         viewedBy: [String]? = nil) { // ✅ NUEVO parámetro
        
        self.id = id ?? UUID().uuidString
        self.conversationId = conversationId
        self.senderId = senderId
        self.type = type
        self.content = content
        self.mediaUrl = mediaUrl
        self.thumbnailUrl = thumbnailUrl
        self.duration = duration
        self.fileName = fileName
        self.fileSize = fileSize
        self.latitude = latitude
        self.longitude = longitude
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
        self.viewedBy = viewedBy
    }
    
    var isExpired: Bool {
        guard let expirationDate = expirationDate else { return false }
        return Date() > expirationDate
    }
    
    // ✅ ACTUALIZADA: Preview mejorado con support para view-once
    var preview: String {
        switch type {
        case .text:
            return content ?? ""
        case .image:
            return "📷 Imagen"
        case .video:
            return "🎥 Video"
        case .audio:
            return "🎵 Audio"
        case .gif:
            return "🎞️ GIF"
        case .sticker:
            return "😊 Sticker"
        case .location:
            return "📍 Ubicación"
        case .file:
            return "📎 \(fileName ?? "Archivo")"
        case .ephemeral:
            return "⏱️ Mensaje temporal"
        case .sharedMoment:
            return "📸 Momento compartido"
        case .viewOnceImage:
            return "📷 Foto (ver una vez)"
        case .viewOnceVideo:
            return "🎥 Video (ver una vez)"
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
            return isViewed ? "Visto" : "Enviado"
        } else {
            // Usuario que recibe el mensaje
            let hasViewed = hasBeenViewedBy(userId: currentUserId)
            return hasViewed ? "Visto" : "Toca para ver"
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
        case .image: return "📷 Foto (ver una vez)"
        case .video: return "🎥 Video (ver una vez)"
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
        return isViewOnce ? "📸 Te envió un mensaje que se borrará al verlo" : messagePreview
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

// MARK: - ✅ NUEVA: Constants para view-once (Instagram Style)
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
    
    // ✅ NUEVAS: Constantes específicas para Instagram-style
    struct InstagramStyle {
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
