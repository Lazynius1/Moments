import Foundation
import SwiftUI


// MARK: - ================== MODELOS DE SEGUIMIENTO Y SOLICITUDES ==================

// MARK: - Enums para Estados de Solicitud
enum FollowRequestStatus: String, CaseIterable, Codable {
    case pending = "pending"
    case accepted = "accepted"
    case rejected = "rejected"
    case cancelled = "cancelled"
    
    var displayName: String {
        switch self {
        case .pending: return "Pendiente"
        case .accepted: return "Aceptada"
        case .rejected: return "Rechazada"
        case .cancelled: return "Cancelada"
        }
    }
}

// MARK: - Modelo de Solicitud de Seguimiento
struct FollowRequest: Codable, Identifiable {
    let id: String
    let senderId: String
    let senderUsername: String
    let recipientId: String
    let status: FollowRequestStatus
    let timestamp: Date
    let expirationDate: Date?
    
    enum CodingKeys: String, CodingKey {
        case id, senderId, senderUsername, recipientId, status, timestamp, expirationDate
    }
    
    init(senderId: String, senderUsername: String, recipientId: String) {
        self.id = UUID().uuidString
        self.senderId = senderId
        self.senderUsername = senderUsername
        self.recipientId = recipientId
        self.status = .pending
        self.timestamp = Date()
        self.expirationDate = Calendar.current.date(byAdding: .day, value: 30, to: Date())
    }
    
    init(id: String, senderId: String, senderUsername: String, recipientId: String, status: FollowRequestStatus, timestamp: Date, expirationDate: Date?) {
        self.id = id
        self.senderId = senderId
        self.senderUsername = senderUsername
        self.recipientId = recipientId
        self.status = status
        self.timestamp = timestamp
        self.expirationDate = expirationDate
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.senderId = try container.decode(String.self, forKey: .senderId)
        self.senderUsername = try container.decode(String.self, forKey: .senderUsername)
        self.recipientId = try container.decode(String.self, forKey: .recipientId)
        
        let statusString = try container.decode(String.self, forKey: .status)
        self.status = FollowRequestStatus(rawValue: statusString) ?? .pending
        
        let timestampFirestore = try container.decode(Timestamp.self, forKey: .timestamp)
        self.timestamp = timestampFirestore.dateValue()
        
        if let expirationFirestore = try container.decodeIfPresent(Timestamp.self, forKey: .expirationDate) {
            self.expirationDate = expirationFirestore.dateValue()
        } else {
            self.expirationDate = nil
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(senderId, forKey: .senderId)
        try container.encode(senderUsername, forKey: .senderUsername)
        try container.encode(recipientId, forKey: .recipientId)
        try container.encode(status.rawValue, forKey: .status)
        try container.encode(Timestamp(date: timestamp), forKey: .timestamp)
        if let expirationDate = expirationDate {
            try container.encode(Timestamp(date: expirationDate), forKey: .expirationDate)
        }
    }
    
    // Verificar si la solicitud ha expirado
    var isExpired: Bool {
        guard let expirationDate = expirationDate else { return false }
        return Date() > expirationDate
    }
    
    // Verificar si la solicitud es válida (no expirada y pendiente)
    var isValid: Bool {
        return status == .pending && !isExpired
    }
}

// MARK: - ================== MODELOS DE CONEXIONES LEGACY ==================

struct Connection: Identifiable, Codable {
    let id: String
    let userId: String
    let timestamp: Date
    
    enum CodingKeys: String, CodingKey {
        case userId
        case timestamp
    }
    
    init(id: String, userId: String, timestamp: Date) {
        self.id = id
        self.userId = userId
        self.timestamp = timestamp
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .userId)
        self.userId = try container.decode(String.self, forKey: .userId)
        let timestamp = try container.decode(Timestamp.self, forKey: .timestamp)
        self.timestamp = timestamp.dateValue()
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userId, forKey: .userId)
        try container.encode(Timestamp(date: timestamp), forKey: .timestamp)
    }
}

struct Admirer: Identifiable, Codable {
    let id: String
    let userId: String
    let timestamp: Date
    
    enum CodingKeys: String, CodingKey {
        case userId
        case timestamp
    }
    
    init(id: String, userId: String, timestamp: Date) {
        self.id = id
        self.userId = userId
        self.timestamp = timestamp
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .userId)
        self.userId = try container.decode(String.self, forKey: .userId)
        let timestamp = try container.decode(Timestamp.self, forKey: .timestamp)
        self.timestamp = timestamp.dateValue()
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userId, forKey: .userId)
        try container.encode(Timestamp(date: timestamp), forKey: .timestamp)
    }
}


