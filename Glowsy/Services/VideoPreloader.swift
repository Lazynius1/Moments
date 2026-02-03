import Foundation
import AVFoundation

class VideoPreloader {
    static let shared = VideoPreloader()
    private var assetCache: [String: AVAsset] = [:]
    private let queue = DispatchQueue(label: "com.moments.videoPreload", qos: .utility)
    private let maxCacheSize = 6
    
    private init() {}
    
    func preloadAssets(urls: [String]) {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            let urlsSet = Set(urls.prefix(self.maxCacheSize))
            
            // Limpiar cache antiguo
            self.assetCache = self.assetCache.filter { urlsSet.contains($0.key) }
            
            // Cargar nuevos
            for urlString in urls.prefix(self.maxCacheSize) {
                if self.assetCache[urlString] == nil, let url = URL(string: urlString) {
                    let asset = AVURLAsset(url: url)
                    let keys = ["duration", "playable", "tracks"]
                    
                    // Solo iniciamos la carga, el sistema hace el caching interno del asset
                    asset.loadValuesAsynchronously(forKeys: keys) {
                        // Opcional: Verificar éxito
                    }
                    self.assetCache[urlString] = asset
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
            // ✅ Buffer inicial optimizado: 2.5s para inicio rápido
            item.preferredForwardBufferDuration = 2.5
            item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
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
        return item
    }
}
