import SwiftUI
import UIKit
import CoreImage

private enum StoryMediaTransformLimits {
    static let minScale: CGFloat = 0.45
    static let maxScale: CGFloat = 1.8
    static let snapScaleThreshold: CGFloat = 0.08
    static let snapRotationThreshold: CGFloat = .pi / 36.0
}

func storyMediaBaseRect(mediaSize: CGSize, canvasSize: CGSize) -> CGRect {
    let rect = storyMediaRectForCanvas(mediaSize: mediaSize, canvasSize: canvasSize)
    return CGRect(
        x: (canvasSize.width - rect.width) / 2,
        y: (canvasSize.height - rect.height) / 2,
        width: rect.width,
        height: rect.height
    )
}

func storyMediaRectForCanvas(mediaSize: CGSize, canvasSize: CGSize) -> CGRect {
    let imageRatio = mediaSize.width / max(mediaSize.height, 1)
    let targetRatio = canvasSize.width / max(canvasSize.height, 1)
    let useFit = StoryMediaLayoutRules.presentationMode(for: imageRatio, canvasAspectRatio: targetRatio) == .fitWithBlur
    let mediaIsWider = imageRatio > targetRatio

    let finalWidth: CGFloat
    let finalHeight: CGFloat

    if useFit {
        if mediaIsWider {
            finalWidth = canvasSize.width
            finalHeight = canvasSize.width / max(imageRatio, 0.0001)
        } else {
            finalHeight = canvasSize.height
            finalWidth = canvasSize.height * imageRatio
        }
    } else {
        if mediaIsWider {
            finalHeight = canvasSize.height
            finalWidth = canvasSize.height * imageRatio
        } else {
            finalWidth = canvasSize.width
            finalHeight = canvasSize.width / max(imageRatio, 0.0001)
        }
    }

    return CGRect(
        x: (canvasSize.width - finalWidth) / 2,
        y: (canvasSize.height - finalHeight) / 2,
        width: finalWidth,
        height: finalHeight
    )
}

func storyShouldShowGeneratedBackground(scale: CGFloat, offset: CGSize, rotation: Angle) -> Bool {
    let isScaledDown = scale < 0.995
    let isMoved = abs(offset.width) > 1 || abs(offset.height) > 1
    let isRotated = abs(rotation.radians) > 0.015
    return isScaledDown || isMoved || isRotated
}

func storyClampedMediaScale(_ proposedScale: CGFloat) -> CGFloat {
    min(max(proposedScale, StoryMediaTransformLimits.minScale), StoryMediaTransformLimits.maxScale)
}

func storyClampedMediaOffset(
    _ proposedOffset: CGSize,
    canvasSize: CGSize,
    mediaSize: CGSize,
    scale: CGFloat
) -> CGSize {
    let baseRect = storyMediaBaseRect(mediaSize: mediaSize, canvasSize: canvasSize)
    let scaledWidth = baseRect.width * scale
    let scaledHeight = baseRect.height * scale

    let minVisibleX = min(max(44, scaledWidth * 0.24), scaledWidth)
    let minVisibleY = min(max(44, scaledHeight * 0.24), scaledHeight)

    let horizontalLimit = max(0, (canvasSize.width / 2) + (scaledWidth / 2) - minVisibleX)
    let verticalLimit = max(0, (canvasSize.height / 2) + (scaledHeight / 2) - minVisibleY)

    return CGSize(
        width: min(max(proposedOffset.width, -horizontalLimit), horizontalLimit),
        height: min(max(proposedOffset.height, -verticalLimit), verticalLimit)
    )
}

func storySnappedMediaScale(_ scale: CGFloat) -> CGFloat {
    abs(scale - 1) < StoryMediaTransformLimits.snapScaleThreshold ? 1.0 : scale
}

func storySnappedMediaRotation(_ rotation: Angle) -> Angle {
    abs(rotation.radians) < StoryMediaTransformLimits.snapRotationThreshold ? .zero : rotation
}