struct Comment: Identifiable, Codable, Equatable {
    var id: String? = nil
    let authorId: String
    let username: String
    let content: String
    let timestamp: Date
    let profileImagePath: String?
    let updatedAt: Date?
    var reactions: [String: [String]]
    let parentCommentId: String?
    let isEdited: Bool?              // NUEVO CAMPO
    let editedTimestamp: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case authorId
        case username
        case content
        case timestamp
        case profileImagePath
        case updatedAt
        case reactions
        case parentCommentId
        case isEdited
        case editedTimestamp
    }

    init(id: String? = nil, authorId: String, username: String, content: String, timestamp: Date, profileImagePath: String? = nil, updatedAt: Date? = nil, reactions: [String: [String]] = [:], parentCommentId: String? = nil, isEdited: Bool? = nil, editedTimestamp: Date? = nil) {
        self.id = id
        self.authorId = authorId
        self.username = username
        self.content = content
        self.timestamp = timestamp
        self.profileImagePath = profileImagePath
        self.updatedAt = updatedAt
        self.reactions = reactions
        self.parentCommentId = parentCommentId
        self.isEdited = isEdited
        self.editedTimestamp = editedTimestamp

    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id)
        self.authorId = try container.decode(String.self, forKey: .authorId)
        self.username = try container.decode(String.self, forKey: .username)
        self.content = try container.decode(String.self, forKey: .content)
        let timestamp = try container.decode(Timestamp.self, forKey: .timestamp)
        self.timestamp = timestamp.dateValue()
        self.profileImagePath = try container.decodeIfPresent(String.self, forKey: .profileImagePath)
        let updatedAt = try container.decodeIfPresent(Timestamp.self, forKey: .updatedAt)
        self.updatedAt = updatedAt?.dateValue()
        self.reactions = try container.decodeIfPresent([String: [String]].self, forKey: .reactions) ?? [:]
        self.parentCommentId = try container.decodeIfPresent(String.self, forKey: .parentCommentId)
        self.isEdited = try container.decodeIfPresent(Bool.self, forKey: .isEdited) ?? false
        let editedTimestamp = try container.decodeIfPresent(Timestamp.self, forKey: .editedTimestamp)
        self.editedTimestamp = editedTimestamp?.dateValue()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(authorId, forKey: .authorId)
        try container.encode(username, forKey: .username)
        try container.encode(content, forKey: .content)
        try container.encode(Timestamp(date: timestamp), forKey: .timestamp)
        try container.encodeIfPresent(profileImagePath, forKey: .profileImagePath)
        if let updatedAt = updatedAt {
            try container.encode(Timestamp(date: updatedAt), forKey: .updatedAt)
        }
        try container.encode(reactions, forKey: .reactions)
        try container.encodeIfPresent(parentCommentId, forKey: .parentCommentId)
        try container.encodeIfPresent(isEdited, forKey: .isEdited)
        if let editedTimestamp = editedTimestamp {
            try container.encode(Timestamp(date: editedTimestamp), forKey: .editedTimestamp)
            
        }
    }

    static func == (lhs: Comment, rhs: Comment) -> Bool {
        return lhs.id == rhs.id &&
               lhs.authorId == rhs.authorId &&
               lhs.username == rhs.username &&
               lhs.content == rhs.content &&
               lhs.timestamp == rhs.timestamp &&
               lhs.profileImagePath == rhs.profileImagePath &&
               lhs.updatedAt == rhs.updatedAt &&
               lhs.reactions == rhs.reactions &&
               lhs.parentCommentId == rhs.parentCommentId &&
               lhs.isEdited == rhs.isEdited &&
               lhs.editedTimestamp == rhs.editedTimestamp
    }
}

extension Comment {
    var isEditedFlag: Bool {
        return isEdited ?? false
    }
    
    var wasEdited: Bool {
        return editedTimestamp != nil
    }
}
// MARK: - ================== MODELOS DE CONTENIDO ==================

struct MediaItem: Identifiable, Codable {
    let id = UUID().uuidString
    let type: MediaType
    let url: String
    // 🔥 NUEVOS CAMPOS
    let thumbnailUrl: String?
    let videoDuration: Double?
    let videoFileSize: Int64?
    let videoResolution: String?

    enum MediaType: String, Codable {
        case image
        case video
    }
    
    // Init para videos con metadata completa
    init(type: MediaType, url: String, thumbnailUrl: String? = nil, videoDuration: Double? = nil, videoFileSize: Int64? = nil, videoResolution: String? = nil) {
        self.type = type
        self.url = url
        self.thumbnailUrl = thumbnailUrl
        self.videoDuration = videoDuration
        self.videoFileSize = videoFileSize
        self.videoResolution = videoResolution
    }
}

// ================== MODELO DE MOMENTO (CORREGIDO) ==================
struct Moment: Identifiable, Codable, Equatable {
    var id: String?
    let authorId: String
    let username: String
    let content: String
    let imagePath: String?
    let videoUrl: String?
    let timestamp: Date
    var reactions: [String: [String]]
    let commentCount: Int
    let profileImagePath: String?
    let taggedUsers: [String]?
    let location: String?
    let locationCoordinate: LocationCoordinate?  // ✅ NUEVO: Coordenadas de la ubicación
    let audience: String?
    let mediaItems: [MediaItem]?
    let aspectRatio: String?
    let customListId: String?
    let thumbnailUrl: String?        // URL del thumbnail generado
    let videoDuration: Double?       // Duración en segundos
    let videoFileSize: Int64?          // Tamaño en bytes
    let videoResolution: String?     // "1080x1920", "1080x1080", etc.
    
    // ✅ NUEVOS CAMPOS DE CONFIGURACIÓN AVANZADA
    let disableComments: Bool
    let hideLikeCounts: Bool
    let allowSharing: Bool
    
    // ✅ NUEVOS CAMPOS DE TRENDING (opcionales para compatibilidad)
    let trendingScore: Double?
    let engagementRate: Double?

    // ✅ NUEVO: Estructura para coordenadas de ubicación
    struct LocationCoordinate: Codable, Equatable {
        let latitude: Double
        let longitude: Double
        
