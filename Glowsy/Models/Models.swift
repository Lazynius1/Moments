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
    enum ModerationState: String, Codable {
        case visible
        case hidden
    }

    let id: String
    let type: MediaType
    let url: String
    let aspectRatio: String?
    // 🔥 NUEVOS CAMPOS
    let thumbnailUrl: String?
    let videoDuration: Double?
    let videoFileSize: Int64?
    let videoResolution: String?
    let tags: [PhotoTag]? // ✅ Etiquetas espaciales para esta imagen
    let moderationState: ModerationState?
    let moderationReason: String?
    let moderationCategory: String?
    let moderationConfidence: String?
    let moderatedAt: Date?

    enum MediaType: String, Codable {
        case image
        case video
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case url
        case aspectRatio
        case thumbnailUrl
        case videoDuration
        case videoFileSize
        case videoResolution
        case tags
        case moderationState
        case moderationReason
        case moderationCategory
        case moderationConfidence
        case moderatedAt
    }

    var isHiddenByModeration: Bool {
        moderationState == .hidden
    }

    var resolvedAspectRatioValue: CGFloat? {
        if let aspectRatio,
           !aspectRatio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let normalizedAspectRatio = aspectRatio.trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = normalizedAspectRatio.split(separator: ":")
            if parts.count == 2,
               let width = Double(parts[0]),
               let height = Double(parts[1]),
               height > 0 {
                let exactRatio = CGFloat(width / height)
                if exactRatio.isFinite, exactRatio > 0 {
                    return exactRatio
                }
            }

            let canonicalRatio = CreatorMedia.AspectRatio(from: normalizedAspectRatio).value
            if canonicalRatio.isFinite, canonicalRatio > 0 {
                return canonicalRatio
            }
        }

        if let videoResolution,
           let separatorIndex = videoResolution.firstIndex(of: "x") {
            let widthString = videoResolution[..<separatorIndex]
            let heightString = videoResolution[videoResolution.index(after: separatorIndex)...]
            if let width = Double(widthString),
               let height = Double(heightString),
               height > 0 {
                let ratio = CGFloat(width / height)
                if ratio.isFinite, ratio > 0 {
                    return ratio
                }
            }
        }

        return nil
    }

    // Init completo para imágenes/videos
    init(
        id: String = UUID().uuidString,
        type: MediaType,
        url: String,
        aspectRatio: String? = nil,
        thumbnailUrl: String? = nil,
        videoDuration: Double? = nil,
        videoFileSize: Int64? = nil,
        videoResolution: String? = nil,
        tags: [PhotoTag]? = nil,
        moderationState: ModerationState? = nil,
        moderationReason: String? = nil,
        moderationCategory: String? = nil,
        moderationConfidence: String? = nil,
        moderatedAt: Date? = nil
    ) {
        self.id = id
        self.type = type
        self.url = url
        self.aspectRatio = aspectRatio
        self.thumbnailUrl = thumbnailUrl
        self.videoDuration = videoDuration
        self.videoFileSize = videoFileSize
        self.videoResolution = videoResolution
        self.tags = tags
        self.moderationState = moderationState
        self.moderationReason = moderationReason
        self.moderationCategory = moderationCategory
        self.moderationConfidence = moderationConfidence
        self.moderatedAt = moderatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        self.type = try container.decode(MediaType.self, forKey: .type)
        self.url = try container.decode(String.self, forKey: .url)
        self.aspectRatio = try container.decodeIfPresent(String.self, forKey: .aspectRatio)
        self.thumbnailUrl = try container.decodeIfPresent(String.self, forKey: .thumbnailUrl)
        self.videoDuration = try container.decodeIfPresent(Double.self, forKey: .videoDuration)
        self.videoFileSize = try container.decodeIfPresent(Int64.self, forKey: .videoFileSize)
        self.videoResolution = try container.decodeIfPresent(String.self, forKey: .videoResolution)
        self.tags = try container.decodeIfPresent([PhotoTag].self, forKey: .tags)
        self.moderationState = try container.decodeIfPresent(ModerationState.self, forKey: .moderationState)
        self.moderationReason = try container.decodeIfPresent(String.self, forKey: .moderationReason)
        self.moderationCategory = try container.decodeIfPresent(String.self, forKey: .moderationCategory)
        self.moderationConfidence = try container.decodeIfPresent(String.self, forKey: .moderationConfidence)
        if let moderatedAtDate = try container.decodeIfPresent(Date.self, forKey: .moderatedAt) {
            self.moderatedAt = moderatedAtDate
        } else if let moderatedAtMillis = try container.decodeIfPresent(Double.self, forKey: .moderatedAt) {
            self.moderatedAt = Date(timeIntervalSince1970: moderatedAtMillis / 1000)
        } else if let moderatedAtMillisInt = try container.decodeIfPresent(Int.self, forKey: .moderatedAt) {
            self.moderatedAt = Date(timeIntervalSince1970: Double(moderatedAtMillisInt) / 1000)
        } else {
            self.moderatedAt = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encode(url, forKey: .url)
        try container.encodeIfPresent(aspectRatio, forKey: .aspectRatio)
        try container.encodeIfPresent(thumbnailUrl, forKey: .thumbnailUrl)
        try container.encodeIfPresent(videoDuration, forKey: .videoDuration)
        try container.encodeIfPresent(videoFileSize, forKey: .videoFileSize)
        try container.encodeIfPresent(videoResolution, forKey: .videoResolution)
        try container.encodeIfPresent(tags, forKey: .tags)
        try container.encodeIfPresent(moderationState, forKey: .moderationState)
        try container.encodeIfPresent(moderationReason, forKey: .moderationReason)
        try container.encodeIfPresent(moderationCategory, forKey: .moderationCategory)
        try container.encodeIfPresent(moderationConfidence, forKey: .moderationConfidence)
        try container.encodeIfPresent(moderatedAt, forKey: .moderatedAt)
    }
}

