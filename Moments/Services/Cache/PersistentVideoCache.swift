import Foundation
import CryptoKit

class PersistentVideoCache {
    static let shared = PersistentVideoCache()
    
    private let fileManager = FileManager.default
    private let cacheDirectory: URL

    /// Tope total del caché de vídeo en disco.
    private let maxCacheBytes: Int = 500 * 1024 * 1024
    /// Descargas en curso, para no duplicar la misma URL.
    private var activeDownloads = Set<String>()
    private let lock = NSLock()
    
    private init() {
        // Carpeta en Caches para que no se suba a iCloud pero persista
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = caches.appendingPathComponent("MomentVideos", isDirectory: true)
        
        createDirectoryIfNeeded()
    }
    
    private func createDirectoryIfNeeded() {
        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }
    }
    
    /// Obtiene la URL local si el video está en cache
    func cachedURL(for remoteURLString: String) -> URL? {
        let filename = hash(remoteURLString) + ".mp4"
        let fileURL = cacheDirectory.appendingPathComponent(filename)
        
        if fileManager.fileExists(atPath: fileURL.path) {
            touch(fileURL)
            return fileURL
        }
        return nil
    }
    
    /// Guarda un archivo temporal en el cache persistente
    func saveToCache(temporaryURL: URL, for remoteURLString: String) {
        let filename = hash(remoteURLString) + ".mp4"
        let destinationURL = cacheDirectory.appendingPathComponent(filename)
        
        // Si ya existe, no hacemos nada
        if fileManager.fileExists(atPath: destinationURL.path) {
            return
        }
        
        do {
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
            // Actualizar fecha de acceso para LRU y aplicar tope de tamaño.
            touch(destinationURL)
            enforceSizeLimit()
            AppLog.debug("✅ Video guardado en cache persistente: \(filename)")
        } catch {
            AppLog.debug("❌ Error al guardar video en cache: \(error.localizedDescription)")
        }
    }
    
    /// Descarga un video en segundo plano para cachearlo (sin duplicar descargas)
    func downloadAndCache(url: URL) {
        let key = url.absoluteString

        // Si ya está en cache, no descargar
        if cachedURL(for: key) != nil { return }

        // Evitar lanzar la misma descarga varias veces concurrentemente.
        lock.lock()
        if activeDownloads.contains(key) {
            lock.unlock()
            return
        }
        activeDownloads.insert(key)
        lock.unlock()
        
        URLSession.shared.downloadTask(with: url) { [weak self] localURL, _, error in
            guard let self = self else { return }
            defer {
                self.lock.lock()
                self.activeDownloads.remove(key)
                self.lock.unlock()
            }
            guard let localURL = localURL, error == nil else { return }
            self.saveToCache(temporaryURL: localURL, for: key)
        }.resume()
    }

    /// Marca el archivo como accedido recientemente (para eviction LRU).
    private func touch(_ fileURL: URL) {
        try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: fileURL.path)
    }

    /// Mantiene el tamaño total bajo `maxCacheBytes`, borrando los archivos
    /// menos recientemente modificados (LRU).
    private func enforceSizeLimit() {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let files = try? fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: keys,
            options: .skipsHiddenFiles
        ) else { return }

        var entries: [(url: URL, size: Int, date: Date)] = files.compactMap { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            let size = values?.fileSize ?? 0
            let date = values?.contentModificationDate ?? .distantPast
            return (url, size, date)
        }

        var totalSize = entries.reduce(0) { $0 + $1.size }
        guard totalSize > maxCacheBytes else { return }

        // Borrar de más antiguo a más nuevo hasta volver bajo el tope.
        entries.sort { $0.date < $1.date }
        for entry in entries {
            if totalSize <= maxCacheBytes { break }
            try? fileManager.removeItem(at: entry.url)
            totalSize -= entry.size
        }
    }
    
    // Función helper para crear un nombre de archivo único basado en la URL
    private func hash(_ string: String) -> String {
        let data = Data(string.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}
