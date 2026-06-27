import Foundation
import AVFoundation
import UIKit

/// Genera y cachea una portada (poster) a partir de un vídeo cuando no existe una
/// miniatura subida. Funciona con file:// (vídeo descifrado en caché) o URLs remotas.
enum ChatVideoPosterGenerator {
    private static let memoryCache = NSCache<NSString, NSString>()

    static func poster(for videoURL: URL, messageId: String) async -> String? {
        let cacheKey = messageId as NSString
        if let cached = memoryCache.object(forKey: cacheKey) as String?,
           let cachedURL = URL(string: cached),
           FileManager.default.fileExists(atPath: cachedURL.path) {
            return cached
        }

        let diskURL = ChatCacheStore.posterURL(for: messageId)
        if FileManager.default.fileExists(atPath: diskURL.path) {
            let absolute = diskURL.absoluteString
            memoryCache.setObject(absolute as NSString, forKey: cacheKey)
            return absolute
        }

        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 720, height: 1280)

        let frameCandidates = [
            CMTime(seconds: 0.15, preferredTimescale: 600),
            CMTime(seconds: 0.0, preferredTimescale: 600),
            CMTime(seconds: 0.5, preferredTimescale: 600)
        ]

        for time in frameCandidates {
            guard let (image, _) = try? await generator.image(at: time),
                  let data = UIImage(cgImage: image).jpegData(compressionQuality: 0.78) else {
                continue
            }
            do {
                try ChatCacheStore.ensureDirectories()
                try data.write(to: diskURL, options: .atomic)
                let absolute = diskURL.absoluteString
                memoryCache.setObject(absolute as NSString, forKey: cacheKey)
                await MainActor.run { ChatCacheStore.enforceQuota() }
                return absolute
            } catch {
                return nil
            }
        }
        return nil
    }

    static func cachedPosterURL(messageId: String) -> URL? {
        let url = ChatCacheStore.posterURL(for: messageId)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
