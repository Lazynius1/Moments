import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - Extensión para Filtrado de Contenido Visible (Momentos)
extension PrivacyService {
    
    // ✅ Filtrar array de momentos según visibilidad para un usuario
    func filterVisibleContent(moments: [Moment], for viewerId: String, completion: @escaping ([Moment]) -> Void) {
        if moments.isEmpty {
            completion([])
            return
        }
        
        let group = DispatchGroup()
        var visibleMomentsDict: [String: Moment] = [:] // Usar dict para evitar duplicados y facilitar concurrencia
        let lock = NSLock()
        
        for moment in moments {
            group.enter()
            canViewMoment(moment: moment, viewerId: viewerId) { canView in
                if canView {
                    lock.lock()
                    if let id = moment.id {
                        visibleMomentsDict[id] = moment
                    }
                    lock.unlock()
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            // Reconstruir array manteniendo el orden original
            let filtered = moments.filter { moment in
                guard let id = moment.id else { return false }
                return visibleMomentsDict[id] != nil
            }
            completion(filtered)
        }
    }
    
    // ✅ Verificar si un momento específico es visible
    func canViewMoment(moment: Moment, viewerId: String, completion: @escaping (Bool) -> Void) {
        // 1. Autor siempre puede ver
        if moment.authorId == viewerId {
            completion(true)
            return
        }
        
        // 1.5. Usuario etiquetado siempre puede ver
        if let taggedUsers = moment.taggedUsers, taggedUsers.contains(viewerId) {
            completion(true)
            return
        }
        
        // 2. Verificar acceso base al perfil (bloqueos y privacidad de cuenta)
        canViewUserContent(viewerId: viewerId, targetUserId: moment.authorId) { [weak self] baseAccess in
            guard let self = self, baseAccess else {
                completion(false)
                return
            }
            
            // 3. Verificar audiencia específica del momento
            let audience = moment.audience ?? "everyone"
            
            switch audience {
            case "everyone":
                completion(true)
                
            case "connections":
                self.checkMutualConnection(user1: viewerId, user2: moment.authorId, completion: completion)
                
            case "bestFriends":
                self.checkIfBestFriend(userId: moment.authorId, friendId: viewerId, completion: completion)
                
            case "custom", "customList":
                // 1. Prioridad: Lista dinámica (si existe ID de lista)
                if let listId = moment.customListId, !listId.isEmpty {
                    self.checkDynamicCustomList(authorId: moment.authorId, listId: listId, viewerId: viewerId, completion: completion)
                    return
                }
                
                // 2. Fallback: Array estático en el objeto (si existe)
                if let customViewers = moment.customViewers {
                    completion(customViewers.contains(viewerId))
                } else if let momentId = moment.id {
                    // 3. Fallback final: Snapshot guardado en subcolección (legacy o ad-hoc)
                    self.checkCustomAudience(contentType: "moment", contentId: momentId, authorId: moment.authorId, viewerId: viewerId, completion: completion)
                } else {
                    completion(false)
                }
                
            case "onlyMe":
                completion(false)
                
            default:
                completion(false)
            }
        }
    }

    
    // ✅ Helper para verificar lista dinámica en tiempo real
    private func checkDynamicCustomList(authorId: String, listId: String, viewerId: String, completion: @escaping (Bool) -> Void) {
        let db = Firestore.firestore()
        db.collection("users").document(authorId)
            .collection("customAudienceLists").document(listId)
            .getDocument { snapshot, error in
                guard let data = snapshot?.data(),
                      let members = data["members"] as? [String] else {
                    completion(false) // Si la lista no existe o no tiene miembros
                    return
                }
                completion(members.contains(viewerId))
            }
    }
}