// MARK: - Hidden Layers for Moments
struct MomentHiddenLayer: Identifiable, Codable, Equatable {
    let id: String
    let type: LayerType
    let anchorX: Double
    let anchorY: Double
    let width: Double
    let height: Double
    let shape: LayerShape
    let zIndex: Int
    let text: String?
    let mediaURL: String?
    let thumbnailURL: String?
    let duration: Double?
    let caption: String?
    let imageOffsetX: Double?
    let imageOffsetY: Double?
    let imageScale: Double?
    let imageFrameStyle: HiddenLayerImageFrameStyle?
    let textStyle: HiddenLayerTextStyle?
    let presentationStyle: HiddenLayerPresentationStyle
    let unlockMode: UnlockMode
    let unlockAt: Date?
    let authorTimezoneIdentifier: String?
    let discoverCount: Int?
    let uniqueDiscovererCount: Int?
    let lastDiscoveredAt: Date?
    let moderationState: ModerationState?
    let moderationReason: String?
    let moderationCategory: String?
    let moderatedAt: Date?
    let createdAt: Date

    enum LayerType: String, Codable, CaseIterable {
        case text
        case audio
        case image
    }

    enum LayerShape: String, Codable, CaseIterable {
        case circle
        case roundedRect
    }

    enum ModerationState: String, Codable {
        case visible
        case hidden
        case pending
    }

    enum UnlockMode: String, Codable, CaseIterable {
        case immediate
        case scheduled
    }

    init(
        id: String = UUID().uuidString,
        type: LayerType,
        anchorX: Double,
        anchorY: Double,
        width: Double,
        height: Double,
        shape: LayerShape = .roundedRect,
        zIndex: Int = 0,
        text: String? = nil,
        mediaURL: String? = nil,
        thumbnailURL: String? = nil,
        duration: Double? = nil,
        caption: String? = nil,
        imageOffsetX: Double? = nil,
        imageOffsetY: Double? = nil,
        imageScale: Double? = nil,
        imageFrameStyle: HiddenLayerImageFrameStyle? = nil,
        textStyle: HiddenLayerTextStyle? = nil,
        presentationStyle: HiddenLayerPresentationStyle = .glassCard,
        unlockMode: UnlockMode = .immediate,
        unlockAt: Date? = nil,
        authorTimezoneIdentifier: String? = nil,
        discoverCount: Int? = nil,
        uniqueDiscovererCount: Int? = nil,
        lastDiscoveredAt: Date? = nil,
        moderationState: ModerationState? = .visible,
        moderationReason: String? = nil,
        moderationCategory: String? = nil,
        moderatedAt: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.anchorX = anchorX
        self.anchorY = anchorY
        self.width = width
        self.height = height
        self.shape = shape
        self.zIndex = zIndex
        self.text = text
        self.mediaURL = mediaURL
        self.thumbnailURL = thumbnailURL
        self.duration = duration
        self.caption = caption
        self.imageOffsetX = imageOffsetX
        self.imageOffsetY = imageOffsetY
        self.imageScale = imageScale
        self.imageFrameStyle = imageFrameStyle
        self.textStyle = textStyle
        self.presentationStyle = presentationStyle
        self.unlockMode = unlockMode
        self.unlockAt = unlockAt
        self.authorTimezoneIdentifier = authorTimezoneIdentifier
        self.discoverCount = discoverCount
        self.uniqueDiscovererCount = uniqueDiscovererCount
        self.lastDiscoveredAt = lastDiscoveredAt
        self.moderationState = moderationState
        self.moderationReason = moderationReason
        self.moderationCategory = moderationCategory
        self.moderatedAt = moderatedAt
        self.createdAt = createdAt
    }

    var isHiddenByModeration: Bool {
        moderationState == .hidden
    }

    var isVisibleInViewer: Bool {
        switch moderationState ?? .visible {
        case .visible:
            return true
        case .hidden, .pending:
            return false
        }
    }

    func isUnlocked(at date: Date = Date()) -> Bool {
        switch unlockMode {
        case .immediate:
            return true
        case .scheduled:
            guard let unlockAt else { return true }
            return unlockAt <= date
        }
    }
}

struct HiddenLayerDiscovery: Identifiable, Codable, Equatable {
    let viewerId: String
    let username: String?
    let profileImagePath: String?
    let discoveredAt: Date

    var id: String { viewerId }
}

struct HiddenLayerMetricsSnapshot {
    let layers: [MomentHiddenLayer]
    let uniquePeopleCount: Int
    let recentDiscoveriesByLayer: [String: [HiddenLayerDiscovery]]

    var totalDiscoveries: Int {
        layers.reduce(0) { $0 + max(0, $1.discoverCount ?? 0) }
    }

    var discoveredLayerCount: Int {
        layers.filter { ($0.discoverCount ?? 0) > 0 }.count
    }

    var totalLayerCount: Int {
        layers.count
    }

    var coverageRatio: Double {
        guard totalLayerCount > 0 else { return 0 }
        return Double(discoveredLayerCount) / Double(totalLayerCount)
    }

    var topLayer: MomentHiddenLayer? {
        layers.max {
            let lhsCount = $0.discoverCount ?? 0
            let rhsCount = $1.discoverCount ?? 0
            if lhsCount == rhsCount {
                return ($0.lastDiscoveredAt ?? .distantPast) < ($1.lastDiscoveredAt ?? .distantPast)
            }
            return lhsCount < rhsCount
        }
    }
}