func storyDominantBackgroundColors(
    from image: UIImage,
    maxColors: Int = 3
) -> [UIColor] {
    guard let cgImage = image.normalized().cgImage else {
        return [
            UIColor(Color(hex: "0B1215")),
            UIColor(Color(hex: "FAF9F6"))
        ]
    }

    let sampleSize = 36
    let bytesPerPixel = 4
    let bytesPerRow = sampleSize * bytesPerPixel
    let bitsPerComponent = 8

    guard let context = CGContext(
        data: nil,
        width: sampleSize,
        height: sampleSize,
        bitsPerComponent: bitsPerComponent,
        bytesPerRow: bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return [UIColor(Color(hex: "0B1215"))]
    }

    context.interpolationQuality = .medium
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: sampleSize, height: sampleSize))

    guard let data = context.data else {
        return [UIColor(Color(hex: "0B1215"))]
    }

    struct Bucket {
        var count: Int = 0
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var saturation: CGFloat = 0
    }

    let quantizationStep = 32
    var buckets: [Int: Bucket] = [:]
    let pointer = data.bindMemory(to: UInt8.self, capacity: sampleSize * sampleSize * bytesPerPixel)

    for y in 0..<sampleSize {
        for x in 0..<sampleSize {
            let pixelIndex = (y * bytesPerRow) + (x * bytesPerPixel)
            let red = CGFloat(pointer[pixelIndex]) / 255.0
            let green = CGFloat(pointer[pixelIndex + 1]) / 255.0
            let blue = CGFloat(pointer[pixelIndex + 2]) / 255.0
            let alpha = CGFloat(pointer[pixelIndex + 3]) / 255.0

            guard alpha > 0.6 else { continue }

            let uiColor = UIColor(red: red, green: green, blue: blue, alpha: 1.0)
            var hue: CGFloat = 0
            var saturation: CGFloat = 0
            var brightness: CGFloat = 0
            uiColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil)

            guard brightness > 0.14, brightness < 0.96 else { continue }
            guard saturation > 0.08 || brightness < 0.28 else { continue }

            let quantizedR = Int(red * 255.0) / quantizationStep
            let quantizedG = Int(green * 255.0) / quantizationStep
            let quantizedB = Int(blue * 255.0) / quantizationStep
            let key = (quantizedR << 16) | (quantizedG << 8) | quantizedB

            var bucket = buckets[key] ?? Bucket()
            bucket.count += 1
            bucket.red += red
            bucket.green += green
            bucket.blue += blue
            bucket.saturation += saturation
            buckets[key] = bucket
        }
    }

    let sortedCandidates = buckets.values
        .filter { $0.count > 4 }
        .sorted { lhs, rhs in
            if lhs.count == rhs.count {
                return lhs.saturation > rhs.saturation
            }
            return lhs.count > rhs.count
        }

    var selected: [UIColor] = []

    for candidate in sortedCandidates {
        let divisor = CGFloat(max(candidate.count, 1))
        let color = UIColor(
            red: candidate.red / divisor,
            green: candidate.green / divisor,
            blue: candidate.blue / divisor,
            alpha: 1.0
        )

        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil)

        let isDistinct = !selected.contains { existing in
            var existingHue: CGFloat = 0
            var existingSaturation: CGFloat = 0
            var existingBrightness: CGFloat = 0
            existing.getHue(&existingHue, saturation: &existingSaturation, brightness: &existingBrightness, alpha: nil)

            let hueDelta = min(abs(existingHue - hue), 1 - abs(existingHue - hue))
            let saturationDelta = abs(existingSaturation - saturation)
            let brightnessDelta = abs(existingBrightness - brightness)

            return hueDelta < 0.08 && saturationDelta < 0.16 && brightnessDelta < 0.16
        }

        if isDistinct {
            selected.append(color)
        }

        if selected.count == maxColors {
            break
        }
    }

    if selected.isEmpty {
        let averageColor = averageColorForStoryBackground(from: image)
        selected = [averageColor]
    }

    return Array(selected.prefix(maxColors))
}

private func averageColorForStoryBackground(from image: UIImage) -> UIColor {
    guard let ciImage = CIImage(image: image) else {
        return UIColor(Color(hex: "0B1215"))
    }

    let extentVector = CIVector(x: ciImage.extent.origin.x, y: ciImage.extent.origin.y, z: ciImage.extent.size.width, w: ciImage.extent.size.height)
    guard
        let filter = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: ciImage, kCIInputExtentKey: extentVector]),
        let outputImage = filter.outputImage
    else {
        return UIColor(Color(hex: "0B1215"))
    }

    var bitmap = [UInt8](repeating: 0, count: 4)
    let ciContext = CIContext(options: [.workingColorSpace: NSNull()])
    ciContext.render(outputImage, toBitmap: &bitmap, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)

    return UIColor(
        red: CGFloat(bitmap[0]) / 255.0,
        green: CGFloat(bitmap[1]) / 255.0,
        blue: CGFloat(bitmap[2]) / 255.0,
        alpha: 1.0
    )
}

func drawStoryMediaBackground(
    in rect: CGRect,
    palette: [UIColor],
    context: CGContext
) {
    let resolvedPalette = palette.isEmpty ? [UIColor(Color(hex: "0B1215"))] : palette

    if resolvedPalette.count == 1 {
        context.setFillColor(resolvedPalette[0].cgColor)
        context.fill(rect)
        return
    }

    let cgColors = resolvedPalette.map(\.cgColor) as CFArray
    let locations = stride(from: 0, to: resolvedPalette.count, by: 1).map { CGFloat($0) / CGFloat(max(resolvedPalette.count - 1, 1)) }
    let colorSpace = CGColorSpaceCreateDeviceRGB()

    if let gradient = CGGradient(colorsSpace: colorSpace, colors: cgColors, locations: locations) {
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.minX, y: rect.minY),
            end: CGPoint(x: rect.maxX, y: rect.maxY),
            options: []
        )
    } else {
        context.setFillColor(resolvedPalette[0].cgColor)
        context.fill(rect)
    }
}

struct StoryMediaBackgroundView: View {
    let palette: [UIColor]

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            context.withCGContext { cgContext in
                drawStoryMediaBackground(in: rect, palette: palette, context: cgContext)
            }
        }
    }
}

