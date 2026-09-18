import SwiftUI
import UIKit
import Kingfisher

/// Recortes de la card de momento (ancho 1080):
/// - Cuadrado:  1080×1080 → 1:1
/// - Retrato:   1080×1350 → 4:5
/// - Retrato alto: 1080×1440 → 3:4
/// - Apaisado:  1080×566  → 1.91:1
enum MomentFeedCrop {
    static let maxScale: CGFloat = 4
    static let exportWidth: CGFloat = 1080

    static let squareSize = CGSize(width: 1080, height: 1080)
    static let portraitSize = CGSize(width: 1080, height: 1350)
    static let reelsGridSize = CGSize(width: 1080, height: 1440)
    static let landscapeSize = CGSize(width: 1080, height: 566)

    static let squareAspect: CGFloat = 1
    static let portraitMax: CGFloat = 1080.0 / 1350.0
    static let reelsGridAspect: CGFloat = 1080.0 / 1440.0
    static let landscapeMax: CGFloat = 1080.0 / 566.0
    /// Peek inmersivo: no más alto que 9:16 (capturas de pantalla).
    static let immersivePortraitMax: CGFloat = 9.0 / 16.0

#if DEBUG
    private static let didValidateContract: Void = {
        let ratios: [(CGFloat, CGFloat)] = [
            (9.0 / 16.0, portraitMax),
            (reelsGridAspect, reelsGridAspect),
            (portraitMax, portraitMax),
            (squareAspect, squareAspect),
            (4.0 / 3.0, 4.0 / 3.0),
            (landscapeMax, landscapeMax)
        ]
        for (source, expected) in ratios {
            assert(abs(feedCardAspect(from: source) - expected) < 0.001)
        }

        let sourceSize = CGSize(width: 1080, height: 2400)
        let cardRect = CGRect(x: 0, y: 525, width: 1080, height: 1350)
        let normalized = normalizedFeedCrop(cardRect, in: sourceSize, cardAspect: portraitMax)
        assert(abs(normalized.rect(in: sourceSize).minY - cardRect.minY) < 0.001)

        let immersiveRect = immersiveCropRect(imageSize: sourceSize, preserving: normalized)
        assert(immersiveRect.contains(cardRect))
        let remapped = remap(normalized, from: sourceSize, into: immersiveRect)
        assert(remapped.rect(in: immersiveRect.size).width > 0)
    }()

    static func validateDebugContract() {
        _ = didValidateContract
    }
#endif

    static func clamp(_ ratio: CGFloat) -> CGFloat {
        guard ratio.isFinite, ratio > 0 else { return squareAspect }
        return ratio
    }

    /// Instagram admite el rango continuo 3:4...1.91:1.
    /// Los presets 3:4, 4:5, 1:1 y 1.91:1 son referencias, no buckets.
    /// Reels 9:16 se limitan a 4:5 dentro de la card.
    static func feedCardAspect(from original: CGFloat) -> CGFloat {
        let ratio = clamp(original)
        if abs(ratio - 9.0 / 16.0) < 0.05 || ratio < 0.70 {
            return portraitMax
        }
        return min(max(ratio, reelsGridAspect), landscapeMax)
    }

    static func immersiveAspect(from original: CGFloat) -> CGFloat {
        max(clamp(original), immersivePortraitMax)
    }

    static func normalizedFeedCrop(
        _ rect: CGRect,
        in imageSize: CGSize,
        cardAspect: CGFloat
    ) -> MediaItemFeedCrop {
        guard imageSize.width > 1, imageSize.height > 1 else {
            return .fullBounds(cardAspect: CreatorMedia.AspectRatio.fromFeedPostRatio(cardAspect).displayName)
        }
        let safe = rect.intersection(CGRect(origin: .zero, size: imageSize))
        return MediaItemFeedCrop(
            cardAspect: CreatorMedia.AspectRatio.fromFeedPostRatio(cardAspect).displayName,
            x: safe.minX / imageSize.width,
            y: safe.minY / imageSize.height,
            width: safe.width / imageSize.width,
            height: safe.height / imageSize.height
        )
    }

