import Foundation
import SwiftUI

class NotificationNavigationService: ObservableObject {
    static let shared = NotificationNavigationService()
    
    @Published var pendingNavigation: PendingNavigation?
    
    enum PendingNavigation: Equatable {
        case moment(String, String)                    // Ir a momento específico
        case profile(String)                   // Ir a perfil de usuario
        case conversation(String)              // Ir a conversación específica
        case story(String)                     // Ir a historia específica
        case followRequests(String)            // Ir a solicitudes de seguimiento
        case notifications(String?)            // Ir a notificaciones (con filtro opcional)
        // ✅ ELIMINADO: groupedReactions - Ya no necesario con agrupación nativa
    }
    
    
    private init() {}
    
    // ✅ SIMPLIFICADO: Método para procesar datos de notificación
    func handleNotificationData(_ userInfo: [AnyHashable: Any]) {
        guard let type = userInfo["type"] as? String else {
            print("⚠️ Tipo de notificación no encontrado")
            return
        }
        
        print("🔔 Procesando notificación tipo: \(type)")
        
        switch type {
        case "moment_reaction":
            if let momentId = userInfo["momentId"] as? String,
               let userId = userInfo["momentOwnerId"] as? String {
                pendingNavigation = .moment(momentId, userId)
                print("🔔 Navegación configurada: momento(\(momentId), \(userId))")
            }
            
        case "moment_comment":
            if let momentId = userInfo["momentId"] as? String,
               let userId = userInfo["momentOwnerId"] as? String {
                pendingNavigation = .moment(momentId, userId)
                print("🔔 Navegación configurada: comentario en momento(\(momentId), \(userId))")
            }
            
        case "story_reaction":
            if let storyId = userInfo["storyId"] as? String {
                pendingNavigation = .notifications(storyId)
                print("🔔 Navegación configurada: reacción en historia(\(storyId))")
            }
            
        case "new_follower":
            if let userId = userInfo["followerId"] as? String ?? userInfo["senderId"] as? String {
                pendingNavigation = .profile(userId)
                print("🔔 Navegación configurada: nuevo seguidor(\(userId))")
            }
            
        case "mutualConnection":
            if let userId = userInfo["senderId"] as? String {
                pendingNavigation = .profile(userId)
                print("🔔 Navegación configurada: conexión mutua(\(userId))")
            }
            
        case "new_message":
            if let conversationId = userInfo["conversationId"] as? String {
                pendingNavigation = .conversation(conversationId)
                print("🔔 Navegación configurada: mensaje(\(conversationId))")
            }
            
        case "follow_request":
            if let requestId = userInfo["requestId"] as? String {
                pendingNavigation = .followRequests(requestId)
                print("🔔 Navegación configurada: solicitud de seguimiento(\(requestId))")
            }
            
        case "mention":
            if let userId = userInfo["senderId"] as? String {
                pendingNavigation = .profile(userId)
                print("🔔 Navegación configurada: mención de usuario(\(userId))")
            }
            
        // ✅ ACTUALIZAR: Caso legacy con userId
        case "like":
            if let momentId = userInfo["momentId"] as? String {
                // ✅ BUSCAR userId en la notificación legacy
                if let userId = userInfo["momentOwnerId"] as? String {
                    pendingNavigation = .moment(momentId, userId)
                    print("🔔 Navegación configurada: like en momento(\(momentId), \(userId))")
                } else {
                    // ✅ FALLBACK: Si no hay userId, ir a notificaciones
                    print("⚠️ Like legacy sin userId, enviando a notificaciones")
                    pendingNavigation = .notifications(nil)
                }
            }
            
        default:
            print("⚠️ Tipo de notificación no manejado: \(type)")
            pendingNavigation = .notifications(nil)
        }
        
        print("🔔 Navegación procesada: \(type) -> \(pendingNavigation?.description ?? "ninguna")")
    }
    
    // ✅ MÉTODO para limpiar navegación pendiente
    func clearPendingNavigation() {
        pendingNavigation = nil
        print("🧹 Navegación pendiente limpiada")
    }
}

// ✅ SIMPLIFICADA: Extensión para debugging
extension NotificationNavigationService.PendingNavigation {
    var description: String {
        switch self {
        case .moment(let momentId, let userId):
            return "momento(\(momentId), \(userId))"  // ✅ CAMBIAR
        case .profile(let id):
            return "perfil(\(id))"
        case .conversation(let id):
            return "conversación(\(id))"
        case .story(let id):
            return "historia(\(id))"
        case .followRequests(let id):
            return "solicitudes(\(id))"
        case .notifications(let filter):
            return "notificaciones(\(filter ?? "todas"))"
        }
    }
    
    // ✅ SIMPLIFICADA: Categoría de navegación para analytics
    var category: String {
        switch self {
        case .moment: return "moment"
        case .profile: return "profile"
        case .conversation: return "chat"
        case .story: return "story"
        case .followRequests: return "social"
        case .notifications: return "notifications"
        }
    }
}
