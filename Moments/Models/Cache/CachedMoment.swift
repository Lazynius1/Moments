import Foundation
import SwiftData

// MARK: - ✅ SwiftData Model: Momento cacheado localmente
// Espejo de `Moment` para persistencia offline, patrón local-first.

@Model
final class CachedMoment {
    // MARK: - Identificador
    @Attribute(.unique) var momentId: String // Firestore Document ID
    
    // MARK: - Campos principales
    var authorId: String
    var username: String
    var content: String
    var imagePath: String?
    var videoUrl: String?
    var timestamp: Date
    var commentCount: Int?
    var profileImagePath: String?
    var location: String?
    var audience: String?
    var aspectRatio: String?
    var thumbnailUrl: String?
    var videoDuration: Double?
    var videoFileSize: Int64?
    var videoResolution: String?
    var customListId: String?
    
    // MARK: - Configuración
    var disableComments: Bool?
    var hideLikeCounts: Bool?
    var allowSharing: Bool?
    var scheduledDate: Date?
    var isPinned: Bool?
    var pinnedAt: Date?
    var gridPreviewScale: Double?
    var gridPreviewOffsetX: Double?
    var gridPreviewOffsetY: Double?
    var gridPreviewFitMode: String?
    var gridPreviewBackground: String?
    var hasHiddenLayers: Bool?
    var hiddenLayerCount: Int?
    
    // MARK: - Trending
    var trendingScore: Double?
    var engagementRate: Double?
    
    // MARK: - Ubicación (serializada como JSON)
    var locationLatitude: Double?
    var locationLongitude: Double?
    
    // MARK: - Datos complejos (serializados como JSON)
    var reactionsData: Data?      // [String: [String]] encoded
    var mediaItemsData: Data?     // [MediaItem] encoded
    var taggedUsersData: Data?    // [String] encoded
    var mentionedUsersData: Data? // [String] encoded
    
    // MARK: - Metadatos de caché
    var lastSyncedAt: Date
    var feedSection: String       // "feed", "explore", "profile"
    
    // MARK: - Init
    init(
        momentId: String,
        authorId: String,
        username: String,
        content: String,
        imagePath: String? = nil,
        videoUrl: String? = nil,
        timestamp: Date,
        commentCount: Int = 0,
        profileImagePath: String? = nil,
        location: String? = nil,
        audience: String? = nil,
        aspectRatio: String? = nil,
        thumbnailUrl: String? = nil,
        videoDuration: Double? = nil,
        videoFileSize: Int64? = nil,
        videoResolution: String? = nil,
        customListId: String? = nil,
        disableComments: Bool? = false,
        hideLikeCounts: Bool? = false,
        allowSharing: Bool? = true,
        scheduledDate: Date? = nil,
        isPinned: Bool? = nil,
        pinnedAt: Date? = nil,
        gridPreviewScale: Double? = nil,
        gridPreviewOffsetX: Double? = nil,
        gridPreviewOffsetY: Double? = nil,
        gridPreviewFitMode: String? = nil,
        gridPreviewBackground: String? = nil,
        hasHiddenLayers: Bool? = false,
        hiddenLayerCount: Int? = 0,
        trendingScore: Double? = nil,
        engagementRate: Double? = nil,
        locationLatitude: Double? = nil,
        locationLongitude: Double? = nil,
        reactionsData: Data? = nil,
        mediaItemsData: Data? = nil,
        taggedUsersData: Data? = nil,
        mentionedUsersData: Data? = nil,
        lastSyncedAt: Date = Date(),
        feedSection: String = "feed"
    ) {
        self.momentId = momentId
        self.authorId = authorId
        self.username = username
        self.content = content
        self.imagePath = imagePath
        self.videoUrl = videoUrl
        self.timestamp = timestamp
        self.commentCount = commentCount
        self.profileImagePath = profileImagePath
        self.location = location
        self.audience = audience
        self.aspectRatio = aspectRatio
        self.thumbnailUrl = thumbnailUrl
        self.videoDuration = videoDuration
        self.videoFileSize = videoFileSize
        self.videoResolution = videoResolution
        self.customListId = customListId
        self.disableComments = disableComments
        self.hideLikeCounts = hideLikeCounts
        self.allowSharing = allowSharing
        self.scheduledDate = scheduledDate
        self.isPinned = isPinned
        self.pinnedAt = pinnedAt
        self.gridPreviewScale = gridPreviewScale
        self.gridPreviewOffsetX = gridPreviewOffsetX
        self.gridPreviewOffsetY = gridPreviewOffsetY
        self.gridPreviewFitMode = gridPreviewFitMode
        self.gridPreviewBackground = gridPreviewBackground
        self.hasHiddenLayers = hasHiddenLayers
        self.hiddenLayerCount = hiddenLayerCount
        self.trendingScore = trendingScore
        self.engagementRate = engagementRate
        self.locationLatitude = locationLatitude
        self.locationLongitude = locationLongitude
        self.reactionsData = reactionsData
        self.mediaItemsData = mediaItemsData
        self.taggedUsersData = taggedUsersData
        self.mentionedUsersData = mentionedUsersData
        self.lastSyncedAt = lastSyncedAt
        self.feedSection = feedSection
    }
}

