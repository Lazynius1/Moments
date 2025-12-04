import Foundation

// MARK: - Constantes para Límites de Story Chains
struct StoryChainLimits {
    static let maxParts = 10                    // Máximo 10 partes por cadena
    static let expirationHours = 48             // 48 horas de duración (vs 24h de historias normales)
    static let minTimeBetweenParts: TimeInterval = 5 * 60  // 5 minutos mínimo entre partes del mismo usuario
    static let maxChainTitleLength = 50         // Máximo 50 caracteres para el título
}

// MARK: - Errores de Límites de Story Chains
enum StoryChainLimitError: LocalizedError {
    case maxPartsReached
    case chainExpired
    case tooSoonBetweenParts
    case chainNotFound
    case userNotAuthorized
    case invalidChainData
    
    var errorDescription: String? {
        switch self {
        case .maxPartsReached:
            return String(format: NSLocalizedString("storyChains.error.maxPartsReached", comment: "Max parts reached"), StoryChainLimits.maxParts)
        case .chainExpired:
            return NSLocalizedString("storyChains.error.chainExpired", comment: "Chain expired")
        case .tooSoonBetweenParts:
            return String(format: NSLocalizedString("storyChains.error.tooSoonBetweenParts", comment: "Too soon between parts"), Int(StoryChainLimits.minTimeBetweenParts / 60))
        case .chainNotFound:
            return NSLocalizedString("storyChains.error.chainNotFound", comment: "Chain not found")
        case .userNotAuthorized:
            return NSLocalizedString("storyChains.error.userNotAuthorized", comment: "User not authorized")
        case .invalidChainData:
            return NSLocalizedString("storyChains.error.invalidChainData", comment: "Invalid chain data")
        }
    }
}

// MARK: - Servicio de Límites de Story Chains
class StoryChainLimitsService: ObservableObject {
    static let shared = StoryChainLimitsService()
    private let firestore = Firestore.firestore()
    
    private init() {}
    
    // MARK: - Validar si se puede continuar una cadena
    func canContinueChain(chainId: String, userId: String) async throws -> Bool {
        // 1. Verificar que la cadena existe y no ha expirado
        let chainDoc = try await firestore.collection("storyChains").document(chainId).getDocument()
        
        guard chainDoc.exists,
              let chainData = chainDoc.data(),
              let createdAt = chainData["createdAt"] as? Timestamp else {
            throw StoryChainLimitError.chainNotFound
        }
        
        // Verificar si la cadena ha expirado (48 horas)
        let expirationDate = Calendar.current.date(byAdding: .hour, value: StoryChainLimits.expirationHours, to: createdAt.dateValue()) ?? Date()
        if Date() > expirationDate {
            throw StoryChainLimitError.chainExpired
        }
        
        // 2. Verificar número máximo de partes
        let storiesSnapshot: QuerySnapshot
        do {
            storiesSnapshot = try await firestore
                .collectionGroup("stories")
                .whereField("chainId", isEqualTo: chainId)
                .getDocuments()
        } catch {
            throw error
        }
        
        if storiesSnapshot.documents.count >= StoryChainLimits.maxParts {
            throw StoryChainLimitError.maxPartsReached
        }
        
        // 3. Verificar tiempo mínimo entre partes del mismo usuario
        let userStoriesSnapshot = try await firestore
            .collectionGroup("stories")
            .whereField("chainId", isEqualTo: chainId)
            .whereField("authorId", isEqualTo: userId)
            .order(by: "timestamp", descending: true)
            .limit(to: 1)
            .getDocuments()
        
        if let lastUserStory = userStoriesSnapshot.documents.first,
           let lastTimestamp = lastUserStory.data()["timestamp"] as? Timestamp {
            let timeSinceLastPart = Date().timeIntervalSince(lastTimestamp.dateValue())
            if timeSinceLastPart < StoryChainLimits.minTimeBetweenParts {
                throw StoryChainLimitError.tooSoonBetweenParts
            }
        }
        
        return true
    }
    
    // MARK: - Obtener siguiente posición en la cadena
    func getNextChainPosition(chainId: String) async throws -> Int {
        let storiesSnapshot = try await firestore
            .collectionGroup("stories")
            .whereField("chainId", isEqualTo: chainId)
            .order(by: "chainPosition", descending: true)
            .limit(to: 1)
            .getDocuments()
        
        if let lastStory = storiesSnapshot.documents.first,
           let lastPosition = lastStory.data()["chainPosition"] as? Int {
            return lastPosition + 1
        }
        
        return 1 // Primera parte
    }
    
    // MARK: - Validar título de cadena
    func validateChainTitle(_ title: String) throws {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmedTitle.isEmpty {
            throw StoryChainLimitError.invalidChainData
        }
        
        if trimmedTitle.count > StoryChainLimits.maxChainTitleLength {
            throw StoryChainLimitError.invalidChainData
        }
    }
    
    // MARK: - Obtener tiempo restante de una cadena
    func getRemainingTime(chainId: String) async throws -> TimeInterval {
        let chainDoc = try await firestore.collection("storyChains").document(chainId).getDocument()
        
        guard chainDoc.exists,
              let chainData = chainDoc.data(),
              let createdAt = chainData["createdAt"] as? Timestamp else {
            throw StoryChainLimitError.chainNotFound
        }
        
        let expirationDate = Calendar.current.date(byAdding: .hour, value: StoryChainLimits.expirationHours, to: createdAt.dateValue()) ?? Date()
        let remainingTime = expirationDate.timeIntervalSince(Date())
        
        return max(0, remainingTime) // No retornar tiempo negativo
    }
    
    // MARK: - Obtener estadísticas de una cadena
    func getChainStats(chainId: String) async throws -> (partCount: Int, remainingTime: TimeInterval, isExpired: Bool) {
        let storiesSnapshot = try await firestore
            .collectionGroup("stories")
            .whereField("chainId", isEqualTo: chainId)
            .getDocuments()
        
        let partCount = storiesSnapshot.documents.count
        let remainingTime = try await getRemainingTime(chainId: chainId)
        let isExpired = remainingTime <= 0
        
        return (partCount: partCount, remainingTime: remainingTime, isExpired: isExpired)
    }
    
    // MARK: - Limpiar cadenas expiradas (para uso en Cloud Functions)
    func cleanupExpiredChains() async throws {
        let expiredDate = Calendar.current.date(byAdding: .hour, value: -StoryChainLimits.expirationHours, to: Date()) ?? Date()
        
        let expiredChainsSnapshot = try await firestore
            .collection("storyChains")
            .whereField("createdAt", isLessThan: Timestamp(date: expiredDate))
            .getDocuments()
        
        let batch = firestore.batch()
        
        for chainDoc in expiredChainsSnapshot.documents {
            // Marcar cadena como expirada
            batch.updateData(["isExpired": true, "expiredAt": Timestamp(date: Date())], forDocument: chainDoc.reference)
        }
        
        try await batch.commit()
    }
}

// MARK: - Extensión para formatear tiempo restante
extension TimeInterval {
    func formattedRemainingTime() -> String {
        let hours = Int(self) / 3600
        let minutes = Int(self) % 3600 / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m restantes"
        } else if minutes > 0 {
            return "\(minutes)m restantes"
        } else {
            return NSLocalizedString("storyChains.time.expired", comment: "Expired")
        }
    }
}
