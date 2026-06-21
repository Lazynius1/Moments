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
    
    func preloadAssets(urls: [String]) {
        PerformanceSignposts.event("VideoPreloadBatch")
        queue.async { [weak self] in
            guard let self = self else { return }

            // Cargar nuevos
            for urlString in urls.prefix(self.maxCacheSize) {
                if self.cachedAsset(for: urlString) == nil, let url = URL(string: urlString) {
                    // ✅ OFFLINE: Si ya está en disco, cargamos de local
                    if let localURL = PersistentVideoCache.shared.cachedURL(for: urlString) {
                        let asset = AVURLAsset(url: localURL)
                        self.setCachedAsset(asset, for: urlString)
                    } else {
                        // Si no está en disco, lo cargamos remoto y lo mandamos a descargar
                        let asset = AVURLAsset(url: url)
                        Task {
                            _ = try? await asset.load(.duration)
                            _ = try? await asset.load(.isPlayable)
                            _ = try? await asset.load(.tracks)
                        }
                        self.setCachedAsset(asset, for: urlString)
                        
                        // ✅ Descargar para futuras sesiones
                        PersistentVideoCache.shared.downloadAndCache(url: url)
                    }
                }
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
        
        // ✅ OFFLINE: Buscar en disco fuera del cache de memoria si no se precargó
        if let localURL = PersistentVideoCache.shared.cachedURL(for: urlString) {
            let item = AVPlayerItem(url: localURL)
            item.preferredForwardBufferDuration = 0.5 // Inicio inmediato desde disco
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
        
        // ✅ Descargar para futuras sesiones
        PersistentVideoCache.shared.downloadAndCache(url: url)
        
        return item
    }
}
