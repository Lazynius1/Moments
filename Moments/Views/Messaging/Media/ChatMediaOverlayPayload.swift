import Foundation
import UIKit
import SwiftUI

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

/// Messaging supplies the same normalized metadata as a Story; the shared renderer owns the visuals.
struct ChatMessageStaticOverlay: View {
    @ObservedObject var message: EnhancedMessage
    var interactiveReveal = false
    var animates = false
    @State private var stickerItems: [StickerItem] = []
    @Environment(\.displayScale) private var displayScale
    @AppStorage private var revealed: Bool

    init(message: EnhancedMessage, interactiveReveal: Bool = false, animates: Bool = false) {
        self.message = message
        self.interactiveReveal = interactiveReveal
        self.animates = animates
        _revealed = AppStorage(wrappedValue: false, "reveal_revealed_\(message.id)")
    }

    var body: some View {
        GeometryReader { geometry in
            let canvasWidth = max(geometry.size.width, geometry.size.height * 9 / 16)
            let canvasSize = CGSize(width: canvasWidth, height: canvasWidth * 16 / 9)
            Group {
                if animates {
            StoryMediaOverlayRendererView(
                containerSize: canvasSize,
                textOverlays: message.resolvedTextOverlays,
                stickerItems: stickerItems,
                drawingData: nil, storyId: message.id, userId: message.senderId,
                reportsDeckInteractionExclusion: false, allowsStickerHitTesting: false,
                revealPolicy: revealed ? .exposed : .concealed,
                interactiveReveal: interactiveReveal,
                renderingMode: animates ? .live : .thumbnail, clipCornerRadius: 0
            )
                } else {
                    StoryThumbnailOverlayView(
                        containerSize: canvasSize,
                        textOverlays: message.resolvedTextOverlays,
                        stickerItems: stickerItems,
                        storyId: message.id, userId: message.senderId,
                        revealPolicy: revealed ? .exposed : .concealed,
                        interactiveReveal: interactiveReveal
                    )
                }
            }
            .frame(width: canvasSize.width, height: canvasSize.height)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .clipped()
        .modifier(StoryMusicPlayback(
            selection: animates ? message.stickers?.compactMap(\.music).first : nil,
            active: animates, elapsed: 0
        ))
        // Compare the source values directly. Serializing Base64 artwork in body to
        // identify a task can repeatedly restart it as the message publishes progress.
        .onChange(of: message.stickers, initial: true) { _, _ in
            rebuildStickerItems()
        }
        .onChange(of: displayScale) { _, _ in
            rebuildStickerItems()
        }
    }

    private func rebuildStickerItems() {
        stickerItems = message.resolvedStickerItems(
            traitCollection: UITraitCollection(displayScale: displayScale)
        )
    }
}
