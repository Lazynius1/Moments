import FirebaseFirestore
import FirebaseAuth

class PrivacyService {
    private let db: Firestore
    private let firestoreService = FirestoreService()

    init() {
        db = Firestore.firestore()
    }

    // MARK: - Privacy Settings Management
    
    // ✅ FUNCIÓN PRINCIPAL ACTUALIZADA: Verificar si un momento debe aparecer en el feed
    func shouldShowInFeed(viewerId: String, moment: Moment, completion: @escaping (Bool) -> Void) {
        // 1. Si es mi propio momento, siempre mostrarlo
        if moment.authorId == viewerId {
            completion(true)
            return
        }
        
        // 2. Verificar bloqueos primero (en ambas direcciones)
        checkMutualBlocks(viewerId: viewerId, targetUserId: moment.authorId) { [weak self] isBlocked in
            if isBlocked {
                print("🚫 Momento filtrado: hay bloqueos entre \(viewerId) y \(moment.authorId)")
                completion(false)
                return
            }
            
            // 3. Verificar si sigo al autor del momento
            self?.firestoreService.isFollowing(currentUserId: viewerId, targetUserId: moment.authorId) { isFollowing in
                if !isFollowing {
                    print("❌ Momento filtrado: \(viewerId) no sigue a \(moment.authorId)")
                    completion(false)
                    return
                }
                
                // 4. Verificar configuración de privacidad del autor
                self?.fetchPrivacySettings(userId: moment.authorId) { result in
                    switch result {
                    case .success(let settings):
                        // Si el autor tiene perfil privado, verificar conexión mutua
                        if settings.isPrivate {
                            self?.firestoreService.isFollowing(currentUserId: moment.authorId, targetUserId: viewerId) { authorFollowsBack in
                                if authorFollowsBack {
                                    print("✅ Momento mostrado: perfil privado con seguimiento mutuo")
                                    completion(true)
                                } else {
                                    print("❌ Momento filtrado: perfil privado sin seguimiento mutuo")
                                    completion(false)
                                }
                            }
                        } else {
                            print("✅ Momento mostrado: perfil público y lo sigo")
                            completion(true)
                        }
                    case .failure(let error):
                        print("❌ Error obteniendo configuración de privacidad: \(error.localizedDescription)")
                        completion(false)
                    }
                }
            }
        }
    }
    
    func fetchPrivacySettings(userId: String, completion: @escaping (Result<(isPrivate: Bool, showMutualConnections: Bool, showFollowing: Bool), Error>) -> Void) {
        db.collection("users").document(userId).getDocument { snapshot, error in
            if let error = error {
                print("Error fetching privacy settings: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }

            guard let document = snapshot, document.exists, let data = document.data() else {
                print("User document not found for userId: \(userId)")
                completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "User document not found"])))
                return
            }

            let isPrivate = data["isPrivate"] as? Bool ?? false
            let showMutualConnections = data["showMutualConnections"] as? Bool ?? true
            let showFollowing = data["showFollowing"] as? Bool ?? true

