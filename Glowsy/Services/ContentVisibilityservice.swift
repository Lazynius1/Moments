import Foundation
import FirebaseAuth
import FirebaseFirestore

// MARK: - UserVisibilitySettings
struct UserVisibilitySettings {
    var defaultStoryVisibility: ContentVisibilityType = .everyone
    var defaultPostVisibility: ContentVisibilityType = .everyone
    var customStoryViewers: [String] = []
    var customPostViewers: [String] = []
    var hiddenFromUsers: [String] = []
}

// MARK: - ContentVisibilityType
enum ContentVisibilityType: String, Codable {
    case everyone = "everyone"
    case connections = "connections"
    case bestFriends = "bestFriends"
    case custom = "custom"
    case onlyMe = "onlyMe"
}

// MARK: - ContentProtocol
protocol ContentProtocol {
    var id: String? { get }
    var authorId: String { get }
    var visibilityType: ContentVisibilityType { get }
    var customViewers: [String]? { get }
    var hiddenFrom: [String]? { get }
}

// MARK: - ContentVisibilityService
class ContentVisibilityService {
    static let shared = ContentVisibilityService()
    private let firestoreService = FirestoreService()
    private let privacyService = PrivacyService()
    
    private init() {}
    
    // MARK: - Verificar si un usuario puede ver contenido
    func canUserSeeContent(
        contentOwnerId: String,
        viewerId: String,
        contentType: ContentVisibilityType,
        customViewers: [String]? = nil,
        hiddenFrom: [String]? = nil,
        completion: @escaping (Bool) -> Void
    ) {
        print("🔍 Verificando visibilidad: \(contentOwnerId) -> \(viewerId), tipo: \(contentType.rawValue)")
        
        // Si es el mismo usuario, siempre puede ver su contenido
        if contentOwnerId == viewerId {
            print("✅ Es el mismo usuario")
            completion(true)
            return
        }
        
        // Verificar si está en la lista de bloqueados
        privacyService.checkMutualBlocks(viewerId: viewerId, targetUserId: contentOwnerId) { isBlocked in
            if isBlocked {
                print("❌ Usuario bloqueado")
                completion(false)
                return
            }
            
            // Verificar según el tipo de visibilidad
            switch contentType {
            case .everyone:
                self.checkEveryoneVisibility(contentOwnerId: contentOwnerId, viewerId: viewerId, completion: completion)
                
            case .connections:
                self.checkConnectionsVisibility(contentOwnerId: contentOwnerId, viewerId: viewerId, completion: completion)
                
            case .bestFriends:
                self.checkBestFriendsVisibility(contentOwnerId: contentOwnerId, viewerId: viewerId, completion: completion)
                
            case .custom:
                self.checkCustomVisibility(
                    contentOwnerId: contentOwnerId,
                    viewerId: viewerId,
                    customViewers: customViewers,
                    completion: completion
                )
                
            case .onlyMe:
                print("❌ Contenido solo para el autor")
                completion(false)
            }
        }
    }
    
    // MARK: - Verificaciones específicas de visibilidad
    
    private func checkEveryoneVisibility(contentOwnerId: String, viewerId: String, completion: @escaping (Bool) -> Void) {
        // Para contenido público, verificar si el perfil del autor es privado
        privacyService.fetchPrivacySettings(userId: contentOwnerId) { result in
            switch result {
            case .success(let settings):
                if settings.isPrivate {
                    // Si el perfil es privado, verificar si el viewer sigue al author
                    self.firestoreService.isFollowing(currentUserId: viewerId, targetUserId: contentOwnerId) { isFollowing in
                        print(isFollowing ? "✅ Perfil privado pero lo sigue" : "❌ Perfil privado y no lo sigue")
                        completion(isFollowing)
                    }
                } else {
                    print("✅ Perfil público")
                    completion(true)
                }
            case .failure:
                print("❌ Error verificando configuración de privacidad")
                completion(false)
            }
        }
    }
    
    private func checkConnectionsVisibility(contentOwnerId: String, viewerId: String, completion: @escaping (Bool) -> Void) {
        // Verificar conexión mutua
        checkMutualConnection(user1: viewerId, user2: contentOwnerId, completion: completion)
    }
    
    private func checkBestFriendsVisibility(contentOwnerId: String, viewerId: String, completion: @escaping (Bool) -> Void) {
        // Verificar si está en la lista de mejores amigos
        firestoreService.db.collection("users").document(contentOwnerId).getDocument { snapshot, error in
            guard let data = snapshot?.data(),
                  let bestFriends = data["bestFriends"] as? [String] else {
                print("❌ No se encontró lista de mejores amigos")
                completion(false)
                return
            }
            
            let isBestFriend = bestFriends.contains(viewerId)
            print(isBestFriend ? "✅ Es mejor amigo" : "❌ No es mejor amigo")
            completion(isBestFriend)
        }
    }
    
