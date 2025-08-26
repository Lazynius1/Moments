import Foundation
import SwiftUI
import Kingfisher

// ✅ EXTENSIONES GLOBALES para Foundation.Notification.Name (especificar namespace completo)
extension Foundation.Notification.Name {
    static let profileImageUpdated = Foundation.Notification.Name("ProfileImageUpdated")
    static let profileUpdated = Foundation.Notification.Name("ProfileUpdated")
    static let conversationUpdated = Foundation.Notification.Name("ConversationUpdated")
    static let commentAdded = Foundation.Notification.Name("CommentAdded")
    
    // ✅ NUEVA: Notificación para cambios de estado de moderación
    static let moderationStatusChanged = Foundation.Notification.Name("ModerationStatusChanged")
}

// ✅ HELPER GLOBAL para limpiar cache de manera controlada
class ImageCacheManager {
    static let shared = ImageCacheManager()
    
    private init() {}
    
    func clearCacheForUser(_ userId: String) {
        // Este método se puede expandir más tarde si necesitamos cache más específico
    }
    
    func clearAllCache() {
        KingfisherManager.shared.cache.clearMemoryCache()
        KingfisherManager.shared.cache.clearDiskCache()
    }
    
    func postProfileUpdate(for userId: String) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Foundation.Notification.Name.profileUpdated,
                object: userId
            )
            NotificationCenter.default.post(
                name: Foundation.Notification.Name.profileImageUpdated,
                object: userId
            )
        }
    }
    
    // ✅ NUEVO: Helper para notificar cambios de moderación
    func postModerationUpdate(contentType: String, contentId: String, status: String, authorId: String? = nil) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Foundation.Notification.Name.moderationStatusChanged,
                object: nil,
                userInfo: [
                    "status": status,
                    "contentType": contentType,
                    "contentId": contentId,
                    "authorId": authorId as Any
                ]
            )
        }
    }
}