            completion(.success((isPrivate: isPrivate, showMutualConnections: showMutualConnections, showFollowing: showFollowing)))
        }
    }

    func updatePrivacySettings(userId: String, isPrivate: Bool? = nil, showMutualConnections: Bool? = nil, showFollowing: Bool? = nil, completion: @escaping (Error?) -> Void) {
        var updateData: [String: Any] = [:]

        if let isPrivate = isPrivate {
            updateData["isPrivate"] = isPrivate
        }
        if let showMutualConnections = showMutualConnections {
            updateData["showMutualConnections"] = showMutualConnections
        }
        if let showFollowing = showFollowing {
            updateData["showFollowing"] = showFollowing
        }

        guard !updateData.isEmpty else {
            print("No privacy settings to update")
            completion(nil)
            return
        }

        db.collection("users").document(userId).updateData(updateData) { error in
            if let error = error {
                print("Error updating privacy settings: \(error.localizedDescription)")
                completion(error)
            } else {
                print("Privacy settings updated successfully")
                completion(nil)
            }
        }
    }

    // MARK: - Content Visibility Logic

    // ✅ ACTUALIZADA: Esta es la función MÁS IMPORTANTE - determina si puedes ver el contenido de alguien
    func canViewUserContent(viewerId: String, targetUserId: String, completion: @escaping (Bool) -> Void) {
        // Si es el mismo usuario, siempre puede ver su propio contenido
        guard viewerId != targetUserId else {
            completion(true)
            return
        }
        
        // Primero verificar si está bloqueado (en ambas direcciones)
        checkMutualBlocks(viewerId: viewerId, targetUserId: targetUserId) { [weak self] isBlocked in
            if isBlocked {
                completion(false)
                return
            }
            
            // Luego verificar privacidad del usuario objetivo
            self?.fetchPrivacySettings(userId: targetUserId) { result in
                switch result {
                case .success(let settings):
                    // Si el perfil es público, cualquiera puede ver el contenido
                    if !settings.isPrivate {
                        completion(true)
                        return
                    }
                    
                    // Si el perfil es privado, solo los seguidores pueden ver el contenido
                    self?.firestoreService.isFollowing(currentUserId: viewerId, targetUserId: targetUserId) { isFollowing in
                        completion(isFollowing)
                    }
                    
                case .failure(let error):
                    print("Error checking privacy settings: \(error)")
                    completion(false)
                }
            }
        }
    }
    
    // ✅ FUNCIÓN CORREGIDA: Ahora interpreta correctamente los toggles
    func canViewUserConnections(viewerId: String, targetUserId: String, completion: @escaping (Result<(canViewMutualConnections: Bool, canViewFollowing: Bool), Error>) -> Void) {
        // Si es el mismo usuario, siempre puede ver sus propias listas
        guard viewerId != targetUserId else {
            completion(.success((canViewMutualConnections: true, canViewFollowing: true)))
            return
        }
        
        fetchPrivacySettings(userId: targetUserId) { [weak self] result in
            switch result {
            case .success(let settings):
                print("🔍 Privacy settings for \(targetUserId):")
                print("   - isPrivate: \(settings.isPrivate)")
                print("   - showMutualConnections: \(settings.showMutualConnections)")
                print("   - showFollowing: \(settings.showFollowing)")
                
                // Verificar si está bloqueado (en ambas direcciones)
                self?.checkMutualBlocks(viewerId: viewerId, targetUserId: targetUserId) { isBlocked in
                    if isBlocked {
                        print("🚫 Conexiones ocultas: hay bloqueos")
                        completion(.success((canViewMutualConnections: false, canViewFollowing: false)))
                        return
                    }
                    
                    // ✅ CORRECCIÓN CLAVE: Interpretar los toggles correctamente
                    // Si showMutualConnections = true, significa "permitir ver"
                    // Si showMutualConnections = false, significa "ocultar"
                    // Lo mismo para showFollowing
                    
                    // Si el perfil es público
                    if !settings.isPrivate {
                        print("🌍 Perfil público - aplicando configuraciones:")
                        print("   - Puede ver mutuas: \(settings.showMutualConnections)")
                        print("   - Puede ver siguiendo: \(settings.showFollowing)")
                        completion(.success((
                            canViewMutualConnections: settings.showMutualConnections,
                            canViewFollowing: settings.showFollowing
                        )))
                        return
                    }
                    
                    // Si el perfil es privado, verificar si es seguidor
                    self?.firestoreService.isFollowing(currentUserId: viewerId, targetUserId: targetUserId) { isFollowing in
                        if isFollowing {
                            print("🔒 Perfil privado pero lo sigue - aplicando configuraciones:")
                            print("   - Puede ver mutuas: \(settings.showMutualConnections)")
                            print("   - Puede ver siguiendo: \(settings.showFollowing)")
                            completion(.success((
                                canViewMutualConnections: settings.showMutualConnections,
                                canViewFollowing: settings.showFollowing
                            )))
                        } else {
                            print("🔒 Perfil privado y no lo sigue - sin acceso a conexiones")
                            completion(.success((canViewMutualConnections: false, canViewFollowing: false)))
                        }
                    }
                }
                
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // ✅ FUNCIÓN CORREGIDA: Ahora interpreta correctamente las configuraciones
    func getVisibleConnectionTypes(viewerId: String, targetUserId: String, completion: @escaping (VisibleConnectionTypes) -> Void) {
        canViewUserConnections(viewerId: viewerId, targetUserId: targetUserId) { result in
            switch result {
            case .success(let permissions):
                // ✅ CORRECCIÓN: Mapear correctamente las configuraciones
                let visibleTypes = VisibleConnectionTypes(
                    canViewAdmirers: permissions.canViewFollowing,  // Admirers = seguidores del target
                    canViewConnections: permissions.canViewFollowing, // Connections = a quién sigue el target
                    canViewMutualConnections: permissions.canViewMutualConnections
                )
                
                print("📊 Tipos de conexiones visibles para \(viewerId) viendo a \(targetUserId):")
                print("   - Admirers (seguidores): \(visibleTypes.canViewAdmirers)")
                print("   - Connections (siguiendo): \(visibleTypes.canViewConnections)")
                print("   - Mutual: \(visibleTypes.canViewMutualConnections)")
                
                completion(visibleTypes)
            case .failure:
                // En caso de error, denegar todo acceso
                print("❌ Error al verificar permisos - denegando acceso a todas las conexiones")
                completion(VisibleConnectionTypes(
                    canViewAdmirers: false,
                    canViewConnections: false,
                    canViewMutualConnections: false
                ))
            }
        }
    }
    
    // MARK: - Helper Methods
    
    // ✅ NUEVA FUNCIÓN: Verificar bloqueos mutuos (en ambas direcciones)
     func checkMutualBlocks(viewerId: String, targetUserId: String, completion: @escaping (Bool) -> Void) {
        firestoreService.checkIfBlocked(currentUserId: viewerId, targetUserId: targetUserId) { isBlockedByViewer, isViewerBlocked, error in
            if let error = error {
                print("Error verificando bloqueos mutuos: \(error.localizedDescription)")
                completion(true) // En caso de error, ser conservador y bloquear
                return
            }
            
            // Si hay bloqueo en cualquier dirección, considerarlo como bloqueado
            let isBlocked = isBlockedByViewer || isViewerBlocked
            completion(isBlocked)
        }
    }
    
    // ✅ FUNCIÓN SIMPLIFICADA: Solo verificar si el target ha bloqueado al viewer
    private func checkIfBlocked(viewerId: String, targetUserId: String, completion: @escaping (Bool) -> Void) {
        db.collection("users").document(targetUserId).getDocument { snapshot, error in
            if let error = error {
                print("Error checking if blocked: \(error.localizedDescription)")
                completion(false)
                return
            }
            
            guard let document = snapshot, document.exists, let data = document.data() else {
                completion(false)
                return
            }
            
            let blockedUsers = data["blockedUsers"] as? [String] ?? []
            completion(blockedUsers.contains(viewerId))
        }
    }
    
    // MARK: - Profile Interaction Logic
    
    // ✅ ACTUALIZADA: Verificar si se puede enviar solicitud de seguimiento
    func canSendFollowRequest(viewerId: String, targetUserId: String, completion: @escaping (Bool) -> Void) {
        // No puedes enviarte solicitud a ti mismo
        guard viewerId != targetUserId else {
            completion(false)
            return
        }
        
        // Verificar si está bloqueado (en ambas direcciones)
        checkMutualBlocks(viewerId: viewerId, targetUserId: targetUserId) { [weak self] isBlocked in
            if isBlocked {
                completion(false)
                return
            }
            
            // Verificar si ya sigue al usuario
            self?.firestoreService.isFollowing(currentUserId: viewerId, targetUserId: targetUserId) { isFollowing in
                if isFollowing {
                    completion(false) // Ya lo sigue
                    return
                }
                
                // Verificar si el perfil es privado
                self?.fetchPrivacySettings(userId: targetUserId) { result in
                    switch result {
                    case .success(let settings):
                        // Solo necesita solicitud si el perfil es privado
                        completion(settings.isPrivate)
                    case .failure:
                        completion(false)
                    }
                }
            }
        }
    }
    
    // ✅ ACTUALIZADA: Obtener estado del botón de seguir
    func getFollowButtonState(viewerId: String, targetUserId: String, completion: @escaping (FollowButtonState) -> Void) {
        guard viewerId != targetUserId else {
            completion(.ownProfile)
            return
        }
        
        checkMutualBlocks(viewerId: viewerId, targetUserId: targetUserId) { [weak self] isBlocked in
            if isBlocked {
                completion(.blocked)
                return
            }
            
            self?.firestoreService.isFollowing(currentUserId: viewerId, targetUserId: targetUserId) { isFollowing in
                if isFollowing {
                    completion(.following)
                    return
                }
                
                // Verificar si hay solicitud pendiente
                self?.checkPendingFollowRequest(senderId: viewerId, recipientId: targetUserId) { hasPendingRequest in
                    if hasPendingRequest {
                        completion(.requestPending)
                        return
                    }
                    
                    // Verificar si el perfil es privado
                    self?.fetchPrivacySettings(userId: targetUserId) { result in
                        switch result {
                        case .success(let settings):
                            if settings.isPrivate {
                                completion(.canRequestFollow)
                            } else {
                                completion(.canFollow)
                            }
                        case .failure:
                            completion(.canFollow)
                        }
                    }
                }
            }
        }
    }
    
    // ✅ NUEVA FUNCIÓN: Verificar si dos usuarios pueden interactuar (sin bloqueos)
    func canUsersInteract(user1Id: String, user2Id: String, completion: @escaping (Bool) -> Void) {
        checkMutualBlocks(viewerId: user1Id, targetUserId: user2Id) { isBlocked in
            completion(!isBlocked)
        }
    }
    
    // ✅ NUEVA FUNCIÓN: Verificar si un usuario puede enviar mensajes a otro
    func canSendMessage(senderId: String, recipientId: String, completion: @escaping (Bool) -> Void) {
        guard senderId != recipientId else {
            completion(false) // No puedes enviarte mensajes a ti mismo
            return
        }
        
        checkMutualBlocks(viewerId: senderId, targetUserId: recipientId) { [weak self] isBlocked in
            if isBlocked {
                completion(false)
                return
            }
            
            // Verificar si siguen mutuamente (para perfiles privados)
            self?.firestoreService.isFollowing(currentUserId: senderId, targetUserId: recipientId) { senderFollowsRecipient in
                if !senderFollowsRecipient {
                    // Si no sigue al receptor, verificar si el receptor tiene perfil público
                    self?.fetchPrivacySettings(userId: recipientId) { result in
                        switch result {
                        case .success(let settings):
                            // Solo puede enviar mensaje si el perfil es público
                            completion(!settings.isPrivate)
                        case .failure:
                            completion(false)
                        }
                    }
                } else {
                    // Si sigue al receptor, puede enviar mensaje
                    completion(true)
                }
            }
        }
    }
    
    // ✅ FUNCIÓN EXISTENTE: Verificar solicitud de seguimiento pendiente
    private func checkPendingFollowRequest(senderId: String, recipientId: String, completion: @escaping (Bool) -> Void) {
        db.collection("users").document(senderId).collection("sentFollowRequests")
            .whereField("recipientId", isEqualTo: recipientId)
            .whereField("status", isEqualTo: FollowRequestStatus.pending.rawValue)
            .limit(to: 1)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("Error checking pending request: \(error)")
                    completion(false)
                    return
                }
                
                completion(!(snapshot?.documents.isEmpty ?? true))
            }
    }
    
    // ✅ NUEVA FUNCIÓN: Guardar audiencia personalizada correctamente
    func saveCustomAudienceForMoment(
        momentId: String,
        authorId: String,
        allowedUsers: [String],
        completion: @escaping (Error?) -> Void
    ) {
        let data: [String: Any] = [
            "contentType": "moment",
            "allowedUsers": allowedUsers,
            "createdAt": FieldValue.serverTimestamp()
        ]
        
        print("💾 Guardando audiencia personalizada para moment_\(momentId)")
        print("📊 Usuarios permitidos: \(allowedUsers)")
        
        db.collection("users").document(authorId)
            .collection("customAudiences")
            .document("moment_\(momentId)")
            .setData(data) { error in
                if let error = error {
                    print("❌ Error guardando audiencia personalizada: \(error)")
                } else {
                    print("✅ Audiencia personalizada guardada exitosamente")
                }
                completion(error)
            }
    }
    
    // ✅ NUEVA FUNCIÓN: Guardar audiencia personalizada para historia
    func saveCustomAudienceForStory(
        storyId: String,
        authorId: String,
        allowedUsers: [String],
        completion: @escaping (Error?) -> Void
    ) {
        let data: [String: Any] = [
            "contentType": "story",
            "allowedUsers": allowedUsers,
            "createdAt": FieldValue.serverTimestamp()
        ]
        
        print("💾 Guardando audiencia personalizada para story_\(storyId)")
        print("📊 Usuarios permitidos: \(allowedUsers)")
        
        db.collection("users").document(authorId)
            .collection("customAudiences")
            .document("story_\(storyId)")
            .setData(data) { error in
                if let error = error {
                    print("❌ Error guardando audiencia personalizada: \(error)")
                } else {
                    print("✅ Audiencia personalizada guardada exitosamente")
                }
                completion(error)
            }
    }
    
    // ✅ FUNCIÓN DE DEBUG: Verificar audiencias personalizadas
    func debugCustomAudiences(authorId: String) {
        print("🔍 Debug: Verificando audiencias personalizadas para \(authorId)")
        
        db.collection("users").document(authorId)
            .collection("customAudiences")
            .getDocuments { snapshot, error in
                if let error = error {
                    print("❌ Error obteniendo audiencias: \(error)")
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    print("📭 No se encontraron audiencias personalizadas")
                    return
                }
                
                print("📊 Audiencias encontradas: \(documents.count)")
                for document in documents {
                    let data = document.data()
                    let allowedUsers = data["allowedUsers"] as? [String] ?? []
                    print("   - \(document.documentID): \(allowedUsers)")
                }
            }
    }
}

