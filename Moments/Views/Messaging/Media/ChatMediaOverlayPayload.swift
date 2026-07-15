import Foundation
import UIKit

struct ChatMediaOverlayPayload {
    let textOverlayLive: Bool?
    let textOverlays: [StoryTextOverlayMetadata]?
    let stickers: [StickerData]?
    let drawingData: Data?

    var isEmpty: Bool {
        (textOverlays?.isEmpty ?? true)
            && (stickers?.isEmpty ?? true)
            && drawingData == nil
    }

    static let empty = ChatMediaOverlayPayload(
        textOverlayLive: nil,
        textOverlays: nil,
        stickers: nil,
        drawingData: nil
    )
}

extension EnhancedMessage {
    var usesLiveTextOverlay: Bool {
        if let textOverlays, !textOverlays.isEmpty { return true }
        return textOverlayLive == true
    }

    var resolvedTextOverlays: [StoryTextOverlayMetadata] {
        guard let textOverlays, !textOverlays.isEmpty else { return [] }
        return textOverlays
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { lhs, rhs in
                if lhs.layerOrder == rhs.layerOrder {
                    return lhs.id < rhs.id
                }
                return lhs.layerOrder < rhs.layerOrder
            }
    }

    @available(*, deprecated, message: "use resolvedStickerItems(traitCollection:) instead")
    var resolvedStickerItems: [StickerItem] {
        resolvedStickerItems(traitCollection: .current)
    }

    func resolvedStickerItems(traitCollection: UITraitCollection) -> [StickerItem] {
        guard let stickers, !stickers.isEmpty else { return [] }
        return storyOverlayShim.convertStickersToStickerItems(traitCollection: traitCollection)
    }

    private var storyOverlayShim: Story {
        Story(
            id: id,
            authorId: senderId,
            username: "",
            mediaItem: MediaItem(
                type: type == .viewOnceVideo ? .video : .image,
                url: mediaUrl ?? ""
            ),
            duration: duration ?? 0,
            timestamp: timestamp,
            expirationDate: expirationDate ?? Date(),
            profileImagePath: nil,
            textOverlayLive: textOverlayLive,
            textOverlays: textOverlays,
            stickers: stickers,
            drawingData: drawingData
        )
    }
}
