import SwiftUI

// MARK: - GIFCache para manejar cache de GIFs animados
// Android: GIF cache is disabled - GIF rendering will be handled natively
class GIFCache {
    static let shared = GIFCache()
    
    // Android: NSCache requires NSObject subclass, so we use a simple dictionary instead
    private var cache: [URL: NSObject] = [:]
    private let maxCacheSize = 50 // Máximo número de GIFs en cache
    
    private init() {}
    
    func getGIF(for url: URL) -> Any? {
        // Android: GIF retrieval will be handled natively
        return cache[url]
    }
    
    func setGIF(_ image: Any, for url: URL) {
        // Android: GIF caching will be handled natively
        if cache.count >= maxCacheSize {
            // Simple LRU: remove first entry if cache is full
            if let firstKey = cache.keys.first {
                cache.removeValue(forKey: firstKey)
            }
        }
        if let imageObj = image as? NSObject {
            cache[url] = imageObj
        }
    }
    
    func clearCache() {
        cache.removeAll()
    }
}

// MARK: - AnimatedStickerView para GIFs (Compartido)
// Android: Replaced UIViewRepresentable with simple SwiftUI view
struct AnimatedStickerView: View {
    let sticker: StickerItem
    let size: CGSize
    
    var body: some View {
        // Android: Animated GIF rendering will be handled natively
        // Placeholder view for compilation
        Rectangle()
            .fill(Color.gray.opacity(0.3))
            .frame(width: size.width, height: size.height)
            .overlay(
                Image(systemName: "photo")
                    .foregroundColor(.gray)
            )
        
        /*
        // iOS-specific UIViewRepresentable code commented out for Android compatibility
        func makeUIView(context: Context) -> UIImageView {
            let imageView = UIImageView()
            imageView.contentMode = .scaleAspectFit
            imageView.clipsToBounds = true
            imageView.isUserInteractionEnabled = false
            
            if sticker.isAnimated, let gifURL = sticker.gifURL {
                if let cachedImage = GIFCache.shared.getGIF(for: gifURL) {
                    imageView.image = cachedImage
                } else {
                    URLSession.shared.dataTask(with: gifURL) { data, response, error in
                        if let data = data, let animatedImage = UIImage.animatedImageWithData(data) {
                            GIFCache.shared.setGIF(animatedImage, for: gifURL)
                            DispatchQueue.main.async {
                                imageView.image = animatedImage
                            }
                        } else {
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
        }
        */
    }
} 