    /// Ventana máxima 9:16 para peek que siempre conserva dentro el crop de la card.
    static func immersiveCropRect(
        imageSize: CGSize,
        preserving feedCrop: MediaItemFeedCrop?
    ) -> CGRect {
        let bounds = CGRect(origin: .zero, size: imageSize)
        let originalAspect = imageSize.width / max(imageSize.height, 1)
        guard originalAspect < immersivePortraitMax else { return bounds }

        let targetHeight = min(imageSize.width / immersivePortraitMax, imageSize.height)
        let protected = feedCrop?.rect(in: imageSize) ?? bounds
        let preferredY = protected.midY - targetHeight / 2
        let minimumY = max(protected.maxY - targetHeight, 0)
        let maximumY = min(protected.minY, imageSize.height - targetHeight)
        let clampedY: CGFloat
        if minimumY <= maximumY {
            clampedY = min(max(preferredY, minimumY), maximumY)
        } else {
            clampedY = min(max(preferredY, 0), imageSize.height - targetHeight)
        }
        return CGRect(x: 0, y: clampedY, width: imageSize.width, height: targetHeight)
    }

    static func remap(
        _ feedCrop: MediaItemFeedCrop,
        from sourceSize: CGSize,
        into sourceRect: CGRect
    ) -> MediaItemFeedCrop {
        guard sourceRect.width > 1, sourceRect.height > 1 else { return feedCrop }
        let old = feedCrop.rect(in: sourceSize).intersection(sourceRect)
        return MediaItemFeedCrop(
            cardAspect: feedCrop.cardAspect,
            x: (old.minX - sourceRect.minX) / sourceRect.width,
            y: (old.minY - sourceRect.minY) / sourceRect.height,
            width: old.width / sourceRect.width,
            height: old.height / sourceRect.height
        )
    }

    /// Traslada un crop normalizado sin cambiar aspect ni tamaño; solo reencuadra.
    static func translated(
        _ feedCrop: MediaItemFeedCrop,
        byNormalized delta: CGSize
    ) -> MediaItemFeedCrop {
        let maxX = max(1 - feedCrop.width, 0)
        let maxY = max(1 - feedCrop.height, 0)
        return MediaItemFeedCrop(
            cardAspect: feedCrop.cardAspect,
            x: min(max(feedCrop.x + delta.width, 0), maxX),
            y: min(max(feedCrop.y + delta.height, 0), maxY),
            width: feedCrop.width,
            height: feedCrop.height
        )
    }

    /// Zoom del crop manteniendo aspect y el centro; `factor` > 1 acerca (ventana más pequeña).
    static func scaled(
        _ feedCrop: MediaItemFeedCrop,
        by factor: CGFloat,
        imageSize: CGSize,
        minNormalizedSide: CGFloat = 0.12
    ) -> MediaItemFeedCrop {
        let safeFactor = max(factor, 0.01)
        let cardAspect = max(feedCrop.cardAspectValue, 0.01)
        let imageAspect = imageSize.width / max(imageSize.height, 1)

        // Relación normalizada width/height para conservar el aspect de card en píxeles.
        // (w * imgW) / (h * imgH) = cardAspect → h = w * imageAspect / cardAspect
        var nextWidth = feedCrop.width / safeFactor
        var nextHeight = nextWidth * imageAspect / cardAspect

        let maxWidth = min(1, cardAspect / max(imageAspect, 0.01))
        let maxHeight = min(1, imageAspect / cardAspect)
        nextWidth = min(max(nextWidth, minNormalizedSide), maxWidth)
        nextHeight = nextWidth * imageAspect / cardAspect
        if nextHeight > maxHeight {
            nextHeight = maxHeight
            nextWidth = nextHeight * cardAspect / max(imageAspect, 0.01)
        }

        let centerX = feedCrop.x + feedCrop.width / 2
        let centerY = feedCrop.y + feedCrop.height / 2
        let nextX = min(max(centerX - nextWidth / 2, 0), max(1 - nextWidth, 0))
        let nextY = min(max(centerY - nextHeight / 2, 0), max(1 - nextHeight, 0))

        return MediaItemFeedCrop(
            cardAspect: feedCrop.cardAspect,
            x: nextX,
            y: nextY,
            width: nextWidth,
            height: nextHeight
        )
    }

