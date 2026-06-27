import Foundation
import SwiftUI
import Kingfisher

// ✅ CACHE MANAGER INTELIGENTE MEJORADO
class CacheManager: ObservableObject {
    static let shared = CacheManager()
    private let userDefaults = UserDefaults.standard
    private let lastCleanupKey = "LastCacheCleanupDate"
    private let maxCacheSize = 2000 * 1024 * 1024  // ✅ 2GB
    private let warningThreshold = 1500 * 1024 * 1024  // ✅ 1.5GB
    
    private init() {
        startIntelligentCleanup()
        setupAppStateObservers()
    }
    
    private func setupAppStateObservers() {
        // ✅ CHECK CUANDO APP VUELVE DE BACKGROUND
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(checkCacheOnAppActivation),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        
        // ✅ NUEVO: Limpiar archivos temporales cuando la app va a background
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(cleanupOnBackground),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        
        // ✅ NUEVO: Limpiar archivos temporales cuando la app se cierra
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(cleanupOnTermination),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
    }
    
    @objc private func checkCacheOnAppActivation() {
        let currentSize = getCurrentCacheSize()
        if currentSize > warningThreshold {
            if currentSize > maxCacheSize {
                performIntelligentCleanup()
            }
        }
    }
    
    private func startIntelligentCleanup() {
        // Verificar cada 12 horas
        Timer.scheduledTimer(withTimeInterval: 12 * 60 * 60, repeats: true) { _ in
            self.performIntelligentCleanup()
        }
        
        // Limpieza inicial si es necesario
        if shouldPerformCleanup() {
            performIntelligentCleanup()
        }
    }
    
    private func shouldPerformCleanup() -> Bool {
        guard let lastCleanup = userDefaults.object(forKey: lastCleanupKey) as? Date else {
            return true
        }
        
        // Limpiar periódicamente (cada 12-24 horas)
        let oneDayAgo = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        return lastCleanup < oneDayAgo
    }
    
    private func performIntelligentCleanup() {
        let currentSize = getCurrentCacheSize()
        
        if currentSize > maxCacheSize {
            
            // ✅ LIMPIEZA INTELIGENTE: Solo borrar lo más antiguo y menos usado
            cleanupOldCache()
            cleanupUnusedCache()
            
        } else {
        }
        
        userDefaults.set(Date(), forKey: lastCleanupKey)
    }
    
    private func cleanupOldCache() {
        // ✅ LIMPIEZA MENOS AGRESIVA: Solo borrar lo expirado
        let kingfisherCache = KingfisherManager.shared.cache
        
        // Solo forzar limpieza si es necesario
        if getCurrentCacheSize() > maxCacheSize {
            // ✅ BORRAR SOLO LO EXPIRADO, NO TODO
            kingfisherCache.clearMemoryCache()
            kingfisherCache.cleanExpiredDiskCache() // Solo lo expirado, no todo
        }
    }
    
    private func cleanupUnusedCache() {
        // Limpiar URLCache no usado
        URLCache.shared.removeAllCachedResponses()
        
        // ✅ NUEVO: Limpiar videos antiguos del cache persistente
        cleanupVideoCache()
        cleanupAudioCache()
    }
    
    private func cleanupVideoCache() {
        let fileManager = FileManager.default
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let videoDir = caches.appendingPathComponent("MomentVideos")
        
        do {
            let files = try fileManager.contentsOfDirectory(at: videoDir, includingPropertiesForKeys: [.contentModificationDateKey])
            
            // Borrar videos con más de 7 días si estamos cerca del límite
            let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            
            for fileURL in files {
                let attributes = try fileURL.resourceValues(forKeys: [.contentModificationDateKey])
                if let modDate = attributes.contentModificationDate, modDate < sevenDaysAgo {
                    try? fileManager.removeItem(at: fileURL)
                }
            }
        } catch {
            // Silencio si no existe la carpeta o hay error
        }
    }

