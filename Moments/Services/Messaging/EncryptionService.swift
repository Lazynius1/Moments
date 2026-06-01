// MARK: - 📊 ENHANCED SUPPORTING TYPES
struct EncryptionMetrics {
    var successfulEncryptions: Int = 0
    var successfulDecryptions: Int = 0
    var encryptionErrors: Int = 0
    var decryptionErrors: Int = 0
    var cacheHits: Int = 0
    var keychainHits: Int = 0
    var firestoreHits: Int = 0
    var firestoreErrors: Int = 0
    var newKeysCreated: Int = 0
    var keyRotations: Int = 0
    var batchPreloadRequests: Int = 0
    var averagePreloadTime: Double = 0.0
    var initializationErrors: Int = 0
    var toggleEvents: Int = 0
    var fullResets: Int = 0
    var cacheLoadTime: Double = 0.0
    var totalKeysLoaded: Int = 0
    var lastError: String?
    
    var totalOperations: Int {
        successfulEncryptions + successfulDecryptions + encryptionErrors + decryptionErrors
    }
    
    var successRate: Double {
        guard totalOperations > 0 else { return 1.0 }
        return Double(successfulEncryptions + successfulDecryptions) / Double(totalOperations)
    }
    
    var cacheEfficiency: Double {
        let totalHits = cacheHits + keychainHits + firestoreHits
        guard totalHits > 0 else { return 0.0 }
        return Double(cacheHits) / Double(totalHits)
    }
}

struct KeychainStatistics {
    let userKeysInKeychain: Int
    let conversationKeysInKeychain: Int
    let otherKeysInKeychain: Int
    let totalSizeBytes: Int
    let userKeysInCache: Int
    let conversationKeysInCache: Int
    
    init(userKeysInKeychain: Int = 0, conversationKeysInKeychain: Int = 0, otherKeysInKeychain: Int = 0, totalSizeBytes: Int = 0, userKeysInCache: Int = 0, conversationKeysInCache: Int = 0) {
        self.userKeysInKeychain = userKeysInKeychain
        self.conversationKeysInKeychain = conversationKeysInKeychain
        self.otherKeysInKeychain = otherKeysInKeychain
        self.totalSizeBytes = totalSizeBytes
        self.userKeysInCache = userKeysInCache
        self.conversationKeysInCache = conversationKeysInCache
    }
    
    var totalKeysInKeychain: Int {
        userKeysInKeychain + conversationKeysInKeychain + otherKeysInKeychain
    }
    
    var totalKeysInCache: Int {
        userKeysInCache + conversationKeysInCache
    }
    
    var cacheToKeychainRatio: Double {
        guard totalKeysInKeychain > 0 else { return 0.0 }
        return Double(totalKeysInCache) / Double(totalKeysInKeychain)
    }
    
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB]
        return formatter.string(fromByteCount: Int64(totalSizeBytes))
    }
    
    var healthStatus: String {
        if cacheToKeychainRatio > 0.9 {
            return "✅ Excelente sincronización"
        } else if cacheToKeychainRatio > 0.7 {
            return "⚠️ Buena sincronización"
        } else {
            return "❌ Baja sincronización"
        }
    }
}

struct CacheStatistics {
    let userKeysCached: Int
    let conversationKeysCached: Int
    let expiredKeys: Int
    let activePreloadTasks: Int
}

struct DetailedEncryptionInfo {
    let isEnabled: Bool
    let status: EncryptionStatus
    let userKeysCount: Int
    let conversationKeysCount: Int
    let hasValidMasterKey: Bool
    let metrics: EncryptionMetrics
    let cacheStatistics: CacheStatistics
    let keyVersions: [String: Int]
    
    var statusDescription: String {
        if !isEnabled {
            return "🔒 Encriptación deshabilitada"
        }
        
        switch status {
        case .ready:
            return "✅ Activa y funcionando (\(String(format: "%.1f", metrics.successRate * 100))% éxito)"
        case .initializing:
            return "⏳ Inicializando sistema de encriptación..."
        case .degraded(let issue):
            return "⚠️ Funcionando con problemas: \(issue) (\(String(format: "%.1f", metrics.successRate * 100))% éxito)"
        case .error(let message):
            return "❌ Error: \(message)"
        }
    }
    
    var performanceReport: String {
        return """
        📊 Reporte de Rendimiento:
        • Operaciones totales: \(metrics.totalOperations)
        • Tasa de éxito: \(String(format: "%.1f", metrics.successRate * 100))%
        • Eficiencia de caché: \(String(format: "%.1f", metrics.cacheEfficiency * 100))%
        • Claves en caché: \(cacheStatistics.userKeysCached + cacheStatistics.conversationKeysCached)
        • Tiempo promedio de precarga: \(String(format: "%.2f", metrics.averagePreloadTime))s
        • Rotaciones de claves: \(metrics.keyRotations)
        """
    }
}

// MARK: - 🔄 ENHANCED STATUS ENUM
enum EncryptionStatus: Equatable {
    case ready
    case initializing
    case degraded(String) // Funcionando pero con problemas
    case error(String)
    
    var description: String {
        switch self {
        case .ready:
            return "Listo"
        case .initializing:
            return "Inicializando..."
        case .degraded(let issue):
            return "Funcionando (⚠️ \(issue))"
        case .error(let message):
            return "Error: \(message)"
        }
    }
    
    var isOperational: Bool {
        switch self {
        case .ready, .degraded:
            return true
        case .initializing, .error:
            return false
        }
    }
}

// MARK: - 🚨 ENHANCED ERROR HANDLING
enum EncryptionError: LocalizedError, Equatable {
    case invalidInput
    case encryptionFailed
    case decryptionFailed
    case invalidPIN
    case recoveryLocked(TimeInterval)
    case keychainError(String)
    case keyNotFound
    case timeout
    case networkError(String)
    case keyCorrupted
    case versionMismatch(String)
    case concurrencyError
    case quotaExceeded
    
    var errorDescription: String? {
        switch self {
        case .invalidInput:
            return "Datos de entrada inválidos para encriptación"
        case .encryptionFailed:
            return "Error en el proceso de encriptación"
        case .decryptionFailed:
            return "Error en el proceso de desencriptación"
        case .invalidPIN:
            return NSLocalizedString("chatRecovery.error.invalidPin", comment: "Incorrect recovery PIN")
        case .recoveryLocked(let remainingSeconds):
            let totalSeconds = max(1, Int(ceil(remainingSeconds)))
            let minutes = totalSeconds / 60
            let seconds = totalSeconds % 60
            return String(
                format: NSLocalizedString("chatRecovery.error.locked", comment: "Recovery locked"),
                String(format: "%d:%02d", minutes, seconds)
            )
        case .keychainError(let message):
            return "Error en Keychain: \(message)"
        case .keyNotFound:
            return "Clave de encriptación no encontrada"
        case .timeout:
            return "Timeout al obtener clave de encriptación"
        case .networkError(let message):
            return "Error de red: \(message)"
        case .keyCorrupted:
            return "Clave de encriptación corrompida"
        case .versionMismatch(let version):
            return "Versión de clave incompatible: \(version)"
        case .concurrencyError:
            return "Error de concurrencia en acceso a claves"
        case .quotaExceeded:
            return "Cuota de operaciones excedida"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .keyCorrupted, .versionMismatch:
            return "Intenta rotar la clave de la conversación"
        case .invalidPIN:
            return NSLocalizedString("chatRecovery.error.invalidPinSuggestion", comment: "Verify the recovery PIN and try again")
        case .recoveryLocked:
            return NSLocalizedString("chatRecovery.error.lockedSuggestion", comment: "Wait before retrying the recovery PIN")
        case .timeout, .networkError:
            return "Verifica tu conexión a internet"
        case .keychainError:
            return "Reinicia la app e intenta de nuevo"
        case .quotaExceeded:
            return "Espera unos minutos antes de intentar de nuevo"
        default:
            return "Contacta soporte si el problema persiste"
        }
    }
    
    var severity: ErrorSeverity {
        switch self {
        case .keyCorrupted, .versionMismatch:
            return .high
        case .keychainError, .concurrencyError:
            return .medium
        case .timeout, .networkError:
            return .low
        default:
            return .medium
        }
    }
}

enum ErrorSeverity {
    case low, medium, high
    
    var emoji: String {
        switch self {
        case .low: return "⚠️"
        case .medium: return "🚨"
        case .high: return "🔥"
        }
    }
}

// MARK: - 🎯 EXTENSION para Better UX
extension EncryptionService {
    
    /// 🚀 Encrypt multiple messages in batch for better performance
    func encryptChatMessagesBatch(_ messages: [(text: String, conversationId: String)]) async -> [String?] {
        await withTaskGroup(of: (Int, String?).self, returning: [String?].self) { group in
            
            for (index, message) in messages.enumerated() {
                group.addTask {
                    let encrypted = await self.encryptChatMessage(message.text, for: message.conversationId)
                    return (index, encrypted)
                }
            }
            
            var results: [String?] = Array(repeating: nil, count: messages.count)
            for await (index, encrypted) in group {
                results[index] = encrypted
            }
            
            await updateMetrics { $0.successfulEncryptions += results.compactMap { $0 }.count }
            return results
        }
    }
    
    /// 🔍 Health check for encryption system
    func performHealthCheck() async -> EncryptionHealthReport {
        var report = EncryptionHealthReport()
        
        // Test master key
        report.masterKeyStatus = masterKey != nil ? .healthy : .unhealthy("Master key missing")
        
        // Test cache performance
        let cacheTestStart = Date()
        let testConversationId = "health_check_test"
        
        do {
            _ = try await getConversationKey(for: testConversationId)
            report.cachePerformance = Date().timeIntervalSince(cacheTestStart)
            await deleteConversationKeys(for: testConversationId)
        } catch {
            report.cachePerformance = -1
            report.lastError = error.localizedDescription
        }
        
        // Test encryption/decryption
        let testMessage = "health_check_\(Date().timeIntervalSince1970)"
        let testKey = SymmetricKey(size: .bits256)
        do {
            let encrypted = try encrypt(text: testMessage, with: testKey)
            let decrypted = try decrypt(encryptedText: encrypted, with: testKey)
            report.encryptionStatus = decrypted == testMessage ? .healthy : .unhealthy("Encryption test failed")
        } catch {
            report.encryptionStatus = .unhealthy("Encryption error: \(error.localizedDescription)")
        }
        
        // Check keychain accessibility
        do {
            let testKey = SymmetricKey(size: .bits256)
            try storeKeyInKeychain(key: testKey, tag: "health_check_keychain")
            _ = try retrieveKeyFromKeychain(tag: "health_check_keychain")
            report.keychainStatus = .healthy
            
            // Cleanup
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: keyChainService,
                kSecAttrAccount as String: "health_check_keychain"
            ]
            SecItemDelete(query as CFDictionary)
        } catch {
            report.keychainStatus = .unhealthy("Keychain error: \(error.localizedDescription)")
        }
        
        // Memory usage analysis
        report.memoryUsage = calculateMemoryUsage()
        
        // Overall health
        report.overallHealth = determineOverallHealth(report)
        
