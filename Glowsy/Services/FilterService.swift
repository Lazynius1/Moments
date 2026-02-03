import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

class FilterService {
    static let shared = FilterService()
    private let context = CIContext(options: [.useSoftwareRenderer: false, .priorityRequestLow: true])
    
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
            }
        }
    }
    
    func applyFilter(_ type: FilterType, to image: UIImage, intensity: Double = 1.0) -> UIImage {
        guard let filterName = type.filterName else { return image }
        
        let ciImage: CIImage
        if let existingCI = image.ciImage {
            ciImage = existingCI
        } else if let cgImage = image.cgImage {
            ciImage = CIImage(cgImage: cgImage)
        } else {
            return image
        }
        
        guard let filter = CIFilter(name: filterName) else { return image }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        
        // Handle specialized intensity if filter supports it
        if type == .sepia {
            filter.setValue(intensity, forKey: kCIInputIntensityKey)
        }
        
        guard let filteredOutput = filter.outputImage else { return image }
        
        // Final output image
        let finalOutput: CIImage
        
        if intensity < 1.0 && type != .sepia {
            // Blend the filtered image with the original image based on intensity
            let builder = CIFilter.sourceOverCompositing()
            
            // To simulate intensity, we adjust the alpha of the filtered image
            let filterWithAlpha = filteredOutput.applyingFilter("CIColorMatrix", parameters: [
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(intensity))
            ])
            
            builder.inputImage = filterWithAlpha
            builder.backgroundImage = ciImage
            finalOutput = builder.outputImage ?? filteredOutput
        } else {
            finalOutput = filteredOutput
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
}