        // ✅ CONVERTIR A CLLocationCoordinate2D
        var toCLLocationCoordinate2D: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, authorId, username, content, timestamp, reactions, commentCount
        case profileImagePath, taggedUsers, location, locationCoordinate, audience, mediaItems
        case aspectRatio, customListId
        case imagePath = "imageUrl"
        case videoUrl
        // ✅ NUEVAS CLAVES
        case disableComments, hideLikeCounts, allowSharing
        case thumbnailUrl, videoDuration, videoFileSize, videoResolution
        case trendingScore, engagementRate
    }
    
    static func == (lhs: Moment, rhs: Moment) -> Bool {
        return lhs.id == rhs.id
    }
    
    // ✅ NUEVO: Inicializador personalizado con campos de trending
    init(
        id: String?,
        authorId: String,
        username: String,
        content: String,
        imagePath: String?,
        videoUrl: String?,
        timestamp: Date,
        reactions: [String: [String]],
        commentCount: Int,
        profileImagePath: String?,
        taggedUsers: [String]?,
        location: String?,
        locationCoordinate: LocationCoordinate? = nil,  // ✅ NUEVO: Coordenadas de ubicación
        audience: String?,
        mediaItems: [MediaItem]?,
        aspectRatio: String?,
        customListId: String?,
        thumbnailUrl: String?,
        videoDuration: Double?,
        videoFileSize: Int64?,
        videoResolution: String?,
        disableComments: Bool,
        hideLikeCounts: Bool,
        allowSharing: Bool,
        trendingScore: Double? = nil,
        engagementRate: Double? = nil
    ) {
        self.id = id
        self.authorId = authorId
        self.username = username
        self.content = content
        self.imagePath = imagePath
        self.videoUrl = videoUrl
        self.timestamp = timestamp
        self.reactions = reactions
        self.commentCount = commentCount
        self.profileImagePath = profileImagePath
        self.taggedUsers = taggedUsers
        self.location = location
        self.locationCoordinate = locationCoordinate  // ✅ NUEVO: Asignar coordenadas
        self.audience = audience
        self.mediaItems = mediaItems
        self.aspectRatio = aspectRatio
        self.customListId = customListId
        self.thumbnailUrl = thumbnailUrl
        self.videoDuration = videoDuration
        self.videoFileSize = videoFileSize
        self.videoResolution = videoResolution
        self.disableComments = disableComments
        self.hideLikeCounts = hideLikeCounts
        self.allowSharing = allowSharing
        self.trendingScore = trendingScore
        self.engagementRate = engagementRate
    }
}



// ================== MODELO DE HISTORIA (CORREGIDO) ==================
struct Story: Identifiable, Codable {
    var id: String?
    let authorId: String
    let duration: Double
    let expirationDate: Date
    let mediaItem: MediaItem
    let profileImagePath: String?
    let timestamp: Date
    let username: String
    let audience: String?
    let customListId: String? // ✅ AÑADIDO: Campo para el ID de la lista personalizada
    let text: String?
    let textPosition: CGPoint?
    let textStyle: String?
    let stickers: [StickerData]?
    let drawingData: Data?
    let aspectRatio: String? // ✅ AÑADIDO: Aspect ratio del video/imagen
    let backgroundFrameURL: String? // ✅ AÑADIDO: URL del frame de fondo para videos horizontales
    let chainId: String? // 🔗 AÑADIDO: ID de la cadena de historias
    let chainPosition: Int? // 🔗 AÑADIDO: Posición en la cadena (1, 2, 3...)
    let chainTitle: String? // 🔗 AÑADIDO: Título de la cadena

    enum CodingKeys: String, CodingKey {
        case id
        case authorId
        case duration
        case expirationDate
        case mediaItem
        case profileImagePath
        case timestamp
        case username
        case audience
        case customListId // ✅ AÑADIDO: Clave de codificación
        case text
        case textPosition
        case textStyle
        case stickers
        case drawingData
        case aspectRatio // ✅ AÑADIDO: Clave de codificación
        case backgroundFrameURL // ✅ AÑADIDO: Clave de codificación
        case chainId // 🔗 AÑADIDO: Clave de codificación
        case chainPosition // 🔗 AÑADIDO: Clave de codificación
        case chainTitle // 🔗 AÑADIDO: Clave de codificación
        
        // Claves antiguas para compatibilidad al leer
        case imagePath
        case videoUrl
    }