enum HiddenLayerTextStyle: String, Codable, CaseIterable, Equatable {
    case clean
    case serif
    case handwritten
    case mono
    case bubble
    case editorial
}

enum HiddenLayerPresentationStyle: String, Codable, CaseIterable, Equatable {
    case glassCard
    case captionPill
    case paperNote
    case markerLabel
    case floatingQuote
    case minimalText
}

enum HiddenLayerImageFrameStyle: String, Codable, CaseIterable, Equatable {
    case classic
    case clean
    case vintage
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
    let isArchived: Bool?             // ✅ NUEVO: Momento archivado
    let archivedAt: Date?             // ✅ NUEVO: Fecha de archivo
    let hasHiddenLayers: Bool
    let hiddenLayerCount: Int
    let isModerationHidden: Bool?
    let originalAudience: String?
    let reviewRequired: Bool?
    let canRestore: Bool?
    // Helper properties for scheduling
    var isScheduled: Bool {
        guard let scheduledDate = scheduledDate else { return false }
        return scheduledDate > Date()
    }

    var visibleMediaItems: [MediaItem] {
        (mediaItems ?? []).filter { item in
            !item.isHiddenByModeration && !item.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var shouldUseLegacyMediaFallback: Bool {
        mediaItems == nil
    }

    var primaryVisibleMediaItem: MediaItem? {
        visibleMediaItems.first
    }

    var previewImageURLString: String? {
        if let primaryVisibleMediaItem {
            switch primaryVisibleMediaItem.type {
            case .image:
                let url = primaryVisibleMediaItem.url.trimmingCharacters(in: .whitespacesAndNewlines)
                return url.isEmpty ? nil : url
            case .video:
                if let thumbnailUrl = primaryVisibleMediaItem.thumbnailUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !thumbnailUrl.isEmpty {
                    return thumbnailUrl
                }
                let url = primaryVisibleMediaItem.url.trimmingCharacters(in: .whitespacesAndNewlines)
                return url.isEmpty ? nil : url
            }
        }

        guard shouldUseLegacyMediaFallback else { return nil }

        if let thumbnailUrl = thumbnailUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !thumbnailUrl.isEmpty {
            return thumbnailUrl
        }
        if let imagePath = imagePath?.trimmingCharacters(in: .whitespacesAndNewlines), !imagePath.isEmpty {
            return imagePath
        }
        return nil
    }

    var previewVideoURLString: String? {
        if let primaryVisibleMediaItem, primaryVisibleMediaItem.type == .video {
            let url = primaryVisibleMediaItem.url.trimmingCharacters(in: .whitespacesAndNewlines)
            return url.isEmpty ? nil : url
        }

        guard shouldUseLegacyMediaFallback else { return nil }

        if let videoUrl = videoUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !videoUrl.isEmpty {
            return videoUrl
        }
        return nil
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
        case isArchived, archivedAt
        case thumbnailUrl, videoDuration, videoFileSize, videoResolution
        case trendingScore, engagementRate
        case hasHiddenLayers, hiddenLayerCount
        case isModerationHidden, originalAudience, reviewRequired, canRestore
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

        self.isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived)
        if let archivedTimestamp = try? container.decodeIfPresent(Timestamp.self, forKey: .archivedAt) {
            self.archivedAt = archivedTimestamp.dateValue()
        } else {
            self.archivedAt = try container.decodeIfPresent(Date.self, forKey: .archivedAt)
        }

        self.disableComments = (try? container.decodeIfPresent(Bool.self, forKey: .disableComments)) ?? false
        self.hideLikeCounts = (try? container.decodeIfPresent(Bool.self, forKey: .hideLikeCounts)) ?? false
        self.allowSharing = (try? container.decodeIfPresent(Bool.self, forKey: .allowSharing)) ?? true
        self.trendingScore = try container.decodeIfPresent(Double.self, forKey: .trendingScore)
        self.engagementRate = try container.decodeIfPresent(Double.self, forKey: .engagementRate)
        self.hasHiddenLayers = (try? container.decodeIfPresent(Bool.self, forKey: .hasHiddenLayers)) ?? false
        self.hiddenLayerCount = (try? container.decodeIfPresent(Int.self, forKey: .hiddenLayerCount)) ?? 0
        self.isModerationHidden = try container.decodeIfPresent(Bool.self, forKey: .isModerationHidden)
        self.originalAudience = try container.decodeIfPresent(String.self, forKey: .originalAudience)
        self.reviewRequired = try container.decodeIfPresent(Bool.self, forKey: .reviewRequired)
        self.canRestore = try container.decodeIfPresent(Bool.self, forKey: .canRestore)
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
        if let archivedAt = archivedAt {
            try container.encode(Timestamp(date: archivedAt), forKey: .archivedAt)
        }
        try container.encodeIfPresent(isArchived, forKey: .isArchived)

        try container.encode(disableComments, forKey: .disableComments)
        try container.encode(hideLikeCounts, forKey: .hideLikeCounts)
        try container.encode(allowSharing, forKey: .allowSharing)
        try container.encodeIfPresent(trendingScore, forKey: .trendingScore)
        try container.encodeIfPresent(engagementRate, forKey: .engagementRate)
        try container.encode(hasHiddenLayers, forKey: .hasHiddenLayers)
        try container.encode(hiddenLayerCount, forKey: .hiddenLayerCount)
        try container.encodeIfPresent(isModerationHidden, forKey: .isModerationHidden)
        try container.encodeIfPresent(originalAudience, forKey: .originalAudience)
        try container.encodeIfPresent(reviewRequired, forKey: .reviewRequired)
        try container.encodeIfPresent(canRestore, forKey: .canRestore)
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
        engagementRate: Double? = nil,
        isArchived: Bool? = nil,
        archivedAt: Date? = nil,
        hasHiddenLayers: Bool = false,
        hiddenLayerCount: Int = 0,
        isModerationHidden: Bool? = nil,
        originalAudience: String? = nil,
        reviewRequired: Bool? = nil,
        canRestore: Bool? = nil
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
        self.isArchived = isArchived
        self.archivedAt = archivedAt
        self.hasHiddenLayers = hasHiddenLayers
        self.hiddenLayerCount = hiddenLayerCount
        self.isModerationHidden = isModerationHidden
        self.originalAudience = originalAudience
        self.reviewRequired = reviewRequired
        self.canRestore = canRestore
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
            if stickerData.moderationState == "hidden" {
                return nil
            }

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
            case .link:
                if let linkURL = stickerData.linkURL {
                    stickerImage = createLinkStickerImage(
                        title: stickerData.linkTitle ?? stickerHostLabel(from: linkURL)
                    )
                } else {
                    stickerImage = UIImage(systemName: "link") ?? UIImage()
                }
            case .countdown:
                if let title = stickerData.countdownTitle,
                   let targetAtMs = stickerData.countdownTargetAtMs {
                    stickerImage = createCountdownStickerImage(title: title, targetAtMs: targetAtMs)
                } else {
                    stickerImage = UIImage(systemName: "timer") ?? UIImage()
                }
            case .emojiSlider:
                stickerImage = createEmojiSliderStickerImage(
                    prompt: stickerData.sliderPrompt ?? "",
                    emoji: stickerData.sliderEmoji ?? "😍"
                )
            case .poll:
                // ✅ RECREAR STICKER DE ENCUESTA
                if let pollOptions = stickerData.pollOptions {
                    stickerImage = createPollStickerImage(pollOptions: pollOptions)
                } else {
                    stickerImage = UIImage(systemName: "chart.bar") ?? UIImage()
                }
            case .time, .weather, .emoji, .sticker, .generic, .selfie, .questionResponse, .shareMoment, .frame, .quiz:
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
                linkURL: stickerData.linkURL,
                linkTitle: stickerData.linkTitle,
                countdownTitle: stickerData.countdownTitle,
                countdownTargetAtMs: stickerData.countdownTargetAtMs,
                sliderEmoji: stickerData.sliderEmoji,
                sliderPrompt: stickerData.sliderPrompt,
                caption: stickerData.caption,
                profileImagePath: stickerData.profileImagePath,
                momentId: stickerData.momentId,
                mediaCount: stickerData.mediaCount,
                quizQuestion: stickerData.quizQuestion,
                quizOptions: stickerData.quizOptions,
                quizCorrectIndex: stickerData.quizCorrectIndex,
                revealType: stickerData.revealType,
                revealPattern: stickerData.revealPattern,
                revealPrimaryColor: stickerData.revealPrimaryColor,
                revealSecondaryColor: stickerData.revealSecondaryColor,
                frameStyle: stickerData.frameStyle,
                contentScale: stickerData.contentScale,
                contentOffsetX: stickerData.contentOffsetX,
                contentOffsetY: stickerData.contentOffsetY,
                audioURL: stickerData.audioURL,
                audioDuration: stickerData.audioDuration
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
                let stableId = stickerData.stickerId ?? "\(stickerData.type)_\(stickerData.position.x)_\(stickerData.position.y)"
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
                let stableId = stickerData.stickerId ?? "\(stickerData.type)_\(stickerData.position.x)_\(stickerData.position.y)"
                stickerItem = StickerItem(
                    id: stableId,
                    image: stickerImage,
                    position: stickerData.position,
                    scale: stickerData.scale,
                    rotation: Angle(radians: stickerData.rotation),
                    gifURL: nil,
                    videoURL: nil,
                    isAnimated: false,
                    type: StickerItem.StickerType(rawValue: stickerData.type) ?? .generic,
                    interactionData: interactionData
                )
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

    private func createLinkStickerImage(title: String) -> UIImage {
        let resolvedSize = linkStickerRenderingSize(for: title)
        let size = CGSize(width: resolvedSize.width, height: resolvedSize.height)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let rect = CGRect(origin: .zero, size: size)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: size.height / 2)

            UIColor.white.withAlphaComponent(0.18).setFill()
            path.fill()

            UIColor.white.withAlphaComponent(0.18).setStroke()
            path.lineWidth = 1
            path.stroke()

            let textAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 16, weight: .semibold),
                .foregroundColor: UIColor.white
            ]
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineBreakMode = .byTruncatingTail

