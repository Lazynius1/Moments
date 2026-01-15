import AVFoundation

class VideoPreloader {
    static let shared = VideoPreloader()
    private var cache: [String: AVPlayerItem] = [:]
    private let queue = DispatchQueue(label: "com.glowsy.videoPreload", qos: .utility)
    
    // Configuración
    private let maxCacheSize = 5 // Mantener los próximos 5 videos listos
    
    private init() {}
    
    func preload(urls: [String]) {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            // 1. Limpieza inteligente: Eliminar items que ya no están en la lista de interés
            // (Mantenemos un margen de seguridad para no borrar el video actual si se scrollea un poco arriba/abajo)
            let urlsKeepSet = Set(urls)
            var cleanCache: [String: AVPlayerItem] = [:]
            
            for (url, item) in self.cache {
                if urlsKeepSet.contains(url) {
                    cleanCache[url] = item
                } else {
                    // Cancelar carga si es posible (no hay API directa para cancelar, pero liberamos la referencia)
                    // En implementaciones más complejas se usaría AVAssetResourceLoaderDelegate
                }
            }
            self.cache = cleanCache
            
            // 2. Cargar nuevos videos (solo los primeros 'maxCacheSize')
            let upcomingUrls = urls.prefix(self.maxCacheSize)
            
            for urlString in upcomingUrls {
                if self.cache[urlString] == nil, let url = URL(string: urlString) {
                    let asset = AVURLAsset(url: url)
                    let keys = ["duration", "playable", "tracks"]
                    
                    // Carga asíncrona de claves para tener el item listo
                    asset.loadValuesAsynchronously(forKeys: keys) {
                        let item = AVPlayerItem(asset: asset, automaticallyLoadedAssetKeys: keys)
                        item.preferredForwardBufferDuration = 5.0 // Buffer agresivo
                        
                        // Guardar en cache (thread-safe sync no es estrictamente necesario si solo escribimos aquí, 
                        // pero para lectura desde UI sí podría serlo. Usamos el serial queue por simplicidad lógica,
                        // pero la escritura final la hacemos en el bloque)
                        self.queue.async {
                            self.cache[urlString] = item
                        }
                    }
                }
            }
        }
    }
    
    // Obtener item cacheado (si existe) o crear uno nuevo
    func getItem(for urlString: String) -> AVPlayerItem {
        // Acceso sincronizado para evitar data races
        var cachedItem: AVPlayerItem?
        queue.sync {
            cachedItem = cache[urlString]
        }
        
        if let item = cachedItem {
            // Importante: Un AVPlayerItem solo puede usarse en un AVPlayer a la vez.
            // Si el item ya fue usado y falló o terminó, mejor recrearlo o resetearlo.
            // Para este caso simple, devolvemos una COPIA (recreando desde el asset source) 
            // O devolvemos el mismo si asumimos que el preloader gestiona items únicos.
            // AVPlayerItem tiene estado. Si lo usamos en un player y luego scrolleamos y volvemos, 
            // el item puede estar "finished".
            
            if item.status == .failed {
                // Si falló, reintentar creación
                return createNewItem(for: urlString)
            }
            
            // Copiar estrategia: AVPlayerItem no es copiable fácilmente (`copy()` da error).
            // Lo ideal es cachear el AVAsset y crear el PlayerItem on demand.
            // MODIFICACIÓN: Cambiemos el cache a [String: AVAsset] para más seguridad
            // O, simplemente devolver el item y verificar si se puede reusar.
            // Dado que TikTok/Reels recrean la celda, el uso único está bien si limpiamos el cache correctamente.
            // Si el item ya tiene un player asociado, necesitamos uno nuevo.
            
            return item
        }
        
        return createNewItem(for: urlString)
    }
    
    private func createNewItem(for urlString: String) -> AVPlayerItem {
        guard let url = URL(string: urlString) else {
            // Fallback dummy (no debería pasar si la URL es válida)
            return AVPlayerItem(url: URL(string: "http://invalid")!) 
        }
        let item = AVPlayerItem(url: url)
        item.preferredForwardBufferDuration = 5.0
        return item
    }
    
    // Método refinado: Cachear AVAssets en lugar de AVPlayerItems
    // Los AVPlayerItems tienen estado (time, status) y no se deben reusar entre players fácilmente.
    // Los AVAssets sí se pueden reusar y mantienen la data descargada.
    private var assetCache: [String: AVAsset] = [:]
    
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
            item.preferredForwardBufferDuration = 5.0
            return item
        }
        
        // Fallback
        return createNewItem(for: urlString)
    }
}