    init(id: String?,
         authorId: String,
         username: String,
         mediaItem: MediaItem,
         duration: Double,
         timestamp: Date,
         expirationDate: Date,
         profileImagePath: String?,
         audience: String? = nil,
         customListId: String? = nil, // ✅ AÑADIDO
         text: String? = nil,
         textPosition: CGPoint? = nil,
         textStyle: String? = nil,
         stickers: [StickerData]? = nil,
         drawingData: Data? = nil,
         aspectRatio: String? = nil, // ✅ AÑADIDO: Aspect ratio
         backgroundFrameURL: String? = nil, // ✅ AÑADIDO: URL del frame de fondo
         chainId: String? = nil, // 🔗 AÑADIDO: ID de la cadena
         chainPosition: Int? = nil, // 🔗 AÑADIDO: Posición en la cadena
         chainTitle: String? = nil) { // 🔗 AÑADIDO: Título de la cadena
        self.id = id
        self.authorId = authorId
        self.username = username
        self.mediaItem = mediaItem
        self.duration = duration
        self.timestamp = timestamp
        self.expirationDate = expirationDate
        self.profileImagePath = profileImagePath
        self.audience = audience
        self.customListId = customListId // ✅ AÑADIDO
        self.text = text
        self.textPosition = textPosition
        self.textStyle = textStyle
        self.stickers = stickers
        self.drawingData = drawingData
        self.aspectRatio = aspectRatio // ✅ AÑADIDO: Asignar aspect ratio
        self.backgroundFrameURL = backgroundFrameURL // ✅ AÑADIDO: Asignar URL del frame de fondo
        self.chainId = chainId // 🔗 AÑADIDO: Asignar ID de la cadena
        self.chainPosition = chainPosition // 🔗 AÑADIDO: Asignar posición en la cadena
        self.chainTitle = chainTitle // 🔗 AÑADIDO: Asignar título de la cadena
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id)
        self.authorId = try container.decode(String.self, forKey: .authorId)
        self.username = try container.decode(String.self, forKey: .username)
        self.duration = try container.decode(Double.self, forKey: .duration)
        let timestamp = try container.decode(Timestamp.self, forKey: .timestamp)
        self.timestamp = timestamp.dateValue()
        let expirationDate = try container.decode(Timestamp.self, forKey: .expirationDate)
        self.expirationDate = expirationDate.dateValue()
        self.profileImagePath = try container.decodeIfPresent(String.self, forKey: .profileImagePath)
        self.audience = try container.decodeIfPresent(String.self, forKey: .audience)
        self.customListId = try container.decodeIfPresent(String.self, forKey: .customListId) // ✅ AÑADIDO
        self.text = try container.decodeIfPresent(String.self, forKey: .text)
        
        if let textPositionData = try container.decodeIfPresent(Data.self, forKey: .textPosition) {
            self.textPosition = try? JSONDecoder().decode(CGPoint.self, from: textPositionData)
        } else {
            self.textPosition = nil
        }
        
        self.textStyle = try container.decodeIfPresent(String.self, forKey: .textStyle)
        self.stickers = try container.decodeIfPresent([StickerData].self, forKey: .stickers)
        self.drawingData = try container.decodeIfPresent(Data.self, forKey: .drawingData)
        self.aspectRatio = try container.decodeIfPresent(String.self, forKey: .aspectRatio) // ✅ AÑADIDO: Decodificar aspect ratio
        self.backgroundFrameURL = try container.decodeIfPresent(String.self, forKey: .backgroundFrameURL) // ✅ AÑADIDO: Decodificar URL del frame de fondo
        self.chainId = try container.decodeIfPresent(String.self, forKey: .chainId) // 🔗 AÑADIDO: Decodificar ID de la cadena
        self.chainPosition = try container.decodeIfPresent(Int.self, forKey: .chainPosition) // 🔗 AÑADIDO: Decodificar posición en la cadena
        self.chainTitle = try container.decodeIfPresent(String.self, forKey: .chainTitle) // 🔗 AÑADIDO: Decodificar título de la cadena
        
        if let mediaItem = try? container.decodeIfPresent(MediaItem.self, forKey: .mediaItem) {
            self.mediaItem = mediaItem
        } else if let imagePath = try container.decodeIfPresent(String.self, forKey: .imagePath), !imagePath.isEmpty {
            self.mediaItem = MediaItem(type: .image, url: imagePath)
        } else if let videoUrl = try container.decodeIfPresent(String.self, forKey: .videoUrl), !videoUrl.isEmpty {
            self.mediaItem = MediaItem(type: .video, url: videoUrl)
        } else {
            throw DecodingError.dataCorruptedError(forKey: .mediaItem, in: container, debugDescription: "No valid mediaItem, imagePath, or videoUrl found")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(authorId, forKey: .authorId)
        try container.encode(username, forKey: .username)
        try container.encode(mediaItem, forKey: .mediaItem)
        try container.encode(duration, forKey: .duration)
        try container.encode(Timestamp(date: timestamp), forKey: .timestamp)
        try container.encode(Timestamp(date: expirationDate), forKey: .expirationDate)
        try container.encodeIfPresent(profileImagePath, forKey: .profileImagePath)
        try container.encodeIfPresent(audience, forKey: .audience)
        try container.encodeIfPresent(customListId, forKey: .customListId) // ✅ AÑADIDO
        try container.encodeIfPresent(text, forKey: .text)
        
        if let textPosition = textPosition {
            let textPositionData = try? JSONEncoder().encode(textPosition)
            try container.encodeIfPresent(textPositionData, forKey: .textPosition)
        }
        
        try container.encodeIfPresent(textStyle, forKey: .textStyle)
        try container.encodeIfPresent(stickers, forKey: .stickers)
        try container.encodeIfPresent(drawingData, forKey: .drawingData)
        try container.encodeIfPresent(aspectRatio, forKey: .aspectRatio) // ✅ AÑADIDO: Codificar aspect ratio
        try container.encodeIfPresent(backgroundFrameURL, forKey: .backgroundFrameURL) // ✅ AÑADIDO: Codificar URL del frame de fondo
        try container.encodeIfPresent(chainId, forKey: .chainId) // 🔗 AÑADIDO: Codificar ID de la cadena
        try container.encodeIfPresent(chainPosition, forKey: .chainPosition) // 🔗 AÑADIDO: Codificar posición en la cadena
        try container.encodeIfPresent(chainTitle, forKey: .chainTitle) // 🔗 AÑADIDO: Codificar título de la cadena
        
        // Mantener compatibilidad
        try container.encodeIfPresent(mediaItem.type == .image ? mediaItem.url : nil, forKey: .imagePath)
        try container.encodeIfPresent(mediaItem.type == .video ? mediaItem.url : nil, forKey: .videoUrl)
    }
    