    static func exportWindow(for aspect: CGFloat) -> CGSize {
        let safe = feedCardAspect(from: aspect)
        if abs(safe - squareAspect) < 0.02 { return squareSize }
        if abs(safe - portraitMax) < 0.02 { return portraitSize }
        if abs(safe - reelsGridAspect) < 0.02 { return reelsGridSize }
        if abs(safe - landscapeMax) < 0.03 { return landscapeSize }
        return CGSize(width: exportWidth, height: exportWidth / safe)
    }

    /// Rectángulo del post dentro del canvas cuadrado de la preview.
    static func cropWindow(aspect: CGFloat, in canvas: CGSize) -> CGSize {
        let safe = feedCardAspect(from: aspect)
        if safe < 1 {
            return CGSize(width: canvas.height * safe, height: canvas.height)
        }
        return CGSize(width: canvas.width, height: canvas.width / safe)
    }

    static func coverScale(imageSize: CGSize, window: CGSize) -> CGFloat {
        guard imageSize.width > 0, imageSize.height > 0, window.width > 0, window.height > 0 else { return 1 }
        return max(window.width / imageSize.width, window.height / imageSize.height)
    }

    static func fitScale(imageSize: CGSize, window: CGSize) -> CGFloat {
        guard imageSize.width > 0, imageSize.height > 0, window.width > 0, window.height > 0 else { return 1 }
        return min(window.width / imageSize.width, window.height / imageSize.height)
    }

    /// Escala relativa a cover (=1). En un cuadrado: fit deja huecos; cover llena el cuadrado.
    static func fitRelativeScale(originalAspect: CGFloat) -> CGFloat {
        let aspect = clamp(originalAspect)
        guard aspect > 0 else { return 1 }
        return min(aspect, 1 / aspect)
    }

    static func minRelativeScale(imageSize: CGSize, window: CGSize, fillWindow: Bool) -> CGFloat {
        let cover = coverScale(imageSize: imageSize, window: window)
        guard cover > 0 else { return 1 }
        if fillWindow { return 1 }
        return min(max(fitScale(imageSize: imageSize, window: window) / cover, 0.01), 1)
    }

    static func clampedOffset(
        imageSize: CGSize,
        window: CGSize,
        scale: CGFloat,
        offset: CGSize,
        minScale: CGFloat
    ) -> CGSize {
        let cover = coverScale(imageSize: imageSize, window: window)
        let drawScale = cover * max(scale, minScale)
        let drawn = CGSize(width: imageSize.width * drawScale, height: imageSize.height * drawScale)
        let maxX = max((drawn.width - window.width) / 2, 0)
        let maxY = max((drawn.height - window.height) / 2, 0)
        return CGSize(
            width: min(max(offset.width, -maxX), maxX),
            height: min(max(offset.height, -maxY), maxY)
        )
    }

    static func expandRect(_ rect: CGRect, toAspect aspect: CGFloat, in bounds: CGSize) -> CGRect {
        let safeAspect = clamp(aspect)
        guard rect.width > 1, rect.height > 1, bounds.width > 1, bounds.height > 1 else { return rect }
        let current = rect.width / rect.height
        var next = rect
        if abs(current - safeAspect) > 0.01 {
            let center = CGPoint(x: rect.midX, y: rect.midY)
            if safeAspect < current {
                let height = rect.width / safeAspect
                next = CGRect(x: rect.minX, y: center.y - height / 2, width: rect.width, height: height)
            } else {
                let width = rect.height * safeAspect
                next = CGRect(x: center.x - width / 2, y: rect.minY, width: width, height: rect.height)
            }
        }
        return next.intersection(CGRect(origin: .zero, size: bounds))
    }