            let titleText = title.trimmingCharacters(in: .whitespacesAndNewlines)

            if let linkIcon = UIImage(systemName: "link")?.withTintColor(UIColor(red: 0.29, green: 0.72, blue: 0.98, alpha: 1), renderingMode: .alwaysOriginal) {
                linkIcon.draw(in: CGRect(x: 18, y: 16, width: 18, height: 18))
            }
            (titleText as NSString).draw(
                in: CGRect(x: 48, y: 14, width: size.width - 66, height: 20),
                withAttributes: textAttributes.merging([.paragraphStyle: paragraphStyle]) { _, new in new }
            )
        }
    }

    private func createCountdownStickerImage(title: String, targetAtMs: Double) -> UIImage {
        let size = CGSize(width: 240, height: 96)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let rect = CGRect(origin: .zero, size: size)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 20)

            let colors = [
                UIColor(red: 0.32, green: 0.24, blue: 0.92, alpha: 0.86).cgColor,
                UIColor(red: 0.86, green: 0.28, blue: 0.73, alpha: 0.92).cgColor
            ] as CFArray

            context.cgContext.saveGState()
            path.addClip()
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                context.cgContext.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: size.width, y: size.height), options: [])
            }
            context.cgContext.restoreGState()

            UIColor.white.withAlphaComponent(0.18).setStroke()
            path.lineWidth = 1
            path.stroke()

            let targetDate = Date(timeIntervalSince1970: targetAtMs / 1000)
            let now = Date()
            let totalSeconds = max(Int(targetDate.timeIntervalSince(now)), 0)
            let hours = totalSeconds / 3_600
            let minutes = (totalSeconds % 3_600) / 60
            let seconds = totalSeconds % 60
            let remainingText = String(format: "%02d:%02d:%02d", hours, minutes, seconds)

            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 15, weight: .semibold),
                .foregroundColor: UIColor.white
            ]
            let digitAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 22, weight: .bold),
                .foregroundColor: UIColor.white
            ]
            let colonAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 22, weight: .bold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.92)
            ]
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineBreakMode = .byTruncatingTail
            paragraphStyle.alignment = .center
            let titleText = (title as NSString).substring(to: min(title.count, 26))

            (titleText as NSString).draw(
                in: CGRect(x: 20, y: 14, width: 200, height: 18),
                withAttributes: titleAttributes.merging([.paragraphStyle: paragraphStyle]) { _, new in new }
            )

            let boxSize = CGSize(width: 26, height: 32)
            let digitSpacing: CGFloat = 4
            let colonWidth: CGFloat = 10
            let sequence = remainingText.map(String.init)

            var totalWidth: CGFloat = 0
            for character in sequence {
                totalWidth += character == ":" ? colonWidth : boxSize.width
            }
            totalWidth += CGFloat(max(0, sequence.count - 1)) * digitSpacing

            var currentX = (size.width - totalWidth) / 2
            let rowY: CGFloat = 44

            for character in sequence {
                if character == ":" {
                    (character as NSString).draw(
                        in: CGRect(x: currentX, y: rowY + 3, width: colonWidth, height: boxSize.height),
                        withAttributes: colonAttributes.merging([.paragraphStyle: paragraphStyle]) { _, new in new }
                    )
                    currentX += colonWidth + digitSpacing
                } else {
                    let boxRect = CGRect(x: currentX, y: rowY, width: boxSize.width, height: boxSize.height)
                    let boxPath = UIBezierPath(roundedRect: boxRect, cornerRadius: 8)
                    UIColor.white.withAlphaComponent(0.18).setFill()
                    boxPath.fill()
                    UIColor.white.withAlphaComponent(0.2).setStroke()
                    boxPath.lineWidth = 1
                    boxPath.stroke()

                    (character as NSString).draw(
                        in: CGRect(x: boxRect.minX, y: boxRect.minY + 3, width: boxRect.width, height: 24),
                        withAttributes: digitAttributes.merging([.paragraphStyle: paragraphStyle]) { _, new in new }
                    )
                    currentX += boxSize.width + digitSpacing
                }
            }
        }
    }

    private func createEmojiSliderStickerImage(prompt: String, emoji: String) -> UIImage {
        createEmojiSliderFallbackImage(prompt: prompt, emoji: emoji, value: 0.5)
    }

}

