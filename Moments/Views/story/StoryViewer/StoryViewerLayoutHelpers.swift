import SwiftUI
import AVFoundation
import UIKit

extension StoryViewerScreen {
    static func resolvedVideoPresentationSize(naturalSize: CGSize, preferredTransform: CGAffineTransform) -> CGSize {
        let transformedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        return CGSize(
            width: abs(transformedRect.width),
            height: abs(transformedRect.height)
        )
    }

    // ✅ FUNCIÓN HELPER: Detectar aspect ratio de un video (CORREGIDA)
    static func detectVideoAspectRatio(from url: URL) async -> String? {
        let asset = AVURLAsset(url: url)
        let tracks = try? await asset.loadTracks(withMediaType: .video)

        if let videoTrack = tracks?.first {
            let naturalSize = try? await videoTrack.load(.naturalSize)
            let preferredTransform = try? await videoTrack.load(.preferredTransform)

            if let size = naturalSize, let transform = preferredTransform {
                let resolvedSize = resolvedVideoPresentationSize(
                    naturalSize: size,
                    preferredTransform: transform
                )
                let width = Int(resolvedSize.width)
                let height = Int(resolvedSize.height)
                let aspectRatio = "\(width):\(height)"

                return aspectRatio
            }
        }

        return nil
    }

    // ✅ FUNCIÓN HELPER: Detectar aspect ratio de una imagen
    static func detectImageAspectRatio(from url: URL) async -> String? {
        guard let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else {
            return nil
        }

        let width = Int(image.size.width)
        let height = Int(image.size.height)
        let aspectRatio = "\(width):\(height)"


        return aspectRatio
    }

    // ✅ FUNCIÓN HELPER: Determinar si un aspect ratio es horizontal
    static func isHorizontalAspectRatio(_ aspectRatio: String?) -> Bool {
        guard let aspectRatio = aspectRatio else {
            return false
        }

        let components = aspectRatio.split(separator: ":")
        if components.count == 2,
           let width = Int(components[0]),
           let height = Int(components[1]) {
            let isHorizontal = width > height
            return isHorizontal
        }

        return false
    }

    static func parseAspectRatio(_ aspectRatio: String?) -> CGFloat? {
        guard let aspectRatio else { return nil }
        let components = aspectRatio.split(separator: ":")
        guard components.count == 2,
              let widthValue = Double(components[0]),
              let heightValue = Double(components[1]) else {
            return nil
        }

        let width = CGFloat(widthValue)
        let height = CGFloat(heightValue)
        guard
              width > 0,
              height > 0 else {
            return nil
        }
        return width / height
    }

    static func contentRect(
        containerSize: CGSize,
        mediaAspectRatio: CGFloat,
        contentMode: SwiftUI.ContentMode
    ) -> CGRect {
        let containerWidth = max(containerSize.width, 1)
        let containerHeight = max(containerSize.height, 1)
        let containerAspectRatio = containerWidth / containerHeight

        let isFit = contentMode == .fit
        let mediaIsWider = mediaAspectRatio > containerAspectRatio

        let width: CGFloat
        let height: CGFloat

        if isFit {
            if mediaIsWider {
                width = containerWidth
                height = containerWidth / max(mediaAspectRatio, 0.0001)
            } else {
                height = containerHeight
                width = containerHeight * mediaAspectRatio
            }
        } else {
            if mediaIsWider {
                height = containerHeight
                width = containerHeight * mediaAspectRatio
            } else {
                width = containerWidth
                height = containerWidth / max(mediaAspectRatio, 0.0001)
            }
        }

        return CGRect(
            x: (containerWidth - width) / 2,
            y: (containerHeight - height) / 2,
            width: width,
            height: height
        )
    }

    func stickerDisplayPosition(_ sticker: StickerItem, containerSize: CGSize) -> CGPoint {
        return CGPoint(
            x: sticker.position.x * max(containerSize.width, 1),
            y: sticker.position.y * max(containerSize.height, 1)
        )
    }

    func stickerForDisplay(_ sticker: StickerItem, containerSize: CGSize) -> StickerItem {
        let scaleFactor = max(containerSize.width, 1) / 375.0
        var displaySticker = sticker
        displaySticker.scale = sticker.scale * scaleFactor
        return displaySticker
    }
}