    // ✅ FUNCIÓN: Convertir StickerData a StickerItem para la UI
    func convertStickersToStickerItems() -> [StickerItem] {
        guard let stickers = stickers else { return [] }
        
        return stickers.compactMap { stickerData in
            
            // ✅ RECREAR IMAGEN DEL STICKER basada en el tipo
            // Android: Stickers will be handled differently, placeholder for now
            let stickerImage: Any = NSNull() // Placeholder - actual sticker rendering will be done on Android side
            
            // Note: Sticker image creation logic removed for Android compatibility
            // The actual sticker rendering will be handled on the Android native side
            
            // Crear datos de interacción
            // ✅ CREAR COORDENADAS SI ESTÁN DISPONIBLES
            let locationCoordinate: CLLocationCoordinate2D?
            if let latitude = stickerData.latitude, let longitude = stickerData.longitude {
                locationCoordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            } else {
                locationCoordinate = nil
            }
            
            // ✅ FALLBACK para weather stickers antiguos sin weatherSymbol
            let weatherSymbol = stickerData.weatherSymbol ?? (stickerData.type == "weather" ? stickerData.content : nil)
            
            let interactionData = StickerItem.StickerInteractionData(
                username: stickerData.username,
                userId: stickerData.userId,
                hashtag: stickerData.hashtag,
                location: stickerData.location,
                locationCoordinate: locationCoordinate,
                pollData: stickerData.pollOptions,
                questionText: stickerData.questionText,
                weatherSymbol: weatherSymbol
            )
            
            // Crear StickerItem con las transformaciones aplicadas
            var stickerItem: StickerItem
            
            // ✅ MANEJAR STICKERS ANIMADOS
            var gifURL: URL? = nil
            
            // Intentar obtener la URL del GIF desde gifURL o desde content
            if let gifURLString = stickerData.gifURL, let url = URL(string: gifURLString) {
                gifURL = url
            } else if stickerData.isAnimated, let url = URL(string: stickerData.content) {
                // Si no hay gifURL pero isAnimated es true, intentar usar content como URL
                gifURL = url
            }
            
            // Android: StickerItem creation will be handled differently
            // For now, create a basic StickerItem
            if stickerData.isAnimated, let finalGifURL = gifURL {
                // Crear sticker animado con GIF
                stickerItem = StickerItem(
                    image: Any.self as! Any, // Placeholder - will be handled on Android
                    gifURL: finalGifURL,
                    position: stickerData.position,
                    type: StickerItem.StickerType(rawValue: stickerData.type) ?? .generic,
                    interactionData: interactionData
                )
            } else {
                // Crear sticker estático
                stickerItem = StickerItem(
                    image: Any.self as! Any, // Placeholder - will be handled on Android
                    position: stickerData.position,
                    type: StickerItem.StickerType(rawValue: stickerData.type) ?? .generic,
                    interactionData: interactionData
                )
            }
            
            // Aplicar transformaciones
            stickerItem.scale = stickerData.scale
            stickerItem.rotation = Angle(radians: stickerData.rotation)
            
            
            return stickerItem
        }
    }
    
    // ✅ FUNCIONES AUXILIARES para recrear imágenes de stickers
    // Android: These functions will be handled natively on Android side
    private func createMentionStickerImage(username: String) -> Any {
        // Android: Sticker rendering will be done natively
        return NSNull()
    }
    
    private func createHashtagStickerImage(hashtag: String) -> Any {
        // Android: Sticker rendering will be done natively
        return NSNull()
    }
    
    private func createLocationStickerImage(location: String) -> Any {
        // Android: Sticker rendering will be done natively
        return NSNull()
    }
    
    private func createQuestionStickerImage(question: String) -> Any {
        // Android: Sticker rendering will be done natively
        return NSNull()
    }
    
    private func createPollStickerImage(pollOptions: [String]) -> Any {
        // Android: Sticker rendering will be done natively
        return NSNull()
    }
}

// Modelo para almacenar datos de stickers
struct StickerData: Codable {
    let type: String
    let content: String
    let position: CGPoint
    let scale: CGFloat
    let rotation: Double
    
    // ✅ PROPIEDADES EXISTENTES para interactividad
    let username: String?
    let userId: String?
    let hashtag: String?
    let location: String?
    let latitude: Double?
    let longitude: Double?
    let questionText: String?
    let pollOptions: [String]?
    let weatherSymbol: String? // ✅ NUEVA: Para stickers de clima
    
    // ✅ NUEVAS PROPIEDADES para animación
    let isAnimated: Bool
    let gifURL: String? // URL como String para Codable

    
    init(type: String, content: String, position: CGPoint, scale: CGFloat, rotation: Double,
         username: String? = nil, userId: String? = nil, hashtag: String? = nil,
         location: String? = nil, latitude: Double? = nil, longitude: Double? = nil, questionText: String? = nil, pollOptions: [String]? = nil, weatherSymbol: String? = nil,
         isAnimated: Bool = false, gifURL: String? = nil) {
        self.type = type
        self.content = content
        self.position = position
        self.scale = scale
        self.rotation = rotation
        self.username = username
        self.userId = userId
        self.hashtag = hashtag
        self.location = location
        self.latitude = latitude
        self.longitude = longitude
        self.questionText = questionText
        self.pollOptions = pollOptions
        self.weatherSymbol = weatherSymbol
        self.isAnimated = isAnimated
        self.gifURL = gifURL
    }
    