// Modelo para almacenar datos de stickers
struct StickerData: Codable {
    let stickerId: String?
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
    let linkURL: String?
    let linkTitle: String?
    let countdownTitle: String?
    let countdownTargetAtMs: Double?
    let sliderEmoji: String?
    let sliderPrompt: String?
    let caption: String? // ✅ NUEVA: Para pie de foto en momentos compartidos
    let profileImagePath: String? // ✅ NUEVA: Ruta de imagen de perfil para reconstrucción
    let momentId: String? // ✅ NUEVA: Para navegación
    let mediaCount: Int? // ✅ NUEVA: Para indicador de galería
    let quizQuestion: String?
    let quizOptions: [String]?
    let quizCorrectIndex: Int?
    let revealType: String?
    let revealPattern: String?
    let revealPrimaryColor: String?
    let revealSecondaryColor: String?
    let frameStyle: String?
    let contentScale: CGFloat?
    let contentOffsetX: CGFloat?
    let contentOffsetY: CGFloat?
    let moderationState: String?
    let moderationReason: String?
    let moderationCategory: String?

    // Audio Data
    let audioURL: String?
    let audioDuration: Double?

    // ✅ NUEVAS PROPIEDADES para animación
    let isAnimated: Bool
    let gifURL: String? // URL como String para Codable
    let videoURL: String? // ✅ NUEVA: URL del vídeo del sticker


