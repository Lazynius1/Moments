import SwiftUI
import UIKit
import Kingfisher
import ImageIO

enum StoryOverlayRenderingMode {
    case live
    case thumbnail
}

enum StoryRevealThumbnailPolicy: Equatable {
    case concealed
    case exposed
}

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
    var renderingMode: StoryOverlayRenderingMode = .live
    var clipCornerRadius: CGFloat = storyViewerCanvasCornerRadius
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
                    replayToken: replayToken,
                    animates: renderingMode == .live
                )
                .frame(width: containerSize.width, height: containerSize.height)
                .allowsHitTesting(false)
                .zIndex(Double(overlay.layerOrder))
            }

            ForEach(stickerItems, id: \.id) { sticker in
                stickerView(for: stickerForDisplay(sticker))
                .position(stickerDisplayPosition(sticker))
                .zIndex(Double(sticker.zIndex))
                .allowsHitTesting(allowsStickerHitTesting)
            }
        }
        .frame(width: containerSize.width, height: containerSize.height)
        .clipShape(
            RoundedRectangle(
                cornerRadius: clipCornerRadius,
                style: .continuous
            )
        )
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

    @ViewBuilder
    private func stickerView(for sticker: StickerItem) -> some View {
        switch renderingMode {
        case .live:
            StoryStickerView(
                sticker: sticker,
                screenSize: containerSize,
                storyId: storyId,
                userId: userId,
                reportsDeckInteractionExclusion: reportsDeckInteractionExclusion,
                onPauseStory: onPauseStory,
                onResumeStory: onResumeStory
            )
        case .thumbnail:
            StoryStaticStickerView(
                sticker: sticker,
                storyId: storyId,
                userId: userId
            )
        }
    }
}

/// Superficie ligera para grids, mensajes y previews. Conserva las mismas
/// coordenadas del visor, pero congela vídeo/animaciones y no crea interacción.
struct StoryStaticPreviewSurface: View {
    let story: Story
    var revealPolicy: StoryRevealThumbnailPolicy = .concealed

    @Environment(\.displayScale) private var displayScale
    @State private var stickerItems: [StickerItem] = []

