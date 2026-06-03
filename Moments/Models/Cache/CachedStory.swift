import Foundation
import SwiftData
import FirebaseFirestore

@Model
final class CachedStory {
    @Attribute(.unique) var id: String
    var authorId: String
    var username: String
    var profileImagePath: String?
    var timestamp: Date
    var expirationDate: Date
    var mediaItemData: Data // JSON encoded MediaItem
    var audience: String?
    var customListId: String?
    var text: String?
    var textPositionData: Data? // JSON encoded CGPoint
    var textStyle: String?
    var textOverlayMetadataData: Data?
    var stickersData: Data? // JSON encoded [StickerData]
    var drawingData: Data?
    var aspectRatio: String?
    var backgroundFrameURL: String?
    var backgroundBlurredFrameURL: String?
    var chainId: String?
    var chainPosition: Int?
    var chainTitle: String?
    
    var cachedAt: Date

    init(id: String,
         authorId: String,
         username: String,
         profileImagePath: String?,
         timestamp: Date,
         expirationDate: Date,
         mediaItemData: Data,
         audience: String? = nil,
         customListId: String? = nil,
         text: String? = nil,
         textPositionData: Data? = nil,
         textStyle: String? = nil,
         textOverlayMetadataData: Data? = nil,
         stickersData: Data? = nil,
         drawingData: Data? = nil,
         aspectRatio: String? = nil,
         backgroundFrameURL: String? = nil,
         backgroundBlurredFrameURL: String? = nil,
         chainId: String? = nil,
         chainPosition: Int? = nil,
         chainTitle: String? = nil) {
        self.id = id
        self.authorId = authorId
        self.username = username
        self.profileImagePath = profileImagePath
        self.timestamp = timestamp
        self.expirationDate = expirationDate
        self.mediaItemData = mediaItemData
        self.audience = audience
        self.customListId = customListId
        self.text = text
        self.textPositionData = textPositionData
        self.textStyle = textStyle
        self.textOverlayMetadataData = textOverlayMetadataData
        self.stickersData = stickersData
        self.drawingData = drawingData
        self.aspectRatio = aspectRatio
        self.backgroundFrameURL = backgroundFrameURL
        self.backgroundBlurredFrameURL = backgroundBlurredFrameURL
        self.chainId = chainId
        self.chainPosition = chainPosition
        self.chainTitle = chainTitle
        self.cachedAt = Date()
    }
    
    // MARK: - Conversión Story -> CachedStory
    static func fromStory(_ story: Story) -> CachedStory? {
        guard let id = story.id else { return nil }
        
        let mediaItemData = (try? JSONEncoder().encode(story.mediaItem)) ?? Data()
        let textPositionData = (try? JSONEncoder().encode(story.textPosition))
        let textOverlayMetadataData = story.resolvedTextOverlayMetadata.flatMap { try? JSONEncoder().encode($0) }
        let stickersData = (try? JSONEncoder().encode(story.stickers))

        return CachedStory(
            id: id,
            authorId: story.authorId,
            username: story.username,
            profileImagePath: story.profileImagePath,
            timestamp: story.timestamp,
            expirationDate: story.expirationDate,
            mediaItemData: mediaItemData,
            audience: story.audience,
            customListId: story.customListId,
            text: story.text,
            textPositionData: textPositionData,
            textStyle: story.textStyle,
            textOverlayMetadataData: textOverlayMetadataData,
            stickersData: stickersData,
            drawingData: story.drawingData,
            aspectRatio: story.aspectRatio,
            backgroundFrameURL: story.backgroundFrameURL,
            backgroundBlurredFrameURL: story.backgroundBlurredFrameURL,
            chainId: story.chainId,
            chainPosition: story.chainPosition,
            chainTitle: story.chainTitle
        )
    }
    
    // MARK: - Conversión CachedStory -> Story
    func toStory() -> Story {
        let mediaItem = (try? JSONDecoder().decode(MediaItem.self, from: mediaItemData)) ?? MediaItem(type: .image, url: "")
        let textPosition = textPositionData != nil ? (try? JSONDecoder().decode(CGPoint.self, from: textPositionData!)) : nil
        let overlayMetadata = textOverlayMetadataData.flatMap { try? JSONDecoder().decode(StoryTextOverlayMetadata.self, from: $0) }
        let stickers = stickersData != nil ? (try? JSONDecoder().decode([StickerData].self, from: stickersData!)) : nil
        
        return Story(
            id: id,
            authorId: authorId,
            username: username,
            mediaItem: mediaItem,
            duration: 15.0, // Default duration if not saved
            timestamp: timestamp,
            expirationDate: expirationDate,
            profileImagePath: profileImagePath,
            audience: audience,
            customListId: customListId,
            text: text,
            textPosition: textPosition,
            textStyle: overlayMetadata?.styleRaw ?? textStyle,
            textPositionNormX: overlayMetadata.map { Double($0.normalizedPosition.x) },
            textPositionNormY: overlayMetadata.map { Double($0.normalizedPosition.y) },
            textColorHex: overlayMetadata?.colorHex,
            textFontSize: overlayMetadata?.fontSize,
            textAlignment: overlayMetadata?.alignmentRaw,
            textBackgroundFill: overlayMetadata?.backgroundFillRaw,
            textStroke: overlayMetadata?.strokeRaw,
            textVisualEffect: overlayMetadata?.visualEffectRaw,
            textMotion: overlayMetadata?.motionRaw,
            forcesAllCaps: overlayMetadata?.forcesAllCaps,
            textLayerOrder: overlayMetadata?.layerOrder,
            textOverlayLive: overlayMetadata?.isLiveOverlay,
            stickers: stickers,
            drawingData: drawingData,
            aspectRatio: aspectRatio,
            backgroundFrameURL: backgroundFrameURL,
            backgroundBlurredFrameURL: backgroundBlurredFrameURL,
            chainId: chainId,
            chainPosition: chainPosition,
            chainTitle: chainTitle
        )
    }
}
