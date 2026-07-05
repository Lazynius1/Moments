import AVFoundation
import CryptoKit
import UIKit

// Cachea en memoria y disco los thumbnails generados en cliente para videos
// legacy sin thumbnailUrl, evitando re-descargar bytes del video por celda.
final class VideoThumbnailCache {
    static let shared = VideoThumbnailCache()

    private let memoryCache = NSCache<NSString, UIImage>()
    private let directory: URL

    private init() {
        memoryCache.countLimit = 150
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appendingPathComponent("VideoThumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func cachedThumbnail(for urlString: String) -> UIImage? {
        memoryCache.object(forKey: urlString as NSString)
    }

    func thumbnail(for urlString: String) async -> UIImage? {
        if let hit = memoryCache.object(forKey: urlString as NSString) {
            return hit
        }

        let file = fileURL(for: urlString)
        if let data = try? Data(contentsOf: file), let image = UIImage(data: data) {
            memoryCache.setObject(image, forKey: urlString as NSString)
            return image
        }

        guard let url = URL(string: urlString) else { return nil }
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 480)

        guard let (cgImage, _) = try? await generator.image(at: CMTime(seconds: 0.8, preferredTimescale: 600)) else {
            return nil
        }

        let image = UIImage(cgImage: cgImage)
        memoryCache.setObject(image, forKey: urlString as NSString)
        if let data = image.jpegData(compressionQuality: 0.8) {
            try? data.write(to: file, options: .atomic)
        }
        return image
    }

    private func fileURL(for urlString: String) -> URL {
        let digest = SHA256.hash(data: Data(urlString.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined().prefix(40)
        return directory.appendingPathComponent("\(name).jpg")
    }
}