        return report
    }
    
    private func calculateMemoryUsage() -> MemoryUsage {
        let userKeysMemory = userKeys.count * 32 // Approximate 32 bytes per key
        let conversationKeysMemory = conversationKeys.count * 32
        let totalMemory = userKeysMemory + conversationKeysMemory
        
        return MemoryUsage(
            userKeys: userKeysMemory,
            conversationKeys: conversationKeysMemory,
            total: totalMemory,
            isHealthy: totalMemory < 1024 * 1024 // Less than 1MB is healthy
        )
    }
    
    private func determineOverallHealth(_ report: EncryptionHealthReport) -> HealthStatus {
        let criticalComponents = [
            report.masterKeyStatus,
            report.encryptionStatus,
            report.keychainStatus
        ]
        
        if criticalComponents.allSatisfy({ $0.isHealthy }) {
            return report.cachePerformance < 1.0 ? .healthy : .degraded("Cache performance slow")
        } else {
            return .unhealthy("Critical components failing")
        }
    }
    
    /// 🎨 Generate encryption metrics for UI dashboard
    func getMetricsForDashboard() async -> DashboardMetrics {
        let info = await getDetailedEncryptionInfo()
        
        return DashboardMetrics(
            encryptionInfo: info,
            recentErrors: getRecentErrors(),
            performanceTrends: getPerformanceTrends(),
            securityScore: calculateSecurityScore(info)
        )
    }
    
    private func getRecentErrors() -> [ErrorEvent] {
        // In a real implementation, you'd maintain a circular buffer of recent errors
        return []
    }
    
    private func getPerformanceTrends() -> PerformanceTrends {
        return PerformanceTrends(
            encryptionLatency: [], // Would track recent latencies
            cacheHitRate: [], // Would track cache performance over time
            errorRate: [] // Would track error rates
        )
    }
    
    private func calculateSecurityScore(_ info: DetailedEncryptionInfo) -> SecurityScore {
        var score = 100
        
        // Deduct points for errors
        if info.metrics.encryptionErrors > 0 {
            score -= min(20, info.metrics.encryptionErrors * 2)
        }
        
        // Deduct points for old keys
        if info.cacheStatistics.expiredKeys > 0 {
            score -= min(10, info.cacheStatistics.expiredKeys)
        }
        
        // Bonus for recent key rotations
        if info.metrics.keyRotations > 0 {
            score = min(100, score + 5)
        }
        
        return SecurityScore(
            value: max(0, score),
            grade: gradeFromScore(score),
            recommendations: generateSecurityRecommendations(info)
        )
    }
    
    private func gradeFromScore(_ score: Int) -> String {
        switch score {
        case 90...100: return "A+"
        case 80...89: return "A"
        case 70...79: return "B"
        case 60...69: return "C"
        default: return "D"
        }
    }
    
    private func generateSecurityRecommendations(_ info: DetailedEncryptionInfo) -> [String] {
        var recommendations: [String] = []
        
        if info.metrics.keyRotations == 0 {
            recommendations.append("Considera rotar claves periódicamente")
        }
        
        if info.cacheStatistics.expiredKeys > 0 {
            recommendations.append("Limpia claves expiradas regularmente")
        }
        
        if info.metrics.encryptionErrors > info.metrics.successfulEncryptions / 10 {
            recommendations.append("Investiga errores de encriptación frecuentes")
        }
        
        return recommendations
    }
}

// MARK: - 📊 SUPPORTING TYPES for Enhanced Features
struct EncryptionHealthReport {
    var masterKeyStatus: HealthStatus = .unknown
    var encryptionStatus: HealthStatus = .unknown
    var keychainStatus: HealthStatus = .unknown
    var cachePerformance: TimeInterval = 0
    var memoryUsage: MemoryUsage = MemoryUsage(userKeys: 0, conversationKeys: 0, total: 0, isHealthy: true)
    var overallHealth: HealthStatus = .unknown
    var lastError: String?
    var timestamp: Date = Date()
}

enum HealthStatus {
    case healthy
    case degraded(String)
    case unhealthy(String)
    case unknown
    
    var isHealthy: Bool {
        switch self {
        case .healthy: return true
        default: return false
        }
    }
    
    var emoji: String {
        switch self {
        case .healthy: return "✅"
        case .degraded: return "⚠️"
        case .unhealthy: return "❌"
        case .unknown: return "❓"
        }
    }
    
    var description: String {
        switch self {
        case .healthy: return "Sistema saludable"
        case .degraded(let message): return "Degradado: \(message)"
        case .unhealthy(let message): return "No saludable: \(message)"
        case .unknown: return "Estado desconocido"
        }
    }
}

struct MemoryUsage {
    let userKeys: Int
    let conversationKeys: Int
    let total: Int
    let isHealthy: Bool
    
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        return formatter.string(fromByteCount: Int64(total))
    }
}

struct DashboardMetrics {
    let encryptionInfo: DetailedEncryptionInfo
    let recentErrors: [ErrorEvent]
    let performanceTrends: PerformanceTrends
    let securityScore: SecurityScore
}

struct ErrorEvent {
    let timestamp: Date
    let error: EncryptionError
    let context: String
}

struct PerformanceTrends {
    let encryptionLatency: [TimeInterval]
    let cacheHitRate: [Double]
    let errorRate: [Double]
}

struct SecurityScore {
    let value: Int
    let grade: String
    let recommendations: [String]
    
    var color: String {
        switch value {
        case 90...100: return "green"
        case 70...89: return "yellow"
        case 50...69: return "orange"
        default: return "red"
        }
    }
}
import Foundation
import CryptoKit
import Security
import FirebaseAuth
import FirebaseFirestore

// MARK: - EncryptionService ULTRA OPTIMIZADO para Moments 🚀
@MainActor
class EncryptionService: ObservableObject {
    static let shared = EncryptionService()
    
    // MARK: - Constants
    private let keyChainService = "com.Momentsapp.encryption.v2"
    private let masterKeyTag = "master_encryption_key_v2"
    private let userKeysPrefix = "user_key_v2_"
    private let conversationKeysPrefix = "conversation_key_v2_"
    private let keyMetadataPrefix = "key_metadata_"
    private let chatIdentityKeyPrefix = "chat_identity_private_v1_"
    private let chatIdentityKeyIdPrefix = "chat_identity_key_id_v1_"
    private let chatRecoveryMarkerPrefix = "chat_recovery_marker_v1_"
    private let chatRecoveryAttemptsPrefix = "chat_recovery_attempts_v1_"
    private let chatRecoveryLockoutPrefix = "chat_recovery_lockout_v1_"
    private let chatRecoveryMaxAttempts = 5
    private let chatRecoveryLockoutDuration: TimeInterval = 5 * 60
    private let chatWrapInfo = Data("moments.chat.wrap.v1".utf8)
    private let db = Firestore.firestore()
    
    // MARK: - Published Properties
    @Published var isEncryptionEnabled: Bool = true
    @Published var encryptionStatus: EncryptionStatus = .ready
    @Published var encryptionMetrics: EncryptionMetrics = EncryptionMetrics()
    @Published var enhancedEncryptionMetrics: EnhancedEncryptionMetrics = EnhancedEncryptionMetrics()
    
    // MARK: - Private Properties
    private var masterKey: SymmetricKey?
    private var userKeys: [String: CachedKey] = [:]
    private var conversationKeys: [String: CachedKey] = [:]
    private let keyAccessQueue = DispatchQueue(label: "encryption.keys", qos: .userInitiated)
    private var preloadTasks: [String: Task<SymmetricKey, Error>] = [:]
    
    // MARK: - 🔑 Enhanced Key Structure (FIXED)
    private struct CachedKey {
        let key: SymmetricKey
        let createdAt: Date
        var lastUsed: Date
        let version: String
        var usageCount: Int
        
        init(key: SymmetricKey, version: String = "2.0") {
            self.key = key
            self.version = version
            let now = Date()
            self.createdAt = now
            self.lastUsed = now
            self.usageCount = 0
        }
        
        mutating func markUsed() {
            usageCount += 1
            lastUsed = Date()
        }
        
        var isExpired: Bool {
            // Claves expiran después de 30 días sin uso
            Date().timeIntervalSince(lastUsed) > 30 * 24 * 60 * 60
        }
    }
    
    // MARK: - 📊 MÉTRICAS MEJORADAS PARA ROBUSTEZ (FIXED - Moved outside CachedKey)
    struct EnhancedEncryptionMetrics {
        // Métricas existentes básicas
        var successfulEncryptions: Int = 0
        var successfulDecryptions: Int = 0
        var encryptionErrors: Int = 0
        var decryptionErrors: Int = 0
        var cacheHits: Int = 0
        var keychainHits: Int = 0
        var firestoreHits: Int = 0
        var firestoreErrors: Int = 0
        var newKeysCreated: Int = 0
        var keyRotations: Int = 0
        
        // Nuevas métricas de robustez
        var deviceRecoveries: Int = 0
        var firstInstalls: Int = 0
        var recoveryErrors: Int = 0
        var keyRecoveryFailures: Int = 0
        var validatedKeys: Int = 0
        var corruptedKeys: Int = 0
        var emergencyRotations: Int = 0
        var backupLocationHits: Int = 0
        var legacyLocationHits: Int = 0
        var initializationErrors: Int = 0
        var lastRecoveryDate: Date?
        var lastError: String?
        
        var recoverySuccessRate: Double {
            let totalRecoveries = deviceRecoveries + recoveryErrors
            guard totalRecoveries > 0 else { return 1.0 }
            return Double(deviceRecoveries) / Double(totalRecoveries)
        }
        
        var keyIntegrityRate: Double {
            let totalValidated = validatedKeys + corruptedKeys
            guard totalValidated > 0 else { return 1.0 }
            return Double(validatedKeys) / Double(totalValidated)
        }
        
        var robustnessScore: Int {
            var score = 100
            
            // Deduct for recovery failures
            if recoveryErrors > 0 {
                score -= min(30, recoveryErrors * 10)
            }
            
            // Deduct for corrupted keys
            if corruptedKeys > 0 {
                score -= min(20, corruptedKeys * 5)
            }
            
            // Bonus for successful recoveries
            if deviceRecoveries > 0 {
                score = min(100, score + 10)
            }
            
            return max(0, score)
        }
    }
    
    // MARK: - Key Metadata
    private struct KeyMetadata: Codable {
        let keyId: String
        let createdAt: Date
        let version: String
        let deviceId: String
        let lastRotation: Date?
        
        init(keyId: String, version: String = "2.0", deviceId: String) {
            self.keyId = keyId
            self.version = version
            self.createdAt = Date()
            self.deviceId = deviceId
            self.lastRotation = nil
        }
    }

    private struct LocalChatIdentity {
        let record: ChatIdentityRecord
        let privateKey: Curve25519.KeyAgreement.PrivateKey
    }
    
    // MARK: - Initialization
    private init() {
        Task {
            await setupEncryptionRobust()
            await cleanupExpiredKeys()
            
            // Iniciar schedule de métricas
            startMetricsUploadSchedule()
        }
    }
    
    // MARK: - 🛡️ SISTEMA 100% ROBUSTO - Como WhatsApp
    private func setupEncryptionRobust() async {
        encryptionStatus = .initializing
        
        do {
            // 1. Setup básico
            masterKey = try await getOrCreateMasterKey()
            
            // 2. Sistema de recuperación
            await setupRecoverySystem()
            
            // 3. Cargar claves
            await loadCachedKeys()
            
            // 4. Limpieza
            await scanAndCleanupKeychain()
            
            encryptionStatus = .ready
            
        } catch {
            encryptionStatus = .error(error.localizedDescription)
            isEncryptionEnabled = false
            
            await updateEnhancedMetrics { metrics in
                metrics.initializationErrors += 1
                metrics.lastError = error.localizedDescription
            }
        }
    }
    
