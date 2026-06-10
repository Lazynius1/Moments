import Foundation
import AVFoundation

class VideoPreloader {
    static let shared = VideoPreloader()
    private var assetCache: [String: AVAsset] = [:]
    private let queue = DispatchQueue(label: "com.moments.videoPreload", qos: .utility)
    private let maxCacheSize = 8
    
    private init() {}
    
    func preloadAssets(urls: [String]) {
        PerformanceSignposts.event("VideoPreloadBatch")
        queue.async { [weak self] in
            guard let self = self else { return }
            
            let urlsSet = Set(urls.prefix(self.maxCacheSize))
            
            // Limpiar cache antiguo
            self.assetCache = self.assetCache.filter { urlsSet.contains($0.key) }
            
            // Cargar nuevos
            for urlString in urls.prefix(self.maxCacheSize) {
                if self.assetCache[urlString] == nil, let url = URL(string: urlString) {
                    // ✅ OFFLINE: Si ya está en disco, cargamos de local
                    if let localURL = PersistentVideoCache.shared.cachedURL(for: urlString) {
                        let asset = AVURLAsset(url: localURL)
                        self.assetCache[urlString] = asset
                    } else {
                        // Si no está en disco, lo cargamos remoto y lo mandamos a descargar
                        let asset = AVURLAsset(url: url)
                        Task {
                            _ = try? await asset.load(.duration)
                            _ = try? await asset.load(.isPlayable)
                            _ = try? await asset.load(.tracks)
                        }
                        self.assetCache[urlString] = asset
                        
                        // ✅ Descargar para futuras sesiones
                        PersistentVideoCache.shared.downloadAndCache(url: url)
                    }
                }
            }
        }
    }
    
    func getPlayerItem(for urlString: String) -> AVPlayerItem {
        var asset: AVAsset?
        queue.sync {
            asset = assetCache[urlString]
        }
        
        if let cachedAsset = asset {
            let item = AVPlayerItem(asset: cachedAsset)
            item.preferredForwardBufferDuration = 2.5
            item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
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
        item.preferredForwardBufferDuration = 2.5
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
        
        // ✅ Descargar para futuras sesiones
        PersistentVideoCache.shared.downloadAndCache(url: url)
        
        return item
    }
}
