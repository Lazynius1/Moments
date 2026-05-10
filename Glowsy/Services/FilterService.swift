import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

class FilterService {
    static let shared = FilterService()
    private let context = CIContext(options: [.useSoftwareRenderer: false, .priorityRequestLow: true])

    enum FilterCategory {
        case basic
        case look
    }
    
    enum FilterType: String, CaseIterable {
        case normal = "Normal"
        case vivid = "Vivid"
        case chrome = "Chrome"
        case fade = "Fade"
        case instant = "Instant"
        case mono = "Mono"
        case noir = "Noir"
        case process = "Process"
        case tonal = "Tonal"
        case transfer = "Transfer"
        case sepia = "Sepia"
        case bloom = "Bloom"
        case cocoa = "Cocoa"
        case arctic = "Arctic"
        case ember = "Ember"
        case drift = "Drift"
        case muse = "Muse"
        case velvet = "Velvet"
        case slate = "Slate"
        case halo = "Halo"
        
        var filterName: String? {
            switch self {
            case .normal: return nil
            case .vivid: return "CIPhotoEffectVibrant"
            case .chrome: return "CIPhotoEffectChrome"
            case .fade: return "CIPhotoEffectFade"
            case .instant: return "CIPhotoEffectInstant"
            case .mono: return "CIPhotoEffectMono"
            case .noir: return "CIPhotoEffectNoir"
            case .process: return "CIPhotoEffectProcess"
            case .tonal: return "CIPhotoEffectTonal"
            case .transfer: return "CIPhotoEffectTransfer"
            case .sepia: return "CISepiaTone"
            case .bloom, .cocoa, .arctic, .ember, .drift, .muse, .velvet, .slate, .halo:
                return nil
            }
        }

        var category: FilterCategory {
            switch self {
            case .normal, .vivid, .chrome, .fade, .instant, .mono, .noir, .process, .tonal, .transfer, .sepia:
                return .basic
            case .bloom, .cocoa, .arctic, .ember, .drift, .muse, .velvet, .slate, .halo:
                return .look
            }
        }
    }

    var basicFilters: [FilterType] {
        FilterType.allCases.filter { $0.category == .basic }
    }

    var lookFilters: [FilterType] {
        FilterType.allCases.filter { $0.category == .look }
    }
    
    func applyFilter(_ type: FilterType, to image: UIImage, intensity: Double = 1.0) -> UIImage {
        let ciImage: CIImage
        if let existingCI = image.ciImage {
            ciImage = existingCI
        } else if let cgImage = image.cgImage {
            ciImage = CIImage(cgImage: cgImage)
        } else {
            return image
        }

        let finalOutput: CIImage
        if let filterName = type.filterName {
            guard let filter = CIFilter(name: filterName) else { return image }
            filter.setValue(ciImage, forKey: kCIInputImageKey)

            if type == .sepia {
                filter.setValue(intensity, forKey: kCIInputIntensityKey)
            }

            guard let filteredOutput = filter.outputImage else { return image }
            finalOutput = blendFilteredImage(filteredOutput, over: ciImage, intensity: type == .sepia ? 1.0 : intensity)
        } else {
            guard let customOutput = applyCustomFilter(type, to: ciImage, intensity: intensity) else { return image }
            finalOutput = customOutput
        }

        guard let cgImage = context.createCGImage(finalOutput, from: finalOutput.extent) else {
            return image
        }
        
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
    }
    
    // Optimized for previews
    func applyFilterToThumbnail(_ type: FilterType, to image: UIImage) -> UIImage {
        return applyFilter(type, to: image, intensity: 1.0)
    }

