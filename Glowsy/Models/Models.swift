import Foundation
import FirebaseFirestore
import FirebaseAuth
import UIKit
import SwiftUI
import CoreLocation

// MARK: - Filter Models
struct FilterSettings: Codable {
    let name: String
    let intensity: Double
}

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
    @DocumentID var id: String? = nil
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
    var isPending: Bool? = false     // NUEVO CAMPO PARA OFFLINE

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
        case isPending               // NUEVO
    }

    init(id: String? = nil, authorId: String, username: String, content: String, timestamp: Date, profileImagePath: String? = nil, updatedAt: Date? = nil, reactions: [String: [String]] = [:], parentCommentId: String? = nil, isEdited: Bool? = nil, editedTimestamp: Date? = nil, isPending: Bool? = false) {
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
        self.isPending = isPending
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
// MARK: - Photo Tag for spatial tagging
struct PhotoTag: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    let userId: String
    let username: String
    let x: Double // 0.0 to 1.0 (relative to image width)
    let y: Double // 0.0 to 1.0 (relative to image height)
}

struct MediaItem: Identifiable, Codable {
    let id = UUID().uuidString
    let type: MediaType
    let url: String
    // 🔥 NUEVOS CAMPOS
    let thumbnailUrl: String?
    let videoDuration: Double?
    let videoFileSize: Int64?
    let videoResolution: String?
    let tags: [PhotoTag]? // ✅ Etiquetas espaciales para esta imagen

    enum MediaType: String, Codable {
        case image
        case video
    }
    
    // Init completo para imágenes/videos
    init(type: MediaType, url: String, thumbnailUrl: String? = nil, videoDuration: Double? = nil, videoFileSize: Int64? = nil, videoResolution: String? = nil, tags: [PhotoTag]? = nil) {
        self.type = type
        self.url = url
        self.thumbnailUrl = thumbnailUrl
        self.videoDuration = videoDuration
        self.videoFileSize = videoFileSize
        self.videoResolution = videoResolution
        self.tags = tags
    }
}

// ================== MODELO DE MOMENTO (CORREGIDO) ==================
struct Moment: Identifiable, Codable, Equatable {
    @DocumentID var id: String?
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
    let videoFileSize: Int64?        // Tamaño en bytes
    let videoResolution: String?     // "1080x1920", "1080x1080", etc.
    let scheduledDate: Date?         // ✅ NUEVO: Fecha programada
    
    // Helper properties for scheduling
    var isScheduled: Bool {
        guard let scheduledDate = scheduledDate else { return false }
        return scheduledDate > Date()
    }