struct VisibleConnectionTypes {
    let canViewAdmirers: Bool      // Puede ver los seguidores del target
    let canViewConnections: Bool   // Puede ver a quién sigue el target
    let canViewMutualConnections: Bool // Puede ver conexiones mutuas
}

// MARK: - Follow Button States

enum FollowButtonState {
    case ownProfile
    case blocked
    case following
    case canFollow
    case canRequestFollow
    case requestPending
    
    var buttonText: String {
        switch self {
        case .ownProfile:
            return "Tu perfil"
        case .blocked:
            return "Bloqueado"
        case .following:
            return "Siguiendo"
        case .canFollow:
            return "Seguir"
        case .canRequestFollow:
            return "Solicitar"
        case .requestPending:
            return "Solicitado"
        }
    }
    
    var isActionable: Bool {
        switch self {
        case .ownProfile, .blocked, .requestPending:
            return false
        case .following, .canFollow, .canRequestFollow:
            return true
        }
    }
    
    // ✅ NUEVA PROPIEDAD: Color del botón
    var buttonColor: String {
        switch self {
        case .ownProfile:
            return "gray"
        case .blocked:
            return "red"
        case .following:
            return "green"
        case .canFollow, .canRequestFollow:
            return "blue"
        case .requestPending:
            return "orange"
        }
    }
}