    /// Píxeles de foto que se ven en el cuadrado de preview (sin huecos del canvas).
    static func visiblePhotoRect(
        imageSize: CGSize,
        canvas: CGSize,
        scale: CGFloat,
        offset: CGSize,
        fillWindow: Bool
    ) -> CGRect {
        let minScale = minRelativeScale(imageSize: imageSize, window: canvas, fillWindow: fillWindow)
        let cover = coverScale(imageSize: imageSize, window: canvas)
        let drawScale = cover * max(scale, minScale)
        guard drawScale > 0, imageSize.width > 1, imageSize.height > 1, canvas.width > 1, canvas.height > 1 else {
            return CGRect(origin: .zero, size: imageSize)
        }
        let drawn = CGSize(width: imageSize.width * drawScale, height: imageSize.height * drawScale)
        let clamped = clampedOffset(
            imageSize: imageSize,
            window: canvas,
            scale: max(scale, minScale),
            offset: offset,
            minScale: minScale
        )
        let originInCanvas = CGPoint(
            x: (canvas.width - drawn.width) / 2 + clamped.width,
            y: (canvas.height - drawn.height) / 2 + clamped.height
        )
        let drawnRect = CGRect(origin: originInCanvas, size: drawn)
        let visibleInCanvas = drawnRect.intersection(CGRect(origin: .zero, size: canvas))
        guard visibleInCanvas.width > 1, visibleInCanvas.height > 1 else {
            return CGRect(origin: .zero, size: imageSize)
        }
        return CGRect(
            x: (visibleInCanvas.minX - originInCanvas.x) / drawScale,
            y: (visibleInCanvas.minY - originInCanvas.y) / drawScale,
            width: visibleInCanvas.width / drawScale,
            height: visibleInCanvas.height / drawScale
        )
    }

    /// Recorta a `target` exacto (sin pasar por la card 4:5).
    static func exactCropRect(_ rect: CGRect, toAspect target: CGFloat, in imageSize: CGSize) -> CGRect {
        let bounds = CGRect(origin: .zero, size: imageSize)
        let safeRect = rect.intersection(bounds)
        let safeTarget = clamp(target)
        guard safeRect.width > 1, safeRect.height > 1, safeTarget > 0 else { return safeRect }
        let raw = safeRect.width / safeRect.height
        if abs(raw - safeTarget) < 0.005 { return safeRect }

        var next = safeRect
        if safeTarget > raw {
            let height = safeRect.width / safeTarget
            next.origin.y += (safeRect.height - height) / 2
            next.size.height = height
        } else {
            let width = safeRect.height * safeTarget
            next.origin.x += (safeRect.width - width) / 2
            next.size.width = width
        }
        return next.intersection(bounds)
    }

    /// Recorta `rect` a `target` (ancho/alto) sin salir de la imagen ni añadir letterbox.
    static func cropRect(_ rect: CGRect, toAspect target: CGFloat, in imageSize: CGSize) -> CGRect {
        let bounds = CGRect(origin: .zero, size: imageSize)
        let safeRect = rect.intersection(bounds)
        let safeTarget = feedCardAspect(from: target)
        guard safeRect.width > 1, safeRect.height > 1, safeTarget > 0 else { return safeRect }
        let raw = safeRect.width / safeRect.height
        if abs(raw - safeTarget) < 0.005 { return safeRect }

        var next = safeRect
        if safeTarget > raw {
            let height = safeRect.width / safeTarget
            next.origin.y += (safeRect.height - height) / 2
            next.size.height = height
        } else {
            let width = safeRect.height * safeTarget
            next.origin.x += (safeRect.width - width) / 2
            next.size.width = width
        }
        return next.intersection(bounds)
    }

    /// Recorta dentro de `rect` al aspect de card (3:4…1.91, 9:16→4:5) sin añadir letterbox.
    static func clampVisibleRect(_ rect: CGRect, in imageSize: CGSize) -> CGRect {
        let bounds = CGRect(origin: .zero, size: imageSize)
        let safeRect = rect.intersection(bounds)
        guard safeRect.width > 1, safeRect.height > 1 else { return safeRect }
        let raw = safeRect.width / safeRect.height
        return cropRect(safeRect, toAspect: feedCardAspect(from: raw), in: imageSize)
    }
}

