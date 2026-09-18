import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

enum PhotoEditTab: String {
    case filter
    case edit
}

enum TiltShiftMode: String, Equatable {
    case radial
    case linear
}

enum PhotoTintTarget: String, Equatable {
    case shadows
    case highlights
}

enum PhotoTintColor: String, CaseIterable, Identifiable {
    case yellow, orange, red, pink, purple, blue, cyan, green

    var id: String { rawValue }

    var uiColor: UIColor {
        switch self {
        case .yellow: return UIColor(red: 0.96, green: 0.84, blue: 0.22, alpha: 1)
        case .orange: return UIColor(red: 0.96, green: 0.55, blue: 0.13, alpha: 1)
        case .red: return UIColor(red: 0.90, green: 0.22, blue: 0.21, alpha: 1)
        case .pink: return UIColor(red: 0.95, green: 0.38, blue: 0.62, alpha: 1)
        case .purple: return UIColor(red: 0.56, green: 0.27, blue: 0.68, alpha: 1)
        case .blue: return UIColor(red: 0.20, green: 0.48, blue: 0.86, alpha: 1)
        case .cyan: return UIColor(red: 0.18, green: 0.80, blue: 0.76, alpha: 1)
        case .green: return UIColor(red: 0.22, green: 0.80, blue: 0.45, alpha: 1)
        }
    }
}

enum PhotoAdjustAxis: String, CaseIterable, Identifiable {
    case straighten
    case vertical
    case horizontal

    var id: String { rawValue }
    var titleKey: String { "creator.adjust.\(rawValue)" }
    var systemImage: String {
        switch self {
        case .straighten: return "rotate.right"
        case .vertical: return "trapezoid.and.line.vertical"
        case .horizontal: return "trapezoid.and.line.horizontal"
        }
    }
}

enum PhotoEditTool: String, CaseIterable, Identifiable {
    case adjust
    case lux
    case brightness
    case contrast
    case texture
    case warmth
    case saturation
    case color
    case fade
    case highlights
    case shadows
    case vignette
    case blur
    case sharpen

    var id: String { rawValue }
    var titleKey: String { "creator.adjust.\(rawValue)" }

    var systemImage: String {
        switch self {
        case .adjust: return "trapezoid.and.line.vertical"
        case .lux: return "sun.max.fill"
        case .brightness: return "sun.max"
        case .contrast: return "circle.lefthalf.filled"
        case .texture: return "triangle.fill"
        case .warmth: return "thermometer.medium"
        case .saturation: return "drop.halffull"
        case .color: return "paintpalette.fill"
        case .fade: return "circle.dotted"
        case .highlights: return "sun.min"
        case .shadows: return "moon.fill"
        case .vignette: return "circle.circle"
        case .blur: return "circle.dashed"
        case .sharpen: return "diamond.fill"
        }
    }

    var usesZeroToHundred: Bool {
        switch self {
        case .lux, .texture, .fade, .vignette, .sharpen, .blur, .color:
            return true
        default:
            return false
        }
    }
}

struct PhotoEdits: Equatable {
    var filter: FilterService.FilterType = .normal
    var filterIntensity: Double = 1.0

    var straighten: Double = 0
    var verticalPerspective: Double = 0
    var horizontalPerspective: Double = 0

    var lux: Double = 0
    var brightness: Double = 0
    var contrast: Double = 0
    var texture: Double = 0
    var warmth: Double = 0
    var saturation: Double = 0
    var fade: Double = 0
    var highlights: Double = 0
    var shadows: Double = 0
    var vignette: Double = 0
    var sharpen: Double = 0

    var tintTarget: PhotoTintTarget = .shadows
    var shadowTint: PhotoTintColor? = nil
    var highlightTint: PhotoTintColor? = nil
    var shadowTintAmount: Double = 0.5
    var highlightTintAmount: Double = 0.5

    var tiltShiftMode: TiltShiftMode? = nil
    var tiltShiftAmount: Double = 0.5
    var tiltShiftCenter: CGPoint = CGPoint(x: 0.5, y: 0.5)
    var tiltShiftRadius: Double = 0.28
    var tiltShiftAngle: Double = 0

