import Foundation

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
        canUserViewMomentEnhanced(moment, viewerId: viewerId, completion: completion)
    }
}