    private func blendFilteredImage(_ filteredOutput: CIImage, over original: CIImage, intensity: Double) -> CIImage {
        guard intensity < 0.999 else { return filteredOutput }

        let builder = CIFilter.sourceOverCompositing()
        let filterWithAlpha = filteredOutput.applyingFilter("CIColorMatrix", parameters: [
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(max(0.0, min(intensity, 1.0))))
        ])
        builder.inputImage = filterWithAlpha
        builder.backgroundImage = original
        return builder.outputImage ?? filteredOutput
    }

    private func applyCustomFilter(_ type: FilterType, to image: CIImage, intensity: Double) -> CIImage? {
        var output = image

        switch type {
        case .bloom:
            output = output
                .applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: 0.12])
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputSaturationKey: 0.92,
                    kCIInputBrightnessKey: 0.03,
                    kCIInputContrastKey: 0.9
                ])
                .applyingFilter("CIHighlightShadowAdjust", parameters: [
                    "inputHighlightAmount": 0.55,
                    "inputShadowAmount": 0.28
                ])
                .applyingFilter("CIVibrance", parameters: ["inputAmount": 0.18])

        case .cocoa:
            output = output
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputSaturationKey: 1.08,
                    kCIInputBrightnessKey: -0.01,
                    kCIInputContrastKey: 1.08
                ])
                .applyingFilter("CITemperatureAndTint", parameters: [
                    "inputNeutral": CIVector(x: 6500, y: 0),
                    "inputTargetNeutral": CIVector(x: 7200, y: 6)
                ])
                .applyingFilter("CISepiaTone", parameters: [kCIInputIntensityKey: 0.18])
                .applyingFilter("CIVignette", parameters: [
                    kCIInputIntensityKey: 0.28,
                    kCIInputRadiusKey: 1.25
                ])

        case .arctic:
            output = output
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputSaturationKey: 0.88,
                    kCIInputBrightnessKey: 0.01,
                    kCIInputContrastKey: 1.12
                ])
                .applyingFilter("CITemperatureAndTint", parameters: [
                    "inputNeutral": CIVector(x: 6500, y: 0),
                    "inputTargetNeutral": CIVector(x: 5000, y: -8)
                ])
                .applyingFilter("CIHighlightShadowAdjust", parameters: [
                    "inputHighlightAmount": 0.42,
                    "inputShadowAmount": 0.1
                ])

        case .ember:
            output = output
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputSaturationKey: 1.12,
                    kCIInputBrightnessKey: 0.02,
                    kCIInputContrastKey: 1.14
                ])
                .applyingFilter("CITemperatureAndTint", parameters: [
                    "inputNeutral": CIVector(x: 6500, y: 0),
                    "inputTargetNeutral": CIVector(x: 7600, y: 12)
                ])
                .applyingFilter("CIVibrance", parameters: ["inputAmount": 0.24])

        case .drift:
            output = output
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputSaturationKey: 0.78,
                    kCIInputBrightnessKey: 0.01,
                    kCIInputContrastKey: 0.92
                ])
                .applyingFilter("CITemperatureAndTint", parameters: [
                    "inputNeutral": CIVector(x: 6500, y: 0),
                    "inputTargetNeutral": CIVector(x: 5600, y: -6)
                ])
                .applyingFilter("CIHighlightShadowAdjust", parameters: [
                    "inputHighlightAmount": 0.35,
                    "inputShadowAmount": 0.32
                ])

        case .muse:
            output = output
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputSaturationKey: 1.02,
                    kCIInputBrightnessKey: 0.03,
                    kCIInputContrastKey: 0.94
                ])
                .applyingFilter("CITemperatureAndTint", parameters: [
                    "inputNeutral": CIVector(x: 6500, y: 0),
                    "inputTargetNeutral": CIVector(x: 6900, y: 14)
                ])
                .applyingFilter("CIVibrance", parameters: ["inputAmount": 0.12])

        case .velvet:
            output = output
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputSaturationKey: 0.96,
                    kCIInputBrightnessKey: -0.04,
                    kCIInputContrastKey: 1.16
                ])
                .applyingFilter("CIHueAdjust", parameters: [kCIInputAngleKey: 0.04])
                .applyingFilter("CIVignette", parameters: [
                    kCIInputIntensityKey: 0.34,
                    kCIInputRadiusKey: 1.3
                ])

        case .slate:
            output = output
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputSaturationKey: 0.52,
                    kCIInputBrightnessKey: -0.01,
                    kCIInputContrastKey: 1.18
                ])
                .applyingFilter("CITemperatureAndTint", parameters: [
                    "inputNeutral": CIVector(x: 6500, y: 0),
                    "inputTargetNeutral": CIVector(x: 5400, y: -4)
                ])

        case .halo:
            output = output
                .applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: 0.2])
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputSaturationKey: 1.06,
                    kCIInputBrightnessKey: 0.02,
                    kCIInputContrastKey: 0.88
                ])
                .applyingFilter("CIHighlightShadowAdjust", parameters: [
                    "inputHighlightAmount": 0.62,
                    "inputShadowAmount": 0.22
                ])
                .applyingFilter("CIVibrance", parameters: ["inputAmount": 0.14])

        case .normal, .vivid, .chrome, .fade, .instant, .mono, .noir, .process, .tonal, .transfer, .sepia:
            return nil
        }

        return blendFilteredImage(output, over: image, intensity: intensity)
    }
}