    private func checkCustomVisibility(
        contentOwnerId: String,
        viewerId: String,
        customViewers: [String]?,
        completion: @escaping (Bool) -> Void
    ) {
        // Si se proporcionan custom viewers específicos, usarlos
        if let customViewers = customViewers {
            let canSee = customViewers.contains(viewerId)
            print(canSee ? "✅ En lista personalizada específica" : "❌ No en lista personalizada específica")
            completion(canSee)
            return
        }
        
        // Si no, obtener la configuración por defecto del usuario
        getUserVisibilitySettings(userId: contentOwnerId) { result in
            switch result {
            case .success(let settings):
                let canSee = settings.customPostViewers.contains(viewerId)
                print(canSee ? "✅ En lista personalizada por defecto" : "❌ No en lista personalizada por defecto")
                completion(canSee)
            case .failure:
                print("❌ Error obteniendo configuración personalizada")
                completion(false)
            }
        }
    }
    
    // MARK: - Métodos auxiliares
    
    private func checkMutualConnection(user1: String, user2: String, completion: @escaping (Bool) -> Void) {
        let group = DispatchGroup()
        var user1FollowsUser2 = false
        var user2FollowsUser1 = false
        
        group.enter()
        firestoreService.isFollowing(currentUserId: user1, targetUserId: user2) { follows in
            user1FollowsUser2 = follows
            group.leave()
        }
        
        group.enter()
        firestoreService.isFollowing(currentUserId: user2, targetUserId: user1) { follows in
            user2FollowsUser1 = follows
            group.leave()
        }
        
        group.notify(queue: .main) {
            let areMutualConnections = user1FollowsUser2 && user2FollowsUser1
            print(areMutualConnections ? "✅ Conexión mutua" : "❌ No hay conexión mutua")
            completion(areMutualConnections)
        }
    }
    
    // MARK: - Obtener configuración de visibilidad del usuario
    func getUserVisibilitySettings(
        userId: String,
        completion: @escaping (Result<UserVisibilitySettings, Error>) -> Void
    ) {
        firestoreService.db.collection("users").document(userId).getDocument { document, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let document = document, document.exists,
                  let data = document.data() else {
                // Configuración por defecto
                let defaultSettings = UserVisibilitySettings()
                completion(.success(defaultSettings))
                return
            }
            
            var settings = UserVisibilitySettings()
            
            // Cargar configuraciones desde Firestore
            if let contentSettings = data["contentVisibilitySettings"] as? [String: Any] {
                if let storyVis = contentSettings["storyVisibility"] as? String {
                    settings.defaultStoryVisibility = ContentVisibilityType(rawValue: storyVis) ?? .everyone
                }
                if let postVis = contentSettings["postVisibility"] as? String {
                    settings.defaultPostVisibility = ContentVisibilityType(rawValue: postVis) ?? .everyone
                }
                if let customStoryViewers = contentSettings["customStoryViewers"] as? [String] {
                    settings.customStoryViewers = customStoryViewers
                }
                if let customPostViewers = contentSettings["customPostViewers"] as? [String] {
                    settings.customPostViewers = customPostViewers
                }
                if let hiddenFrom = contentSettings["hiddenFromUsers"] as? [String] {
                    settings.hiddenFromUsers = hiddenFrom
                }
            }
            
            completion(.success(settings))
        }
    }
    
    // MARK: - Aplicar filtros a lista de contenido
    func filterVisibleContent<T: ContentProtocol>(
        content: [T],
        viewerId: String,
        completion: @escaping ([T]) -> Void
    ) {
        let group = DispatchGroup()
        var visibleContent: [T] = []
        let syncQueue = DispatchQueue(label: "content.visibility.filter")
        
        for item in content {
            group.enter()
            
            canUserSeeContent(
                contentOwnerId: item.authorId,
                viewerId: viewerId,
                contentType: item.visibilityType,
                customViewers: item.customViewers,
                hiddenFrom: item.hiddenFrom
            ) { canSee in
                syncQueue.async {
                    if canSee {
                        visibleContent.append(item)
                    }
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            // Mantener el orden original
            let orderedContent = content.filter { item in
                visibleContent.contains { $0.id == item.id }
            }
            completion(orderedContent)
        }
    }
    
    // MARK: - Guardar configuración de visibilidad
    func saveUserVisibilitySettings(
        userId: String,
        settings: UserVisibilitySettings,
        completion: @escaping (Error?) -> Void
    ) {
        let contentSettings: [String: Any] = [
            "storyVisibility": settings.defaultStoryVisibility.rawValue,
            "postVisibility": settings.defaultPostVisibility.rawValue,
            "customStoryViewers": settings.customStoryViewers,
            "customPostViewers": settings.customPostViewers,
            "hiddenFromUsers": settings.hiddenFromUsers
        ]
        
        firestoreService.db.collection("users").document(userId).updateData([
            "contentVisibilitySettings": contentSettings
        ], completion: completion)
    }
}
