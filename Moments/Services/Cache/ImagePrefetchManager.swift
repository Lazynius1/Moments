import Foundation
import Kingfisher

/// Un gestor centralizado para la precarga (prefetching) de imágenes usando Kingfisher.
/// Este servicio evita que se envíen peticiones duplicadas a la red si una imagen ya se
/// está descargando o si ya está en caché, ahorrando ancho de banda y batería, mejorando
/// así la fluidez de la app (Scroll, Feed, etc.).
class ImagePrefetchManager {
    
    /// Instancia compartida (Singleton)
    static let shared = ImagePrefetchManager()
    
    // Cola de concurrencia para evitar problemas de hilos al acceder al Set
    private let queue = DispatchQueue(label: "com.glowsyapp.prefetching", attributes: .concurrent)
    
    // Almacenamos las URLs que ya estamos procesando para no instanciar ImagePrefetcher múltiples veces
    private var currentlyPrefetchingUrls: Set<URL> = []
    
    private init() {}
    
    /// Inicia la precarga de una lista de URLs, ignorando las que ya están en proceso.
    /// - Parameter urls: Lista de URLs de imágenes a descargar.
    func prefetch(urls: [URL]) {
        guard !urls.isEmpty else { return }
        
        let urlsToProcess: [URL] = queue.sync {
            // Filtramos las URLs que ya estamos precargando en estos momentos
            let newUrls = urls.filter { !self.currentlyPrefetchingUrls.contains($0) }
            newUrls.forEach { self.currentlyPrefetchingUrls.insert($0) }
            return newUrls
        }
        
        // Si no hay nuevas, no hacemos nada
        if urlsToProcess.isEmpty { return }
        
        // Comenzar la precarga de las nuevas URLs
        let prefetcher = ImagePrefetcher(urls: urlsToProcess, completionHandler: { [self] skipped, failed, completed in
            // Cuando termine (independientemente si falla, se salta porque ya estaba en caché, o termina bien),
            // limpiamos las URLs del Set para liberar memoria y permitir futuros prefetchs si se borra el caché.
            
            self.queue.async(flags: .barrier) {
                // Removemos del set las que han terminado de ser procesadas
                let processedUrls = skipped + failed + completed
                let processedUrlSet = Set(processedUrls.compactMap { $0.downloadURL })
                
                self.currentlyPrefetchingUrls.subtract(processedUrlSet)
            }
        })
        
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
        queue.async(flags: .barrier) {
            self.currentlyPrefetchingUrls.removeAll()
        }
    }
}
