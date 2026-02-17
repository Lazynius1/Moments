import Foundation
import CryptoKit

class PersistentVideoCache {
    static let shared = PersistentVideoCache()
    
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    
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
            print("✅ Video guardado en cache persistente: \(filename)")
        } catch {
            print("❌ Error al guardar video en cache: \(error.localizedDescription)")
        }
    }
    
    /// Descarga un video en segundo plano para cachearlo
    func downloadAndCache(url: URL) {
        // Si ya está en cache, no descargar
        if cachedURL(for: url.absoluteString) != nil { return }
        
        URLSession.shared.downloadTask(with: url) { [weak self] localURL, _, error in
            guard let self = self, let localURL = localURL, error == nil else { return }
            self.saveToCache(temporaryURL: localURL, for: url.absoluteString)
        }.resume()
    }
    
    // Función helper para crear un nombre de archivo único basado en la URL
    private func hash(_ string: String) -> String {
        let data = Data(string.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}