struct StoryEditableMediaContainer<Foreground: View>: View {
    let mediaSize: CGSize
    @Binding var scale: CGFloat
    @Binding var offset: CGSize
    @Binding var rotation: Angle
    let canvasSize: CGSize
    let paletteIdentity: String
    let paletteSourceImage: UIImage
    var isInteractionEnabled: Bool = true
    @ViewBuilder let foreground: (_ baseRect: CGRect) -> Foreground

    @State private var lastScale: CGFloat = 1.0
    @State private var lastOffset: CGSize = .zero
    @State private var lastRotation: Angle = .zero
    @State private var dominantColors: [UIColor] = []

    private var baseRect: CGRect {
        storyMediaBaseRect(mediaSize: mediaSize, canvasSize: canvasSize)
    }

    private var showsGeneratedBackground: Bool {
        storyShouldShowGeneratedBackground(scale: scale, offset: offset, rotation: rotation)
    }

    var body: some View {
        Group {
            if isInteractionEnabled {
                transformableBody
                    .gesture(dragGesture())
                    .simultaneousGesture(magnificationGesture())
                    .simultaneousGesture(rotationGesture())
            } else {
                transformableBody
            }
        }
        .task(id: paletteIdentity) {
            dominantColors = storyDominantBackgroundColors(from: paletteSourceImage)
        }
        .onAppear {
            lastScale = scale
            lastOffset = offset
            lastRotation = rotation
        }
    }

    private var transformableBody: some View {
        ZStack {
            StoryMediaBackgroundView(palette: dominantColors)
                .opacity(showsGeneratedBackground ? 1 : 0)

            foreground(baseRect)
                .frame(width: baseRect.width, height: baseRect.height)
                .scaleEffect(scale)
                .rotationEffect(rotation)
                .offset(offset)
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .contentShape(Rectangle())
    }

    private func dragGesture() -> some Gesture {
        DragGesture()
            .onChanged { value in
                let proposedOffset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
                offset = storyClampedMediaOffset(
                    proposedOffset,
                    canvasSize: canvasSize,
                    mediaSize: mediaSize,
                    scale: scale
                )
            }
            .onEnded { _ in
                offset = storyClampedMediaOffset(
                    offset,
                    canvasSize: canvasSize,
                    mediaSize: mediaSize,
                    scale: scale
                )
                lastOffset = offset
            }
    }

    private func magnificationGesture() -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let proposedScale = storyClampedMediaScale(lastScale * value)
                scale = proposedScale
                offset = storyClampedMediaOffset(
                    offset,
                    canvasSize: canvasSize,
                    mediaSize: mediaSize,
                    scale: proposedScale
                )
            }
            .onEnded { value in
                let resolvedScale = storySnappedMediaScale(storyClampedMediaScale(lastScale * value))
                scale = resolvedScale
                offset = storyClampedMediaOffset(
                    offset,
                    canvasSize: canvasSize,
                    mediaSize: mediaSize,
                    scale: resolvedScale
                )
                lastScale = resolvedScale
                lastOffset = offset
            }
    }

    private func rotationGesture() -> some Gesture {
        RotationGesture()
            .onChanged { value in
                rotation = lastRotation + value
            }
            .onEnded { value in
                let resolvedRotation = storySnappedMediaRotation(lastRotation + value)
                rotation = resolvedRotation
                lastRotation = resolvedRotation
            }
    }
}

struct EditableImageView: View {
    let image: UIImage
    @Binding var scale: CGFloat
    @Binding var offset: CGSize
    @Binding var rotation: Angle
    let filteredImage: UIImage?
    let canvasSize: CGSize
    var paletteIdentity: String
    var isInteractionEnabled: Bool = true

    init(
        image: UIImage,
        scale: Binding<CGFloat>,
        offset: Binding<CGSize>,
        rotation: Binding<Angle>,
        filteredImage: UIImage? = nil,
        canvasSize: CGSize,
        paletteIdentity: String,
        isInteractionEnabled: Bool = true
    ) {
        self.image = image
        self._scale = scale
        self._offset = offset
        self._rotation = rotation
        self.filteredImage = filteredImage
        self.canvasSize = canvasSize
        self.paletteIdentity = paletteIdentity
        self.isInteractionEnabled = isInteractionEnabled
    }

    var displayImage: UIImage {
        filteredImage ?? image
    }

    var body: some View {
        StoryEditableMediaContainer(
            mediaSize: displayImage.size,
            scale: $scale,
            offset: $offset,
            rotation: $rotation,
            canvasSize: canvasSize,
            paletteIdentity: paletteIdentity,
            paletteSourceImage: displayImage,
            isInteractionEnabled: isInteractionEnabled
        ) { baseRect in
            Image(uiImage: displayImage)
                .resizable()
                .aspectRatio(
                    contentMode: StoryMediaLayoutRules.presentationMode(
                        for: displayImage.size,
                        canvasSize: canvasSize
                    ).swiftUIContentMode
                )
                .frame(width: baseRect.width, height: baseRect.height)
        }
    }
}