struct AssetCropSession: Equatable {
    var originalAspect: CGFloat
    var isSquareExpanded: Bool
    var scale: CGFloat
    var offset: CGSize

    init(pixelWidth: Int, pixelHeight: Int) {
        let raw = CGFloat(pixelWidth) / max(CGFloat(pixelHeight), 1)
        self.originalAspect = MomentFeedCrop.clamp(raw)
        // IG: el lienzo es el cuadrado; la foto entra en fit y el pinch la lleva a fill.
        self.isSquareExpanded = false
        self.scale = MomentFeedCrop.fitRelativeScale(originalAspect: originalAspect)
        self.offset = .zero
    }

    /// `pixelWidth/Height` de PHAsset ignora EXIF; la preview ya viene orientada.
    mutating func applyOrientedSize(_ size: CGSize) {
        let previousFit = MomentFeedCrop.fitRelativeScale(originalAspect: originalAspect)
        let aspect = MomentFeedCrop.clamp(size.width / max(size.height, 1))
        originalAspect = aspect
        if !isSquareExpanded, abs(scale - previousFit) < 0.03 {
            scale = MomentFeedCrop.fitRelativeScale(originalAspect: aspect)
            offset = .zero
        }
    }

    /// El lienzo de preview es siempre 1:1. El botón solo fija export a 1:1 (fill).
    var fillsPreview: Bool { isSquareExpanded }

    var cropAspect: CGFloat {
        isSquareExpanded ? 1 : MomentFeedCrop.feedCardAspect(from: originalAspect)
    }

    var canExpandToSquare: Bool {
        abs(MomentFeedCrop.feedCardAspect(from: originalAspect) - 1) > 0.02
    }
}

/// Aplica un `feedCrop` normalizado sin volver a generar el archivo.
/// El contenido debe representar la fuente completa con aspect-fit dentro del frame recibido.
struct NormalizedMediaCropContainer<Content: View>: View {
    let feedCrop: MediaItemFeedCrop?
    let content: () -> Content

    init(feedCrop: MediaItemFeedCrop?, @ViewBuilder content: @escaping () -> Content) {
        self.feedCrop = feedCrop
        self.content = content
    }

    var body: some View {
        GeometryReader { geometry in
            if let feedCrop,
               feedCrop.width > 0.0001,
               feedCrop.height > 0.0001 {
                let sourceWidth = geometry.size.width / feedCrop.width
                let sourceHeight = geometry.size.height / feedCrop.height
                ZStack(alignment: .topLeading) {
                    content()
                        .frame(width: sourceWidth, height: sourceHeight)
                        .offset(
                            x: -sourceWidth * feedCrop.x,
                            y: -sourceHeight * feedCrop.y
                        )
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                .clipped()
            } else {
                content()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
            }
        }
    }
}

struct FeedCroppedRemoteImage: View {
    let url: URL?
    let feedCrop: MediaItemFeedCrop?
    var placeholderColor: Color = .clear

    var body: some View {
        NormalizedMediaCropContainer(feedCrop: feedCrop) {
            KFImage(url)
                .placeholder { placeholderColor }
                .cancelOnDisappear(true)
                .resizable()
                .scaledToFit()
        }
        .aspectRatio(feedCrop?.cardAspectValue ?? 1, contentMode: .fit)
    }
}

/// Aplica `feedCrop` al bitmap y deja que el contenedor (grid 1:1) haga fill/fit.
struct NormalizedFeedCropProcessor: ImageProcessor {
    let feedCrop: MediaItemFeedCrop

    var identifier: String {
        "moments.feedCrop.\(feedCrop.cardAspect).\(feedCrop.x).\(feedCrop.y).\(feedCrop.width).\(feedCrop.height)"
    }