// MARK: - Extensión del PrivacyService para manejar audiencias de contenido

extension PrivacyService {
    
    // MARK: - Verificar conexión mutua
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
            completion(user1FollowsUser2 && user2FollowsUser1)
        }
    }
    
    // MARK: - Verificar si es mejor amigo
    private func checkIfBestFriend(userId: String, friendId: String, completion: @escaping (Bool) -> Void) {
        db.collection("users").document(userId).getDocument { snapshot, error in
            if let error = error {
                print("Error checking best friends: \(error)")
                completion(false)
                return
            }
            
            guard let data = snapshot?.data(),
                  let bestFriends = data["bestFriends"] as? [String] else {
                completion(false)
                return
            }
            
            completion(bestFriends.contains(friendId))
        }
    }
    
    // ✅ FUNCIÓN CORREGIDA: Verificar audiencia personalizada
    private func checkCustomAudience(contentType: String, contentId: String, authorId: String, viewerId: String, completion: @escaping (Bool) -> Void) {
        print("🎯 Verificando audiencia personalizada para \(contentType)_\(contentId)")
        
        db.collection("users").document(authorId)
            .collection("customAudiences")
            .document("\(contentType)_\(contentId)")
            .getDocument { snapshot, error in
                if let error = error {
                    print("❌ Error verificando audiencia personalizada: \(error)")
                    completion(false)
                    return
                }
                
                guard let data = snapshot?.data(),
                      let allowedUsers = data["allowedUsers"] as? [String] else {
                    print("❌ No se encontró audiencia personalizada para \(contentType)_\(contentId)")
                    completion(false)
                    return
                }
                
                let canView = allowedUsers.contains(viewerId)
                print("📊 Audiencia personalizada encontrada: \(allowedUsers)")
                print(canView ? "✅ Usuario \(viewerId) está en la audiencia" : "❌ Usuario \(viewerId) NO está en la audiencia")
                completion(canView)
            }
    }
    
    // MARK: - Verificar configuración de visibilidad de historias
    private func checkStoryVisibilitySettings(authorId: String, viewerId: String, completion: @escaping (Bool) -> Void) {
        db.collection("users").document(authorId).getDocument { snapshot, error in
            if let error = error {
                print("Error checking story visibility: \(error)")
                completion(false)
                return
            }
            
            guard let data = snapshot?.data(),
                  let settings = data["contentVisibilitySettings"] as? [String: Any],
                  let storyVisibility = settings["storyVisibility"] as? String else {
                // Sin configuración, usar default (everyone)
                self.canViewUserContent(viewerId: viewerId, targetUserId: authorId, completion: completion)
                return
            }
            
            switch storyVisibility {
            case "everyone":
                self.canViewUserContent(viewerId: viewerId, targetUserId: authorId, completion: completion)
            case "connections":
                self.checkMutualConnection(user1: viewerId, user2: authorId, completion: completion)
            case "bestFriends":
                self.checkIfBestFriend(userId: authorId, friendId: viewerId, completion: completion)
            case "custom":
                // Verificar lista personalizada global de historias
                if let customViewers = settings["customStoryViewers"] as? [String] {
                    completion(customViewers.contains(viewerId))
                } else {
                    completion(false)
                }
            default:
                completion(false)
            }
        }
    }
    
    // MARK: - Guardar audiencia personalizada para contenido
    func saveCustomAudience(contentType: String, contentId: String, authorId: String, allowedUsers: [String], completion: @escaping (Error?) -> Void) {
        let data: [String: Any] = [
            "contentType": contentType,
            "contentId": contentId,
            "allowedUsers": allowedUsers,
            "createdAt": FieldValue.serverTimestamp()
        ]
        
        db.collection("users").document(authorId)
            .collection("customAudiences")
            .document("\(contentType)_\(contentId)")
            .setData(data, completion: completion)
    }
    
    // MARK: - Obtener lista de usuarios que pueden ver contenido
    func getContentViewers(for moment: Moment, completion: @escaping ([String]) -> Void) {
        let audience = ContentAudience(rawValue: moment.audience ?? "everyone") ?? .everyone
        
        switch audience {
        case .everyone:
            // Todos los seguidores si el perfil es público, o conexiones mutuas si es privado
            fetchPotentialViewers(for: moment.authorId, completion: completion)
            
        case .connections:
            // Solo conexiones mutuas
            fetchMutualConnections(for: moment.authorId, completion: completion)
            
        case .bestFriends:
            // Solo mejores amigos
            fetchBestFriends(for: moment.authorId, completion: completion)
            
        case .custom:
            // Lista personalizada simple
            fetchCustomAudience(
                contentType: "moment",
                contentId: moment.id ?? "",
                authorId: moment.authorId,
                completion: completion
            )
            
        case .customList:
            // Lista personalizada reutilizable
            fetchCustomListViewers(
                for: moment,
                completion: completion
            )
            
        case .onlyMe:
            // Solo el autor
            completion([moment.authorId])
        }
    }
    
    // MARK: - Obtener viewers de lista personalizada
    private func fetchCustomListViewers(
        for moment: Moment,
        completion: @escaping ([String]) -> Void
    ) {
        guard let momentId = moment.id else {
            completion([])
            return
        }
        
        // Obtener el customListId del momento
        db.collection("users").document(moment.authorId)
            .collection("moments").document(momentId)
            .getDocument { [weak self] document, error in
                guard let data = document?.data(),
                      let customListId = data["customListId"] as? String else {
                    completion([])
                    return
                }
                
                // Obtener los miembros de la lista
                self?.getCustomListViewers(
                    listId: customListId,
                    ownerId: moment.authorId,
                    completion: completion
                )
            }
    }
    
    // MARK: - Verificar lista personalizada (método que faltaba)
    func checkCustomList(
        contentType: String,
        contentId: String,
        authorId: String,
        viewerId: String,
        completion: @escaping (Bool) -> Void
    ) {
        print("📝 Verificando lista personalizada para \(contentType)_\(contentId)")
        
        // Primero obtener el customListId del contenido
        let contentCollection = contentType == "story" ? "stories" : "moments"
        
        db.collection("users").document(authorId)
            .collection(contentCollection).document(contentId)
            .getDocument { [weak self] document, error in
                guard let data = document?.data(),
                      let customListId = data["customListId"] as? String else {
                    print("❌ No se encontró customListId para \(contentType)_\(contentId)")
                    completion(false)
                    return
                }
                
                // Verificar si el viewer está en la lista
                self?.checkUserInList(
                    userId: viewerId,
                    listId: customListId,
                    listOwnerId: authorId,
                    completion: completion
                )
            }
    }
    
    // MARK: - Helpers para obtener listas de usuarios
    private func fetchPotentialViewers(for userId: String, completion: @escaping ([String]) -> Void) {
        fetchPrivacySettings(userId: userId) { result in
            switch result {
            case .success(let settings):
                if settings.isPrivate {
                    // Si es privado, solo seguidores
                    self.firestoreService.fetchFollowers(userId: userId) { result in
                        switch result {
                        case .success(let followers):
                            completion(followers.map { $0.id })
                        case .failure:
                            completion([])
                        }
                    }
                } else {
                    // Si es público, potencialmente todos (pero limitamos a seguidores por practicidad)
                    self.firestoreService.fetchFollowers(userId: userId) { result in
                        switch result {
                        case .success(let followers):
                            completion(followers.map { $0.id })
                        case .failure:
                            completion([])
                        }
                    }
                }
            case .failure:
                completion([])
            }
        }
    }
    
    private func fetchMutualConnections(for userId: String, completion: @escaping ([String]) -> Void) {
        firestoreService.fetchMutualConnections(userId: userId) { result in
            switch result {
            case .success(let users):
                completion(users.map { $0.id })
            case .failure:
                completion([])
            }
        }
    }
    
    private func fetchBestFriends(for userId: String, completion: @escaping ([String]) -> Void) {
        db.collection("users").document(userId).getDocument { snapshot, error in
            guard let data = snapshot?.data(),
                  let bestFriends = data["bestFriends"] as? [String] else {
                completion([])
                return
            }
            completion(bestFriends)
        }
    }
    
    private func fetchCustomAudience(contentType: String, contentId: String, authorId: String, completion: @escaping ([String]) -> Void) {
        db.collection("users").document(authorId)
            .collection("customAudiences")
            .document("\(contentType)_\(contentId)")
            .getDocument { snapshot, error in
                guard let data = snapshot?.data(),
                      let allowedUsers = data["allowedUsers"] as? [String] else {
                    completion([])
                    return
                }
                completion(allowedUsers)
            }
    }
}

