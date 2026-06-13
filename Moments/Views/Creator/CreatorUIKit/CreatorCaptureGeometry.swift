import CoreGraphics
import UIKit

let creatorMomentsCaptureAspectRatio: CGFloat = 9.0 / 16.0
let creatorMomentsCaptureTopOffset: CGFloat = 8.0
let creatorMomentsCaptureSideInset: CGFloat = 4.0

func creatorMomentsAspectRect(aspectRatio: CGFloat, in rect: CGRect) -> CGRect {
    guard rect.width > 0, rect.height > 0 else { return .zero }

    let candidateHeight = rect.width / aspectRatio
    if candidateHeight <= rect.height {
        let y = rect.minY + ((rect.height - candidateHeight) / 2)
        return CGRect(x: rect.minX, y: y, width: rect.width, height: candidateHeight)
    } else {
        let width = rect.height * aspectRatio
        let x = rect.minX + ((rect.width - width) / 2)
        return CGRect(x: x, y: rect.minY, width: width, height: rect.height)
    }
}

func creatorMomentsCaptureRect(in size: CGSize, topInset: CGFloat, bottomInset: CGFloat) -> CGRect {
    let availableWidth = max(size.width - (creatorMomentsCaptureSideInset * 2), 0)
    let desiredHeight = availableWidth / creatorMomentsCaptureAspectRatio
    let maximumHeight = max(size.height - creatorMomentsCaptureTopOffset - bottomInset - 20, 0)

    let resolvedHeight = min(desiredHeight, maximumHeight)
    let resolvedWidth = resolvedHeight * creatorMomentsCaptureAspectRatio

    return CGRect(
        x: (size.width - resolvedWidth) / 2,
        y: creatorMomentsCaptureTopOffset,
        width: resolvedWidth,
        height: resolvedHeight
    )
}

var storyViewerCanvasCornerRadius: CGFloat {
    FeedMomentCardLayout.storyCanvasCornerRadius
}

func keyWindowSafeAreaInsets() -> UIEdgeInsets {
    let scenes = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
    let keyWindow = scenes
        .flatMap(\.windows)
        .first(where: \.isKeyWindow)
    return keyWindow?.safeAreaInsets ?? .zero
}

/// Misma geometría de canvas que `StoryViewerScreen`.
func storyViewerCaptureRect(
    in size: CGSize,
    safeAreaTop: CGFloat,
    safeAreaBottom: CGFloat
) -> CGRect {
    let windowInsets = keyWindowSafeAreaInsets()
    let resolvedTopInset = max(safeAreaTop, windowInsets.top)
    let resolvedBottomInset = max(safeAreaBottom, windowInsets.bottom)
    let baseCaptureRect = creatorMomentsCaptureRect(
        in: size,
        topInset: resolvedTopInset,
        bottomInset: resolvedBottomInset
    )
    return CGRect(
        x: baseCaptureRect.origin.x,
        y: baseCaptureRect.origin.y + resolvedTopInset,
        width: baseCaptureRect.width,
        height: baseCaptureRect.height
    )
}