    // ✅ INICIALIZADOR PERSONALIZADO para compatibilidad hacia atrás
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.type = try container.decode(String.self, forKey: .type)
        self.content = try container.decode(String.self, forKey: .content)
        
        // ✅ COMPATIBILIDAD HACIA ATRÁS: Manejar tanto position como positionX/positionY
        let position: CGPoint
        if let positionPoint = try? container.decode(CGPoint.self, forKey: .position) {
            // Nuevo formato: position como CGPoint
            position = positionPoint
        } else {
            // Formato antiguo: positionX y positionY separados
            let positionX = try container.decode(CGFloat.self, forKey: .positionX)
            let positionY = try container.decode(CGFloat.self, forKey: .positionY)
            position = CGPoint(x: positionX, y: positionY)
        }
        self.position = position
        
        self.scale = try container.decode(CGFloat.self, forKey: .scale)
        self.rotation = try container.decode(Double.self, forKey: .rotation)
        

        self.username = try container.decodeIfPresent(String.self, forKey: .username)
        self.userId = try container.decodeIfPresent(String.self, forKey: .userId)
        self.hashtag = try container.decodeIfPresent(String.self, forKey: .hashtag)
        self.location = try container.decodeIfPresent(String.self, forKey: .location)
        self.latitude = try container.decodeIfPresent(Double.self, forKey: .latitude)
        self.longitude = try container.decodeIfPresent(Double.self, forKey: .longitude)
        self.questionText = try container.decodeIfPresent(String.self, forKey: .questionText)
        self.pollOptions = try container.decodeIfPresent([String].self, forKey: .pollOptions)
        self.weatherSymbol = try container.decodeIfPresent(String.self, forKey: .weatherSymbol)
        
        // ✅ COMPATIBILIDAD HACIA ATRÁS: Detectar stickers animados basándose en el contenido
        let decodedIsAnimated = try container.decodeIfPresent(Bool.self, forKey: .isAnimated) ?? false
        let decodedGifURL = try container.decodeIfPresent(String.self, forKey: .gifURL)
        

        
        // Si no hay isAnimated en la base de datos, intentar detectarlo desde el contenido
        if !decodedIsAnimated && decodedGifURL == nil {
            // Detectar si es un GIF basándose en el contenido o tipo
            let isGifFromContent = self.content.hasPrefix("http") && (self.content.contains(".gif") || self.content.contains("giphy"))
            let isGifFromType = self.type == "sticker" && self.content.hasPrefix("http")
            
            self.isAnimated = isGifFromContent || isGifFromType
            self.gifURL = isGifFromContent ? self.content : nil
            
        } else {
            self.isAnimated = decodedIsAnimated
            self.gifURL = decodedGifURL
        }
    }
    
    // ✅ FUNCIÓN HELPER: Crear desde StickerItem - ACTUALIZADA
    static func from(_ stickerItem: StickerItem) -> StickerData {
        let interactionData = stickerItem.interactionData
        
        let stickerData = StickerData(
            type: stickerItem.type.rawValue,
            content: extractContent(from: stickerItem),
            position: stickerItem.position,
            scale: stickerItem.scale,
            rotation: stickerItem.rotation.radians,
            username: interactionData?.username,
            userId: interactionData?.userId,
            hashtag: interactionData?.hashtag,
            location: interactionData?.location,
            latitude: interactionData?.locationCoordinate?.latitude,
            longitude: interactionData?.locationCoordinate?.longitude,
            questionText: interactionData?.questionText,
            pollOptions: interactionData?.pollData,
            weatherSymbol: interactionData?.weatherSymbol,
            isAnimated: stickerItem.isAnimated,
            gifURL: stickerItem.gifURL?.absoluteString
        )
        
        return stickerData
    }
    
    // ✅ FUNCIÓN extractContent ACTUALIZADA para incluir música
    private static func extractContent(from sticker: StickerItem) -> String {
        // Para stickers interactivos, usar los datos de interacción
        if let interactionData = sticker.interactionData {
            switch sticker.type {
            case .mention:
                return "@\(interactionData.username ?? "")"
            case .hashtag:
                return "#\(interactionData.hashtag ?? "")"
            case .location:
                return interactionData.location ?? ""
            case .question:
                return interactionData.questionText ?? ""
            case .poll:
                return interactionData.pollData?.joined(separator: "|") ?? ""
            case .weather:
                return interactionData.weatherSymbol ?? "🌤️"
            default:
                break
            }
        }
        
        // Para stickers animados, guardar la URL del GIF como contenido
        if sticker.isAnimated, let gifURL = sticker.gifURL {
            return gifURL.absoluteString
        }
        
        // Para otros tipos de stickers, usar un identificador basado en el tipo
        return "sticker_\(sticker.type.rawValue)"
    }
}