    // MARK: - 🚀 RECOVERY SYSTEM ULTRA ROBUSTO
    private func setupRecoverySystem() async {
        await detectAndRecoverFromDeviceChange()
        await validateExistingKeys()
        await syncWithFirestore()
    }
    
    // MARK: - ✅ VALIDAR CLAVES EXISTENTES
    private func validateExistingKeys() async {
        
        var validKeys = 0
        var invalidKeys = 0
        
        // Validar user keys
        for (userId, cachedKey) in userKeys {
            if await isKeyValid(cachedKey.key) {
                validKeys += 1
            } else {
                invalidKeys += 1
                // Eliminar clave inválida
                userKeys.removeValue(forKey: userId)
                await cleanupKeychainKey(tag: userKeysPrefix + userId)
            }
        }
        
        // Validar conversation keys
        for (conversationId, cachedKey) in conversationKeys {
            if await isKeyValid(cachedKey.key) {
                validKeys += 1
            } else {
                invalidKeys += 1
                await handleCorruptedKey(conversationId: conversationId)
            }
        }
        
        
        await updateEnhancedMetrics { metrics in
            metrics.validatedKeys = validKeys
            metrics.corruptedKeys = invalidKeys
        }
    }
    
    // MARK: - 🔑 HELPER: Verificar si una clave es válida
    private func isKeyValid(_ key: SymmetricKey) async -> Bool {
        do {
            let testMessage = "validation_test_\(Date().timeIntervalSince1970)"
            let encrypted = try encrypt(text: testMessage, with: key)
            let decrypted = try decrypt(encryptedText: encrypted, with: key)
            return decrypted == testMessage
        } catch {
            return false
        }
    }
    
    // MARK: - 📱 DETECCIÓN DE CAMBIO DE DISPOSITIVO
    private func detectAndRecoverFromDeviceChange() async {
        let currentDeviceId = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        let storedDeviceId = UserDefaults.standard.string(forKey: "encryption_device_id")
        let isFirstInstall = storedDeviceId == nil
        
        if isFirstInstall {
            UserDefaults.standard.set(currentDeviceId, forKey: "encryption_device_id")
            UserDefaults.standard.set(Date(), forKey: "encryption_first_install")
            await updateEnhancedMetrics { $0.firstInstalls += 1 }
        } else if storedDeviceId != currentDeviceId {
            await performDeviceRecovery(oldDeviceId: storedDeviceId ?? "unknown", newDeviceId: currentDeviceId)
            UserDefaults.standard.set(currentDeviceId, forKey: "encryption_device_id")
        } else {
        }
    }
    
    // MARK: - 🔄 RECUPERACIÓN TOTAL DE DISPOSITIVO
    private func performDeviceRecovery(oldDeviceId: String, newDeviceId: String) async {
        
        encryptionStatus = .degraded("Recuperando claves del dispositivo anterior")
        
        await updateEnhancedMetrics {
            $0.deviceRecoveries += 1
            $0.lastRecoveryDate = Date()
        }
        
        // 1. Recuperar todas las conversaciones del usuario
        await recoverAllUserConversations()
        
        // 2. Validar integridad de claves recuperadas
        await validateRecoveredKeys()
        
        encryptionStatus = .ready
    }
    
