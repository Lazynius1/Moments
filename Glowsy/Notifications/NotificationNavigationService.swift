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
        case storyChain(String, String)        // 🔗 Ir a cadena de historias (chainId, chainTitle)
        case followRequests(String)            // Ir a solicitudes de seguimiento
        case notifications(String?)            // Ir a notificaciones (con filtro opcional)
        case echoSuggestion(String)              // ✅ NUEVO: Ir a invitación de Echo
        case echo(String)                        // ✅ NUEVO: Ir a visor de Echo (activo)
    }
    
    
    private init() {}
    
    // ✅ Helpers para navegación directa (usados por InAppBannerView)
    func navigateToMoment(momentId: String, userId: String) {
         pendingNavigation = .moment(momentId, userId)
    }
    
    func navigateToProfile(userId: String) {
        pendingNavigation = .profile(userId)
    }
    
    func navigateToNotifications(filter: String?) {
        pendingNavigation = .notifications(filter)
    }
    
    func navigateToStory(storyId: String) {
        pendingNavigation = .story(storyId)
    }
    
    func navigateToConversation(conversationId: String) {
        pendingNavigation = .conversation(conversationId)
    }
    
    // ✅ SIMPLIFICADO: Método para procesar datos de notificación
    func handleNotificationData(_ userInfo: [AnyHashable: Any]) {
        guard let type = userInfo["type"] as? String else {
            return
        }
        
        switch type {
        case "moment_reaction":
            if let momentId = userInfo["momentId"] as? String,
               let userId = userInfo["momentOwnerId"] as? String {
                pendingNavigation = .moment(momentId, userId)
            }
            
        case "moment_comment":
            if let momentId = userInfo["momentId"] as? String,
               let userId = userInfo["momentOwnerId"] as? String {
                pendingNavigation = .moment(momentId, userId)
            }
            
        case "story_reaction":
            if let storyId = userInfo["storyId"] as? String {
                pendingNavigation = .notifications(storyId)
            }
            
        case "new_follower":
            if let userId = userInfo["followerId"] as? String ?? userInfo["senderId"] as? String {
                pendingNavigation = .profile(userId)
            }
            
        case "mutualConnection":
            if let userId = userInfo["senderId"] as? String {
                pendingNavigation = .profile(userId)
            }
            
        case "new_message":
            if let conversationId = userInfo["conversationId"] as? String {
                pendingNavigation = .conversation(conversationId)
            }
            
        case "follow_request":
            if let requestId = userInfo["requestId"] as? String {
                pendingNavigation = .followRequests(requestId)
            }
            
        case "mention":
            if let userId = userInfo["senderId"] as? String {
                pendingNavigation = .profile(userId)
            }
            
        // 🔗 STORY CHAINS: Notificación cuando alguien continúa una cadena
        case "story_chain_continued":
            if let chainId = userInfo["chainId"] as? String,
               let chainTitle = userInfo["chainTitle"] as? String {
                pendingNavigation = .storyChain(chainId, chainTitle)
            }
            
        // ✅ CASO LEGACY: Para notificaciones antiguas de tipo 'like'
        case "echo_suggestion":
            if let echoId = userInfo["echoId"] as? String {
                pendingNavigation = .echoSuggestion(echoId)
            }
            
        case "like":
            if let momentId = userInfo["momentId"] as? String {
                // ✅ BUSCAR userId en la notificación legacy
                if let userId = userInfo["momentOwnerId"] as? String {
                    pendingNavigation = .moment(momentId, userId)
                } else {
                    // ✅ FALLBACK: Si no hay userId, ir a notificaciones
                    pendingNavigation = .notifications(nil)
                }
            }
            
        default:
            pendingNavigation = .notifications(nil)
        }
        
    }
    
    // ✅ MÉTODO para limpiar navegación pendiente
    func clearPendingNavigation() {
        pendingNavigation = nil
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
        case .storyChain(let chainId, let chainTitle):
            return "cadena(\(chainId), \(chainTitle))"  // 🔗 AÑADIDO
        case .followRequests(let id):
            return "solicitudes(\(id))"
        case .notifications(let filter):
            return "notificaciones(\(filter ?? "todas"))"
        case .echoSuggestion(let id):
            return "invitacionEcho(\(id))"
        case .echo(let id):
            return "verEcho(\(id))"
        }
    }
    
    // ✅ SIMPLIFICADA: Categoría de navegación para analytics
    var category: String {
        switch self {
        case .moment: return "moment"
        case .profile: return "profile"
        case .conversation: return "chat"
        case .story: return "story"
        case .storyChain: return "story_chain"  // 🔗 AÑADIDO
        case .followRequests: return "social"
        case .notifications: return "notifications"
        case .echoSuggestion: return "echo_invite"
        case .echo: return "echo_view"
        }
    }
}