    init(stickerId: String? = nil, type: String, content: String, position: CGPoint, scale: CGFloat, rotation: Double,
         username: String? = nil, userId: String? = nil, hashtag: String? = nil,
         location: String? = nil, latitude: Double? = nil, longitude: Double? = nil, questionText: String? = nil, pollOptions: [String]? = nil, weatherSymbol: String? = nil, linkURL: String? = nil, linkTitle: String? = nil, countdownTitle: String? = nil, countdownTargetAtMs: Double? = nil, sliderEmoji: String? = nil, sliderPrompt: String? = nil, caption: String? = nil, profileImagePath: String? = nil, momentId: String? = nil, mediaCount: Int? = nil,
         quizQuestion: String? = nil, quizOptions: [String]? = nil, quizCorrectIndex: Int? = nil,
         revealType: String? = nil, revealPattern: String? = nil, revealPrimaryColor: String? = nil, revealSecondaryColor: String? = nil,
         frameStyle: String? = nil,
         contentScale: CGFloat? = nil, contentOffsetX: CGFloat? = nil, contentOffsetY: CGFloat? = nil,
         moderationState: String? = nil, moderationReason: String? = nil, moderationCategory: String? = nil,
         audioURL: String? = nil, audioDuration: Double? = nil,
         isAnimated: Bool = false, gifURL: String? = nil, videoURL: String? = nil) {
        self.stickerId = stickerId
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
        self.linkURL = linkURL
        self.linkTitle = linkTitle
        self.countdownTitle = countdownTitle
        self.countdownTargetAtMs = countdownTargetAtMs
        self.sliderEmoji = sliderEmoji
        self.sliderPrompt = sliderPrompt
        self.caption = caption
        self.profileImagePath = profileImagePath
        self.momentId = momentId
        self.mediaCount = mediaCount
        self.quizQuestion = quizQuestion
        self.quizOptions = quizOptions
        self.quizCorrectIndex = quizCorrectIndex
        self.revealType = revealType
        self.revealPattern = revealPattern
        self.revealPrimaryColor = revealPrimaryColor
        self.revealSecondaryColor = revealSecondaryColor
        self.frameStyle = frameStyle
        self.contentScale = contentScale
        self.contentOffsetX = contentOffsetX
        self.contentOffsetY = contentOffsetY
        self.moderationState = moderationState
        self.moderationReason = moderationReason
        self.moderationCategory = moderationCategory
        self.audioURL = audioURL
        self.audioDuration = audioDuration
        self.isAnimated = isAnimated
        self.gifURL = gifURL
        self.videoURL = videoURL
    }