// MARK: - CodingKeys para StickerData
extension StickerData {
    enum CodingKeys: String, CodingKey {
        case type
        case content
        case position
        case positionX
        case positionY
        case scale
        case rotation
        case username
        case userId
        case hashtag
        case location
        case latitude
        case longitude
        case questionText
        case pollOptions
        case weatherSymbol
        case isAnimated
        case gifURL
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(type, forKey: .type)
        try container.encode(content, forKey: .content)
        try container.encode(position, forKey: .position)
        try container.encode(scale, forKey: .scale)
        try container.encode(rotation, forKey: .rotation)
        try container.encodeIfPresent(username, forKey: .username)
        try container.encodeIfPresent(userId, forKey: .userId)
        try container.encodeIfPresent(hashtag, forKey: .hashtag)
        try container.encodeIfPresent(location, forKey: .location)
        try container.encodeIfPresent(latitude, forKey: .latitude)
        try container.encodeIfPresent(longitude, forKey: .longitude)
        try container.encodeIfPresent(questionText, forKey: .questionText)
        try container.encodeIfPresent(pollOptions, forKey: .pollOptions)
        try container.encodeIfPresent(weatherSymbol, forKey: .weatherSymbol)
        try container.encode(isAnimated, forKey: .isAnimated)
        try container.encodeIfPresent(gifURL, forKey: .gifURL)
    }
}

// MARK: - Extensión para StickerItem.StickerType
extension StickerItem.StickerType {
    var rawValue: String {
        switch self {
        case .emoji: return "emoji"
        case .sticker: return "sticker"
        case .mention: return "mention"
        case .hashtag: return "hashtag"
        case .location: return "location"
        case .poll: return "poll"
        case .question: return "question"
        case .questionResponse: return "questionResponse"
        case .generic: return "generic"
        case .weather: return "weather"
        case .time: return "time"
        case .selfie: return "selfie"
        }
    }
    
    init?(rawValue: String) {
        switch rawValue {
        case "emoji": self = .emoji
        case "sticker": self = .sticker
        case "mention": self = .mention
        case "hashtag": self = .hashtag
        case "location": self = .location
        case "poll": self = .poll
        case "question": self = .question
        case "questionResponse": self = .questionResponse
        case "generic": self = .generic
        case "weather": self = .weather
        case "time": self = .time
        case "selfie": self = .selfie
        default: return nil
        }
    }
}

// MARK: - ================== MODELOS DE NOTIFICACIONES ACTUALIZADOS ==================

struct Notification: Identifiable, Codable {
    let id: String
    let type: NotificationType
    let senderId: String
    let senderUsername: String
    let timestamp: Date
    var isPending: Bool
    let momentId: String?
    let visitCount: Int?
    let storyId: String?
    let storyAuthorId: String?
    let reaction: String?
    let commentId: String? // ✅ NUEVO: Para identificar comentarios específicos
    
    enum CodingKeys: String, CodingKey {
        case id
        case type
        case senderId
        case senderUsername
        case timestamp
        case isPending
        case momentId
        case visitCount
        case storyId
        case storyAuthorId
        case reaction
        case commentId
    }

    init(id: String = UUID().uuidString,
         type: NotificationType,
         senderId: String,
         senderUsername: String,
         timestamp: Date = Date(),
         isPending: Bool = true,
         momentId: String? = nil,
         visitCount: Int? = nil,
         storyId: String? = nil,
         storyAuthorId: String? = nil,
         reaction: String? = nil,
         commentId: String? = nil) {
        self.id = id
        self.type = type
        self.senderId = senderId
        self.senderUsername = senderUsername
        self.timestamp = timestamp
        self.isPending = isPending
        self.momentId = momentId
        self.visitCount = visitCount
        self.storyId = storyId
        self.storyAuthorId = storyAuthorId
        self.reaction = reaction
        self.commentId = commentId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        let typeString = try container.decode(String.self, forKey: .type)
        self.type = NotificationType(rawValue: typeString) ?? .newFollower
        self.senderId = try container.decode(String.self, forKey: .senderId)
        self.senderUsername = try container.decode(String.self, forKey: .senderUsername)
        let timestamp = try container.decode(Timestamp.self, forKey: .timestamp)
        self.timestamp = timestamp.dateValue()
        self.isPending = try container.decode(Bool.self, forKey: .isPending)
        self.momentId = try container.decodeIfPresent(String.self, forKey: .momentId)
        self.visitCount = try container.decodeIfPresent(Int.self, forKey: .visitCount)
        self.storyId = try container.decodeIfPresent(String.self, forKey: .storyId)
        self.storyAuthorId = try container.decodeIfPresent(String.self, forKey: .storyAuthorId)
        self.reaction = try container.decodeIfPresent(String.self, forKey: .reaction)
        self.commentId = try container.decodeIfPresent(String.self, forKey: .commentId)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type.rawValue, forKey: .type)
        try container.encode(senderId, forKey: .senderId)
        try container.encode(senderUsername, forKey: .senderUsername)
        try container.encode(Timestamp(date: timestamp), forKey: .timestamp)
        try container.encode(isPending, forKey: .isPending)
        try container.encodeIfPresent(momentId, forKey: .momentId)
        try container.encodeIfPresent(visitCount, forKey: .visitCount)
        try container.encodeIfPresent(storyId, forKey: .storyId)
        try container.encodeIfPresent(storyAuthorId, forKey: .storyAuthorId)
        try container.encodeIfPresent(reaction, forKey: .reaction)
        try container.encodeIfPresent(commentId, forKey: .commentId)
    }
}