    func scheduledTimeFormatted() -> String {
        guard let scheduledDate = scheduledDate else { return "" }
        let diff = scheduledDate.timeIntervalSince(Date())
        
        if diff <= 0 { return NSLocalizedString("moment.publishing", comment: "Publishing...") }
        
        let hours = Int(diff) / 3600
        let minutes = (Int(diff) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
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
        case scheduledDate
        case thumbnailUrl, videoDuration, videoFileSize, videoResolution
        case trendingScore, engagementRate
    }
    
    // ✅ MANUAL CODABLE: Necesario para que JSONEncoder no falle con @DocumentID
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // ✅ FIX: Manejar ID para Firestore (@DocumentID) y JSON (String)
        if let docID = try? container.decode(DocumentID<String>.self, forKey: .id) {
            self._id = docID
        } else {
            self.id = try container.decodeIfPresent(String.self, forKey: .id)
        }
        
        // Campos obligatorios con fallbacks seguros
        self.authorId = (try? container.decode(String.self, forKey: .authorId)) ?? ""
        self.username = (try? container.decode(String.self, forKey: .username)) ?? ""
        self.content = (try? container.decode(String.self, forKey: .content)) ?? ""
        self.imagePath = try container.decodeIfPresent(String.self, forKey: .imagePath)
        self.videoUrl = try container.decodeIfPresent(String.self, forKey: .videoUrl)
        
        // Manejo flexible de fechas (Firestore Timestamp o Double/Date)
        if let timestamp = try? container.decode(Timestamp.self, forKey: .timestamp) {
            self.timestamp = timestamp.dateValue()
        } else if let doubleValue = try? container.decode(Double.self, forKey: .timestamp) {
            self.timestamp = Date(timeIntervalSince1970: doubleValue)
        } else {
            self.timestamp = (try? container.decode(Date.self, forKey: .timestamp)) ?? Date()
        }
        
        self.reactions = (try? container.decode([String: [String]].self, forKey: .reactions)) ?? [:]
        self.commentCount = (try? container.decode(Int.self, forKey: .commentCount)) ?? 0
        self.profileImagePath = try container.decodeIfPresent(String.self, forKey: .profileImagePath)
        self.taggedUsers = try container.decodeIfPresent([String].self, forKey: .taggedUsers)
        self.location = try container.decodeIfPresent(String.self, forKey: .location)
        self.locationCoordinate = try container.decodeIfPresent(LocationCoordinate.self, forKey: .locationCoordinate)
        self.audience = try container.decodeIfPresent(String.self, forKey: .audience)
        self.mediaItems = try container.decodeIfPresent([MediaItem].self, forKey: .mediaItems)
        self.aspectRatio = try container.decodeIfPresent(String.self, forKey: .aspectRatio)
        self.customListId = try container.decodeIfPresent(String.self, forKey: .customListId)
        self.thumbnailUrl = try container.decodeIfPresent(String.self, forKey: .thumbnailUrl)
        self.videoDuration = try container.decodeIfPresent(Double.self, forKey: .videoDuration)
        self.videoFileSize = try container.decodeIfPresent(Int64.self, forKey: .videoFileSize)
        self.videoResolution = try container.decodeIfPresent(String.self, forKey: .videoResolution)
        
        if let scheduledTimestamp = try? container.decodeIfPresent(Timestamp.self, forKey: .scheduledDate) {
            self.scheduledDate = scheduledTimestamp.dateValue()
        } else {
            self.scheduledDate = try container.decodeIfPresent(Date.self, forKey: .scheduledDate)
        }
        
        self.disableComments = (try? container.decodeIfPresent(Bool.self, forKey: .disableComments)) ?? false
        self.hideLikeCounts = (try? container.decodeIfPresent(Bool.self, forKey: .hideLikeCounts)) ?? false
        self.allowSharing = (try? container.decodeIfPresent(Bool.self, forKey: .allowSharing)) ?? true
        self.trendingScore = try container.decodeIfPresent(Double.self, forKey: .trendingScore)
        self.engagementRate = try container.decodeIfPresent(Double.self, forKey: .engagementRate)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        // 🔥 CRUCIAL: Codificar el ID como String normal (evita error DocumentID con JSONEncoder)
        try container.encodeIfPresent(id, forKey: .id)
        
        try container.encode(authorId, forKey: .authorId)
        try container.encode(username, forKey: .username)
        try container.encode(content, forKey: .content)
        try container.encodeIfPresent(imagePath, forKey: .imagePath)
        try container.encodeIfPresent(videoUrl, forKey: .videoUrl)
        
        // Codificar fecha como Timestamp para compatibilidad con Firestore
        try container.encode(Timestamp(date: timestamp), forKey: .timestamp)
        
        try container.encode(reactions, forKey: .reactions)
        try container.encode(commentCount, forKey: .commentCount)
        try container.encodeIfPresent(profileImagePath, forKey: .profileImagePath)
        try container.encodeIfPresent(taggedUsers, forKey: .taggedUsers)
        try container.encodeIfPresent(location, forKey: .location)
        try container.encodeIfPresent(locationCoordinate, forKey: .locationCoordinate)
        try container.encodeIfPresent(audience, forKey: .audience)
        try container.encodeIfPresent(mediaItems, forKey: .mediaItems)
        try container.encodeIfPresent(aspectRatio, forKey: .aspectRatio)
        try container.encodeIfPresent(customListId, forKey: .customListId)
        try container.encodeIfPresent(thumbnailUrl, forKey: .thumbnailUrl)
        try container.encodeIfPresent(videoDuration, forKey: .videoDuration)
        try container.encodeIfPresent(videoFileSize, forKey: .videoFileSize)
        try container.encodeIfPresent(videoResolution, forKey: .videoResolution)
        
        if let scheduledDate = scheduledDate {
            try container.encode(Timestamp(date: scheduledDate), forKey: .scheduledDate)
        }
        
        try container.encode(disableComments, forKey: .disableComments)
        try container.encode(hideLikeCounts, forKey: .hideLikeCounts)
        try container.encode(allowSharing, forKey: .allowSharing)
        try container.encodeIfPresent(trendingScore, forKey: .trendingScore)
        try container.encodeIfPresent(engagementRate, forKey: .engagementRate)
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
        scheduledDate: Date? = nil,
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
        self.scheduledDate = scheduledDate // ✅ FIXED: Asignar fecha programada
        self.trendingScore = trendingScore
        self.engagementRate = engagementRate
    }
}