import FirebaseFirestore
import FirebaseAuth

// MARK: - Extensión del PrivacyService para Listas Personalizadas
extension PrivacyService {
    
    // MARK: - Verificar si usuario puede ver contenido con lista personalizada
    func canUserViewContentWithCustomList(
        _ content: ContentProtocol,
        viewerId: String,
        completion: @escaping (Bool) -> Void
    ) {
        // Si es el autor, siempre puede verlo
        if content.authorId == viewerId {
            completion(true)
            return
        }
        
        // Verificar bloqueos primero
        checkMutualBlocks(viewerId: viewerId, targetUserId: content.authorId) { [weak self] isBlocked in
            if isBlocked {
                completion(false)
                return
            }
            
            // Si el contenido tiene customListId, verificar membresía
            if let moment = content as? Moment {
                self?.checkCustomListMembership(
                    for: moment,
                    viewerId: viewerId,
                    completion: completion
                )
            } else if let story = content as? Story {
                self?.checkCustomListMembership(
                    for: story,
                    viewerId: viewerId,
                    completion: completion
                )
            } else {
                completion(false)
            }
        }
    }
    
    // En tu archivo PrivacyService.swift
    
    // MARK: - Verificar membresía en lista para Historia (CORREGIDO)
    private func checkCustomListMembership(
        for story: Story,
        viewerId: String,
        completion: @escaping (Bool) -> Void
    ) {
        // ✅ CORRECCIÓN: No es necesario volver a buscar el documento de la historia.
        // El 'customListId' ya debería estar en el objeto 'story' que recibimos.
        // Asumimos que tu modelo 'Story' tiene una propiedad 'customListId: String?'.
        
        guard let customListId = story.customListId, !customListId.isEmpty else {
            // Si la historia no tiene un ID de lista personalizada, el usuario no puede verla por este método.
            print("❌ La historia de \(story.authorId) no tiene un customListId asociado.")
            completion(false)
            return
        }
        
        print("📝 Verificando si \(viewerId) es miembro de la lista \(customListId) para la historia de \(story.authorId).")
        
        // Ahora que tenemos el ID de la lista, verificamos si el viewer es miembro.
        self.checkUserInList(
            userId: viewerId,
            listId: customListId,
            listOwnerId: story.authorId,
            completion: completion
        )
    }
    
    
    // MARK: - Verificar membresía en lista para Momento (CORREGIDO)
    private func checkCustomListMembership(
        for moment: Moment,
        viewerId: String,
        completion: @escaping (Bool) -> Void
    ) {
        // ✅ CORRECCIÓN: Lógica similar a la de las historias.
        // Asumimos que tu modelo 'Moment' tiene una propiedad 'customListId: String?'.
        
        guard let customListId = moment.customListId, !customListId.isEmpty else {
            // Si el momento no tiene un ID de lista personalizada, el usuario no puede verlo por este método.
            print("❌ El momento de \(moment.authorId) no tiene un customListId asociado.")
            completion(false)
            return
        }
        
        print("📝 Verificando si \(viewerId) es miembro de la lista \(customListId) para el momento de \(moment.authorId).")
        
        // Verificar si el viewer es miembro de la lista.
        self.checkUserInList(
            userId: viewerId,
            listId: customListId,
            listOwnerId: moment.authorId,
            completion: completion
        )
    }

    
    // MARK: - Verificar si usuario está en lista específica
    private func checkUserInList(
        userId: String,
        listId: String,
        listOwnerId: String,
        completion: @escaping (Bool) -> Void
    ) {
        db.collection("users").document(listOwnerId)
            .collection("customAudienceLists").document(listId)
            .getDocument { document, error in
                guard let data = document?.data(),
                      let members = data["members"] as? [String] else {
                    print("❌ Lista no encontrada o sin miembros: \(listId)")
                    completion(false)
                    return
                }
                
                let isMember = members.contains(userId)
                print(isMember ?
                      "✅ Usuario \(userId) está en la lista \(listId)" :
                      "❌ Usuario \(userId) NO está en la lista \(listId)")
                completion(isMember)
            }
    }
    