    private func cleanupAudioCache() {
        PersistentAudioCache.shared.cleanupFiles(olderThan: 7)
    }
    
    /// Limpia archivos temporales que pueden estar ocupando mucho espacio
    private func cleanupTemporaryFiles() {
        let fileManager = FileManager.default
        
        // Limpiar directorio temporal del sistema
        let tempDir = fileManager.temporaryDirectory
        do {
            let tempFiles = try fileManager.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: [.fileSizeKey, .creationDateKey])
            
            var totalSize: Int64 = 0
            var filesToDelete: [URL] = []
            
            for fileURL in tempFiles {
                // Solo considerar archivos de nuestra app (por nombre o extensión)
                let fileName = fileURL.lastPathComponent
                if fileName.contains("story_video") || 
                   fileName.contains("compressed_") ||
                   fileName.contains("thumbnail_") ||
                   fileName.contains("Glowsy") ||
                   fileName.hasSuffix(".mp4") ||
                   fileName.hasSuffix(".mov") ||
                   fileName.hasSuffix(".jpg") ||
                   fileName.hasSuffix(".jpeg") ||
                   fileName.hasSuffix(".m4a") ||
                   fileName.hasSuffix(".wav") {
                    
                    let attributes = try fileURL.resourceValues(forKeys: [.fileSizeKey, .creationDateKey])
                    if let fileSize = attributes.fileSize {
                        totalSize += Int64(fileSize)
                        
                        // Borrar archivos más antiguos de 30 minutos (más agresivo)
                        if let creationDate = attributes.creationDate,
                           Date().timeIntervalSince(creationDate) > 1800 { // 30 minutos
                            filesToDelete.append(fileURL)
                        }
                    }
                }
            }
            
            // Borrar archivos antiguos
            for fileURL in filesToDelete {
                try? fileManager.removeItem(at: fileURL)
            }
            
            if totalSize > 0 {
            }
            
        } catch {
        }
    }
    
    private func getCurrentCacheSize() -> Int {
        let urlCacheSize = URLCache.shared.currentDiskUsage
        let kingfisherSize = Int((try? KingfisherManager.shared.cache.diskStorage.totalSize()) ?? 0)
        let kingfisherMemoryCost = KingfisherManager.shared.cache.memoryStorage.totalCacheCost()
        
        // ✅ NUEVO: Incluir tamaño de los videos cacheados
        let videoCacheSize = getVideoCacheSize()
        let audioCacheSize = PersistentAudioCache.shared.cacheSizeInBytes()
        let chatMediaCacheSize = Int(ChatCacheStore.totalMediaBytes())

        _ = kingfisherMemoryCost // reservado para tuning futuro de RAM (Kingfisher 8.10+)
        return urlCacheSize + kingfisherSize + videoCacheSize + audioCacheSize + chatMediaCacheSize
    }
    
    private func getVideoCacheSize() -> Int {
        let fileManager = FileManager.default
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let videoDir = caches.appendingPathComponent("MomentVideos")
        
        var totalSize: Int = 0
        if let enumerator = fileManager.enumerator(at: videoDir, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let fileURL as URL in enumerator {
                if let attributes = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
                   let size = attributes.fileSize {
                    totalSize += size
                }
            }
        }
        return totalSize
    }
    
    func getCacheSize() -> String {
        let sizeInMB = getCurrentCacheSize() / (1024 * 1024)
        return "\(sizeInMB) MB"
    }
    
    // ✅ MÉTODO PÚBLICO: Limpieza manual si es necesario
    func forceCleanup() {
        cleanupOldCache()
        cleanupUnusedCache()
        userDefaults.set(Date(), forKey: lastCleanupKey)
    }
    
    /// Limpia archivos temporales cuando la app va a background
    @objc private func cleanupOnBackground() {
        cleanupTemporaryFiles()
    }
    
    /// Limpia archivos temporales cuando la app se cierra
    @objc private func cleanupOnTermination() {
        cleanupTemporaryFiles()
    }
}
