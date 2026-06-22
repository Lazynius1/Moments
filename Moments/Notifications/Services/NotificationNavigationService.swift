import Foundation
import SwiftUI

class NotificationNavigationService: ObservableObject {
    static let shared = NotificationNavigationService()
    
    @Published var pendingNavigation: PendingNavigation?
    
    enum PendingNavigation: Equatable {
        case moment(String, String)                    // Ir a momento específico
        case profile(String)                   // Ir a perfil de usuario
        case conversation(String)              // Ir a conversación específica
        case story(storyId: String, authorId: String?) // Ir a historia específica
        case storyChain(String, String)        // 🔗 Ir a cadena de historias (chainId, chainTitle)
        case followRequests(String)            // Ir a solicitudes de seguimiento
        case notifications(String?)            // Ir a notificaciones (con filtro opcional)
        case creator                           // Abrir creador para un nuevo momento
        case echoSuggestion(String)              // ✅ NUEVO: Ir a invitación de Echo
        case echo(String)                        // ✅ NUEVO: Ir a visor de Echo (activo)
    }
    
    
    private init() {}
    
    func syncPendingNavigation(from destination: AppRouter.Destination) {
        pendingNavigation = destination.legacyPendingNavigation
    }

    // ✅ Helpers para navegación directa (usados por InAppBannerView)
    func navigateToMoment(momentId: String, userId: String) {
        AppRouter.shared.navigate(to: .moment(id: momentId, authorId: userId))
    }
    
    func navigateToProfile(userId: String) {
        AppRouter.shared.navigate(to: .profile(userId: userId))
    }
    
    func navigateToNotifications(filter: String?) {
        AppRouter.shared.navigate(to: .notifications(filter: filter))
    }
    
    func navigateToStory(storyId: String) {
        navigateToStory(storyId: storyId, authorId: nil)
    }

    func navigateToStory(storyId: String, authorId: String?) {
        AppRouter.shared.navigate(to: .story(storyId: storyId, authorId: authorId))
    }
    
    func navigateToConversation(conversationId: String) {
        AppRouter.shared.navigate(to: .conversation(id: conversationId))
    }

    func navigateToCreator() {
        AppRouter.shared.navigate(to: .creator)
    }
    
