import Foundation
import Kingfisher
import UIKit

/// Un gestor centralizado para la precarga (prefetching) de imágenes usando Kingfisher.
/// Este servicio evita que se envíen peticiones duplicadas a la red si una imagen ya se
/// está descargando o si ya está en caché, ahorrando ancho de banda y batería, mejorando
/// así la fluidez de la app (Scroll, Feed, etc.).
class ImagePrefetchManager {
    
    /// Instancia compartida (Singleton)
    static let shared = ImagePrefetchManager()
    
    // Cola de concurrencia para evitar problemas de hilos al acceder al estado interno
    private let queue = DispatchQueue(label: "com.glowsyapp.prefetching", attributes: .concurrent)
    
    // Almacenamos las URLs que ya estamos procesando para no instanciar ImagePrefetcher múltiples veces
    private var currentlyPrefetchingUrls: Set<URL> = []

    // Referencias a los prefetchers activos para poder cancelarlos de verdad.
    private var activePrefetchers: [ObjectIdentifier: ImagePrefetcher] = [:]

    /// Tope global de URLs en vuelo para acotar el ancho de banda en picos.
    private let maxInFlightUrls = 20
    
    private init() {}
    
    /// Inicia la precarga de una lista de URLs, ignorando las que ya están en proceso.
    /// - Parameter urls: Lista de URLs de imágenes a descargar.
    func prefetch(urls: [URL]) {
        guard !urls.isEmpty else { return }
        
        let imageURLs = urls.filter { !VideoPlaybackSelector.shared.isLikelyVideoURLString($0.absoluteString) }
        guard !imageURLs.isEmpty else { return }

        let urlsToProcess: [URL] = queue.sync(flags: .barrier) {
            // Respetar el tope global de URLs en vuelo.
            let availableSlots = max(0, self.maxInFlightUrls - self.currentlyPrefetchingUrls.count)
            guard availableSlots > 0 else { return [] }

            // Filtramos las URLs que ya estamos precargando en estos momentos
            let newUrls = imageURLs.filter { !self.currentlyPrefetchingUrls.contains($0) }
            let bounded = Array(newUrls.prefix(availableSlots))
            bounded.forEach { self.currentlyPrefetchingUrls.insert($0) }
            return bounded
        }
        
        // Si no hay nuevas (o no hay slots), no hacemos nada
        if urlsToProcess.isEmpty { return }
        
        // Comenzar la precarga de las nuevas URLs
        let retryStrategy = DelayRetryStrategy(maxRetryCount: 2, retryInterval: .seconds(2))
        // Prefetch a tamaño de card típico (píxeles), no full-res.
        let scale = UIApplication.shared.activeDisplayScale
        let targetSize = CGSize(width: 1080 * scale / 3, height: 1920 * scale / 3)
        weak var weakPrefetcher: ImagePrefetcher?
        let prefetcher = ImagePrefetcher(
            urls: urlsToProcess,
            options: [
                .retryStrategy(retryStrategy),
                .processor(DownsamplingImageProcessor(size: targetSize)),
                .scaleFactor(scale),
                .backgroundDecode
            ],
            completionHandler: { [weak self] skipped, failed, completed in
            // Cuando termine (independientemente si falla, se salta porque ya estaba en caché, o termina bien),
            // limpiamos las URLs del Set para liberar memoria y permitir futuros prefetchs si se borra el caché.
            guard let self else { return }
            self.queue.async(flags: .barrier) {
                // Removemos del set las que han terminado de ser procesadas
                let processedUrls = skipped + failed + completed
                let processedUrlSet = Set(processedUrls.compactMap { $0.downloadURL })
                
                self.currentlyPrefetchingUrls.subtract(processedUrlSet)
                if let finished = weakPrefetcher {
                    self.activePrefetchers.removeValue(forKey: ObjectIdentifier(finished))
                }
            }
        })
        weakPrefetcher = prefetcher

        // Retener el prefetcher para poder cancelarlo realmente en cancelAll().
        let key = ObjectIdentifier(prefetcher)
        queue.async(flags: .barrier) {
            self.activePrefetchers[key] = prefetcher
        }
        prefetcher.start()
    }
    
    /// Inicia la precarga usando un array de Strings
    /// - Parameter urlStrings: Lista de String URL
    func prefetch(urlStrings: [String]) {
        let urls = urlStrings.compactMap { URL(string: $0) }
        prefetch(urls: urls)
    }
    
    /// Cancela todas las descargas activas y limpia la cola local (Útil cuando te vas de una vista muy pesada)
    func cancelAll() {
        let prefetchers: [ImagePrefetcher] = queue.sync(flags: .barrier) {
            let values = Array(self.activePrefetchers.values)
            self.activePrefetchers.removeAll()
            self.currentlyPrefetchingUrls.removeAll()
            return values
        }
        // Detener de verdad las descargas en curso (antes solo se limpiaba el Set).
        prefetchers.forEach { $0.stop() }
    }
}
