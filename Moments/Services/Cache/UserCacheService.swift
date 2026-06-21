import Foundation
import FirebaseAuth

// MARK: - UserCacheService - Sistema de cache como 
class UserCacheService: ObservableObject {
    static let shared = UserCacheService()
    
    @Published private var userCache: [String: AppUser] = [:]
    private let cacheExpirationTime: TimeInterval = 300 // 5 minutos
    private var lastFetchTimes: [String: Date] = [:]
    private var pendingFetches: [String: [(AppUser?) -> Void]] = [:] // ✅ NUEVO: Evitar múltiples requests

    /// Tope de usuarios en RAM. Evita crecimiento ilimitado en feeds con muchos autores.
    private let maxCachedUsers = 500
    private var memoryWarningObserver: NSObjectProtocol?

    private init() {
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: .momentsDidReceiveMemoryWarning,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleMemoryWarning()
        }
    }

    deinit {
        if let memoryWarningObserver {
            NotificationCenter.default.removeObserver(memoryWarningObserver)
        }
    }

    /// Expulsa las entradas menos recientemente refrescadas si se supera el tope.
    private func evictIfNeeded() {
        guard userCache.count > maxCachedUsers else { return }
        let overflow = userCache.count - maxCachedUsers
        // Ordenar por fecha de fetch ascendente (las más antiguas primero).
        let sortedByAge = lastFetchTimes.sorted { $0.value < $1.value }
        for (userId, _) in sortedByAge.prefix(overflow) {
            userCache.removeValue(forKey: userId)
            lastFetchTimes.removeValue(forKey: userId)
        }
    }
    
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
                    self.evictIfNeeded()
                    
                    // ✅ Ejecutar todos los callbacks
                    for callback in callbacks {
                        callback(user)
                    }
                    
                case .failure:
                    
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

    private func handleMemoryWarning() {
        // Soltamos solo el contenido en RAM. Las peticiones en vuelo deben poder
        // terminar y notificar a sus callbacks para no dejar la UI colgada.
        userCache.removeAll()
        lastFetchTimes.removeAll()
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