    // MARK: - 🔍 RECUPERAR TODAS LAS CONVERSACIONES
    private func recoverAllUserConversations() async {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            return
        }
        
        
        do {
            // Obtener todas las conversaciones del usuario
            let conversationsSnapshot = try await db.collection("conversations")
                .whereField("participants", arrayContains: currentUserId)
                .getDocuments()
            
            
            // Recuperar claves en paralelo
            await withTaskGroup(of: Void.self) { group in
                for document in conversationsSnapshot.documents {
                    group.addTask {
                        await self.recoverConversationKey(
                            conversationId: document.documentID,
                            conversationData: document.data()
                        )
                    }
                }
            }
            
            
        } catch {
            await updateEnhancedMetrics {
                $0.recoveryErrors += 1
                $0.lastError = error.localizedDescription
            }
        }
    }
    
    // MARK: - 🔑 RECUPERAR CLAVE INDIVIDUAL CON MÁXIMA ROBUSTEZ
    private func recoverConversationKey(conversationId: String, conversationData: [String: Any]) async {
        
        // Verificar si ya tenemos la clave localmente
        if conversationKeys[conversationId] != nil {
            return
        }
        
        // Buscar clave en Firestore con múltiples intentos
        if let recoveredKey = await recoverKeyFromFirestoreWithRetry(
            conversationId: conversationId,
            conversationData: conversationData
        ) {
            await cacheConversationKey(conversationId: conversationId, key: recoveredKey)
        } else {
            await updateEnhancedMetrics { $0.keyRecoveryFailures += 1 }
        }
    }
    
    // MARK: - 🔄 RECUPERACIÓN CON REINTENTOS COMO WHATSAPP
    private func recoverKeyFromFirestoreWithRetry(
        conversationId: String,
        conversationData: [String: Any],
        maxRetries: Int = 5
    ) async -> SymmetricKey? {
        
        for attempt in 1...maxRetries {
            
            do {
                // Buscar en múltiples ubicaciones
                if let key = await tryRecoverFromPrimaryLocation(conversationData: conversationData) {
                    await updateEnhancedMetrics { $0.firestoreHits += 1 }
                    return key
                }
                
                if let key = await tryRecoverFromBackupLocation(conversationId: conversationId) {
                    await updateEnhancedMetrics { $0.backupLocationHits += 1 }
                    return key
                }
                
                if let key = await tryRecoverFromLegacyLocation(conversationId: conversationId) {
                    await updateEnhancedMetrics { $0.legacyLocationHits += 1 }
                    return key
                }
                
                // Si no encontramos la clave, esperar antes del siguiente intento
                if attempt < maxRetries {
                    let delay = Double(attempt) * 0.5 // Backoff exponencial
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
                
            } catch {
                if attempt < maxRetries {
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                }
            }
        }
        
        return nil
    }
    
    // MARK: - 📍 MÚLTIPLES UBICACIONES DE RECUPERACIÓN
    private func tryRecoverFromPrimaryLocation(conversationData: [String: Any]) async -> SymmetricKey? {
        // Ubicación primaria: campo sharedEncryptionKey
        guard let keyDataString = conversationData["sharedEncryptionKey"] as? String,
              let keyData = Data(base64Encoded: keyDataString) else {
            return nil
        }
        
        return SymmetricKey(data: keyData)
    }
    
    private func tryRecoverFromBackupLocation(conversationId: String) async -> SymmetricKey? {
        // Ubicación de respaldo: subcollection dedicada
        do {
            let keyDoc = try await db.collection("conversations")
                .document(conversationId)
                .collection("encryption")
                .document("shared_key")
                .getDocument()
            
            guard let data = keyDoc.data(),
                  let keyDataString = data["encryptionKey"] as? String,
                  let keyData = Data(base64Encoded: keyDataString) else {
                return nil
            }
            
            return SymmetricKey(data: keyData)
        } catch {
            return nil
        }
    }
    
    private func tryRecoverFromLegacyLocation(conversationId: String) async -> SymmetricKey? {
        // Ubicación legacy: campo encryptionKey (versión anterior)
        do {
            let doc = try await db.collection("conversations")
                .document(conversationId)
                .getDocument()
            
            guard let data = doc.data(),
                  let keyDataString = data["encryptionKey"] as? String,
                  let keyData = Data(base64Encoded: keyDataString) else {
                return nil
            }
            
            return SymmetricKey(data: keyData)
        } catch {
            return nil
        }
    }
    
    // MARK: - ✅ VALIDACIÓN DE CLAVES RECUPERADAS
    private func validateRecoveredKeys() async {
        
        var validKeys = 0
        var corruptedKeys = 0
        
        for (conversationId, _) in conversationKeys {
            let status = await verifyKeyIntegrity(for: conversationId)
            
            switch status {
            case .valid:
                validKeys += 1
            case .corrupted, .notFound:
                corruptedKeys += 1
                await handleCorruptedKey(conversationId: conversationId)
            }
        }
        
        
        await updateEnhancedMetrics { metrics in
            metrics.validatedKeys = validKeys
            metrics.corruptedKeys = corruptedKeys
        }
    }
    
    // MARK: - 🚨 MANEJO DE CLAVES CORROMPIDAS
    private func handleCorruptedKey(conversationId: String) async {
        
        // 1. Eliminar clave corrompida
        conversationKeys.removeValue(forKey: conversationId)
        await cleanupKeychainKey(tag: conversationKeysPrefix + conversationId)
        
        // 2. Intentar recuperación desde múltiples fuentes
        await recoverConversationKey(conversationId: conversationId, conversationData: [:])
        
        // 3. Si todo falla, crear nueva clave y notificar
        if conversationKeys[conversationId] == nil {
            
            do {
                let newKey = try await createNewSharedConversationKey(conversationId: conversationId)
                await cacheConversationKey(conversationId: conversationId, key: newKey)
                
                // Marcar que hubo rotación por corrupción
                await updateEnhancedMetrics { $0.emergencyRotations += 1 }
                
            } catch {
                encryptionStatus = .error("No se pudo recuperar clave para \(conversationId)")
            }
        }
    }
    
    // MARK: - 🔄 SINCRONIZACIÓN CON FIRESTORE
    private func syncWithFirestore() async {
        
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        // Actualizar estado del dispositivo en Firestore
        let deviceInfo: [String: Any] = [
            "deviceId": UIDevice.current.identifierForVendor?.uuidString ?? "unknown",
            "lastSyncDate": FieldValue.serverTimestamp(),
            "encryptionVersion": "2.0",
            "keysRecovered": conversationKeys.count,
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        ]
        
        do {
            try await db.collection("users")
                .document(currentUserId)
                .collection("devices")
                .document("current")
                .setData(deviceInfo, merge: true)
            
        } catch {
        }
    }
    
    // MARK: - Master Key Management Async
    private func getOrCreateMasterKey() async throws -> SymmetricKey {
        return try await withCheckedThrowingContinuation { continuation in
            keyAccessQueue.async {
                do {
                    // Try to retrieve existing key
                    if let existingKey = try? self.retrieveKeyFromKeychain(tag: self.masterKeyTag) {
                        continuation.resume(returning: existingKey)
                        return
                    }
                    
                    // Create new master key
                    let newKey = SymmetricKey(size: .bits256)
                    try self.storeKeyInKeychain(key: newKey, tag: self.masterKeyTag)
                    
                    continuation.resume(returning: newKey)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - 🚀 OPTIMIZED User Keys con Cache Inteligente
    private func getUserKey(for userId: String) async throws -> SymmetricKey {
        // Input validation
        guard !userId.isEmpty else {
            throw EncryptionError.invalidInput
        }
        
        // 1. Check hot cache first
        if var cachedKey = userKeys[userId] {
            if !cachedKey.isExpired {
                cachedKey.markUsed()
                userKeys[userId] = cachedKey
                await updateMetrics { $0.cacheHits += 1 }
                return cachedKey.key
            } else {
                // Clean expired key
                userKeys.removeValue(forKey: userId)
                await cleanupKeychainKey(tag: userKeysPrefix + userId)
            }
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            keyAccessQueue.async {
                do {
                    let keyTag = self.userKeysPrefix + userId
                    
                    // Try keychain
                    if let storedKey = try? self.retrieveKeyFromKeychain(tag: keyTag) {
                        let cachedKey = CachedKey(key: storedKey)
                        Task { @MainActor in
                            self.userKeys[userId] = cachedKey
                            Task {
                                await self.updateMetrics { $0.keychainHits += 1 }
                            }
                        }
                        continuation.resume(returning: storedKey)
                        return
                    }
                    
                    // Create new user key
                    let newKey = SymmetricKey(size: .bits256)
                    try self.storeKeyInKeychain(key: newKey, tag: keyTag)
                    
                    let cachedKey = CachedKey(key: newKey)
                    Task { @MainActor in
                        self.userKeys[userId] = cachedKey
                        Task {
                            await self.updateMetrics { $0.newKeysCreated += 1 }
                        }
                    }
                    
                    continuation.resume(returning: newKey)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Chat Identity & Recovery
    func chatAccessState() async -> ChatAccessState {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            return .unavailable(NSLocalizedString("messaging.error.notAuthenticated", comment: "User not authenticated"))
        }

        do {
            let hasLocalIdentity = hasLocalChatIdentity(for: currentUserId)
            let hasRecoveryBundle = try await hasChatRecoveryBundle(for: currentUserId)
            let markerKey = chatRecoveryMarkerPrefix + currentUserId
            let hasRecoveryMarker = UserDefaults.standard.bool(forKey: markerKey)

            if hasLocalIdentity && hasRecoveryBundle && !hasRecoveryMarker {
                try deleteLocalChatIdentity(for: currentUserId)
                UserDefaults.standard.set(true, forKey: markerKey)
                return .needsRestore
            }

            if hasLocalIdentity {
                if hasRecoveryBundle {
                    UserDefaults.standard.set(true, forKey: markerKey)
                    return .available
                }
                return .needsPinSetup
            }

            if hasRecoveryBundle {
                UserDefaults.standard.set(true, forKey: markerKey)
                return .needsRestore
            }

            _ = try await ensureChatIdentity()
            return .needsPinSetup
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }

    func hasLocalChatIdentity(for userId: String? = Auth.auth().currentUser?.uid) -> Bool {
        guard let userId else { return false }
        let keyTag = chatIdentityKeyPrefix + userId
        return (try? retrieveDataFromKeychain(tag: keyTag)) != nil
    }

    func hasChatRecoveryBundle(for userId: String) async throws -> Bool {
        let snapshot = try await db.collection("users")
            .document(userId)
            .collection("chatRecovery")
            .document("default")
            .getDocument()
        return snapshot.exists
    }

    func chatRecoveryAttemptState(for userId: String? = Auth.auth().currentUser?.uid) -> ChatRecoveryAttemptState {
        guard let userId else {
            return ChatRecoveryAttemptState(maxAttempts: chatRecoveryMaxAttempts)
        }
        return currentRecoveryAttemptState(for: userId)
    }

    func chatRecoveryLockoutMessage(for state: ChatRecoveryAttemptState) -> String? {
        guard let remaining = state.remainingLockoutInterval else { return nil }
        return String(
            format: NSLocalizedString("chatRecovery.error.lockedTimer", comment: "Recovery locked timer"),
            formatRecoveryLockoutDuration(remaining)
        )
    }

    func ensureChatIdentity() async throws -> ChatIdentityRecord {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw EncryptionError.keyNotFound
        }

        let localIdentity = try await loadOrCreateLocalChatIdentity(for: currentUserId)
        try await syncChatIdentityRecord(localIdentity.record, for: currentUserId)
        return localIdentity.record
    }

    func createRecoveryBundle(pin: String) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw EncryptionError.keyNotFound
        }

        let trimmedPIN = pin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedPIN.count == 6, trimmedPIN.allSatisfy(\.isNumber) else {
            throw EncryptionError.invalidPIN
        }

        let localIdentity = try await loadOrCreateLocalChatIdentity(for: currentUserId)
        let salt = ChatRecoveryCrypto.randomSalt()
        let kdfParams = ChatRecoveryKDFParams()
        let pinKey = try ChatRecoveryCrypto.derivePINKey(
            pin: trimmedPIN,
            salt: salt,
            iterations: kdfParams.iterations,
            keyLength: kdfParams.keyLength
        )

        let privateKeyData = localIdentity.privateKey.rawRepresentation
        let sealedBox = try AES.GCM.seal(privateKeyData, using: pinKey)
        guard let combined = sealedBox.combined else {
            throw EncryptionError.encryptionFailed
        }

        let userKey = try await getUserKey(for: currentUserId)
        let userKeyData = userKey.withUnsafeBytes { Data($0) }
        let sealedUserKeyBox = try AES.GCM.seal(userKeyData, using: pinKey)
        guard let sealedUserKeyCombined = sealedUserKeyBox.combined else {
            throw EncryptionError.encryptionFailed
        }

        let bundle = ChatRecoveryBundle(
            keyId: localIdentity.record.keyId,
            encryptedPrivateKey: combined.base64EncodedString(),
            nonce: sealedBox.nonce.dataRepresentation.base64EncodedString(),
            salt: salt.base64EncodedString(),
            kdfParams: kdfParams,
            encryptedUserKey: sealedUserKeyCombined.base64EncodedString()
        )

        try await db.collection("users")
            .document(currentUserId)
            .collection("chatRecovery")
            .document("default")
            .setData(bundle.asFirestoreData(), merge: true)

        try await syncChatIdentityRecord(localIdentity.record, for: currentUserId)
        UserDefaults.standard.set(true, forKey: chatRecoveryMarkerPrefix + currentUserId)
        clearRecoveryAttemptState(for: currentUserId)
    }

    func restoreChatIdentity(pin: String) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw EncryptionError.keyNotFound
        }

        let attemptState = currentRecoveryAttemptState(for: currentUserId)
        if attemptState.isLocked {
            throw EncryptionError.recoveryLocked(attemptState.remainingLockout)
        }

        let trimmedPIN = pin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedPIN.count == 6, trimmedPIN.allSatisfy(\.isNumber) else {
            throw EncryptionError.invalidPIN
        }

        let snapshot = try await db.collection("users")
            .document(currentUserId)
            .collection("chatRecovery")
            .document("default")
            .getDocument()

        guard
            let data = snapshot.data(),
            let bundle = ChatRecoveryBundle(map: data),
            let salt = Data(base64Encoded: bundle.salt),
            let encryptedPrivateKey = Data(base64Encoded: bundle.encryptedPrivateKey)
        else {
            throw EncryptionError.keyNotFound
        }

        let pinKey = try ChatRecoveryCrypto.derivePINKey(
            pin: trimmedPIN,
            salt: salt,
            iterations: bundle.kdfParams.iterations,
            keyLength: bundle.kdfParams.keyLength
        )

        do {
            let sealedBox = try AES.GCM.SealedBox(combined: encryptedPrivateKey)
            let privateKeyData = try AES.GCM.open(sealedBox, using: pinKey)
            let privateKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: privateKeyData)
            let keyTag = chatIdentityKeyPrefix + currentUserId

            try storeDataInKeychain(data: privateKey.rawRepresentation, tag: keyTag)

            let publicKeyBase64 = privateKey.publicKey.rawRepresentation.base64EncodedString()
            let restoredKeyId = try await resolveStableChatKeyId(
                for: currentUserId,
                publicKeyBase64: publicKeyBase64,
                preferredKeyId: bundle.keyId
            )

            let restoredRecord = ChatIdentityRecord(
                keyId: restoredKeyId,
                publicKeyBase64: publicKeyBase64
            )

            try await syncChatIdentityRecord(restoredRecord, for: currentUserId)
            do {
                try restoreUserKeyIfPresent(from: bundle, pinKey: pinKey, userId: currentUserId)
            } catch {
                // Chat identity restored; Nova key stays unavailable until recovery bundle is refreshed.
            }
            UserDefaults.standard.set(true, forKey: chatRecoveryMarkerPrefix + currentUserId)
            clearRecoveryAttemptState(for: currentUserId)
        } catch {
            registerFailedRecoveryAttempt(for: currentUserId)
            let updatedAttemptState = currentRecoveryAttemptState(for: currentUserId)
            if updatedAttemptState.isLocked {
                throw EncryptionError.recoveryLocked(updatedAttemptState.remainingLockout)
            }
            throw EncryptionError.invalidPIN
        }
    }

    func removeLocalChatIdentity() async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw EncryptionError.keyNotFound
        }

        try deleteLocalChatIdentity(for: currentUserId)
    }

    func fetchChatIdentity(for userId: String) async throws -> ChatIdentityRecord? {
        if let currentUserId = Auth.auth().currentUser?.uid, currentUserId == userId {
            return try await ensureChatIdentity()
        }

        let snapshot = try await db.collection("users").document(userId).getDocument()
        guard
            let data = snapshot.data(),
            let chatKey = data["chatKey"] as? [String: Any]
        else {
            return nil
        }

        return ChatIdentityRecord(map: chatKey)
    }

    func cacheConversationKeyLocally(conversationId: String, key: SymmetricKey) async {
        await cacheConversationKey(conversationId: conversationId, key: key)
    }

    func buildWrappedConversationKeys(
        for participantIds: [String],
        conversationKey: SymmetricKey,
        wrappedBy: String
    ) async throws -> [String: [String: Any]] {
        var wrappedKeys: [String: [String: Any]] = [:]
        let conversationKeyData = conversationKey.withUnsafeBytes { Data($0) }

        for participantId in participantIds {
            guard let identity = try await fetchChatIdentity(for: participantId) else {
                continue
            }

            let wrappedKey = try wrapConversationKey(
                conversationKeyData,
                for: identity,
                wrappedBy: wrappedBy
            )
            wrappedKeys[participantId] = wrappedKey.asFirestoreData()
        }

        return wrappedKeys
    }

    private func loadOrCreateLocalChatIdentity(for userId: String) async throws -> LocalChatIdentity {
        let keyTag = chatIdentityKeyPrefix + userId

        if let existingData = try? retrieveDataFromKeychain(tag: keyTag) {
            let privateKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: existingData)
            let publicKeyBase64 = privateKey.publicKey.rawRepresentation.base64EncodedString()
            let stableKeyId = try await resolveStableChatKeyId(for: userId, publicKeyBase64: publicKeyBase64)
            return LocalChatIdentity(
                record: ChatIdentityRecord(
                    keyId: stableKeyId,
                    publicKeyBase64: publicKeyBase64
                ),
                privateKey: privateKey
            )
        }

        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        try storeDataInKeychain(data: privateKey.rawRepresentation, tag: keyTag)
        let publicKeyBase64 = privateKey.publicKey.rawRepresentation.base64EncodedString()
        let stableKeyId = try await resolveStableChatKeyId(for: userId, publicKeyBase64: publicKeyBase64)

        return LocalChatIdentity(
            record: ChatIdentityRecord(
                keyId: stableKeyId,
                publicKeyBase64: publicKeyBase64
            ),
            privateKey: privateKey
        )
    }

    private func syncChatIdentityRecord(_ record: ChatIdentityRecord, for userId: String) async throws {
        persistLocalChatKeyId(record.keyId, for: userId)
        try await db.collection("users")
            .document(userId)
            .setData([
                "chatKey": record.asFirestoreData()
            ], merge: true)
    }

    private func resolveStableChatKeyId(
        for userId: String,
        publicKeyBase64: String,
        preferredKeyId: String? = nil
    ) async throws -> String {
        if let preferredKeyId, !preferredKeyId.isEmpty {
            persistLocalChatKeyId(preferredKeyId, for: userId)
            return preferredKeyId
        }

        if let localKeyId = storedLocalChatKeyId(for: userId), !localKeyId.isEmpty {
            return localKeyId
        }

        let userDoc = try await db.collection("users").document(userId).getDocument()
        if
            let data = userDoc.data(),
            let chatKey = data["chatKey"] as? [String: Any],
            let remoteIdentity = ChatIdentityRecord(map: chatKey),
            remoteIdentity.publicKeyBase64 == publicKeyBase64
        {
            persistLocalChatKeyId(remoteIdentity.keyId, for: userId)
            return remoteIdentity.keyId
        }

        if
            let recoveryData = try? await db.collection("users")
                .document(userId)
                .collection("chatRecovery")
                .document("default")
                .getDocument()
                .data(),
            let recoveryBundle = ChatRecoveryBundle(map: recoveryData),
            let recoveryKeyId = recoveryBundle.keyId,
            !recoveryKeyId.isEmpty
        {
            persistLocalChatKeyId(recoveryKeyId, for: userId)
            return recoveryKeyId
        }

        let generatedKeyId = UUID().uuidString
        persistLocalChatKeyId(generatedKeyId, for: userId)
        return generatedKeyId
    }

    private func persistLocalChatKeyId(_ keyId: String, for userId: String) {
        UserDefaults.standard.set(keyId, forKey: chatIdentityKeyIdPrefix + userId)
    }

    private func recoveryAttemptsKey(for userId: String) -> String {
        chatRecoveryAttemptsPrefix + userId
    }

    private func recoveryLockoutKey(for userId: String) -> String {
        chatRecoveryLockoutPrefix + userId
    }

    private func currentRecoveryAttemptState(for userId: String) -> ChatRecoveryAttemptState {
        let defaults = UserDefaults.standard
        let attemptsKey = recoveryAttemptsKey(for: userId)
        let lockoutKey = recoveryLockoutKey(for: userId)

        let failedAttempts = defaults.integer(forKey: attemptsKey)
        let lockedUntil = defaults.object(forKey: lockoutKey) as? Date

        if let lockedUntil, lockedUntil.timeIntervalSinceNow <= 0 {
            defaults.removeObject(forKey: attemptsKey)
            defaults.removeObject(forKey: lockoutKey)
            return ChatRecoveryAttemptState(maxAttempts: chatRecoveryMaxAttempts)
        }

        return ChatRecoveryAttemptState(
            failedAttempts: failedAttempts,
            maxAttempts: chatRecoveryMaxAttempts,
            lockedUntil: lockedUntil
        )
    }

    private func registerFailedRecoveryAttempt(for userId: String) {
        let defaults = UserDefaults.standard
        let attemptsKey = recoveryAttemptsKey(for: userId)
        let lockoutKey = recoveryLockoutKey(for: userId)

        let nextAttemptCount = defaults.integer(forKey: attemptsKey) + 1
        defaults.set(nextAttemptCount, forKey: attemptsKey)

        if nextAttemptCount >= chatRecoveryMaxAttempts {
            defaults.set(Date().addingTimeInterval(chatRecoveryLockoutDuration), forKey: lockoutKey)
            defaults.removeObject(forKey: attemptsKey)
        }
    }

    private func clearRecoveryAttemptState(for userId: String) {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: recoveryAttemptsKey(for: userId))
        defaults.removeObject(forKey: recoveryLockoutKey(for: userId))
    }

    private func formatRecoveryLockoutDuration(_ interval: TimeInterval) -> String {
        let totalSeconds = max(1, Int(interval.rounded(.up)))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func storedLocalChatKeyId(for userId: String) -> String? {
        UserDefaults.standard.string(forKey: chatIdentityKeyIdPrefix + userId)
    }

    private func deleteLocalChatIdentity(for userId: String) throws {
        let keyTag = chatIdentityKeyPrefix + userId
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keyChainService,
            kSecAttrAccount as String: keyTag
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw EncryptionError.keychainError("Failed to delete key (\(keyTag)): \(status)")
        }
    }

    private func restoreUserKeyIfPresent(
        from bundle: ChatRecoveryBundle,
        pinKey: SymmetricKey,
        userId: String
    ) throws {
        guard
            let encryptedUserKeyB64 = bundle.encryptedUserKey,
            let encryptedUserKeyData = Data(base64Encoded: encryptedUserKeyB64)
        else {
            return
        }

        let sealedBox = try AES.GCM.SealedBox(combined: encryptedUserKeyData)
        let userKeyData = try AES.GCM.open(sealedBox, using: pinKey)
        guard userKeyData.count == 32 else {
            throw EncryptionError.decryptionFailed
        }

        let restoredKey = SymmetricKey(data: userKeyData)
        let keyTag = userKeysPrefix + userId
        try storeKeyInKeychain(key: restoredKey, tag: keyTag)

        Task { @MainActor in
            self.userKeys[userId] = CachedKey(key: restoredKey)
        }
    }

    private func wrapConversationKey(
        _ conversationKeyData: Data,
        for identity: ChatIdentityRecord,
        wrappedBy: String
    ) throws -> WrappedConversationKey {
        guard let recipientPublicKeyData = Data(base64Encoded: identity.publicKeyBase64) else {
            throw EncryptionError.invalidInput
        }

        let recipientPublicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: recipientPublicKeyData)
        let ephemeralPrivateKey = Curve25519.KeyAgreement.PrivateKey()
        let sharedSecret = try ephemeralPrivateKey.sharedSecretFromKeyAgreement(with: recipientPublicKey)
        let wrappingKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: chatWrapInfo,
            outputByteCount: 32
        )

        let sealedBox = try AES.GCM.seal(conversationKeyData, using: wrappingKey)
        guard let combined = sealedBox.combined else {
            throw EncryptionError.encryptionFailed
        }

        return WrappedConversationKey(
            wrappedKey: combined.base64EncodedString(),
            senderPublicKey: ephemeralPrivateKey.publicKey.rawRepresentation.base64EncodedString(),
            recipientKeyId: identity.keyId,
            wrappedBy: wrappedBy
        )
    }

    private func unwrapConversationKey(_ wrappedKey: WrappedConversationKey, for userId: String) throws -> SymmetricKey {
        let keyTag = chatIdentityKeyPrefix + userId
        let privateKeyData = try retrieveDataFromKeychain(tag: keyTag)
        let privateKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: privateKeyData)

        guard
            let senderPublicKeyData = Data(base64Encoded: wrappedKey.senderPublicKey),
            let wrappedKeyData = Data(base64Encoded: wrappedKey.wrappedKey)
        else {
            throw EncryptionError.invalidInput
        }

        let senderPublicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: senderPublicKeyData)
        let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: senderPublicKey)
        let wrappingKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: chatWrapInfo,
            outputByteCount: 32
        )
        let sealedBox = try AES.GCM.SealedBox(combined: wrappedKeyData)
        let unwrappedKeyData = try AES.GCM.open(sealedBox, using: wrappingKey)
        return SymmetricKey(data: unwrappedKeyData)
    }

    private func persistWrappedKeyIfNeeded(
        conversationId: String,
        conversationData: [String: Any],
        conversationKey: SymmetricKey,
        for userId: String
    ) async {
        guard let identity = try? await fetchChatIdentity(for: userId) else {
            return
        }

        let existingWrappedKeys = conversationData["wrappedKeys"] as? [String: Any] ?? [:]
        guard existingWrappedKeys[userId] == nil else {
            return
        }

        let conversationKeyData = conversationKey.withUnsafeBytes { Data($0) }
        guard let wrappedKey = try? wrapConversationKey(conversationKeyData, for: identity, wrappedBy: userId) else {
            return
        }

        do {
            try await db.collection("conversations")
                .document(conversationId)
                .setData([
                    "wrappedKeys": [
                        userId: wrappedKey.asFirestoreData()
                    ],
                    "conversationKeyVersion": 1,
                    "encryptionVersion": "3.0"
                ], merge: true)
        } catch {
        }
    }

    // MARK: - 🚀 CONVERSATION KEYS ULTRA RÁPIDAS con Concurrent Loading
    private func getConversationKey(for conversationId: String) async throws -> SymmetricKey {
        // Input validation
        guard !conversationId.isEmpty else {
            throw EncryptionError.invalidInput
        }
        
        // 1. Check if there's already a task loading this key
        if let existingTask = preloadTasks[conversationId] {
            do {
                let result = try await existingTask.value
                await updateMetrics { $0.cacheHits += 1 }
                return result
            } catch {
                // Remove failed task and continue
                preloadTasks.removeValue(forKey: conversationId)
                throw error
            }
        }
        
        // 2. Check hot cache
        if var cachedKey = conversationKeys[conversationId] {
            if !cachedKey.isExpired {
                cachedKey.markUsed()
                conversationKeys[conversationId] = cachedKey
                await updateMetrics { $0.cacheHits += 1 }
                return cachedKey.key
            } else {
                conversationKeys.removeValue(forKey: conversationId)
                await cleanupKeychainKey(tag: conversationKeysPrefix + conversationId)
            }
        }
        
        // 3. Create loading task (mismo actor que el servicio; evita deadlock con upload de media)
        let loadingTask = Task { @MainActor in
            defer {
                preloadTasks.removeValue(forKey: conversationId)
            }
            return try await loadConversationKeyFromStorage(conversationId: conversationId)
        }
        
        preloadTasks[conversationId] = loadingTask
        return try await loadingTask.value
    }
    
    private func loadConversationKeyFromStorage(conversationId: String) async throws -> SymmetricKey {
        let keyTag = conversationKeysPrefix + conversationId
        
        // Try keychain first
        if let storedKey = try? retrieveKeyFromKeychain(tag: keyTag) {
            let cachedKey = CachedKey(key: storedKey)
            conversationKeys[conversationId] = cachedKey
            await updateMetrics { $0.keychainHits += 1 }
            return storedKey
        }
        
        // Fetch from Firestore with timeout
        return try await withTimeout(seconds: 5) {
            try await self.getConversationKeyFromFirestore(conversationId: conversationId)
        }
    }
    
    // MARK: - 🚀 FIRESTORE OPERATIONS Optimizadas
    private func getConversationKeyFromFirestore(conversationId: String) async throws -> SymmetricKey {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw EncryptionError.keyNotFound
        }

        do {
            let snapshot = try await db.collection("conversations")
                .document(conversationId)
                .getDocument()
            
            guard let data = snapshot.data() else {
                throw EncryptionError.keyNotFound
            }

            if
                let wrappedKeys = data["wrappedKeys"] as? [String: Any],
                let wrappedKeyMap = wrappedKeys[currentUserId] as? [String: Any],
                let wrappedKey = WrappedConversationKey(map: wrappedKeyMap)
            {
                let conversationKey = try unwrapConversationKey(wrappedKey, for: currentUserId)
                await cacheConversationKey(conversationId: conversationId, key: conversationKey)
                await updateMetrics { $0.firestoreHits += 1 }
                return conversationKey
            }

            if let keyDataString = data["sharedEncryptionKey"] as? String,
               let keyData = Data(base64Encoded: keyDataString) {
                let sharedKey = SymmetricKey(data: keyData)
                await cacheConversationKey(conversationId: conversationId, key: sharedKey)
                await persistWrappedKeyIfNeeded(
                    conversationId: conversationId,
                    conversationData: data,
                    conversationKey: sharedKey,
                    for: currentUserId
                )
                await updateMetrics { $0.firestoreHits += 1 }
                return sharedKey
            }

            if let keyDataString = data["encryptionKey"] as? String,
               let keyData = Data(base64Encoded: keyDataString) {
                let sharedKey = SymmetricKey(data: keyData)
                await cacheConversationKey(conversationId: conversationId, key: sharedKey)
                await persistWrappedKeyIfNeeded(
                    conversationId: conversationId,
                    conversationData: data,
                    conversationKey: sharedKey,
                    for: currentUserId
                )
                await updateMetrics { $0.firestoreHits += 1 }
                return sharedKey
            }

            if let participants = data["participants"] as? [String],
               participants.contains(currentUserId) {
                let sharedKey = try await createNewSharedConversationKey(conversationId: conversationId)
                await persistWrappedKeyIfNeeded(
                    conversationId: conversationId,
                    conversationData: data,
                    conversationKey: sharedKey,
                    for: currentUserId
                )
                await updateMetrics { $0.newKeysCreated += 1 }
                return sharedKey
            }

            throw EncryptionError.keyNotFound
            
        } catch {
            await updateMetrics {
                $0.firestoreErrors += 1
                $0.lastError = error.localizedDescription
            }
            throw error
        }
    }
    
    // MARK: - 🛡️ ATOMIC Key Creation (evita race conditions)
    private func createNewSharedConversationKey(conversationId: String) async throws -> SymmetricKey {
        let deviceId = await MainActor.run { UIDevice.current.identifierForVendor?.uuidString ?? "unknown" }
        
        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }
        let keyDataString = keyData.base64EncodedString()
        let metadata = KeyMetadata(keyId: UUID().uuidString, deviceId: deviceId)
        
        let uploadData: [String: Any] = [
            "encryptionKey": keyDataString,
            "encryptionKeyCreatedAt": FieldValue.serverTimestamp(),
            "encryptionVersion": "2.0",
            "keyMetadata": try JSONEncoder().encode(metadata).base64EncodedString(),
            "lastKeyUpdate": FieldValue.serverTimestamp(),
            "createdByDevice": deviceId
        ]
        
        // Atomic write with merge
        try await db.collection("conversations")
            .document(conversationId)
            .setData(uploadData, merge: true)
        
        await cacheConversationKey(conversationId: conversationId, key: newKey)
        
        return newKey
    }
    
    // MARK: - 🗂️ CACHE Management
    private func cacheConversationKey(conversationId: String, key: SymmetricKey) async {
        let cachedKey = CachedKey(key: key)
        conversationKeys[conversationId] = cachedKey
        
        // Store in keychain asynchronously
        let keyTag = conversationKeysPrefix + conversationId
        Task {
            await withCheckedContinuation { continuation in
                keyAccessQueue.async {
                    do {
                        try self.storeKeyInKeychain(key: key, tag: keyTag)
                    } catch {
                    }
                    continuation.resume()
                }
            }
        }
    }
    
    private func loadCachedKeys() async {
        let startTime = Date()
        
        await withTaskGroup(of: Void.self) { group in
            // Load user keys
            group.addTask {
                await self.loadUserKeysFromKeychain()
            }
            
            // Load conversation keys
            group.addTask {
                await self.loadConversationKeysFromKeychain()
            }
        }
        
        let loadTime = Date().timeIntervalSince(startTime)
        
        await updateMetrics { metrics in
            metrics.cacheLoadTime = loadTime
            metrics.totalKeysLoaded = userKeys.count + conversationKeys.count
        }
    }
    
    // MARK: - 🔍 KEYCHAIN SCANNING IMPLEMENTATION
    private func loadUserKeysFromKeychain() async {
        await withCheckedContinuation { continuation in
            keyAccessQueue.async {
                var loadedCount = 0
                
                // Query para obtener todos los user keys
                let query: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: self.keyChainService,
                    kSecMatchLimit as String: kSecMatchLimitAll,
                    kSecReturnAttributes as String: true,
                    kSecReturnData as String: true
                ]
                
                var result: AnyObject?
                let status = SecItemCopyMatching(query as CFDictionary, &result)
                
                guard status == errSecSuccess,
                      let items = result as? [[String: Any]] else {
                    continuation.resume()
                    return
                }
                
                for item in items {
                    guard let account = item[kSecAttrAccount as String] as? String,
                          account.hasPrefix(self.userKeysPrefix),
                          let keyData = item[kSecValueData as String] as? Data else {
                        continue
                    }
                    
                    // Extraer userId del tag
                    let userId = String(account.dropFirst(self.userKeysPrefix.count))
                    
                    let symmetricKey = SymmetricKey(data: keyData)
                    let cachedKey = CachedKey(key: symmetricKey)
                    
                    Task { @MainActor in
                        self.userKeys[userId] = cachedKey
                    }
                    
                    loadedCount += 1
                }
                
                continuation.resume()
            }
        }
    }
    
    private func loadConversationKeysFromKeychain() async {
        await withCheckedContinuation { continuation in
            keyAccessQueue.async {
                var loadedCount = 0
                
                // Query para obtener todos los conversation keys
                let query: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: self.keyChainService,
                    kSecMatchLimit as String: kSecMatchLimitAll,
                    kSecReturnAttributes as String: true,
                    kSecReturnData as String: true
                ]
                
                var result: AnyObject?
                let status = SecItemCopyMatching(query as CFDictionary, &result)
                
                guard status == errSecSuccess,
                      let items = result as? [[String: Any]] else {
                    continuation.resume()
                    return
                }
                
                for item in items {
                    guard let account = item[kSecAttrAccount as String] as? String,
                          account.hasPrefix(self.conversationKeysPrefix),
                          let keyData = item[kSecValueData as String] as? Data else {
                        continue
                    }
                    
                    // Extraer conversationId del tag
                    let conversationId = String(account.dropFirst(self.conversationKeysPrefix.count))
                    
                    let symmetricKey = SymmetricKey(data: keyData)
                    let cachedKey = CachedKey(key: symmetricKey)
                    
                    Task { @MainActor in
                        self.conversationKeys[conversationId] = cachedKey
                    }
                    
                    loadedCount += 1
                }
                
                continuation.resume()
            }
        }
    }
    
    // MARK: - 🧹 ENHANCED CLEANUP con Keychain Scanning
    private func scanAndCleanupKeychain() async {
        
        await withTaskGroup(of: Void.self) { group in
            // Cleanup expired user keys
            group.addTask {
                await self.cleanupExpiredKeysFromKeychain(prefix: self.userKeysPrefix, type: "user")
            }
            
            // Cleanup expired conversation keys
            group.addTask {
                await self.cleanupExpiredKeysFromKeychain(prefix: self.conversationKeysPrefix, type: "conversation")
            }
            
            // Cleanup orphaned keys (keys without cache entries)
            group.addTask {
                await self.cleanupOrphanedKeys()
            }
        }
    }
    
    private func cleanupExpiredKeysFromKeychain(prefix: String, type: String) async {
        // Capture expired IDs on MainActor before entering queue
        let expiredIds: Set<String> = await MainActor.run {
            if type == "user" {
                return Set(self.userKeys.compactMap { $0.value.isExpired ? $0.key : nil })
            } else {
                return Set(self.conversationKeys.compactMap { $0.value.isExpired ? $0.key : nil })
            }
        }
        
        await withCheckedContinuation { continuation in
            keyAccessQueue.async {
                let query: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: self.keyChainService,
                    kSecMatchLimit as String: kSecMatchLimitAll,
                    kSecReturnAttributes as String: true
                ]
                
                var result: AnyObject?
                let status = SecItemCopyMatching(query as CFDictionary, &result)
                
                guard status == errSecSuccess,
                      let items = result as? [[String: Any]] else {
                    continuation.resume()
                    return
                }
                
                var deletedCount = 0
                
                for item in items {
                    guard let account = item[kSecAttrAccount as String] as? String,
                          account.hasPrefix(prefix) else {
                        continue
                    }
                    
                    // Check if this key should be deleted
                    let id = String(account.dropFirst(prefix.count))
                    let shouldDelete = expiredIds.contains(id)
                    
                    if shouldDelete {
                        let deleteQuery: [String: Any] = [
                            kSecClass as String: kSecClassGenericPassword,
                            kSecAttrService as String: self.keyChainService,
                            kSecAttrAccount as String: account
                        ]
                        
                        let deleteStatus = SecItemDelete(deleteQuery as CFDictionary)
                        if deleteStatus == errSecSuccess {
                            deletedCount += 1
                        }
                    }
                }
                
                continuation.resume()
            }
        }
    }
    
    private func cleanupOrphanedKeys() async {
        // Capture existing IDs on MainActor before entering queue
        let existingUserIds: Set<String> = await MainActor.run { Set(self.userKeys.keys) }
        let existingConversationIds: Set<String> = await MainActor.run { Set(self.conversationKeys.keys) }
        
        await withCheckedContinuation { continuation in
            keyAccessQueue.async {
                let query: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: self.keyChainService,
                    kSecMatchLimit as String: kSecMatchLimitAll,
                    kSecReturnAttributes as String: true
                ]
                
                var result: AnyObject?
                let status = SecItemCopyMatching(query as CFDictionary, &result)
                
                guard status == errSecSuccess,
                      let items = result as? [[String: Any]] else {
                    continuation.resume()
                    return
                }
                
                var orphanedCount = 0
                
                for item in items {
                    guard let account = item[kSecAttrAccount as String] as? String else {
                        continue
                    }
                    
                    // Skip master key
                    if account == self.masterKeyTag {
                        continue
                    }
                    
                    var isOrphaned = false
                    
                    if account.hasPrefix(self.userKeysPrefix) {
                        let userId = String(account.dropFirst(self.userKeysPrefix.count))
                        isOrphaned = !existingUserIds.contains(userId)
                    } else if account.hasPrefix(self.conversationKeysPrefix) {
                        let conversationId = String(account.dropFirst(self.conversationKeysPrefix.count))
                        isOrphaned = !existingConversationIds.contains(conversationId)
                    }
                    
                    if isOrphaned {
                        let deleteQuery: [String: Any] = [
                            kSecClass as String: kSecClassGenericPassword,
                            kSecAttrService as String: self.keyChainService,
                            kSecAttrAccount as String: account
                        ]
                        
                        let deleteStatus = SecItemDelete(deleteQuery as CFDictionary)
                        if deleteStatus == errSecSuccess {
                            orphanedCount += 1
                        }
                    }
                }
                
                continuation.resume()
            }
        }
    }
    
    // MARK: - 📊 KEYCHAIN STATISTICS
    func getKeychainStatistics() async -> KeychainStatistics {
        // Capture counts on MainActor before entering queue
        let userCacheCount = await MainActor.run { self.userKeys.count }
        let conversationCacheCount = await MainActor.run { self.conversationKeys.count }
        
        return await withCheckedContinuation { continuation in
            keyAccessQueue.async {
                let query: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: self.keyChainService,
                    kSecMatchLimit as String: kSecMatchLimitAll,
                    kSecReturnAttributes as String: true
                ]
                
                var result: AnyObject?
                let status = SecItemCopyMatching(query as CFDictionary, &result)
                
                guard status == errSecSuccess,
                      let items = result as? [[String: Any]] else {
                    continuation.resume(returning: KeychainStatistics())
                    return
                }
                
                var userKeysInKeychain = 0
                var conversationKeysInKeychain = 0
                var otherKeysInKeychain = 0
                var totalSizeBytes = 0
                
                for item in items {
                    guard let account = item[kSecAttrAccount as String] as? String else {
                        continue
                    }
                    
                    if let data = item[kSecValueData as String] as? Data {
                        totalSizeBytes += data.count
                    }
                    
                    if account.hasPrefix(self.userKeysPrefix) {
                        userKeysInKeychain += 1
                    } else if account.hasPrefix(self.conversationKeysPrefix) {
                        conversationKeysInKeychain += 1
                    } else {
                        otherKeysInKeychain += 1
                    }
                }
                
                let stats = KeychainStatistics(
                    userKeysInKeychain: userKeysInKeychain,
                    conversationKeysInKeychain: conversationKeysInKeychain,
                    otherKeysInKeychain: otherKeysInKeychain,
                    totalSizeBytes: totalSizeBytes,
                    userKeysInCache: userCacheCount,
                    conversationKeysInCache: conversationCacheCount
                )
                
                continuation.resume(returning: stats)
            }
        }
    }
    
    // MARK: - 🧹 CLEANUP Operations
    private func cleanupExpiredKeys() async {
        let expiredUsers = userKeys.compactMap { key, value in
            value.isExpired ? key : nil
        }
        
        let expiredConversations = conversationKeys.compactMap { key, value in
            value.isExpired ? key : nil
        }
        
        
        for userId in expiredUsers {
            userKeys.removeValue(forKey: userId)
            await cleanupKeychainKey(tag: userKeysPrefix + userId)
        }
        
        for conversationId in expiredConversations {
            conversationKeys.removeValue(forKey: conversationId)
            await cleanupKeychainKey(tag: conversationKeysPrefix + conversationId)
        }
    }
    
    private func cleanupKeychainKey(tag: String) async {
        await withCheckedContinuation { continuation in
            keyAccessQueue.async {
                let query: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: self.keyChainService,
                    kSecAttrAccount as String: tag
                ]
                SecItemDelete(query as CFDictionary)
                continuation.resume()
            }
        }
    }
    
    // MARK: - 🔄 KEY ROTATION (Nueva funcionalidad)
    func rotateConversationKey(for conversationId: String, reason: KeyRotationReason = .manual) async throws -> Bool {
        
        // Generate new key
        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }
        let keyDataString = keyData.base64EncodedString()
        
        // Update Firestore with new key
        let rotationData: [String: Any] = [
            "sharedEncryptionKey": keyDataString,
            "lastKeyRotation": FieldValue.serverTimestamp(),
            "rotationReason": reason.rawValue,
            "encryptionVersion": "2.0",
            "rotatedByDevice": UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        ]
        
        try await db.collection("conversations")
            .document(conversationId)
            .updateData(rotationData)
        
        // Update local cache
        await cacheConversationKey(conversationId: conversationId, key: newKey)
        
        await updateMetrics { $0.keyRotations += 1 }
        
        return true
    }
    
    enum KeyRotationReason: String, CaseIterable {
        case manual = "manual"
        case userLeft = "user_left"
        case securityBreach = "security_breach"
        case scheduled = "scheduled"
        case corruption = "corruption"
    }
    
    // MARK: - 🔍 KEY VERIFICATION
    func verifyKeyIntegrity(for conversationId: String) async -> KeyIntegrityStatus {
        guard let cachedKey = conversationKeys[conversationId] else {
            return .notFound
        }
        
        do {
            // Test encryption/decryption
            let testMessage = "integrity_test_\(Date().timeIntervalSince1970)"
            let encrypted = try encrypt(text: testMessage, with: cachedKey.key)
            let decrypted = try decrypt(encryptedText: encrypted, with: cachedKey.key)
            
            if decrypted == testMessage {
                return .valid
            } else {
                return .corrupted
            }
        } catch {
            return .corrupted
        }
    }
    
    enum KeyIntegrityStatus {
        case valid
        case corrupted
        case notFound
    }
    
    // MARK: - 🚀 BATCH PRELOADING Optimizado
    func preloadConversationKeys(for conversationIds: [String]) async {
        
        await updateMetrics { $0.batchPreloadRequests += 1 }
        let startTime = Date()
        
        await withTaskGroup(of: Void.self) { group in
            for conversationId in conversationIds {
                group.addTask {
                    do {
                        _ = try await self.getConversationKey(for: conversationId)
                    } catch {
                    }
                }
            }
        }
        
        let duration = Date().timeIntervalSince(startTime)
        await updateMetrics {
            $0.averagePreloadTime = (($0.averagePreloadTime * Double($0.batchPreloadRequests - 1)) + duration) / Double($0.batchPreloadRequests)
        }
        
    }

    func encryptChatMedia(
        _ data: Data,
        for conversationId: String,
        messageId: String,
        purpose: ChatMediaPurpose,
        contentType: String,
        fileExtension: String
    ) async throws -> (ciphertext: Data, metadata: EncryptedChatMediaMetadata) {
        let key = try await getConversationKey(for: conversationId)
        let mediaKey = deriveChatMediaKey(
            from: key,
            conversationId: conversationId,
            messageId: messageId,
            purpose: purpose
        )
        let authenticatedData = mediaAuthenticatedData(
            conversationId: conversationId,
            messageId: messageId,
            purpose: purpose,
            contentType: contentType
        )
        let sealedBox = try AES.GCM.seal(data, using: mediaKey, authenticating: authenticatedData)
        guard let combined = sealedBox.combined else {
            throw EncryptionError.encryptionFailed
        }

        return (
            combined,
            EncryptedChatMediaMetadata(
                purpose: purpose,
                mediaId: messageId,
                contentType: contentType,
                fileExtension: fileExtension,
                plaintextSize: Int64(data.count)
            )
        )
    }

    func decryptChatMedia(
        _ encryptedData: Data,
        metadata: EncryptedChatMediaMetadata,
        for conversationId: String,
        messageId: String
    ) async throws -> Data {
        let key = try await getConversationKey(for: conversationId)
        let mediaKey = deriveChatMediaKey(
            from: key,
            conversationId: conversationId,
            messageId: messageId,
            purpose: metadata.purpose
        )
        let authenticatedData = mediaAuthenticatedData(
            conversationId: conversationId,
            messageId: messageId,
            purpose: metadata.purpose,
            contentType: metadata.contentType
        )
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
        return try AES.GCM.open(sealedBox, using: mediaKey, authenticating: authenticatedData)
    }
    
    // MARK: - PUBLIC ENCRYPTION METHODS (Optimizadas con métricas)
    func encryptNovaData(_ text: String, for userId: String) async -> String? {
        guard isEncryptionEnabled else { return text }
        
        do {
            let key = try await getUserKey(for: userId)
            let result = try encrypt(text: text, with: key)
            await updateMetrics { $0.successfulEncryptions += 1 }
            return result
        } catch {
            await updateMetrics {
                $0.encryptionErrors += 1
                $0.lastError = error.localizedDescription
            }
            return text
        }
    }

    func encryptNovaBlob(_ data: Data, for userId: String, purpose: String) async throws -> Data {
        let key = try await getUserKey(for: userId)
        let blobKey = deriveNovaBlobKey(from: key, userId: userId, purpose: purpose)
        let authenticatedData = novaBlobAuthenticatedData(userId: userId, purpose: purpose)
        let sealedBox = try AES.GCM.seal(data, using: blobKey, authenticating: authenticatedData)
        guard let combined = sealedBox.combined else {
            throw EncryptionError.encryptionFailed
        }
        return combined
    }

    func decryptNovaBlob(_ encryptedData: Data, for userId: String, purpose: String) async throws -> Data {
        let key = try await getUserKey(for: userId)
        let blobKey = deriveNovaBlobKey(from: key, userId: userId, purpose: purpose)
        let authenticatedData = novaBlobAuthenticatedData(userId: userId, purpose: purpose)
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
        return try AES.GCM.open(sealedBox, using: blobKey, authenticating: authenticatedData)
    }
    
    func decryptNovaData(_ encryptedText: String, for userId: String) async -> String? {
        guard isEncryptionEnabled else { return encryptedText }
        
        do {
            let key = try await getUserKey(for: userId)
            let result = try decrypt(encryptedText: encryptedText, with: key)
            await updateMetrics { $0.successfulDecryptions += 1 }
            return result
        } catch {
            await updateMetrics {
                $0.decryptionErrors += 1
                $0.lastError = error.localizedDescription
            }
            return encryptedText
        }
    }
    
    func encryptChatMessage(_ text: String, for conversationId: String) async -> String? {
        guard isEncryptionEnabled else { return text }
        
        do {
            let key = try await getConversationKey(for: conversationId)
            let result = try encrypt(text: text, with: key)
            await updateMetrics { $0.successfulEncryptions += 1 }
            return result
        } catch {
            await updateMetrics {
                $0.encryptionErrors += 1
                $0.lastError = error.localizedDescription
            }
            return text
        }
    }
    
    func decryptChatMessage(_ encryptedText: String, for conversationId: String) async -> String? {
        guard isEncryptionEnabled else { return encryptedText }
        
        do {
            let key = try await getConversationKey(for: conversationId)
            let result = try decrypt(encryptedText: encryptedText, with: key)
            await updateMetrics { $0.successfulDecryptions += 1 }
            return result
        } catch {
            await updateMetrics {
                $0.decryptionErrors += 1
                $0.lastError = error.localizedDescription
            }
            return encryptedText
        }
    }
    
    func encryptUserData(_ text: String, for userId: String) async -> String? {
        guard isEncryptionEnabled else { return text }
        
        do {
            let key = try await getUserKey(for: userId)
            let result = try encrypt(text: text, with: key)
            await updateMetrics { $0.successfulEncryptions += 1 }
            return result
        } catch {
            await updateMetrics {
                $0.encryptionErrors += 1
                $0.lastError = error.localizedDescription
            }
            return text
        }
    }
    
    func decryptUserData(_ encryptedText: String, for userId: String) async -> String? {
        guard isEncryptionEnabled else { return encryptedText }
        
        do {
            let key = try await getUserKey(for: userId)
            let result = try decrypt(encryptedText: encryptedText, with: key)
            await updateMetrics { $0.successfulDecryptions += 1 }
            return result
        } catch {
            await updateMetrics {
                $0.decryptionErrors += 1
                $0.lastError = error.localizedDescription
            }
            return encryptedText
        }
    }
    
    // MARK: - CORE ENCRYPTION (Sin cambios, probado y funcional)
    private func encrypt(text: String, with key: SymmetricKey) throws -> String {
        guard let data = text.data(using: .utf8) else {
            throw EncryptionError.invalidInput
        }
        
        let sealedBox = try AES.GCM.seal(data, using: key)
        return sealedBox.combined?.base64EncodedString() ?? ""
    }
    
    private func decrypt(encryptedText: String, with key: SymmetricKey) throws -> String {
        guard let encryptedData = Data(base64Encoded: encryptedText) else {
            throw EncryptionError.invalidInput
        }
        
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
        let decryptedData = try AES.GCM.open(sealedBox, using: key)
        
        guard let decryptedString = String(data: decryptedData, encoding: .utf8) else {
            throw EncryptionError.decryptionFailed
        }
        
        return decryptedString
    }

    private func deriveChatMediaKey(
        from conversationKey: SymmetricKey,
        conversationId: String,
        messageId: String,
        purpose: ChatMediaPurpose
    ) -> SymmetricKey {
        let salt = Data("moments.chat.media.salt.v1".utf8)
        let info = Data("moments.chat.media.v1|\(conversationId)|\(messageId)|\(purpose.rawValue)".utf8)
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: conversationKey,
            salt: salt,
            info: info,
            outputByteCount: 32
        )
    }

    private func mediaAuthenticatedData(
        conversationId: String,
        messageId: String,
        purpose: ChatMediaPurpose,
        contentType: String
    ) -> Data {
        Data("moments.chat.media.aad.v1|\(conversationId)|\(messageId)|\(purpose.rawValue)|\(contentType)".utf8)
    }

    private func deriveNovaBlobKey(
        from userKey: SymmetricKey,
        userId: String,
        purpose: String
    ) -> SymmetricKey {
        let salt = Data("moments.nova.blob.salt.v1".utf8)
        let info = Data("moments.nova.blob.v1|\(userId)|\(purpose)".utf8)
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: userKey,
            salt: salt,
            info: info,
            outputByteCount: 32
        )
    }

    private func novaBlobAuthenticatedData(userId: String, purpose: String) -> Data {
        Data("moments.nova.blob.aad.v1|\(userId)|\(purpose)".utf8)
    }
    
    // MARK: - KEYCHAIN OPERATIONS (Mejoradas con mejor error handling)
    nonisolated private func storeKeyInKeychain(key: SymmetricKey, tag: String) throws {
        let keyData = key.withUnsafeBytes { Data($0) }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keyChainService,
            kSecAttrAccount as String: tag,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable as String: false // No iCloud sync for security
        ]
        
        // Delete existing item first
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw EncryptionError.keychainError("Failed to store key (\(tag)): \(status)")
        }
    }
    
    nonisolated private func retrieveKeyFromKeychain(tag: String) throws -> SymmetricKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keyChainService,
            kSecAttrAccount as String: tag,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else {
            throw EncryptionError.keychainError("Failed to retrieve key (\(tag)): \(status)")
        }
        
        guard let keyData = result as? Data else {
            throw EncryptionError.keychainError("Invalid key data for: \(tag)")
        }
        
        return SymmetricKey(data: keyData)
    }

    private func storeDataInKeychain(data: Data, tag: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keyChainService,
            kSecAttrAccount as String: tag,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable as String: false
        ]

        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw EncryptionError.keychainError("Failed to store data (\(tag)): \(status)")
        }
    }

    private func retrieveDataFromKeychain(tag: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keyChainService,
            kSecAttrAccount as String: tag,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            throw EncryptionError.keychainError("Failed to retrieve data (\(tag)): \(status)")
        }

        guard let data = result as? Data else {
            throw EncryptionError.keychainError("Invalid keychain data for: \(tag)")
        }

        return data
    }
    
    // MARK: - 📊 METRICS & MONITORING
    private func updateMetrics(_ update: (inout EncryptionMetrics) -> Void) async {
        var metrics = encryptionMetrics
        update(&metrics)
        encryptionMetrics = metrics
    }
    
    // ✅ NUEVA: Para métricas mejoradas
    private func updateEnhancedMetrics(_ update: (inout EnhancedEncryptionMetrics) -> Void) async {
        var metrics = enhancedEncryptionMetrics
        update(&metrics)
        enhancedEncryptionMetrics = metrics
    }
    
    func getDetailedEncryptionInfo() async -> DetailedEncryptionInfo {
        return DetailedEncryptionInfo(
            isEnabled: isEncryptionEnabled,
            status: encryptionStatus,
            userKeysCount: userKeys.count,
            conversationKeysCount: conversationKeys.count,
            hasValidMasterKey: masterKey != nil,
            metrics: encryptionMetrics,
            cacheStatistics: CacheStatistics(
                userKeysCached: userKeys.count,
                conversationKeysCached: conversationKeys.count,
                expiredKeys: userKeys.values.filter { $0.isExpired }.count + conversationKeys.values.filter { $0.isExpired }.count,
                activePreloadTasks: preloadTasks.count
            ),
            keyVersions: getKeyVersionDistribution()
        )
    }
    
    private func getKeyVersionDistribution() -> [String: Int] {
        var distribution: [String: Int] = [:]
        
        for key in userKeys.values {
            distribution[key.version, default: 0] += 1
        }
        
        for key in conversationKeys.values {
            distribution[key.version, default: 0] += 1
        }
        
        return distribution
    }
    
    // MARK: - 🛠️ UTILITY FUNCTIONS
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw EncryptionError.timeout
            }
            
            guard let result = try await group.next() else {
                throw EncryptionError.timeout
            }
            
            group.cancelAll()
            return result
        }
    }
    
    // MARK: - LEGACY SUPPORT & CLEANUP
    func deleteUserKeys(for userId: String) async {
        userKeys.removeValue(forKey: userId)
        await cleanupKeychainKey(tag: userKeysPrefix + userId)
    }
    
    func deleteConversationKeys(for conversationId: String) async {
        conversationKeys.removeValue(forKey: conversationId)
        preloadTasks.removeValue(forKey: conversationId)?.cancel()
        await cleanupKeychainKey(tag: conversationKeysPrefix + conversationId)
    }
    
    func deleteAllKeys() async {
        userKeys.removeAll()
        conversationKeys.removeAll()
        
        // Cancel all preload tasks
        for task in preloadTasks.values {
            task.cancel()
        }
        preloadTasks.removeAll()
        
        await withCheckedContinuation { continuation in
            keyAccessQueue.async {
                let query: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: self.keyChainService
                ]
                SecItemDelete(query as CFDictionary)
                continuation.resume()
            }
        }
        
        await updateMetrics { $0.fullResets += 1 }
    }
    
    func toggleEncryption(_ enabled: Bool) async {
        isEncryptionEnabled = enabled
        await updateMetrics { $0.toggleEvents += 1 }
    }
    
    // MARK: - 📊 FIRESTORE METRICS UPLOAD
    func uploadMetricsToFirestore() async {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            return
        }
        
        do {
            let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
            let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
            
            // 1. Upload encryption metrics (SISTEMA) - ✅ FIX: Usar FieldValue.serverTimestamp()
            let metricsData: [String: Any] = [
                "successfulEncryptions": enhancedEncryptionMetrics.successfulEncryptions,
                "successfulDecryptions": enhancedEncryptionMetrics.successfulDecryptions,
                "encryptionErrors": enhancedEncryptionMetrics.encryptionErrors,
                "decryptionErrors": enhancedEncryptionMetrics.decryptionErrors,
                "cacheHits": enhancedEncryptionMetrics.cacheHits,
                "keychainHits": enhancedEncryptionMetrics.keychainHits,
                "firestoreHits": enhancedEncryptionMetrics.firestoreHits,
                "firestoreErrors": enhancedEncryptionMetrics.firestoreErrors,
                "newKeysCreated": enhancedEncryptionMetrics.newKeysCreated,
                "keyRotations": enhancedEncryptionMetrics.keyRotations,
                "deviceRecoveries": enhancedEncryptionMetrics.deviceRecoveries,
                "firstInstalls": enhancedEncryptionMetrics.firstInstalls,
                "recoveryErrors": enhancedEncryptionMetrics.recoveryErrors,
                "keyRecoveryFailures": enhancedEncryptionMetrics.keyRecoveryFailures,
                "validatedKeys": enhancedEncryptionMetrics.validatedKeys,
                "corruptedKeys": enhancedEncryptionMetrics.corruptedKeys,
                "emergencyRotations": enhancedEncryptionMetrics.emergencyRotations,
                "backupLocationHits": enhancedEncryptionMetrics.backupLocationHits,
                "legacyLocationHits": enhancedEncryptionMetrics.legacyLocationHits,
                "initializationErrors": enhancedEncryptionMetrics.initializationErrors,
                "recoverySuccessRate": enhancedEncryptionMetrics.recoverySuccessRate,
                "keyIntegrityRate": enhancedEncryptionMetrics.keyIntegrityRate,
                "robustnessScore": enhancedEncryptionMetrics.robustnessScore,
                "lastRecoveryDate": enhancedEncryptionMetrics.lastRecoveryDate ?? NSNull(),
                "lastError": enhancedEncryptionMetrics.lastError ?? NSNull(),
                // ✅ FIX: Usar FieldValue.serverTimestamp() en lugar de Date()
                "timestamp": FieldValue.serverTimestamp(),
                "deviceId": deviceId,
                "appVersion": appVersion,
                "reportedByUserId": currentUserId,
                "systemMetric": true
            ]
            
            try await db.collection("encryption_metrics").addDocument(data: metricsData)
            
            // 2. Upload keychain statistics (SISTEMA) - ✅ FIX: Usar FieldValue.serverTimestamp()
            let keychainStats = await getKeychainStatistics()
            let keychainData: [String: Any] = [
                "userKeysInKeychain": keychainStats.userKeysInKeychain,
                "conversationKeysInKeychain": keychainStats.conversationKeysInKeychain,
                "otherKeysInKeychain": keychainStats.otherKeysInKeychain,
                "totalSizeBytes": keychainStats.totalSizeBytes,
                "userKeysInCache": keychainStats.userKeysInCache,
                "conversationKeysInCache": keychainStats.conversationKeysInCache,
                "totalKeysInKeychain": keychainStats.totalKeysInKeychain,
                "totalKeysInCache": keychainStats.totalKeysInCache,
                "cacheToKeychainRatio": keychainStats.cacheToKeychainRatio,
                "formattedSize": keychainStats.formattedSize,
                "healthStatus": keychainStats.healthStatus,
                // ✅ FIX: Usar FieldValue.serverTimestamp()
                "timestamp": FieldValue.serverTimestamp(),
                "deviceId": deviceId,
                "appVersion": appVersion,
                "reportedByUserId": currentUserId,
                "systemMetric": true
            ]
            
            try await db.collection("keychain_statistics").addDocument(data: keychainData)
            
            // 3. Upload health report (SISTEMA) - ✅ FIX: Usar FieldValue.serverTimestamp()
            let healthReport = await performHealthCheck()
            let healthData: [String: Any] = [
                "masterKeyStatus": healthReport.masterKeyStatus.emoji + " " + healthReport.masterKeyStatus.description,
                "encryptionStatus": healthReport.encryptionStatus.emoji + " " + healthReport.encryptionStatus.description,
                "keychainStatus": healthReport.keychainStatus.emoji + " " + healthReport.keychainStatus.description,
                "cachePerformance": healthReport.cachePerformance,
                "memoryUsage": [
                    "userKeys": healthReport.memoryUsage.userKeys,
                    "conversationKeys": healthReport.memoryUsage.conversationKeys,
                    "total": healthReport.memoryUsage.total,
                    "isHealthy": healthReport.memoryUsage.isHealthy,
                    "formattedSize": healthReport.memoryUsage.formattedSize
                ],
                "overallHealth": healthReport.overallHealth.emoji + " " + healthReport.overallHealth.description,
                "lastError": healthReport.lastError ?? NSNull(),
                // ✅ FIX: Usar FieldValue.serverTimestamp()
                "timestamp": FieldValue.serverTimestamp(),
                "deviceId": deviceId,
                "appVersion": appVersion,
                "reportedByUserId": currentUserId,
                "systemMetric": true
            ]
            
            try await db.collection("encryption_health").addDocument(data: healthData)
            
            
        } catch {
            
            // Log más detallado del error
            _ = error
        }
    }
    
    // MARK: - 🔄 SCHEDULED METRICS UPLOAD
    func startMetricsUploadSchedule() {
        // Subir métricas cada 6 horas (21600 segundos)
        Timer.scheduledTimer(withTimeInterval: 21600, repeats: true) { _ in
            Task {
                await self.uploadMetricsToFirestore()
            }
        }
        
        // También subir métricas al iniciar la app
        Task {
            await self.uploadMetricsToFirestore()
        }
    }
}