    func process(
        item: ImageProcessItem,
        options: KingfisherParsedOptionsInfo
    ) -> KFCrossPlatformImage? {
        let image: UIImage?
        switch item {
        case .image(let value):
            image = value
        case .data(let data):
            image = UIImage(data: data)
        }
        guard let image else { return nil }
        let oriented = image.momentsOrientedUp()
        guard !feedCrop.isFullBounds else { return oriented }
        return oriented.cropped(to: feedCrop.rect(in: oriented.size))
    }
}

extension KFImage {
    func applyingFeedCrop(_ feedCrop: MediaItemFeedCrop?) -> KFImage {
        guard let feedCrop, !feedCrop.isFullBounds else { return self }
        return setProcessor(NormalizedFeedCropProcessor(feedCrop: feedCrop))
    }
}

extension UIImage {
    func croppedToFeedWindow(
        aspect: CGFloat,
        scale: CGFloat,
        offset: CGSize,
        windowSize: CGSize,
        sourceWindowSize: CGSize? = nil
    ) -> UIImage {
        let oriented = momentsOrientedUp()
        let imageSize = oriented.size
        guard imageSize.width > 1, imageSize.height > 1, windowSize.width > 1, windowSize.height > 1 else {
            return oriented
        }

        let fillWindow = abs(aspect - MomentFeedCrop.squareAspect) < 0.02
        let minScale = MomentFeedCrop.minRelativeScale(
            imageSize: imageSize,
            window: windowSize,
            fillWindow: fillWindow
        )
        let cover = MomentFeedCrop.coverScale(imageSize: imageSize, window: windowSize)
        let drawScale = cover * max(scale, minScale)
        let sourceWidth = sourceWindowSize?.width ?? windowSize.width
        let offsetScale = sourceWidth > 0 ? windowSize.width / sourceWidth : 1
        let exportOffset = CGSize(
            width: offset.width * offsetScale,
            height: offset.height * offsetScale
        )
        let clamped = MomentFeedCrop.clampedOffset(
            imageSize: imageSize,
            window: windowSize,
            scale: scale,
            offset: exportOffset,
            minScale: minScale
        )

        let visibleWidth = windowSize.width / drawScale
        let visibleHeight = windowSize.height / drawScale
        let originX = (imageSize.width - visibleWidth) / 2 - clamped.width / drawScale
        let originY = (imageSize.height - visibleHeight) / 2 - clamped.height / drawScale
        let visible = CGRect(x: originX, y: originY, width: visibleWidth, height: visibleHeight)
        let cropRect = MomentFeedCrop.expandRect(
            visible,
            toAspect: aspect,
            in: imageSize
        )

        return oriented.cropped(to: cropRect)
    }

    func croppedFromVisiblePreview(
        canvas: CGSize,
        scale: CGFloat,
        offset: CGSize,
        fillWindow: Bool
    ) -> UIImage {
        let oriented = momentsOrientedUp()
        let visible = MomentFeedCrop.visiblePhotoRect(
            imageSize: oriented.size,
            canvas: canvas,
            scale: scale,
            offset: offset,
            fillWindow: fillWindow
        )
        let cropRect = MomentFeedCrop.clampVisibleRect(visible, in: oriented.size)
        return oriented.cropped(to: cropRect)
    }

    func cappedForImmersivePeek() -> UIImage {
        let oriented = momentsOrientedUp()
        let rect = MomentFeedCrop.immersiveCropRect(imageSize: oriented.size, preserving: nil)
        if rect == CGRect(origin: .zero, size: oriented.size) { return oriented }
        return oriented.cropped(to: rect)
    }

    func cropped(to cropRect: CGRect) -> UIImage {
        guard cropRect.width > 1, cropRect.height > 1 else { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: cropRect.size, format: format)
        return renderer.image { _ in
            draw(at: CGPoint(x: -cropRect.origin.x, y: -cropRect.origin.y))
        }
    }

