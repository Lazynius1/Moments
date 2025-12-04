
import UserNotifications
import Foundation

class AppDelegate: NSObject, UIApplicationDelegate, MessagingDelegate, UNUserNotificationCenterDelegate {
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [AnyHashable: Any]?) -> Bool {
        
        
        // ✅ CONFIGURAR PRIMERO el delegate de messaging
        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self
        
        // ✅ NUEVO: Configurar badge service
        NotificationBadgeService.shared.setupListeners()
        
        // ✅ PERMISOS DE NOTIFICACIONES MOVIDOS AL FEED
        // UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
        //     if let error = error {
        //     }
        //     if granted {
        //         DispatchQueue.main.async {
        //             application.registerForRemoteNotifications()
        //         }
        //     } else {
        //     }
        // }
        
        return true
    }
    
    // ✅ LOGS DETALLADOS: Registro exitoso de APNs
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        
        // ✅ PRIMERO: Configurar el token en Firebase Messaging
        Messaging.messaging().apnsToken = deviceToken
        
        // ✅ SEGUNDO: Esperar un poco y luego obtener FCM token
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            FCMTokenService.shared.updateFCMToken()
        }
    }
    
    // ✅ LOGS DETALLADOS: Registro fallido de APNs
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
    }
    
    // MARK: - MessagingDelegate
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        
        // ✅ USAR EL SERVICIO CENTRALIZADO mejorado
        FCMTokenService.shared.updateFCMToken()
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    // ✅ MEJORADO: Mostrar notificaciones cuando la app está abierta con badge
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        
        let userInfo = notification.request.content.userInfo
        
        // ✅ VERIFICAR si es notificación silenciosa para badge
        if userInfo["silent"] as? Bool == true {
            // Solo actualizar badge, sin mostrar banner
            completionHandler([.badge])
        } else {
            // Mostrar notificación normal
            completionHandler([.banner, .sound, .badge])
        }
        
        // ✅ NUEVO: Actualizar badge service cuando llegue notificación
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationBadgeService.shared.setupListeners()
        }
    }
    
    // ✅ MEJORADO: Usar el servicio de navegación con mejor logging
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        
        
        // ✅ USAR EL SERVICIO DE NAVEGACIÓN
        NotificationNavigationService.shared.handleNotificationData(userInfo)
        
        // ✅ NUEVO: Marcar notificación como leída automáticamente
        if let notificationId = userInfo["notificationId"] as? String,
           let userId = Auth.auth().currentUser?.uid {
            markNotificationAsRead(userId: userId, notificationId: notificationId)
        }
        
        completionHandler()
    }
    
    // ✅ NUEVO: Marcar notificación como leída
    private func markNotificationAsRead(userId: String, notificationId: String) {
        Firestore.firestore()
            .collection("users")
            .document(userId)
            .collection("notifications")
            .document(notificationId)
            .updateData(["isPending": false]) { error in
                if let error = error {
                } else {
                }
            }
    }
}
