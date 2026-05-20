import SwiftUI
import UIKit

// MARK: - GIFCache para manejar cache de GIFs animados
class GIFCache {
    static let shared = GIFCache()
    
    private var cache = NSCache<NSURL, UIImage>()
    private let maxCacheSize = 50 // Máximo número de GIFs en cache
    
    private init() {
        cache.countLimit = maxCacheSize
        cache.totalCostLimit = 50 * 1024 * 1024 // 50MB máximo
    }
    
    func getGIF(for url: URL) -> UIImage? {
        return cache.object(forKey: url as NSURL)
    }
    
    func setGIF(_ image: UIImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL)
    }
    
    func clearCache() {
        cache.removeAllObjects()
    }
}

// MARK: - AnimatedStickerView para GIFs (Compartido)
struct AnimatedStickerView: UIViewRepresentable {
    let sticker: StickerItem
    let size: CGSize
    
    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.isUserInteractionEnabled = false // ✅ DESHABILITAR INTERACCIÓN PARA QUE LOS GESTOS PASEN AL PADRE
        imageView.frame = CGRect(origin: .zero, size: size)
        imageView.bounds = CGRect(origin: .zero, size: size)
        imageView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        imageView.setContentHuggingPriority(.defaultLow, for: .vertical)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        
        // ✅ USAR EL CACHE para evitar cargar múltiples veces
        if sticker.isAnimated, let gifURL = sticker.gifURL {
            if let cachedImage = GIFCache.shared.getGIF(for: gifURL) {
                imageView.image = cachedImage
            } else {
                // Solo cargar si no está en cache
                URLSession.shared.dataTask(with: gifURL) { data, response, error in
                    if let data = data, let animatedImage = UIImage.animatedImageWithData(data) {
                        GIFCache.shared.setGIF(animatedImage, for: gifURL)
                        DispatchQueue.main.async {
                            imageView.image = animatedImage
                        }
                    } else {
                        // Si falla el GIF, NO usar la imagen estática
                        DispatchQueue.main.async {
                            imageView.image = nil
                        }
                    }
                }.resume()
            }
        } else {
            imageView.image = sticker.image
        }
        
        return imageView
    }
    
    func updateUIView(_ uiView: UIImageView, context: Context) {
        uiView.frame = CGRect(origin: .zero, size: size)
        uiView.bounds = CGRect(origin: .zero, size: size)
        uiView.contentMode = .scaleAspectFit
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIImageView, context: Context) -> CGSize? {
        size
    }
}
