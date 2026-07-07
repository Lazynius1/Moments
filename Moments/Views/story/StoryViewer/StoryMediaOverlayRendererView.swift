import SwiftUI
import UIKit

struct StoryMediaOverlayRendererView: View {
    let containerSize: CGSize
    let textOverlays: [StoryTextOverlayMetadata]
    let stickerItems: [StickerItem]
    let drawingData: Data?
    let storyId: String
    let userId: String
    var replayToken: Int = 0
    var reportsDeckInteractionExclusion: Bool = true
    var allowsStickerHitTesting: Bool = true
    var onPauseStory: () -> Void = {}
    var onResumeStory: () -> Void = {}

    var body: some View {
        ZStack {
            if let drawingImage {
                Image(uiImage: drawingImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: containerSize.width, height: containerSize.height)
                    .clipped()
                    .allowsHitTesting(false)
                    .zIndex(-1)
            }

            ForEach(textOverlays, id: \.id) { overlay in
                StoryLiveTextOverlayView(
                    metadata: overlay,
                    containerSize: containerSize,
                    replayToken: replayToken
                )
                .frame(width: containerSize.width, height: containerSize.height)
                .allowsHitTesting(false)
                .zIndex(Double(overlay.layerOrder))
            }

            ForEach(stickerItems, id: \.id) { sticker in
                StoryStickerView(
                    sticker: stickerForDisplay(sticker),
                    screenSize: containerSize,
                    storyId: storyId,
                    userId: userId,
                    reportsDeckInteractionExclusion: reportsDeckInteractionExclusion,
                    onPauseStory: onPauseStory,
                    onResumeStory: onResumeStory
                )
                .position(stickerDisplayPosition(sticker))
                .zIndex(Double(sticker.zIndex))
                .allowsHitTesting(allowsStickerHitTesting)
            }
        }
        .frame(width: containerSize.width, height: containerSize.height)
    }

    private var drawingImage: UIImage? {
        guard let drawingData else { return nil }
        return UIImage(data: drawingData)
    }

    private func stickerDisplayPosition(_ sticker: StickerItem) -> CGPoint {
        CGPoint(
            x: sticker.position.x * max(containerSize.width, 1),
            y: sticker.position.y * max(containerSize.height, 1)
        )
    }

    private func stickerForDisplay(_ sticker: StickerItem) -> StickerItem {
        let scaleFactor = max(containerSize.width, 1) / 375.0
        var displaySticker = sticker
        displaySticker.scale = sticker.scale * scaleFactor
        return displaySticker
    }
}