    var isIdentity: Bool {
        filter == .normal
            && !hasGeometry
            && lux == 0
            && abs(brightness) < 0.001
            && abs(contrast) < 0.001
            && texture == 0
            && abs(warmth) < 0.001
            && abs(saturation) < 0.001
            && fade == 0
            && abs(highlights) < 0.001
            && abs(shadows) < 0.001
            && vignette == 0
            && sharpen == 0
            && shadowTint == nil
            && highlightTint == nil
            && (tiltShiftMode == nil || tiltShiftAmount < 0.001)
    }

    var hasGeometry: Bool {
        abs(straighten) > 0.001
            || abs(verticalPerspective) > 0.001
            || abs(horizontalPerspective) > 0.001
    }

    func isApplied(_ tool: PhotoEditTool) -> Bool {
        switch tool {
        case .adjust: return hasGeometry
        case .lux: return lux > 0.001
        case .brightness: return abs(brightness) > 0.001
        case .contrast: return abs(contrast) > 0.001
        case .texture: return texture > 0.001
        case .warmth: return abs(warmth) > 0.001
        case .saturation: return abs(saturation) > 0.001
        case .color: return shadowTint != nil || highlightTint != nil
        case .fade: return fade > 0.001
        case .highlights: return abs(highlights) > 0.001
        case .shadows: return abs(shadows) > 0.001
        case .vignette: return vignette > 0.001
        case .blur: return tiltShiftMode != nil && tiltShiftAmount > 0.001
        case .sharpen: return sharpen > 0.001
        }
    }

    func canReset(tab: PhotoEditTab, tool: PhotoEditTool?, axis: PhotoAdjustAxis) -> Bool {
        switch tab {
        case .filter:
            return filter != .normal
        case .edit:
            guard let tool else { return false }
            switch tool {
            case .adjust:
                switch axis {
                case .straighten: return abs(straighten) > 0.001
                case .vertical: return abs(verticalPerspective) > 0.001
                case .horizontal: return abs(horizontalPerspective) > 0.001
                }
            case .color:
                return tintTarget == .shadows ? shadowTint != nil : highlightTint != nil
            default:
                return isApplied(tool)
            }
        }
    }

    mutating func reset(tab: PhotoEditTab, tool: PhotoEditTool?, axis: PhotoAdjustAxis) {
        switch tab {
        case .filter:
            filter = .normal
            filterIntensity = 1
        case .edit:
            guard let tool else { return }
            switch tool {
            case .adjust:
                switch axis {
                case .straighten: straighten = 0
                case .vertical: verticalPerspective = 0
                case .horizontal: horizontalPerspective = 0
                }
            case .lux: lux = 0
            case .brightness: brightness = 0
            case .contrast: contrast = 0
            case .texture: texture = 0
            case .warmth: warmth = 0
            case .saturation: saturation = 0
            case .color:
                if tintTarget == .shadows {
                    shadowTint = nil
                    shadowTintAmount = 0.5
                } else {
                    highlightTint = nil
                    highlightTintAmount = 0.5
                }
            case .fade: fade = 0
            case .highlights: highlights = 0
            case .shadows: shadows = 0
            case .vignette: vignette = 0
            case .blur:
                tiltShiftMode = nil
                tiltShiftAmount = 0.5
                tiltShiftCenter = CGPoint(x: 0.5, y: 0.5)
                tiltShiftRadius = 0.28
                tiltShiftAngle = 0
            case .sharpen: sharpen = 0
            }
        }
    }
}

extension FilterService {
    func applyPhotoEdits(_ edits: PhotoEdits, to image: UIImage) -> UIImage {
        if edits.isIdentity { return image }

        var working = image
        if edits.hasGeometry {
            working = render(applyGeometry(edits, to: ciImage(from: working)), from: working) ?? working
        }
        if edits.filter != .normal {
            working = applyFilter(edits.filter, to: working, intensity: edits.filterIntensity)
        }
        return render(applyAdjustments(edits, to: ciImage(from: working)), from: working) ?? working
    }

    private func ciImage(from image: UIImage) -> CIImage {
        if let cgImage = image.cgImage {
            return CIImage(cgImage: cgImage)
        }
        if let ciImage = image.ciImage {
            return ciImage
        }
        return CIImage(image: image) ?? CIImage.empty()
    }

    private func render(_ ciImage: CIImage, from original: UIImage) -> UIImage? {
        let extent = ciImage.extent.integral
        guard !extent.isEmpty, let cgImage = context.createCGImage(ciImage, from: extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage, scale: original.scale, orientation: original.imageOrientation)
    }