// MARK: - Moment Helpers
extension Moment {
    var scheduledRemainingText: String {
        guard let scheduledDate = scheduledDate else { return "" }
        let now = Date()
        guard scheduledDate > now else { return "" }
        
        let components = Calendar.current.dateComponents([.day, .hour, .minute], from: now, to: scheduledDate)
        
        if let days = components.day, days > 0 {
            let key = days == 1 ? "moment.scheduled.day" : "moment.scheduled.days"
            return String(format: NSLocalizedString(key, comment: "Scheduled in X days"), days)
        } else if let hours = components.hour, hours > 0 {
            let key = hours == 1 ? "moment.scheduled.hour" : "moment.scheduled.hours"
            return String(format: NSLocalizedString(key, comment: "Scheduled in X hours"), hours)
        } else if let minutes = components.minute, minutes > 0 {
            let key = minutes == 1 ? "moment.scheduled.minute" : "moment.scheduled.minutes"
            return String(format: NSLocalizedString(key, comment: "Scheduled in X minutes"), minutes)
        } else {
            return NSLocalizedString("moment.scheduled.soon", comment: "Scheduled soon")
        }
    }
}



// ================== MODELO DE HISTORIAS DESTACADAS ==================
struct HighlightedStory: Identifiable, Codable {
    @DocumentID var id: String?
    let title: String
    let coverImageUrl: String?
    let storiesCount: Int
    let createdAt: Date
    let storyIds: [String]
    let authorId: String
    
    enum CodingKeys: String, CodingKey {
        case id, title, coverImageUrl, storiesCount, createdAt, storyIds, authorId
    }
}

// ================== MODELO DE HISTORIA (CORREGIDO) ==================
struct Story: Identifiable, Codable {
    @DocumentID var id: String?
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
            let stickerImage: UIImage
            