    // ✅ SIMPLIFICADO: Método para procesar datos de notificación
    func handleNotificationData(_ userInfo: [AnyHashable: Any]) {
        guard let type = userInfo["type"] as? String else {
            return
        }
        
        switch normalizedType(type) {
        case "reaction":
            if let momentId = firstString(in: userInfo, keys: ["momentId", "targetId"]),
               let userId = firstString(in: userInfo, keys: ["targetAuthorId", "momentOwnerId"]) {
                AppRouter.shared.navigate(to: .moment(id: momentId, authorId: userId))
            }
            
        case "comment":
            if let momentId = firstString(in: userInfo, keys: ["momentId", "targetId"]),
               let userId = firstString(in: userInfo, keys: ["targetAuthorId", "momentOwnerId"]) {
                AppRouter.shared.navigate(to: .moment(id: momentId, authorId: userId))
            }
            
        case "storyReaction":
            if let storyId = userInfo["storyId"] as? String {
                let authorId = userInfo["storyAuthorId"] as? String
                    ?? userInfo["storyOwnerId"] as? String
                    ?? userInfo["targetAuthorId"] as? String
                AppRouter.shared.navigate(to: .story(storyId: storyId, authorId: authorId))
            }
            
        case "newFollower":
            if let userId = firstString(in: userInfo, keys: ["followerId", "senderId", "targetId"]) {
                AppRouter.shared.navigate(to: .profile(userId: userId))
            }
            
        case "mutualConnection":
            if let userId = firstString(in: userInfo, keys: ["senderId", "targetId"]) {
                AppRouter.shared.navigate(to: .profile(userId: userId))
            }

        case "requestAccepted":
            if let userId = firstString(in: userInfo, keys: ["senderId", "targetId"]) {
                AppRouter.shared.navigate(to: .profile(userId: userId))
            }
            
        case "message":
            if let conversationId = userInfo["conversationId"] as? String {
                AppRouter.shared.navigate(to: .conversation(id: conversationId))
            }

        case "messageReaction":
            if let conversationId = userInfo["conversationId"] as? String {
                let messageId = firstString(in: userInfo, keys: ["messageId", "targetMessageId"])
                if let messageId {
                    ChatNavigationIntentStore.enqueueHighlight(conversationId: conversationId, messageId: messageId)
                }
                AppRouter.shared.navigate(to: .conversation(id: conversationId))
            }
            
        case "followRequest":
            if let requestId = userInfo["requestId"] as? String {
                AppRouter.shared.navigate(to: .followRequests(requestId: requestId))
            }
            
        case "mention":
            if let momentId = userInfo["momentId"] as? String, !momentId.isEmpty {
                let userId = userInfo["targetAuthorId"] as? String
                    ?? userInfo["momentOwnerId"] as? String
                    ?? userInfo["senderId"] as? String
                    ?? ""
                if !userId.isEmpty {
                    AppRouter.shared.navigate(to: .moment(id: momentId, authorId: userId))
                } else {
                    AppRouter.shared.navigate(to: .notifications(filter: nil))
                }
            } else if let storyId = userInfo["storyId"] as? String, !storyId.isEmpty {
                let authorId = userInfo["storyAuthorId"] as? String
                    ?? userInfo["targetAuthorId"] as? String
                    ?? userInfo["senderId"] as? String
                AppRouter.shared.navigate(to: .story(storyId: storyId, authorId: authorId))
            } else if let userId = userInfo["senderId"] as? String {
                AppRouter.shared.navigate(to: .profile(userId: userId))
            }

        case "gentle_reminder":
            AppRouter.shared.navigate(to: .creator)
            
        // 🔗 STORY CHAINS: Notificación cuando alguien continúa una cadena
        case "storyChainContinued":
            if let chainId = userInfo["chainId"] as? String,
               let chainTitle = userInfo["chainTitle"] as? String {
                AppRouter.shared.navigate(to: .storyChain(chainId: chainId, title: chainTitle))
            } else if let storyId = userInfo["storyId"] as? String {
                AppRouter.shared.navigate(to: .story(storyId: storyId, authorId: userInfo["senderId"] as? String))
            }
            
        // ✅ CASO LEGACY: Para notificaciones antiguas de tipo 'like'
        case "echoSuggestion":
            if let echoId = userInfo["echoId"] as? String {
                AppRouter.shared.navigate(to: .echoSuggestion(echoId: echoId))
            }
            
        case "like", "photoTag":
            if let momentId = firstString(in: userInfo, keys: ["momentId", "targetId"]) {
                // ✅ BUSCAR userId en la notificación legacy
                if let userId = firstString(in: userInfo, keys: ["targetAuthorId", "momentOwnerId", "senderId"]) {
                    AppRouter.shared.navigate(to: .moment(id: momentId, authorId: userId))
                } else {
                    // ✅ FALLBACK: Si no hay userId, ir a notificaciones
                    AppRouter.shared.navigate(to: .notifications(filter: nil))
                }
            }
            
        case "mediaModeration":
            if let momentId = firstString(in: userInfo, keys: ["momentId", "targetId"]), !momentId.isEmpty {
                let userId = firstString(in: userInfo, keys: ["targetAuthorId", "momentOwnerId", "senderId"]) ?? ""
                if !userId.isEmpty {
                    AppRouter.shared.navigate(to: .moment(id: momentId, authorId: userId))
                } else {
                    AppRouter.shared.navigate(to: .notifications(filter: nil))
                }
            } else if let storyId = userInfo["storyId"] as? String, !storyId.isEmpty {
                AppRouter.shared.navigate(to: .story(
                    storyId: storyId,
                    authorId: userInfo["storyAuthorId"] as? String ?? userInfo["targetAuthorId"] as? String
                ))
            } else {
                AppRouter.shared.navigate(to: .notifications(filter: nil))
            }

        default:
            #if DEBUG
            print("⚠️ Unknown notification push type: \(type)")
            #endif
            AppRouter.shared.navigate(to: .notifications(filter: nil))
        }
        
    }

    private func normalizedType(_ rawType: String) -> String {
        switch rawType {
        case "moment_reaction":
            return "reaction"
        case "moment_comment":
            return "comment"
        case "story_reaction":
            return "storyReaction"
        case "story_chain_continued":
            return "storyChainContinued"
        case "new_follower":
            return "newFollower"
        case "follow_request":
            return "followRequest"
        case "new_message":
            return "message"
        case "message_reaction":
            return "messageReaction"
        case "photo_tag":
            return "photoTag"
        case "media_moderation":
            return "mediaModeration"
        case "echo_suggestion":
            return "echoSuggestion"
        case "data_export_ready":
            return "data_export_ready"
        default:
            return rawType
        }
    }

    private func firstString(in userInfo: [AnyHashable: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = userInfo[key] as? String,
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return nil
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
        case .story(let storyId, let authorId):
            return "historia(\(storyId), autor: \(authorId ?? "desconocido"))"
        case .storyChain(let chainId, let chainTitle):
            return "cadena(\(chainId), \(chainTitle))"  // 🔗 AÑADIDO
        case .followRequests(let id):
            return "solicitudes(\(id))"
        case .notifications(let filter):
            return "notificaciones(\(filter ?? "todas"))"
        case .creator:
            return "creator"
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
        case .creator: return "creator"
        case .echoSuggestion: return "echo_invite"
        case .echo: return "echo_view"
        }
    }
}