    // MARK: - Obtener todos los viewers permitidos para una lista
    func getCustomListViewers(
        listId: String,
        ownerId: String,
        completion: @escaping ([String]) -> Void
    ) {
        db.collection("users").document(ownerId)
            .collection("customAudienceLists").document(listId)
            .getDocument { document, error in
                guard let data = document?.data(),
                      let members = data["members"] as? [String] else {
                    completion([])
                    return
                }
                completion(members)
            }
    }
    
    // MARK: - Actualizar canUserViewMoment para soportar listas
    func canUserViewMomentEnhanced(_ moment: Moment, viewerId: String, completion: @escaping (Bool) -> Void) {
        guard let momentId = moment.id, !momentId.isEmpty else {
            print("❌ [PrivacyService] Momento sin ID válido")
            completion(false)
            return
        }
        
        print("🔍 Verificando si \(viewerId) puede ver momento \(momentId) de \(moment.authorId)")
        
        // 1. Si es el autor, siempre puede verlo
        if moment.authorId == viewerId {
            completion(true)
            return
        }
        
        // 2. Verificar bloqueos
        checkMutualBlocks(viewerId: viewerId, targetUserId: moment.authorId) { [weak self] isBlocked in
            guard let self = self else {
                print("❌ [PrivacyService] Self liberado durante verificación de bloqueos")
                completion(false)
                return
            }
            
            if isBlocked {
                print("🚫 [PrivacyService] Bloqueo detectado entre \(viewerId) y \(moment.authorId)")
                completion(false)
                return
            }
            
            // 3. Verificar según la audiencia del momento
            let audience = moment.audience ?? "everyone"
            
            switch audience {
            case "everyone":
                self.canViewUserContent(viewerId: viewerId, targetUserId: moment.authorId) { canView in
                    print("📜 [PrivacyService] everyone - Puede ver: \(canView)")
                    completion(canView)
                }
                
            case "connections":
                self.firestoreService.isFollowing(currentUserId: moment.authorId, targetUserId: viewerId) { authorFollowsViewer in
                    print("📜 [PrivacyService] connections - Sigue: \(authorFollowsViewer)")
                    completion(authorFollowsViewer)
                }
                
            case "bestFriends":
                self.checkIfBestFriend(userId: moment.authorId, friendId: viewerId) { isBestFriend in
                    print("📜 [PrivacyService] bestFriends - Es mejor amigo: \(isBestFriend)")
                    completion(isBestFriend)
                }
                
            case "custom":
                self.checkCustomAudience(
                    contentType: "moment",
                    contentId: momentId,
                    authorId: moment.authorId,
                    viewerId: viewerId
                ) { canView in
                    print("📜 [PrivacyService] custom - Puede ver: \(canView)")
                    completion(canView)
                }
                
            case "customList":
                self.checkCustomListMembership(
                    for: moment,
                    viewerId: viewerId
                ) { isMember in
                    print("📜 [PrivacyService] customList - Es miembro: \(isMember)")
                    completion(isMember)
                }
                
            default:
                print("❌ [PrivacyService] Audiencia desconocida: \(audience)")
                completion(false)
            }
        }
    }
    