// MARK: - Conversión Moment ↔ CachedMoment

extension CachedMoment {
    
    /// Convierte un `Moment` de Firestore a `CachedMoment` para SwiftData
    static func from(_ moment: Moment, section: String = "feed") -> CachedMoment {
        let encoder = JSONEncoder()
        
        // Serializar reactions
        let reactionsData = try? encoder.encode(moment.reactions)
        
        // Serializar mediaItems
        let mediaItemsData = try? encoder.encode(moment.mediaItems)
        
        // Serializar taggedUsers
        let taggedUsersData = try? encoder.encode(moment.taggedUsers)
        let mentionedUsersData = try? encoder.encode(moment.mentionedUsers)
        
        return CachedMoment(
            momentId: moment.id ?? UUID().uuidString,
            authorId: moment.authorId,
            username: moment.username,
            content: moment.content,
            imagePath: moment.imagePath,
            videoUrl: moment.videoUrl,
            timestamp: moment.timestamp,
            commentCount: moment.commentCount,
            profileImagePath: moment.profileImagePath,
            location: moment.location,
            audience: moment.audience,
            aspectRatio: moment.aspectRatio,
            thumbnailUrl: moment.thumbnailUrl,
            videoDuration: moment.videoDuration,
            videoFileSize: moment.videoFileSize,
            videoResolution: moment.videoResolution,
            customListId: moment.customListId,
            disableComments: moment.disableComments,
            hideLikeCounts: moment.hideLikeCounts,
            allowSharing: moment.allowSharing,
            scheduledDate: moment.scheduledDate,
            isPinned: moment.isPinned,
            pinnedAt: moment.pinnedAt,
            gridPreviewScale: moment.gridPreviewScale,
            gridPreviewOffsetX: moment.gridPreviewOffsetX,
            gridPreviewOffsetY: moment.gridPreviewOffsetY,
            gridPreviewFitMode: moment.gridPreviewFitMode,
            gridPreviewBackground: moment.gridPreviewBackground,
            hasHiddenLayers: moment.hasHiddenLayers,
            hiddenLayerCount: moment.hiddenLayerCount,
            trendingScore: moment.trendingScore,
            engagementRate: moment.engagementRate,
            locationLatitude: moment.locationCoordinate?.latitude,
            locationLongitude: moment.locationCoordinate?.longitude,
            reactionsData: reactionsData,
            mediaItemsData: mediaItemsData,
            taggedUsersData: taggedUsersData,
            mentionedUsersData: mentionedUsersData,
            lastSyncedAt: Date(),
            feedSection: section
        )
    }
    
    /// Convierte un `CachedMoment` de SwiftData a `Moment` para usar en las Views
    func toMoment() -> Moment? {
        let decoder = JSONDecoder()
        
        // Deserializar reactions
        let reactions: [String: [String]] = {
            guard let data = reactionsData else { return [:] }
            return (try? decoder.decode([String: [String]].self, from: data)) ?? [:]
        }()
        
        // Deserializar mediaItems
        let mediaItems: [MediaItem]? = {
            guard let data = mediaItemsData else { return nil }
            return try? decoder.decode([MediaItem].self, from: data)
        }()
        
        // Deserializar taggedUsers
        let taggedUsers: [String]? = {
            guard let data = taggedUsersData else { return nil }
            return try? decoder.decode([String].self, from: data)
        }()
        let mentionedUsers: [String]? = {
            guard let data = mentionedUsersData else { return nil }
            return try? decoder.decode([String].self, from: data)
        }()
        
        // LocationCoordinate
        let locationCoordinate: Moment.LocationCoordinate? = {
            guard let lat = locationLatitude, let lon = locationLongitude else { return nil }
            return Moment.LocationCoordinate(latitude: lat, longitude: lon)
        }()
        
        return Moment(
            id: momentId,
            authorId: authorId,
            username: username,
            content: content,
            imagePath: imagePath,
            videoUrl: videoUrl,
            timestamp: timestamp,
            reactions: reactions,
            commentCount: commentCount ?? 0,
            profileImagePath: profileImagePath,
            taggedUsers: taggedUsers,
            mentionedUsers: mentionedUsers,
            location: location,
            locationCoordinate: locationCoordinate,
            audience: audience,
            mediaItems: mediaItems,
            aspectRatio: aspectRatio,
            customListId: customListId,
            thumbnailUrl: thumbnailUrl,
            videoDuration: videoDuration,
            videoFileSize: videoFileSize,
            videoResolution: videoResolution,
            disableComments: disableComments ?? false,
            hideLikeCounts: hideLikeCounts ?? false,
            allowSharing: allowSharing ?? true,
            scheduledDate: scheduledDate,
            trendingScore: trendingScore,
            engagementRate: engagementRate,
            isPinned: isPinned,
            pinnedAt: pinnedAt,
            gridPreviewScale: gridPreviewScale,
            gridPreviewOffsetX: gridPreviewOffsetX,
            gridPreviewOffsetY: gridPreviewOffsetY,
            gridPreviewFitMode: gridPreviewFitMode,
            gridPreviewBackground: gridPreviewBackground,
            hasHiddenLayers: hasHiddenLayers ?? false,
            hiddenLayerCount: hiddenLayerCount ?? 0
        )
    }
}
