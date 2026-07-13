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

/// Resolución de exportación 9:16 alineada con editor/viewer/stories.
let creatorMomentsStoryOutputPixelSize = CGSize(width: 1080, height: 1920)

/// Insets del chrome de `StoryCameraView` dentro del canvas 9:16.
/// Deben mantenerse alineados con los overlays de captura (top controls, reel, botón texto).
enum CreatorMomentsCameraChromeInsets {
    static let top: CGFloat = 58
    static let bottom: CGFloat = 62
    static let horizontal: CGFloat = 52
}

/// Zona donde Camera Kit puede dibujar la UI del lens (Safe Render).
/// Coordenadas en el espacio del canvas `creatorMomentsCaptureRect`.
func creatorMomentsLensInterfaceSafeArea(in canvasSize: CGSize) -> CGRect {
    let horizontal = CreatorMomentsCameraChromeInsets.horizontal
    let top = CreatorMomentsCameraChromeInsets.top
    let bottom = CreatorMomentsCameraChromeInsets.bottom

    return CGRect(
        x: horizontal,
        y: top,
        width: max(canvasSize.width - (horizontal * 2), 0),
        height: max(canvasSize.height - top - bottom, 0)
    )
}

func creatorMomentsStoryOutputResolution(for canvasSize: CGSize) -> CGSize {
    guard canvasSize.width > 0, canvasSize.height > 0 else {
        return creatorMomentsStoryOutputPixelSize
    }

    // Mantener 9:16 y escalar a ~1080 px de ancho para alinear captura con el viewer.
    let scale = creatorMomentsStoryOutputPixelSize.width / canvasSize.width
    return CGSize(
        width: (canvasSize.width * scale).rounded(),
        height: (canvasSize.height * scale).rounded()
    )
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