    // MARK: - Actualizar canUserViewStory para soportar listas
    func canUserViewStoryEnhanced(_ story: Story, viewerId: String, completion: @escaping (Bool) -> Void) {
        print("🔍 Verificando si \(viewerId) puede ver historia de \(story.authorId)")
        
        // 1. Si es el autor, siempre puede verla
        if story.authorId == viewerId {
            completion(true)
            return
        }
        
        // 2. Verificar bloqueos
        checkMutualBlocks(viewerId: viewerId, targetUserId: story.authorId) { [weak self] isBlocked in
            if isBlocked {
                completion(false)
                return
            }
            
            // 3. Verificar audiencia de la historia
            let audience = story.audience ?? "everyone"
            
            switch audience {
            case "everyone":
                self?.canViewUserContent(viewerId: viewerId, targetUserId: story.authorId, completion: completion)
                
            case "connections":
                self?.checkMutualConnection(user1: viewerId, user2: story.authorId, completion: completion)
                
            case "bestFriends":
                self?.checkIfBestFriend(userId: story.authorId, friendId: viewerId, completion: completion)
                
            case "custom":
                // Audiencia personalizada simple
                self?.checkCustomAudience(
                    contentType: "story",
                    contentId: story.id ?? "",
                    authorId: story.authorId,
                    viewerId: viewerId,
                    completion: completion
                )
                
            case "customList":
                // Nueva audiencia: lista personalizada reutilizable
                self?.checkCustomListMembership(
                    for: story,
                    viewerId: viewerId,
                    completion: completion
                )
                
            case "onlyMe":
                completion(false)
                
            default:
                completion(false)
            }
        }
    }
}