enum NotificationType: String, Codable, CaseIterable {
    case like = "like" // Para likes en comentarios
    case reaction = "reaction" // ✅ NUEVO: Para reacciones en momentos (vibe, fire, etc.)
    case comment = "comment"
    case mention = "mention" // ✅ NUEVO: Tipo general para menciones
    case newFollower = "newFollower"
    case followRequest = "followRequest" // NUEVO
    case mutualConnection = "mutualConnection"
    case profileVisit = "profileVisit"
    case storyReaction = "storyReaction"
    
    var displayName: String {
        switch self {
        case .like: return "Me gusta" // Para comentarios
        case .reaction: return "Reacción" // ✅ NUEVO: Para momentos
        case .comment: return "Comentario"
        case .mention: return "Menciones" // ✅ NUEVO
        case .newFollower: return "Nuevos seguidores"
        case .followRequest: return "Solicitudes de seguimiento" // NUEVO
        case .mutualConnection: return "Conexiones mutuas"
        case .profileVisit: return "Visitas al perfil"
        case .storyReaction: return "Reacción a historia"
        }
    }
    
    var systemIconName: String {
        switch self {
        case .like: return "heart.fill" // Para comentarios
        case .reaction: return "sparkles" // ✅ NUEVO: Para reacciones de momentos
        case .comment: return "bubble.right.fill"
        case .mention: return "at.circle.fill" // ✅ NUEVO: Icono @ para menciones
        case .newFollower: return "person.badge.plus"
        case .followRequest: return "person.crop.circle.badge.questionmark"
        case .mutualConnection: return "person.2.fill"
        case .profileVisit: return "eye.fill"
        case .storyReaction: return "face.smiling"
        }
    }
}

// MARK: - ================== MODELOS DE CHAT Y MENSAJERÍA ==================



// MARK: - Extensiones para CGPoint (para compatibilidad con Stickers)

extension CGPoint: Codable {
    enum CodingKeys: String, CodingKey {
        case x
        case y
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let x = try container.decode(CGFloat.self, forKey: .x)
        let y = try container.decode(CGFloat.self, forKey: .y)
        self.init(x: x, y: y)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(x, forKey: .x)
        try container.encode(y, forKey: .y)
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

extension Moment: ContentProtocol {
    var visibilityType: ContentVisibilityType {
        guard let audience = self.audience else { return .everyone }
        
        switch audience {
        case "everyone": return .everyone
        case "connections": return .connections
        case "bestFriends": return .bestFriends
        case "custom": return .custom
        default: return .everyone
        }
    }
    
    var customViewers: [String]? {
        // Si la audiencia es custom, obtener la lista desde Firestore
        // Por ahora retornar nil, pero esto necesita implementación
        return nil
    }
    
    var hiddenFrom: [String]? {
        // Lista de usuarios que no pueden ver este contenido
        // Se puede obtener de la configuración del usuario
        return nil
    }
}

// MARK: - Extensión de Story para implementar ContentProtocol
extension Story: ContentProtocol {
    var visibilityType: ContentVisibilityType {
        guard let audience = self.audience else { return .everyone }
        
        switch audience {
        case "everyone": return .everyone
        case "connections": return .connections
        case "bestFriends": return .bestFriends
        case "custom": return .custom
        default: return .everyone
        }
    }
    
    var customViewers: [String]? {
        return nil
    }
    
    var hiddenFrom: [String]? {
        return nil
    }
}

// MARK: - ================== MODELOS PARA STICKER QUESTIONS ==================

// MARK: - Modelo de Respuesta de Question
struct QuestionResponse: Codable, Identifiable {
    let id: String
    let userId: String          // Solo para el autor (no se muestra)
    let response: String        // Texto de la respuesta
    let timestamp: Date
    let isAnonymous: Bool       // Siempre true para privacidad
    
    enum CodingKeys: String, CodingKey {
        case id, userId, response, timestamp, isAnonymous
    }
    
    init(userId: String, response: String) {
        self.id = UUID().uuidString
        self.userId = userId
        self.response = response
        self.timestamp = Date()
        self.isAnonymous = true // Siempre true para privacidad
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.userId = try container.decode(String.self, forKey: .userId)
        self.response = try container.decode(String.self, forKey: .response)
        
        let timestampFirestore = try container.decode(Timestamp.self, forKey: .timestamp)
        self.timestamp = timestampFirestore.dateValue()
        
        self.isAnonymous = try container.decodeIfPresent(Bool.self, forKey: .isAnonymous) ?? true
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userId, forKey: .userId)
        try container.encode(response, forKey: .response)
        try container.encode(Timestamp(date: timestamp), forKey: .timestamp)
        try container.encode(isAnonymous, forKey: .isAnonymous)
    }
}

// MARK: - Modelo de Datos de Question
struct QuestionData: Codable {
    let questionText: String
    let responses: [QuestionResponse]
    let responseCount: Int
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case questionText, responses, responseCount, createdAt
    }
    
    init(questionText: String) {
        self.questionText = questionText
        self.responses = []
        self.responseCount = 0
        self.createdAt = Date()
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.questionText = try container.decode(String.self, forKey: .questionText)
        self.responses = try container.decode([QuestionResponse].self, forKey: .responses)
        self.responseCount = try container.decode(Int.self, forKey: .responseCount)
        
        let timestampFirestore = try container.decode(Timestamp.self, forKey: .createdAt)
        self.createdAt = timestampFirestore.dateValue()
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(questionText, forKey: .questionText)
        try container.encode(responses, forKey: .responses)
        try container.encode(responseCount, forKey: .responseCount)
        try container.encode(Timestamp(date: createdAt), forKey: .createdAt)
    }
}