            switch StickerItem.StickerType(rawValue: stickerData.type) {
            case .mention:
                // ✅ RECREAR STICKER DE MENCION con estilo nativo
                if let username = stickerData.username {
                    stickerImage = createMentionStickerImage(username: username)
                } else {
                    stickerImage = UIImage(systemName: "at.circle") ?? UIImage()
                }
            case .hashtag:
                // ✅ RECREAR STICKER DE HASHTAG
                if let hashtag = stickerData.hashtag {
                    stickerImage = createHashtagStickerImage(hashtag: hashtag)
                } else {
                    stickerImage = UIImage(systemName: "number") ?? UIImage()
                }
            case .location:
                // ✅ RECREAR STICKER DE UBICACIÓN
                if let location = stickerData.location {
                    stickerImage = createLocationStickerImage(location: location)
                } else {
                    stickerImage = UIImage(systemName: "location.circle") ?? UIImage()
                }
            case .question:
                // ✅ RECREAR STICKER DE PREGUNTA
                if let question = stickerData.questionText {
                    stickerImage = createQuestionStickerImage(question: question)
                } else {
                    stickerImage = UIImage(systemName: "questionmark.circle") ?? UIImage()
                }
            case .poll:
                // ✅ RECREAR STICKER DE ENCUESTA
                if let pollOptions = stickerData.pollOptions {
                    stickerImage = createPollStickerImage(pollOptions: pollOptions)
                } else {
                    stickerImage = UIImage(systemName: "chart.bar") ?? UIImage()
                }
            case .time, .weather, .emoji, .sticker, .generic, .selfie, .questionResponse, .shareMoment:
                // ✅ INTENTAR DECODIFICAR IMAGEN BASE64
                // Usar UIScreen.main.scale para restaurar el tamaño lógico (puntos) original
                if let data = Data(base64Encoded: stickerData.content),
                   let image = UIImage(data: data, scale: UIScreen.main.scale) {
                    stickerImage = image
                } else {
                    stickerImage = UIImage(systemName: "sticker") ?? UIImage()
                }
            default:
                stickerImage = UIImage(systemName: "sticker") ?? UIImage()
            }
            
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
                weatherSymbol: weatherSymbol,
                caption: stickerData.caption,
                profileImagePath: stickerData.profileImagePath,
                momentId: stickerData.momentId,
                mediaCount: stickerData.mediaCount
            )
            
            // Crear StickerItem con las transformaciones aplicadas
            var stickerItem: StickerItem
            
            // ✅ MANEJAR STICKERS ANIMADOS
            var gifURL: URL? = nil
            var videoURL: URL? = nil
            
            // 1. Intentar obtener la URL del GIF
            if let gifURLString = stickerData.gifURL, let url = URL(string: gifURLString) {
                gifURL = url
            } else if stickerData.isAnimated && stickerData.content.hasPrefix("http") && (stickerData.content.contains(".gif") || stickerData.content.contains("giphy")) {
                // Fallback for older stickers where URL was in content
                gifURL = URL(string: stickerData.content)
            }
            
            // 2. Intentar obtener la URL del Vídeo
            if let videoURLString = stickerData.videoURL, let url = URL(string: videoURLString) {
                videoURL = url
            }
            
            if stickerData.isAnimated {
                // Crear sticker animado con GIF o Video
                // ✅ FIX ID: No usar content (Base64) como ID, usar combo estable
                let stableId = "\(stickerData.type)_\(stickerData.position.x)_\(stickerData.position.y)"
                stickerItem = StickerItem(
                    id: stableId,
                    image: stickerImage,
                    position: stickerData.position,
                    scale: stickerData.scale,
                    rotation: Angle(radians: stickerData.rotation),
                    gifURL: gifURL,
                    videoURL: videoURL,
                    isAnimated: true,
                    type: StickerItem.StickerType(rawValue: stickerData.type) ?? .generic,
                    interactionData: interactionData
                )
            } else {
                // Crear sticker estático
                stickerItem = StickerItem(
                    image: stickerImage,
                    position: stickerData.position,
                    type: StickerItem.StickerType(rawValue: stickerData.type) ?? .generic,
                    interactionData: interactionData
                )
                stickerItem.scale = stickerData.scale
                stickerItem.rotation = Angle(radians: stickerData.rotation)
            }
            
            return stickerItem
        }
    }
    
    // ✅ FUNCIONES AUXILIARES para recrear imágenes de stickers
    private func createMentionStickerImage(username: String) -> UIImage {
        let text = "@\(username)"
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 18, weight: .semibold),
            .foregroundColor: UIColor.black
        ]
        
        let textSize = text.size(withAttributes: textAttributes)
        let padding: CGFloat = 12
        let width = textSize.width + (padding * 2)
        let height = textSize.height + (padding * 2)
        
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        return renderer.image { context in
            let rect = CGRect(x: 0, y: 0, width: width, height: height)
            
            // ✅ FONDO BLANCO
            let backgroundPath = UIBezierPath(roundedRect: rect, cornerRadius: height / 2)
            UIColor.white.setFill()
            backgroundPath.fill()
            
            // ✅ BORDE SUTIL
            UIColor.black.withAlphaComponent(0.1).setStroke()
            backgroundPath.lineWidth = 0.5
            backgroundPath.stroke()
            
            // ✅ TEXTO CENTRADO
            let textRect = CGRect(
                x: padding,
                y: padding,
                width: textSize.width,
                height: textSize.height
            )
            
            text.draw(in: textRect, withAttributes: textAttributes)
        }
    }
    
    private func createHashtagStickerImage(hashtag: String) -> UIImage {
        // Placeholder para hashtag
        return UIImage(systemName: "number") ?? UIImage()
    }
    
    private func createLocationStickerImage(location: String) -> UIImage {
        // Placeholder para ubicación
        return UIImage(systemName: "location.circle") ?? UIImage()
    }
    
    private func createQuestionStickerImage(question: String) -> UIImage {
        // Placeholder para pregunta
        return UIImage(systemName: "questionmark.circle") ?? UIImage()
    }
    
    private func createPollStickerImage(pollOptions: [String]) -> UIImage {
        // Placeholder para encuesta
        return UIImage(systemName: "chart.bar") ?? UIImage()
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
    let caption: String? // ✅ NUEVA: Para pie de foto en momentos compartidos
    let profileImagePath: String? // ✅ NUEVA: Ruta de imagen de perfil para reconstrucción
    let momentId: String? // ✅ NUEVA: Para navegación
    let mediaCount: Int? // ✅ NUEVA: Para indicador de galería
    
    // ✅ NUEVAS PROPIEDADES para animación
    let isAnimated: Bool
    let gifURL: String? // URL como String para Codable
    let videoURL: String? // ✅ NUEVA: URL del vídeo del sticker

    
    init(type: String, content: String, position: CGPoint, scale: CGFloat, rotation: Double,
         username: String? = nil, userId: String? = nil, hashtag: String? = nil,
         location: String? = nil, latitude: Double? = nil, longitude: Double? = nil, questionText: String? = nil, pollOptions: [String]? = nil, weatherSymbol: String? = nil, caption: String? = nil, profileImagePath: String? = nil, momentId: String? = nil, mediaCount: Int? = nil,
         isAnimated: Bool = false, gifURL: String? = nil, videoURL: String? = nil) {
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
        self.caption = caption
        self.profileImagePath = profileImagePath
        self.momentId = momentId
        self.mediaCount = mediaCount
        self.isAnimated = isAnimated
        self.gifURL = gifURL
        self.videoURL = videoURL
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
        self.caption = try container.decodeIfPresent(String.self, forKey: .caption)
        self.profileImagePath = try container.decodeIfPresent(String.self, forKey: .profileImagePath)
        self.momentId = try container.decodeIfPresent(String.self, forKey: .momentId)
        self.mediaCount = try container.decodeIfPresent(Int.self, forKey: .mediaCount)
        
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
            self.videoURL = nil
        } else {
            self.isAnimated = decodedIsAnimated
            self.gifURL = decodedGifURL
            self.videoURL = try container.decodeIfPresent(String.self, forKey: .videoURL)
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
            caption: stickerItem.interactionData?.caption,
            profileImagePath: stickerItem.interactionData?.profileImagePath,
            momentId: stickerItem.interactionData?.momentId,
            mediaCount: stickerItem.interactionData?.mediaCount,
            isAnimated: stickerItem.isAnimated,
            gifURL: stickerItem.gifURL?.absoluteString,
            videoURL: stickerItem.videoURL?.absoluteString
        )
        
        return stickerData
    }
    
    // ✅ FUNCIÓN extractContent ACTUALIZADA para incluir música y renderizar imágenes a Base64
    private static func extractContent(from sticker: StickerItem) -> String {
        // 1. PRIORIDAD: Shared Moments y otros que requieren Base64 para el template visual
        // Esto garantiza que el sticker se vea perfecto en el visor aunque no cargue el media aún
        if [.generic, .sticker, .emoji, .time, .selfie, .questionResponse, .shareMoment].contains(sticker.type) {
            if let jpegData = sticker.image.jpegData(compressionQuality: 0.6) {
                return jpegData.base64EncodedString()
            }
        }
        
        // 2. Stickers interactivos: Guardar metadatos en content por compatibilidad con versiones antiguas
        if let interactionData = sticker.interactionData {
            switch sticker.type {
            case .mention: return "@\(interactionData.username ?? "")"
            case .hashtag: return "#\(interactionData.hashtag ?? "")"
            case .location: return interactionData.location ?? ""
            case .question: return interactionData.questionText ?? ""
            case .poll: return interactionData.pollData?.joined(separator: "|") ?? ""
            case .weather: return interactionData.weatherSymbol ?? "🌤️"
            default: break
            }
        }
        
        // 3. Stickers animados (GIFs): Guardar URL como contenido principal si existe
        if sticker.isAnimated, let gifURL = sticker.gifURL {
            return gifURL.absoluteString
        }
        
        // 4. Fallback: Identificador basado en tipo
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
        case videoURL
        case caption
        case profileImagePath
        case momentId
        case mediaCount
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
        try container.encodeIfPresent(videoURL, forKey: .videoURL)
        try container.encodeIfPresent(caption, forKey: .caption)
        try container.encodeIfPresent(profileImagePath, forKey: .profileImagePath)
        try container.encodeIfPresent(momentId, forKey: .momentId)
        try container.encodeIfPresent(mediaCount, forKey: .mediaCount)
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
        case .shareMoment: return "shareMoment"
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
        case "shareMoment": self = .shareMoment
        case "selfie": self = .selfie
        default: return nil
        }
    }
}