    private func applyGeometry(_ edits: PhotoEdits, to image: CIImage) -> CIImage {
        var output = image
        let extent = image.extent
        let center = CGPoint(x: extent.midX, y: extent.midY)

        if abs(edits.straighten) > 0.001 {
            let angle = edits.straighten * 45 * .pi / 180
            let cover = abs(sin(angle)) + abs(cos(angle))
            var transform = CGAffineTransform(translationX: center.x, y: center.y)
            transform = transform.rotated(by: CGFloat(angle))
            transform = transform.scaledBy(x: cover, y: cover)
            transform = transform.translatedBy(x: -center.x, y: -center.y)
            output = output.transformed(by: transform)
        }

        output = output.cropped(to: extent)

        if abs(edits.verticalPerspective) > 0.001 || abs(edits.horizontalPerspective) > 0.001 {
            let v = edits.verticalPerspective * extent.width * 0.22
            let h = edits.horizontalPerspective * extent.height * 0.22
            output = output.applyingFilter("CIPerspectiveTransform", parameters: [
                "inputTopLeft": CIVector(x: extent.minX + v, y: extent.maxY - h),
                "inputTopRight": CIVector(x: extent.maxX - v, y: extent.maxY + h),
                "inputBottomLeft": CIVector(x: extent.minX - v, y: extent.minY + h),
                "inputBottomRight": CIVector(x: extent.maxX + v, y: extent.minY - h)
            ])
        }

        return output.cropped(to: extent)
    }

