import Foundation
import SwiftUI

// ✅ CACHE MANAGER INTELIGENTE MEJORADO (estilo Instagram/TikTok)
class CacheManager: ObservableObject {
    static let shared = CacheManager()
    private let userDefaults = UserDefaults.standard
    private let lastCleanupKey = "LastCacheCleanupDate"
    private let maxCacheSize = 150 * 1024 * 1024  // ✅ AJUSTADO: 150MB (más conservador)
    private let warningThreshold = 100 * 1024 * 1024  // ✅ ALERTA: 100MB
    
    private init() {
        startIntelligentCleanup()
        setupAppStateObservers()
    }
    
    private func setupAppStateObservers() {
        // Android: App state observers will be handled natively
        // iOS-specific notification observers commented out for Android compatibility
        /*
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
        */
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
        // Verificar cada 12 horas (como Instagram)
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
        
        // Limpiar cada 12-24 horas (como Instagram)
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
        // Android: Cache cleanup will be handled natively
        // Kingfisher-specific cache cleanup commented out for Android compatibility
        /*
        // ✅ LIMPIEZA MENOS AGRESIVA: Solo borrar lo expirado
        let kingfisherCache = KingfisherManager.shared.cache
        
        // Solo forzar limpieza si es necesario
        if getCurrentCacheSize() > maxCacheSize {
            // ✅ BORRAR SOLO LO EXPIRADO, NO TODO
            kingfisherCache.clearMemoryCache()
            kingfisherCache.cleanExpiredDiskCache() // Solo lo expirado, no todo
        }
        */
    }
    
    private func cleanupUnusedCache() {
        // Limpiar URLCache no usado
        URLCache.shared.removeAllCachedResponses()
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
        // Android: Kingfisher cache size calculation will be handled natively
        let kingfisherSize = 0 // Placeholder - will be calculated on Android side
        // let kingfisherSize = Int((try? KingfisherManager.shared.cache.diskStorage.totalSize()) ?? 0)
        return urlCacheSize + kingfisherSize
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