    // ✅ INICIALIZADOR PERSONALIZADO para compatibilidad hacia atrás
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.stickerId = try container.decodeIfPresent(String.self, forKey: .stickerId)
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
        self.linkURL = try container.decodeIfPresent(String.self, forKey: .linkURL)
        self.linkTitle = try container.decodeIfPresent(String.self, forKey: .linkTitle)
        self.countdownTitle = try container.decodeIfPresent(String.self, forKey: .countdownTitle)
        self.countdownTargetAtMs = try container.decodeIfPresent(Double.self, forKey: .countdownTargetAtMs)
        self.sliderEmoji = try container.decodeIfPresent(String.self, forKey: .sliderEmoji)
        self.sliderPrompt = try container.decodeIfPresent(String.self, forKey: .sliderPrompt)
        self.caption = try container.decodeIfPresent(String.self, forKey: .caption)
        self.profileImagePath = try container.decodeIfPresent(String.self, forKey: .profileImagePath)
        self.momentId = try container.decodeIfPresent(String.self, forKey: .momentId)
        self.mediaCount = try container.decodeIfPresent(Int.self, forKey: .mediaCount)
        self.quizQuestion = try container.decodeIfPresent(String.self, forKey: .quizQuestion)
        self.quizOptions = try container.decodeIfPresent([String].self, forKey: .quizOptions)
        self.quizCorrectIndex = try container.decodeIfPresent(Int.self, forKey: .quizCorrectIndex)
        self.revealType = try container.decodeIfPresent(String.self, forKey: .revealType)
        self.revealPattern = try container.decodeIfPresent(String.self, forKey: .revealPattern)
        self.revealPrimaryColor = try container.decodeIfPresent(String.self, forKey: .revealPrimaryColor)
        self.revealSecondaryColor = try container.decodeIfPresent(String.self, forKey: .revealSecondaryColor)
        self.frameStyle = try container.decodeIfPresent(String.self, forKey: .frameStyle)
        self.contentScale = try container.decodeIfPresent(CGFloat.self, forKey: .contentScale)
        self.contentOffsetX = try container.decodeIfPresent(CGFloat.self, forKey: .contentOffsetX)
        self.contentOffsetY = try container.decodeIfPresent(CGFloat.self, forKey: .contentOffsetY)
        self.moderationState = try container.decodeIfPresent(String.self, forKey: .moderationState)
        self.moderationReason = try container.decodeIfPresent(String.self, forKey: .moderationReason)
        self.moderationCategory = try container.decodeIfPresent(String.self, forKey: .moderationCategory)
        self.audioURL = try container.decodeIfPresent(String.self, forKey: .audioURL)
        self.audioDuration = try container.decodeIfPresent(Double.self, forKey: .audioDuration)

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
            stickerId: stickerItem.id,
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
            linkURL: interactionData?.linkURL,
            linkTitle: interactionData?.linkTitle,
            countdownTitle: interactionData?.countdownTitle,
            countdownTargetAtMs: interactionData?.countdownTargetAtMs,
            sliderEmoji: interactionData?.sliderEmoji,
            sliderPrompt: interactionData?.sliderPrompt,
            caption: stickerItem.interactionData?.caption,
            profileImagePath: stickerItem.interactionData?.profileImagePath,
            momentId: stickerItem.interactionData?.momentId,
            mediaCount: stickerItem.interactionData?.mediaCount,
            quizQuestion: stickerItem.interactionData?.quizQuestion,
            quizOptions: stickerItem.interactionData?.quizOptions,
            quizCorrectIndex: stickerItem.interactionData?.quizCorrectIndex,
            revealType: stickerItem.interactionData?.revealType,
            revealPattern: stickerItem.interactionData?.revealPattern,
            revealPrimaryColor: stickerItem.interactionData?.revealPrimaryColor,
            revealSecondaryColor: stickerItem.interactionData?.revealSecondaryColor,
            frameStyle: stickerItem.interactionData?.frameStyle,
            contentScale: stickerItem.interactionData?.contentScale,
            contentOffsetX: stickerItem.interactionData?.contentOffsetX,
            contentOffsetY: stickerItem.interactionData?.contentOffsetY,
            moderationState: nil,
            moderationReason: nil,
            moderationCategory: nil,
            audioURL: interactionData?.audioURL,
            audioDuration: interactionData?.audioDuration,
            isAnimated: stickerItem.isAnimated,
            gifURL: stickerItem.gifURL?.absoluteString,
            videoURL: stickerItem.videoURL?.absoluteString
        )

        return stickerData
    }

    // ✅ FUNCIÓN extractContent ACTUALIZADA para incluir música y renderizar imágenes a Base64
    private static func extractContent(from sticker: StickerItem) -> String {
        // Selfie stickers need alpha channel to avoid black corners after upload/render.
        if sticker.type == .selfie, let pngData = sticker.image.pngData() {
            return pngData.base64EncodedString()
        }

        // 1. PRIORIDAD: Shared Moments y otros que requieren Base64 para el template visual
        // Esto garantiza que el sticker se vea perfecto en el visor aunque no cargue el media aún
        if sticker.type == .frame {
            let resizedImage = sticker.image.resized(toMaxDimension: 900).normalized()
            if let jpegData = resizedImage.jpegData(compressionQuality: 0.42) {
                return jpegData.base64EncodedString()
            }
        }

        if [.generic, .sticker, .emoji, .time, .selfie, .questionResponse, .shareMoment, .link, .countdown, .emojiSlider, .frame, .quiz].contains(sticker.type) {
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
            case .link: return interactionData.linkURL ?? ""
            case .countdown: return interactionData.countdownTitle ?? ""
            case .emojiSlider: return interactionData.sliderPrompt ?? ""
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
        case stickerId
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
        case linkURL
        case linkTitle
        case countdownTitle
        case countdownTargetAtMs
        case sliderEmoji
        case sliderPrompt
        case isAnimated
        case gifURL
        case videoURL
        case caption
        case profileImagePath
        case momentId
        case mediaCount
        case quizQuestion
        case quizOptions
        case quizCorrectIndex
        case revealType
        case revealPattern
        case revealPrimaryColor
        case revealSecondaryColor
        case frameStyle
        case contentScale
        case contentOffsetX
        case contentOffsetY
        case moderationState
        case moderationReason
        case moderationCategory
        case audioURL
        case audioDuration
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encodeIfPresent(stickerId, forKey: .stickerId)
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
        try container.encodeIfPresent(linkURL, forKey: .linkURL)
        try container.encodeIfPresent(linkTitle, forKey: .linkTitle)
        try container.encodeIfPresent(countdownTitle, forKey: .countdownTitle)
        try container.encodeIfPresent(countdownTargetAtMs, forKey: .countdownTargetAtMs)
        try container.encodeIfPresent(sliderEmoji, forKey: .sliderEmoji)
        try container.encodeIfPresent(sliderPrompt, forKey: .sliderPrompt)
        try container.encode(isAnimated, forKey: .isAnimated)
        try container.encodeIfPresent(gifURL, forKey: .gifURL)
        try container.encodeIfPresent(videoURL, forKey: .videoURL)
        try container.encodeIfPresent(caption, forKey: .caption)
        try container.encodeIfPresent(profileImagePath, forKey: .profileImagePath)
        try container.encodeIfPresent(momentId, forKey: .momentId)
        try container.encodeIfPresent(mediaCount, forKey: .mediaCount)
        try container.encodeIfPresent(quizQuestion, forKey: .quizQuestion)
        try container.encodeIfPresent(quizOptions, forKey: .quizOptions)
        try container.encodeIfPresent(quizCorrectIndex, forKey: .quizCorrectIndex)
        try container.encodeIfPresent(revealType, forKey: .revealType)
        try container.encodeIfPresent(revealPattern, forKey: .revealPattern)
        try container.encodeIfPresent(revealPrimaryColor, forKey: .revealPrimaryColor)
        try container.encodeIfPresent(revealSecondaryColor, forKey: .revealSecondaryColor)
        try container.encodeIfPresent(frameStyle, forKey: .frameStyle)
        try container.encodeIfPresent(contentScale, forKey: .contentScale)
        try container.encodeIfPresent(contentOffsetX, forKey: .contentOffsetX)
        try container.encodeIfPresent(contentOffsetY, forKey: .contentOffsetY)
        try container.encodeIfPresent(moderationState, forKey: .moderationState)
        try container.encodeIfPresent(moderationReason, forKey: .moderationReason)
        try container.encodeIfPresent(moderationCategory, forKey: .moderationCategory)
        try container.encodeIfPresent(audioURL, forKey: .audioURL)
        try container.encodeIfPresent(audioDuration, forKey: .audioDuration)
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
        case .link: return "link"
        case .countdown: return "countdown"
        case .emojiSlider: return "emojiSlider"
        case .questionResponse: return "questionResponse"
        case .generic: return "generic"
        case .weather: return "weather"
        case .time: return "time"
        case .shareMoment: return "shareMoment"
        case .selfie: return "selfie"
        case .quiz: return "quiz"
        case .frame: return "frame"
        case .reveal: return "reveal"
        case .audio: return "audio"
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
        case "link": self = .link
        case "countdown": self = .countdown
        case "emojiSlider": self = .emojiSlider
        case "questionResponse": self = .questionResponse
        case "generic": self = .generic
        case "weather": self = .weather
        case "time": self = .time
        case "shareMoment": self = .shareMoment
        case "selfie": self = .selfie
        case "quiz": self = .quiz
        case "frame": self = .frame
        case "reveal": self = .reveal
        case "audio": self = .audio
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
    let title: String?
    let message: String?
    let downloadURL: String?
    let momentId: String?
    let visitCount: Int?
    let storyId: String?
    let storyAuthorId: String?
    let reaction: String?
    let reactionCount: Int?
    let commentId: String? // ✅ NUEVO: Para identificar comentarios específicos
    let echoId: String? // ✅ NUEVO: Para identificar el Echo sugerido
    let moderationScope: String? // 🛡️ Contexto de moderación: post, story, storySticker
    let chainId: String? // 🔗 Story Chains
    let chainTitle: String? // 🔗 Story Chains
    let chainPosition: Int? // 🔗 Story Chains

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case senderId
        case senderUsername
        case timestamp
        case isPending
        case isRead
        case title
        case message
        case downloadURL
        case momentId
        case visitCount
        case storyId
        case storyAuthorId
        case reaction
        case reactionCount
        case reactionType // ✅ COMPATIBILIDAD: El servidor usa este campo para momentos
        case commentText  // ✅ COMPATIBILIDAD: El servidor usa este campo para comentarios
        case commentId
        case echoId
        case moderationScope
        case chainId
        case chainTitle
        case chainPosition
    }

    init(id: String? = nil,
         type: NotificationType,
         senderId: String,
         senderUsername: String,
         timestamp: Date = Date(),
         isPending: Bool = true,
         title: String? = nil,
         message: String? = nil,
         downloadURL: String? = nil,
         momentId: String? = nil,
         visitCount: Int? = nil,
         storyId: String? = nil,
         storyAuthorId: String? = nil,
         reaction: String? = nil,
         reactionCount: Int? = nil,
         commentId: String? = nil,
         echoId: String? = nil,
         moderationScope: String? = nil,
         chainId: String? = nil,
         chainTitle: String? = nil,
         chainPosition: Int? = nil) {

        self.id = id
        self.type = type
        self.senderId = senderId
        self.senderUsername = senderUsername
        self.timestamp = timestamp
        self.isPending = isPending
        self.title = title
        self.message = message
        self.downloadURL = downloadURL
        self.momentId = momentId
        self.visitCount = visitCount
        self.storyId = storyId
        self.storyAuthorId = storyAuthorId
        self.reaction = reaction
        self.reactionCount = reactionCount
        self.commentId = commentId
        self.echoId = echoId
        self.moderationScope = moderationScope
        self.chainId = chainId
        self.chainTitle = chainTitle
        self.chainPosition = chainPosition
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id)
        let typeString = try container.decode(String.self, forKey: .type)
        self.type = NotificationType(rawValue: typeString) ?? .newFollower
        self.senderId = try container.decodeIfPresent(String.self, forKey: .senderId) ?? ""
        self.senderUsername = try container.decodeIfPresent(String.self, forKey: .senderUsername) ?? ""
        if let firebaseTimestamp = try? container.decode(Timestamp.self, forKey: .timestamp) {
            self.timestamp = firebaseTimestamp.dateValue()
        } else if let date = try? container.decode(Date.self, forKey: .timestamp) {
            self.timestamp = date
        } else {
            self.timestamp = Date()
        }
        if let pending = try container.decodeIfPresent(Bool.self, forKey: .isPending) {
            self.isPending = pending
        } else if let isRead = try container.decodeIfPresent(Bool.self, forKey: .isRead) {
            self.isPending = !isRead
        } else {
            self.isPending = true
        }
        self.title = try container.decodeIfPresent(String.self, forKey: .title)
        self.message = try container.decodeIfPresent(String.self, forKey: .message)
        self.downloadURL = try container.decodeIfPresent(String.self, forKey: .downloadURL)
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
        self.reactionCount = try container.decodeIfPresent(Int.self, forKey: .reactionCount)

        self.commentId = try container.decodeIfPresent(String.self, forKey: .commentId)
        self.echoId = try container.decodeIfPresent(String.self, forKey: .echoId)
        self.moderationScope = try container.decodeIfPresent(String.self, forKey: .moderationScope)
        self.chainId = try container.decodeIfPresent(String.self, forKey: .chainId)
        self.chainTitle = try container.decodeIfPresent(String.self, forKey: .chainTitle)
        self.chainPosition = try container.decodeIfPresent(Int.self, forKey: .chainPosition)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(type.rawValue, forKey: .type)
        try container.encode(senderId, forKey: .senderId)
        try container.encode(senderUsername, forKey: .senderUsername)
        try container.encode(Timestamp(date: timestamp), forKey: .timestamp)
        try container.encode(isPending, forKey: .isPending)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(message, forKey: .message)
        try container.encodeIfPresent(downloadURL, forKey: .downloadURL)
        try container.encodeIfPresent(momentId, forKey: .momentId)
        try container.encodeIfPresent(visitCount, forKey: .visitCount)
        try container.encodeIfPresent(storyId, forKey: .storyId)
        try container.encodeIfPresent(storyAuthorId, forKey: .storyAuthorId)
        try container.encodeIfPresent(reaction, forKey: .reaction)
        try container.encodeIfPresent(reactionCount, forKey: .reactionCount)
        try container.encodeIfPresent(commentId, forKey: .commentId)
        try container.encodeIfPresent(echoId, forKey: .echoId)
        try container.encodeIfPresent(moderationScope, forKey: .moderationScope)
        try container.encodeIfPresent(chainId, forKey: .chainId)
        try container.encodeIfPresent(chainTitle, forKey: .chainTitle)
        try container.encodeIfPresent(chainPosition, forKey: .chainPosition)
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
    case dataExportReady = "data_export_ready"
    case storyChainContinued = "storyChainContinued" // 🔗 Story Chain continuada
    case mediaModeration = "mediaModeration" // 🛡️ Moderación de contenido multimedia

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
        case .dataExportReady: return "Exportación de datos"
        case .storyChainContinued: return "Cadena de historias" // 🔗
        case .mediaModeration: return "Moderación" // 🛡️
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
        case .dataExportReady: return "tray.and.arrow.down.fill"
        case .storyChainContinued: return "link.circle.fill" // 🔗
        case .mediaModeration: return "exclamationmark.shield.fill" // 🛡️
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
