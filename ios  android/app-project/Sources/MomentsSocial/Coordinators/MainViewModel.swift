import SwiftUI

// Este objeto controlará el estado de las notificaciones de la barra de pestañas.
class MainViewModel: ObservableObject {
    @Published var hasNewFeedContent: Bool = false
    @Published var hasUnreadNotifications: Bool = false
    
    // Llama a esta función cuando lleguen nuevos momentos en el feed.
    func newFeedContentArrived() {
        // Android: App state checking will be handled natively
        // For now, always mark as new content
        self.hasNewFeedContent = true
        /*
        // iOS: Solo actualiza si no estamos ya en la app para evitar cambios molestos.
        if UIApplication.shared.applicationState != .active {
            self.hasNewFeedContent = true
        }
        */
    }
    
    // Llama a esta función cuando el usuario visite el feed.
    func markFeedAsSeen() {
        self.hasNewFeedContent = false
    }
    
    // Llama a esta función cuando lleguen nuevas notificaciones.
    func newNotificationsArrived() {
        // Android: App state checking will be handled natively
        // For now, always mark as new notifications
        self.hasUnreadNotifications = true
        /*
        // iOS: Solo actualiza si no estamos ya en la app
        if UIApplication.shared.applicationState != .active {
            self.hasUnreadNotifications = true
        }
        */
    }
    
    // Llama a esta función cuando el usuario visite las notificaciones.
    func markNotificationsAsSeen() {
        self.hasUnreadNotifications = false
    }
}
