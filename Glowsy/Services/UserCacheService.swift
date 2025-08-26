import Foundation
import FirebaseAuth

// MARK: - UserCacheService - Sistema de cache como 
class UserCacheService: ObservableObject {
    static let shared = UserCacheService()
    
    @Published private var userCache: [String: AppUser] = [:]
    private let cacheExpirationTime: TimeInterval = 300 // 5 minutos
    private var lastFetchTimes: [String: Date] = [:]
    private var pendingFetches: [String: [(AppUser?) -> Void]] = [:] // ✅ NUEVO: Evitar múltiples requests
    
    private init() {}
    
    // MARK: - Obtener usuario con cache inteligente (CORREGIDO)
    func getUser(userId: String, completion: @escaping (AppUser?) -> Void) {
        // 1. Verificar cache primero
        if let cachedUser = userCache[userId],
           let lastFetch = lastFetchTimes[userId],
           Date().timeIntervalSince(lastFetch) < cacheExpirationTime {
            completion(cachedUser)
            return
        }
        
        // 2. ✅ Si ya hay una petición pendiente, añadir callback
        if pendingFetches[userId] != nil {
            pendingFetches[userId]?.append(completion)
            return
        }
        
        // 3. ✅ Iniciar nueva petición
        pendingFetches[userId] = [completion]
        
        // ✅ Usar una referencia fuerte para evitar liberación
        let firestoreService = FirestoreService()
        firestoreService.fetchUser(userId: userId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else {
                    // Si self fue liberado, aún ejecutamos los callbacks
                    let callbacks = self?.pendingFetches[userId] ?? []
                    for callback in callbacks {
                        callback(nil)
                    }
                    return
                }
                
                // ✅ Obtener todos los callbacks pendientes
                let callbacks = self.pendingFetches[userId] ?? []
                self.pendingFetches.removeValue(forKey: userId)
                
                switch result {
                case .success(let user):
                    self.userCache[userId] = user
                    self.lastFetchTimes[userId] = Date()
                    
                    // ✅ Ejecutar todos los callbacks
                    for callback in callbacks {
                        callback(user)
                    }
                    
                case .failure(let error):
                    
                    // ✅ Ejecutar callbacks con cache antiguo si existe
                    let cachedUser = self.userCache[userId]
                    for callback in callbacks {
                        callback(cachedUser)
                    }
                }
            }
        }
    }
    
    // MARK: - Resto de funciones (sin cambios)
    func getCachedUser(userId: String) -> AppUser? {
        return userCache[userId]
    }
    
    func preloadUsers(userIds: [String]) {
        for userId in userIds {
            if userCache[userId] == nil {
                getUser(userId: userId) { _ in }
            }
        }
    }
    
    func clearCache() {
        userCache.removeAll()
        lastFetchTimes.removeAll()
        pendingFetches.removeAll()
    }
    
    func refreshUser(userId: String, completion: @escaping (AppUser?) -> Void) {
        // ✅ Forzar refresh eliminando del cache
        lastFetchTimes.removeValue(forKey: userId)
        getUser(userId: userId, completion: completion)
    }
}