    func momentsOrientedUp() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

struct MomentFeedCropCanvas: View {
    let image: UIImage?
    let isVideo: Bool
    let videoDurationText: String?
    let session: AssetCropSession
    let cropAspect: CGFloat
    let onSessionChange: (AssetCropSession) -> Void
    var showsAspectToggle: Bool = true
    var onWindowSizeChange: ((CGSize) -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @State private var gestureScale: CGFloat = 1
    @State private var gestureOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            // El lienzo de interacción es siempre el cuadrado completo.
            // El aspect de exportación no encoje ese marco: el pinch puede llenarlo.
            let window = geo.size
            ZStack {
                (colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6"))
                if let image {
                    let minScale = MomentFeedCrop.minRelativeScale(
                        imageSize: image.size,
                        window: window,
                        fillWindow: session.fillsPreview
                    )
                    let liveScale = min(
                        max(session.scale * gestureScale, minScale),
                        MomentFeedCrop.maxScale
                    )
                    let liveOffset = CGSize(
                        width: session.offset.width + gestureOffset.width,
                        height: session.offset.height + gestureOffset.height
                    )
                    let cover = MomentFeedCrop.coverScale(imageSize: image.size, window: window)
                    let drawScale = cover * liveScale
                    let drawn = CGSize(width: image.size.width * drawScale, height: image.size.height * drawScale)
                    let clamped = MomentFeedCrop.clampedOffset(
                        imageSize: image.size,
                        window: window,
                        scale: liveScale,
                        offset: liveOffset,
                        minScale: minScale
                    )
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: drawn.width, height: drawn.height)
                        .offset(clamped)
                        .frame(width: window.width, height: window.height)
                        .clipped()
                        .contentShape(Rectangle())
                        .highPriorityGesture(pinchAndPan(imageSize: image.size, window: window, minScale: minScale))
                } else {
                    ProgressView()
                }
            }
            .overlay(alignment: .bottomLeading) {
                if showsAspectToggle, session.canExpandToSquare {
                    Button {
                        var next = session
                        next.isSquareExpanded.toggle()
                        next.scale = next.isSquareExpanded
                            ? 1
                            : MomentFeedCrop.fitRelativeScale(originalAspect: next.originalAspect)
                        next.offset = .zero
                        withAnimation(.easeInOut(duration: 0.2)) {
                            onSessionChange(next)
                        }
                    } label: {
                        GridPreviewModeChipIcon(fitMode: session.fillsPreview ? .fill : .fit)
                            .frame(width: 14, height: 14)
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(12)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if isVideo, let videoDurationText {
                    Text(videoDurationText)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.45), in: Capsule())
                        .padding(12)
                        .allowsHitTesting(false)
                }
            }
            .onAppear {
                onWindowSizeChange?(window)
            }
            .onChange(of: window) { _, size in
                onWindowSizeChange?(size)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .animation(.easeInOut(duration: 0.2), value: session.isSquareExpanded)
    }

    private func pinchAndPan(imageSize: CGSize, window: CGSize, minScale: CGFloat) -> some Gesture {
        SimultaneousGesture(
            MagnificationGesture()
                .onChanged { value in
                    gestureScale = value
                }
                .onEnded { value in
                    var next = session
                    next.scale = min(max(session.scale * value, minScale), MomentFeedCrop.maxScale)
                    next.offset = MomentFeedCrop.clampedOffset(
                        imageSize: imageSize,
                        window: window,
                        scale: next.scale,
                        offset: CGSize(
                            width: session.offset.width + gestureOffset.width,
                            height: session.offset.height + gestureOffset.height
                        ),
                        minScale: minScale
                    )
                    gestureScale = 1
                    gestureOffset = .zero
                    onSessionChange(next)
                },
            DragGesture()
                .onChanged { value in
                    gestureOffset = value.translation
                }
                .onEnded { value in
                    var next = session
                    next.offset = MomentFeedCrop.clampedOffset(
                        imageSize: imageSize,
                        window: window,
                        scale: next.scale * gestureScale,
                        offset: CGSize(
                            width: session.offset.width + value.translation.width,
                            height: session.offset.height + value.translation.height
                        ),
                        minScale: minScale
                    )
                    gestureOffset = .zero
                    onSessionChange(next)
                }
        )
    }
}