// MARK: - Protocolo para contenido con lista personalizada
protocol CustomListContent {
    var authorId: String { get }
    var customListId: String? { get }
}

extension PrivacyService {
    
    // ✅ NUEVA FUNCIÓN: Verificar visibilidad para ExploreView (más permisiva)
    func canUserViewMomentInExplore(_ moment: Moment, viewerId: String, completion: @escaping (Bool) -> Void) {
        print("🔍 [Explore] Verificando si \(viewerId) puede ver momento de \(moment.authorId) con audiencia: \(moment.audience ?? "everyone")")
        
        // 1. Si es el autor, siempre puede verlo
        if moment.authorId == viewerId {
            completion(true)
            return
        }
        
        // 2. Verificar bloqueos primero (esto siempre aplica)
        checkMutualBlocks(viewerId: viewerId, targetUserId: moment.authorId) { [weak self] isBlocked in
            if isBlocked {
                print("❌ [Explore] Momento filtrado: hay bloqueos entre usuarios")
                completion(false)
                return
            }
            
            // 3. Verificar según la audiencia del momento
            let audience = moment.audience ?? "everyone"
            
            switch audience {
            case "everyone":
                // Para contenido público, solo verificar si el perfil del autor es accesible
                print("📢 [Explore] Momento público - verificando acceso al perfil")
                self?.canViewUserContentForExplore(viewerId: viewerId, targetUserId: moment.authorId, completion: completion)
                
            case "connections":
                // Solo mostrar si hay conexión mutua
                print("👥 [Explore] Momento para conexiones - verificando conexión mutua")
                self?.checkMutualConnection(user1: viewerId, user2: moment.authorId, completion: completion)
                
            case "bestFriends":
                // Solo mostrar si es mejor amigo
                print("⭐ [Explore] Momento para mejores amigos - verificando membresía")
                self?.checkIfBestFriend(userId: moment.authorId, friendId: viewerId, completion: completion)
                
            case "custom":
                // Solo mostrar si está en la audiencia personalizada
                print("🎯 [Explore] Momento con audiencia personalizada - verificando membresía")
                self?.checkCustomAudience(
                    contentType: "moment",
                    contentId: moment.id ?? "",
                    authorId: moment.authorId,
                    viewerId: viewerId,
                    completion: completion
                )
                
            case "customList":
                // Solo mostrar si está en la lista personalizada
                print("📝 [Explore] Momento con lista personalizada - verificando membresía")
                self?.checkCustomListMembership(
                    for: moment,
                    viewerId: viewerId,
                    completion: completion
                )
                
            case "onlyMe":
                // Nunca mostrar en Explore (solo para el autor)
                print("🔒 [Explore] Momento privado - no mostrar")
                completion(false)
                
            default:
                print("❓ [Explore] Audiencia desconocida: \(audience)")
                completion(false)
            }
        }
    }
    
    // ✅ NUEVA FUNCIÓN: Verificar acceso al perfil para ExploreView (más permisiva)
     func canViewUserContentForExplore(viewerId: String, targetUserId: String, completion: @escaping (Bool) -> Void) {
        // Si es el mismo usuario, siempre puede ver su propio contenido
        guard viewerId != targetUserId else {
            completion(true)
            return
        }
        
        // Verificar configuración de privacidad del usuario objetivo
        fetchPrivacySettings(userId: targetUserId) { result in
            switch result {
            case .success(let settings):
                if !settings.isPrivate {
                    // ✅ PERFIL PÚBLICO: Mostrar en Explore
                    print("🌍 [Explore] Perfil público - contenido visible")
                    completion(true)
                } else {
                    // ❌ PERFIL PRIVADO: Solo mostrar si lo sigue
                    print("🔒 [Explore] Perfil privado - verificando si lo sigue")
                    self.firestoreService.isFollowing(currentUserId: viewerId, targetUserId: targetUserId) { isFollowing in
                        print(isFollowing ?
                              "✅ [Explore] Lo sigue - contenido visible" :
                              "❌ [Explore] No lo sigue - contenido oculto")
                        completion(isFollowing)
                    }
                }
                
            case .failure(let error):
                print("❌ [Explore] Error verificando configuración de privacidad: \(error)")
                completion(false)
            }
        }
    }
}

extension PrivacyService {
    func canShareMoment(_ moment: Moment) -> Bool {
        let audience = moment.audience ?? "everyone"
        return audience == "everyone"
    }
}
