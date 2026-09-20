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

struct StoryAdaptiveCanvasLayout {
    let canvasRect: CGRect
    let controlsRect: CGRect
    let usesSideControls: Bool
    let usesSupplementaryControls: Bool
}

/// Geometría compartida por cámara y editor. Mantiene el lienzo 9:16 dentro de
/// la escena consumidora y separa los controles cuando hay ancho o una división.
func storyAdaptiveCanvasLayout(
    in size: CGSize,
    safeAreaInsets: UIEdgeInsets,
    divisionRegions: [CGRect],
    prefersSideControls: Bool = true
) -> StoryAdaptiveCanvasLayout {
    let container = CGRect(origin: .zero, size: size)
    let safeRect = CGRect(
        x: safeAreaInsets.left,
        y: safeAreaInsets.top,
        width: max(size.width - safeAreaInsets.left - safeAreaInsets.right, 1),
        height: max(size.height - safeAreaInsets.top - safeAreaInsets.bottom, 1)
    )
    let divisions = divisionRegions
        .map { $0.intersection(container) }
        .filter { !$0.isNull && !$0.isEmpty }

    // Sin una división física, conserva exactamente el encuadre de Moments
    // normal. La adaptación Duo solo debe cambiar el canvas cuando el sistema
    // comunica una región reservada que realmente divide la escena.
    if divisions.isEmpty {
        let canvas = creatorMomentsCaptureRect(
            in: size,
            topInset: safeAreaInsets.top,
            bottomInset: safeAreaInsets.bottom
        )
        let controlsTop = min(canvas.maxY + 6, size.height)
        return StoryAdaptiveCanvasLayout(
            canvasRect: canvas,
            controlsRect: CGRect(
                x: 0,
                y: controlsTop,
                width: size.width,
                height: max(size.height - controlsTop, 1)
            ),
            usesSideControls: false,
            usesSupplementaryControls: false
        )
    }

    if let division = divisions.first(where: { $0.height >= $0.width }) {
        let leading = CGRect(
            x: safeRect.minX,
            y: safeRect.minY,
            width: max(division.minX - safeRect.minX, 0),
            height: safeRect.height
        )
        let trailingX = max(division.maxX, safeRect.minX)
        let trailing = CGRect(
            x: trailingX,
            y: safeRect.minY,
            width: max(safeRect.maxX - trailingX, 0),
            height: safeRect.height
        )
        let canvasRegion = leading.width >= 150 ? leading : trailing
        let controlsRegion = canvasRegion == leading ? trailing : leading
        if controlsRegion.width >= 170 {
            return StoryAdaptiveCanvasLayout(
                canvasRect: storyCanvasRect(in: canvasRegion, reservesBottomControls: false),
                controlsRect: controlsRegion.insetBy(dx: 8, dy: 8),
                usesSideControls: true,
                usesSupplementaryControls: true
            )
        }
    }

    // En postura de mesa la división es horizontal: la historia se mantiene en
    // una mitad y los controles pasan a la otra, sin introducir un salto en el
    // flujo ni comprimir el lienzo entre ambas zonas.
    if let division = divisions.first(where: { $0.width > $0.height }) {
        let top = CGRect(
            x: safeRect.minX,
            y: safeRect.minY,
            width: safeRect.width,
            height: max(division.minY - safeRect.minY, 0)
        )
        let bottomY = max(division.maxY, safeRect.minY)
        let bottom = CGRect(
            x: safeRect.minX,
            y: bottomY,
            width: safeRect.width,
            height: max(safeRect.maxY - bottomY, 0)
        )
        let canvasRegion = top.height >= 180 ? top : bottom
        let controlsRegion = canvasRegion == top ? bottom : top
        if controlsRegion.height >= 110 {
            return StoryAdaptiveCanvasLayout(
                canvasRect: storyCanvasRect(in: canvasRegion, reservesBottomControls: false),
                controlsRect: controlsRegion.insetBy(dx: 8, dy: 8),
                usesSideControls: false,
                usesSupplementaryControls: true
            )
        }
    }

    let region = storyUsableRegions(in: safeRect, excluding: divisions).max(by: {
        storyCanvasArea(in: $0) < storyCanvasArea(in: $1)
    }) ?? safeRect

    if prefersSideControls, region.width >= region.height * 1.35 {
        let canvasColumnWidth = min(
            region.width * 0.58,
            region.height * creatorMomentsCaptureAspectRatio + 32
        )
        let canvasRegion = CGRect(
            x: region.minX,
            y: region.minY,
            width: canvasColumnWidth,
            height: region.height
        )
        return StoryAdaptiveCanvasLayout(
            canvasRect: storyCanvasRect(in: canvasRegion, reservesBottomControls: false),
            controlsRect: CGRect(
                x: canvasRegion.maxX,
                y: region.minY,
                width: max(region.maxX - canvasRegion.maxX, 1),
                height: region.height
            ).insetBy(dx: 8, dy: 8),
            usesSideControls: true,
            usesSupplementaryControls: true
        )
    }

    let canvas = storyCanvasRect(in: region, reservesBottomControls: true)
    let controlsTop = min(canvas.maxY + 6, region.maxY)
    return StoryAdaptiveCanvasLayout(
        canvasRect: canvas,
        controlsRect: CGRect(
            x: region.minX,
            y: controlsTop,
            width: region.width,
            height: max(region.maxY - controlsTop, 1)
        ),
        usesSideControls: false,
        usesSupplementaryControls: false
    )
}

private func storyCanvasRect(in region: CGRect, reservesBottomControls: Bool) -> CGRect {
    let inset = region.insetBy(dx: 4, dy: 4)
    let topSpace: CGFloat = 30
    let bottomSpace: CGFloat = reservesBottomControls
        ? min(104, max(72, inset.height * 0.13))
        : 8
    let available = CGRect(
        x: inset.minX,
        y: inset.minY + topSpace,
        width: inset.width,
        height: max(inset.height - topSpace - bottomSpace, 1)
    )
    return creatorMomentsAspectRect(aspectRatio: creatorMomentsCaptureAspectRatio, in: available)
}

private func storyCanvasArea(in region: CGRect) -> CGFloat {
    let canvas = storyCanvasRect(in: region, reservesBottomControls: true)
    return canvas.width * canvas.height
}

private func storyUsableRegions(in safeRect: CGRect, excluding divisions: [CGRect]) -> [CGRect] {
    divisions.reduce([safeRect]) { regions, division in
        regions.flatMap { region in
            guard region.intersects(division) else { return [region] }
            if division.height >= division.width {
                return [
                    CGRect(x: region.minX, y: region.minY, width: max(division.minX - region.minX, 0), height: region.height),
                    CGRect(x: max(division.maxX, region.minX), y: region.minY, width: max(region.maxX - max(division.maxX, region.minX), 0), height: region.height)
                ].filter { $0.width >= 120 }
            }
            return [
                CGRect(x: region.minX, y: region.minY, width: region.width, height: max(division.minY - region.minY, 0)),
                CGRect(x: region.minX, y: max(division.maxY, region.minY), width: region.width, height: max(region.maxY - max(division.maxY, region.minY), 0))
            ].filter { $0.height >= 180 }
        }
    }
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
