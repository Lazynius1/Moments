import Foundation
import AVFoundation

class VideoPreloader {
    static let shared = VideoPreloader()
    private var assetCache: [String: AVAsset] = [:]
    private var lastAccessDates: [String: Date] = [:]
    private let cacheLock = NSLock()
    private let queue = DispatchQueue(label: "com.moments.videoPreload", qos: .utility)
    private let maxCacheSize = 12
    
    private init() {}

    private func cachedAsset(for urlString: String) -> AVAsset? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if assetCache[urlString] != nil {
            lastAccessDates[urlString] = Date()
        }
        return assetCache[urlString]
    }

    private func setCachedAsset(_ asset: AVAsset?, for urlString: String) {
        cacheLock.lock()
        assetCache[urlString] = asset
        if asset != nil {
            lastAccessDates[urlString] = Date()
        } else {
            lastAccessDates.removeValue(forKey: urlString)
        }
        evictIfNeededLocked()
        cacheLock.unlock()
    }

    private func evictIfNeededLocked() {
        guard assetCache.count > maxCacheSize else { return }

        let sortedKeys = lastAccessDates.sorted { $0.value < $1.value }.map(\.key)
        let overflow = assetCache.count - maxCacheSize

        for key in sortedKeys.prefix(overflow) {
            assetCache.removeValue(forKey: key)
            lastAccessDates.removeValue(forKey: key)
        }
    }
    
    /// Carga playlist/tracks fuera del main. El `AVPlayerItem` se crea después, en main.
    func warmAsset(for urlString: String) async {
        if cachedAsset(for: urlString) != nil { return }
        guard let url = URL(string: urlString) else { return }

        let isHLS = VideoPlaybackSelector.shared.isHLSURLString(urlString)
        let asset: AVURLAsset
        if !isHLS, let localURL = PersistentVideoCache.shared.cachedURL(for: urlString) {
            asset = AVURLAsset(url: localURL)
        } else {
            asset = AVURLAsset(url: url)
        }

        _ = try? await asset.load(.isPlayable)
        _ = try? await asset.load(.duration)
        _ = try? await asset.load(.tracks)
        setCachedAsset(asset, for: urlString)
    }

    func preloadAssets(urls: [String]) {
        PerformanceSignposts.event("VideoPreloadBatch")
        queue.async { [weak self] in
            guard let self = self else { return }

            for urlString in urls.prefix(self.maxCacheSize) {
                if self.cachedAsset(for: urlString) != nil { continue }
                guard let url = URL(string: urlString) else { continue }

                let isHLS = VideoPlaybackSelector.shared.isHLSURLString(urlString)
                // HLS nunca desde disco: un `.m3u8` guardado como `.mp4` rompe segmentos relativos.
                if !isHLS, let localURL = PersistentVideoCache.shared.cachedURL(for: urlString) {
                    let asset = AVURLAsset(url: localURL)
                    self.setCachedAsset(asset, for: urlString)
                    continue
                }

                // Stream: calienta playlist (y el player bajará los primeros segmentos).
                // No downloadAndCache — el MP4 es fallback de reproducción, no caché del feed.
                let asset = AVURLAsset(url: url)
                Task {
                    _ = try? await asset.load(.isPlayable)
                    _ = try? await asset.load(.duration)
                    _ = try? await asset.load(.tracks)
                }
                self.setCachedAsset(asset, for: urlString)
            }
        }
    }
    
    func getPlayerItem(for urlString: String) -> AVPlayerItem {
        // Lectura no bloqueante respecto a la cola .utility (antes usaba queue.sync).
        let asset = cachedAsset(for: urlString)
        
        if let cachedAsset = asset {
            let item = AVPlayerItem(asset: cachedAsset)
            VideoPlaybackSelector.shared.configure(
                playerItem: item,
                tier: VideoPlaybackSelector.shared.recommendedTier()
            )
            return item
        }

        let isHLS = VideoPlaybackSelector.shared.isHLSURLString(urlString)
        if !isHLS, let localURL = PersistentVideoCache.shared.cachedURL(for: urlString) {
            let item = AVPlayerItem(url: localURL)
            item.preferredForwardBufferDuration = 0.5
            return item
        }
        
        return createNewItem(for: urlString)
    }
    
    private func createNewItem(for urlString: String) -> AVPlayerItem {
        guard let url = URL(string: urlString) else {
            return AVPlayerItem(url: URL(string: "http://invalid")!) 
        }
        let item = AVPlayerItem(url: url)
        VideoPlaybackSelector.shared.configure(
            playerItem: item,
            tier: VideoPlaybackSelector.shared.recommendedTier()
        )
        return item
    }
}