// MARK: - ================== MODELOS DE NOTIFICACIONES ACTUALIZADOS ==================

struct Notification: Identifiable, Codable {
    @DocumentID var id: String?
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
    let echoId: String? // ✅ NUEVO: Para identificar el Echo sugerido
    
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
        case reactionType // ✅ COMPATIBILIDAD: El servidor usa este campo para momentos
        case commentText  // ✅ COMPATIBILIDAD: El servidor usa este campo para comentarios
        case commentId
        case echoId
    }

    init(id: String? = nil,
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
         commentId: String? = nil,
         echoId: String? = nil) {
        
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
        self.echoId = echoId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id)
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
        
        // ✅ MAPEO INTELIGENTE DE CONTENIDO
        // 1. Intentar campo 'reaction' (Stories y manual)
        // 2. Intentar campo 'reactionType' (Moment reactions de Cloud Functions)
        // 3. Intentar campo 'commentText' (Comentarios de Cloud Functions)
        if let reaction = try container.decodeIfPresent(String.self, forKey: .reaction) {
            self.reaction = reaction
        } else if let reactionType = try container.decodeIfPresent(String.self, forKey: .reactionType) {
            self.reaction = reactionType
        } else if let commentText = try container.decodeIfPresent(String.self, forKey: .commentText) {
            self.reaction = commentText
        } else {
            self.reaction = nil
        }
        
        self.commentId = try container.decodeIfPresent(String.self, forKey: .commentId)
        self.echoId = try container.decodeIfPresent(String.self, forKey: .echoId)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
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
        try container.encodeIfPresent(echoId, forKey: .echoId)
    }
}

