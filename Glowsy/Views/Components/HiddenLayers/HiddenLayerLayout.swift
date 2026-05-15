import SwiftUI

enum HiddenLayerLayout {
    static let imageAspectRatio: CGFloat = 1.26
    static let minimumPostAspectRatio: CGFloat = 0.8
    static let maximumPostAspectRatio: CGFloat = 4.0 / 3.0

    static func displayedPostAspectRatio(for imageSize: CGSize) -> CGFloat {
        let safeRatio = imageSize.width / max(imageSize.height, 1)
        guard safeRatio.isFinite, safeRatio > 0 else { return 1.0 }
        return min(max(safeRatio, minimumPostAspectRatio), maximumPostAspectRatio)
    }

    static func fixedAspectRect(aspectRatio: CGFloat, containerSize: CGSize) -> CGRect {
        guard aspectRatio > 0, containerSize.width > 0, containerSize.height > 0 else {
            return CGRect(origin: .zero, size: containerSize)
        }

        let containerAspectRatio = containerSize.width / containerSize.height
        let width: CGFloat
        let height: CGFloat

        if aspectRatio > containerAspectRatio {
            width = containerSize.width
            height = width / aspectRatio
        } else {
            height = containerSize.height
            width = height * aspectRatio
        }

        return CGRect(
            x: (containerSize.width - width) / 2,
            y: (containerSize.height - height) / 2,
            width: width,
            height: height
        )
    }

    static func frame(for layer: MomentHiddenLayer, in imageRect: CGRect) -> CGRect {
        let width = max(44, imageRect.width * layer.width)
        let height: CGFloat

        if layer.type == .image {
            height = max(44, width * imageAspectRatio)
        } else {
            height = max(44, imageRect.height * layer.height)
        }

        let centerX = imageRect.minX + imageRect.width * layer.anchorX
        let centerY = imageRect.minY + imageRect.height * layer.anchorY

        return CGRect(
            x: centerX - width / 2,
            y: centerY - height / 2,
            width: width,
            height: height
        )
    }

    static func frame(for draft: HiddenLayerDraft, in imageRect: CGRect) -> CGRect {
        let width = max(44, imageRect.width * draft.width)
        let height: CGFloat

        if draft.type == .image {
            height = max(44, width * imageAspectRatio)
        } else {
            height = max(44, imageRect.height * draft.height)
        }

        let centerX = imageRect.minX + imageRect.width * draft.anchorX
        let centerY = imageRect.minY + imageRect.height * draft.anchorY

        return CGRect(
            x: centerX - width / 2,
            y: centerY - height / 2,
            width: width,
            height: height
        )
    }
}