    private func applyAdjustments(_ edits: PhotoEdits, to image: CIImage) -> CIImage {
        var output = image
        let extent = image.extent

        if edits.lux > 0.001 {
            output = output.applyingFilter("CIHighlightShadowAdjust", parameters: [
                "inputHighlightAmount": 1.0 - edits.lux * 0.12,
                "inputShadowAmount": edits.lux * 0.48
            ])
            output = output.applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 1 + edits.lux * 0.1,
                kCIInputBrightnessKey: edits.lux * 0.03,
                kCIInputContrastKey: 1 + edits.lux * 0.16
            ])
            output = output.applyingFilter("CIVibrance", parameters: ["inputAmount": edits.lux * 0.22])
            output = output.applyingFilter("CIUnsharpMask", parameters: [
                kCIInputRadiusKey: 1.8,
                kCIInputIntensityKey: edits.lux * 0.38
            ])
        }

        if abs(edits.brightness) > 0.001 || abs(edits.contrast) > 0.001 || abs(edits.saturation) > 0.001 {
            output = output.applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 1 + edits.saturation * 0.55,
                kCIInputBrightnessKey: edits.brightness * 0.28,
                kCIInputContrastKey: 1 + edits.contrast * 0.38
            ])
        }

        if edits.texture > 0.001 {
            output = output.applyingFilter("CIUnsharpMask", parameters: [
                kCIInputRadiusKey: 2.8,
                kCIInputIntensityKey: edits.texture * 1.05
            ])
        }

        if abs(edits.warmth) > 0.001 {
            output = output.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: 6500, y: 0),
                "inputTargetNeutral": CIVector(x: 6500 - edits.warmth * 2100, y: edits.warmth * 8)
            ])
        }

        if abs(edits.highlights) > 0.001 || abs(edits.shadows) > 0.001 {
            output = output.applyingFilter("CIHighlightShadowAdjust", parameters: [
                "inputHighlightAmount": 1 - max(0, -edits.highlights) * 0.72,
                "inputShadowAmount": edits.shadows * 0.85
            ])
            if edits.highlights > 0.001 {
                output = output.applyingFilter("CIExposureAdjust", parameters: [
                    kCIInputEVKey: edits.highlights * 0.18
                ])
            }
        }

        if let tint = edits.shadowTint {
            output = applySplitTone(to: output, color: tint.uiColor, amount: edits.shadowTintAmount, highlights: false)
        }
        if let tint = edits.highlightTint {
            output = applySplitTone(to: output, color: tint.uiColor, amount: edits.highlightTintAmount, highlights: true)
        }

        if edits.fade > 0.001 {
            let lift = edits.fade * 0.16
            output = output.applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 1 - edits.fade * 0.22,
                kCIInputBrightnessKey: edits.fade * 0.06,
                kCIInputContrastKey: 1 - edits.fade * 0.3
            ])
            output = output.applyingFilter("CIColorMatrix", parameters: [
                "inputBiasVector": CIVector(x: lift, y: lift, z: lift, w: 0)
            ])
        }

        if edits.vignette > 0.001 {
            output = output.applyingFilter("CIVignette", parameters: [
                kCIInputIntensityKey: edits.vignette * 1.35,
                kCIInputRadiusKey: 1.4
            ])
        }

        if edits.sharpen > 0.001 {
            output = output.applyingFilter("CISharpenLuminance", parameters: [
                kCIInputSharpnessKey: edits.sharpen * 0.9
            ])
        }

        if let mode = edits.tiltShiftMode, edits.tiltShiftAmount > 0.001 {
            output = applyTiltShift(edits, mode: mode, to: output, extent: extent)
        }

        return output.cropped(to: extent)
    }

    private func applySplitTone(to image: CIImage, color: UIColor, amount: Double, highlights: Bool) -> CIImage {
        let extent = image.extent
        let ciColor = CIColor(color: color)
        let luma = image.applyingFilter("CIColorMonochrome", parameters: [
            kCIInputColorKey: CIColor.white,
            kCIInputIntensityKey: 1.0
        ])
        var mask = highlights ? luma : luma.applyingFilter("CIColorInvert")
        mask = mask.applyingFilter("CIColorControls", parameters: [
            kCIInputContrastKey: 1.4
        ])
        mask = mask.applyingFilter("CIColorMatrix", parameters: [
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(amount))
        ])
        let tint = CIImage(color: ciColor).cropped(to: extent)
        let overlay = image.applyingFilter("CIOverlayBlendMode", parameters: [
            kCIInputBackgroundImageKey: tint
        ])
        return overlay.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: image,
            kCIInputMaskImageKey: mask
        ])
    }

    private func applyTiltShift(_ edits: PhotoEdits, mode: TiltShiftMode, to image: CIImage, extent: CGRect) -> CIImage {
        let blurred = image
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [
                kCIInputRadiusKey: edits.tiltShiftAmount * 22
            ])
            .cropped(to: extent)

        let width = extent.width
        let height = extent.height
        let cx = extent.minX + edits.tiltShiftCenter.x * width
        let cy = extent.minY + (1 - edits.tiltShiftCenter.y) * height
        let radius = edits.tiltShiftRadius * min(width, height)

        let mask: CIImage
        switch mode {
        case .radial:
            let gradient = CIFilter.radialGradient()
            gradient.center = CGPoint(x: cx, y: cy)
            gradient.radius0 = Float(radius * 0.52)
            gradient.radius1 = Float(radius)
            gradient.color0 = CIColor(red: 1, green: 1, blue: 1, alpha: 1)
            gradient.color1 = CIColor(red: 0, green: 0, blue: 0, alpha: 1)
            mask = (gradient.outputImage ?? image).cropped(to: extent)
        case .linear:
            let nx = cos(edits.tiltShiftAngle)
            let ny = sin(edits.tiltShiftAngle)
            let inner = radius * 0.18
            let gradA = CIFilter.linearGradient()
            gradA.point0 = CGPoint(x: cx - nx * radius, y: cy - ny * radius)
            gradA.point1 = CGPoint(x: cx - nx * inner, y: cy - ny * inner)
            gradA.color0 = CIColor(red: 0, green: 0, blue: 0, alpha: 1)
            gradA.color1 = CIColor(red: 1, green: 1, blue: 1, alpha: 1)
            let gradB = CIFilter.linearGradient()
            gradB.point0 = CGPoint(x: cx + nx * radius, y: cy + ny * radius)
            gradB.point1 = CGPoint(x: cx + nx * inner, y: cy + ny * inner)
            gradB.color0 = CIColor(red: 0, green: 0, blue: 0, alpha: 1)
            gradB.color1 = CIColor(red: 1, green: 1, blue: 1, alpha: 1)
            let a = (gradA.outputImage ?? image).cropped(to: extent)
            let b = (gradB.outputImage ?? image).cropped(to: extent)
            mask = a.applyingFilter("CIMultiplyBlendMode", parameters: [
                kCIInputBackgroundImageKey: b
            ])
        }

        return image.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: blurred,
            kCIInputMaskImageKey: mask
        ])
    }
}