enum NotificationType: String, Codable, CaseIterable {
    case like = "like" // Para likes en comentarios
    case reaction = "reaction" // ✅ NUEVO: Para reacciones en momentos (vibe, fire, etc.)
    case comment = "comment"
    case mention = "mention" // ✅ NUEVO: Tipo general para menciones
    case newFollower = "newFollower"
    case followRequest = "followRequest" // NUEVO
    case requestAccepted = "requestAccepted" // ✅ NUEVO: Solicitud aceptada
    case mutualConnection = "mutualConnection"
    case profileVisit = "profileVisit"
    case storyReaction = "storyReaction"
    case message = "message" // ✅ NUEVO: Para mensajes directos (DM)
    case photoTag = "photoTag" // ✅ NUEVO: Para etiquetas en fotos
    case echoSuggestion = "echoSuggestion" // 🌊 NUEVO: Sugerencia de Echo (Nova Spark)

    var displayName: String {
        switch self {
        case .like: return "Reacción" // Para comentarios
        case .reaction: return "Reacción" // ✅ NUEVO: Para momentos
        case .comment: return "Comentario"
        case .mention: return "Menciones" // ✅ NUEVO
        case .newFollower: return "Nuevos seguidores"
        case .followRequest: return "Solicitudes de seguimiento" // NUEVO
        case .requestAccepted: return "Solicitud aceptada" // ✅ NUEVO
        case .mutualConnection: return "Conexiones mutuas"
        case .profileVisit: return "Visitas al perfil"
        case .storyReaction: return "Reacción a historia"
        case .message: return "Mensajes"
        case .photoTag: return "Etiquetas en fotos"
        case .echoSuggestion: return "Sugerencia de Echo"
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
        case .requestAccepted: return "person.crop.circle.badge.checkmark" // ✅ NUEVO
        case .mutualConnection: return "person.2.fill"
        case .profileVisit: return "eye.fill"
        case .storyReaction: return "face.smiling"
        case .message: return "envelope.fill"
        case .photoTag: return "person.crop.rectangle"
        case .echoSuggestion: return "sparkles.rectangle.stack"
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