    var body: some View {
        GeometryReader { geometry in
            let canvasSize = aspectFillCanvasSize(in: geometry.size)

            ZStack {
                StoryStaticPreviewMedia(story: story)

                StoryMediaOverlayRendererView(
                    containerSize: canvasSize,
                    textOverlays: story.resolvedTextOverlays,
                    stickerItems: stickerItems,
                    drawingData: nil,
                    storyId: story.id ?? "",
                    userId: story.authorId,
                    reportsDeckInteractionExclusion: false,
                    allowsStickerHitTesting: false,
                    renderingMode: .thumbnail,
                    clipCornerRadius: 0
                )
                .allowsHitTesting(false)

                if revealPolicy == .concealed,
                   let revealSticker = stickerItems.first(where: { $0.type == .reveal }) {
                    StoryStaticRevealOverlay(sticker: revealSticker)
                        .frame(width: canvasSize.width, height: canvasSize.height)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: canvasSize.width, height: canvasSize.height)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .clipped()
        .task(id: previewIdentity) {
            stickerItems = story.convertStickersToStickerItems(
                traitCollection: UITraitCollection(displayScale: displayScale)
            )
        }
    }

    private var previewIdentity: String {
        "\(story.id ?? "")-\(story.timestamp.timeIntervalSince1970)-\(story.stickers?.count ?? 0)"
    }

    private func aspectFillCanvasSize(in target: CGSize) -> CGSize {
        let storyAspectRatio: CGFloat = 9.0 / 16.0
        let targetAspectRatio = target.width / max(target.height, 1)

        if targetAspectRatio > storyAspectRatio {
            return CGSize(width: target.width, height: target.width / storyAspectRatio)
        }
        return CGSize(width: target.height * storyAspectRatio, height: target.height)
    }
}

private struct StoryStaticRevealOverlay: View {
    let sticker: StickerItem

    var body: some View {
        RevealSurfaceView(
            type: sticker.interactionData?.revealType,
            pattern: sticker.interactionData?.revealPattern,
            primaryColor: sticker.interactionData?.revealPrimaryColor,
            secondaryColor: sticker.interactionData?.revealSecondaryColor,
            effectColor: sticker.interactionData?.revealEffectColor
        )
        .allowsHitTesting(false)
    }
}

private struct StoryStaticPreviewMedia: View {
    let story: Story

    var body: some View {
        ZStack {
            Color.black

            if let url = previewURL {
                KFImage(url)
                    .placeholder {
                        ZStack {
                            Color.white.opacity(0.08)
                            ProgressView().tint(.white.opacity(0.7))
                        }
                    }
                    .cancelOnDisappear(true)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: story.mediaItem.type == .video ? "video.fill" : "photo.fill")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .clipped()
    }

    private var previewURL: URL? {
        let candidates: [String?] = story.mediaItem.type == .video
            ? [story.mediaItem.thumbnailUrl, story.backgroundFrameURL, story.backgroundBlurredFrameURL, story.mediaItem.url]
            : [story.mediaItem.url, story.backgroundFrameURL, story.backgroundBlurredFrameURL]

        return candidates.lazy
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
            .flatMap(URL.init(string:))
    }
}

private struct StoryStaticStickerView: View {
    let sticker: StickerItem
    let storyId: String
    let userId: String

    @ViewBuilder
    var body: some View {
        if sticker.type == .shareMoment {
            SharedMomentStoryCardView(
                image: sticker.image,
                videoURL: nil,
                username: sticker.interactionData?.username
                    ?? NSLocalizedString("storyEditor.mention.userFallback", comment: "Fallback username for shared Moment"),
                userId: sticker.interactionData?.userId,
                profileImagePath: sticker.interactionData?.profileImagePath,
                sharedMediaPath: sticker.interactionData?.sharedMediaPath,
                caption: sticker.interactionData?.caption,
                mediaCount: sticker.interactionData?.mediaCount ?? 1,
                styleVariant: sticker.interactionData?.styleVariant ?? 0,
                cardLayoutVariant: sticker.interactionData?.cardLayoutVariant ?? 0
            )
            .scaleEffect(sticker.scale)
            .frame(
                width: sticker.image.size.width * sticker.scale,
                height: sticker.image.size.height * sticker.scale
            )
            .rotationEffect(sticker.rotation)
            .allowsHitTesting(false)
        } else if let gifURL = sticker.gifURL {
            StoryStaticGIFFrameView(
                url: gifURL,
                size: CGSize(
                    width: sticker.image.size.width * sticker.scale,
                    height: sticker.image.size.height * sticker.scale
                )
            )
            .rotationEffect(sticker.rotation)
            .allowsHitTesting(false)
        } else if sticker.isAnimated || sticker.videoURL != nil {
            Image(uiImage: sticker.image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(
                    width: sticker.image.size.width * sticker.scale,
                    height: sticker.image.size.height * sticker.scale
                )
                .rotationEffect(sticker.rotation)
                .allowsHitTesting(false)
        } else {
            StoryStickerView(
                sticker: sticker,
                screenSize: .zero,
                storyId: storyId,
                userId: userId,
                reportsDeckInteractionExclusion: false,
                onPauseStory: {},
                onResumeStory: {}
            )
            .allowsHitTesting(false)
        }
    }
}

private struct StoryStaticGIFFrameView: View {
    let url: URL
    let size: CGSize

    @State private var frameImage: UIImage?

    var body: some View {
        Group {
            if let frameImage {
                Image(uiImage: frameImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Color.clear
            }
        }
        .frame(width: size.width, height: size.height)
        .task(id: url) {
            if let cached = StoryStaticGIFFrameCache.frames.object(forKey: url as NSURL) {
                frameImage = cached
                return
            }

            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  !Task.isCancelled,
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let firstFrame = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                return
            }

            let image = UIImage(cgImage: firstFrame)
            StoryStaticGIFFrameCache.frames.setObject(image, forKey: url as NSURL)
            frameImage = image
        }
    }
}

@MainActor
private enum StoryStaticGIFFrameCache {
    static let frames = NSCache<NSURL, UIImage>()
}
