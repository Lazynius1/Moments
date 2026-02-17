import UIKit
import Firebase
import FirebaseMessaging
import UserNotifications
import FirebaseAuth
import FirebaseFirestore

class AppDelegate: NSObject, UIApplicationDelegate {
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        
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
    
    // ✅ Registro exitoso de APNs
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // ✅ PRIMERO: Configurar el token en Firebase Messaging
        Messaging.messaging().apnsToken = deviceToken
        
        // ✅ SEGUNDO: Esperar un poco y luego obtener FCM token
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            FCMTokenService.shared.updateFCMToken()
        }
    }
    
    // ✅ Registro fallido de APNs
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
    }
    
    // ✅ Handler para notificaciones en BACKGROUND - marca mensajes como delivered y actualiza WIDGET
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        
        let group = DispatchGroup()
        
        // 1. Marcar mensaje como entregado
        if let conversationId = userInfo["conversationId"] as? String,
           let messageId = userInfo["messageId"] as? String {
            group.enter()
            ChatService.shared.markMessageAsDeliveredFromNotification(
                conversationId: conversationId,
                messageId: messageId
            ) { _ in group.leave() }
        }
        
        // 2. Refrescar contadores para el Widget SOLO si es una notificación silenciosa
        // Si es visual, el NotificationServiceExtension ya lo hizo de forma más fiable (server-side)
        if userInfo["silent"] as? Bool == true || userInfo["content-available"] as? Int == 1 {
            group.enter()
            NotificationBadgeService.shared.refreshAllCounts {
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            completionHandler(.newData)
        }
    }
}

// MARK: - MessagingDelegate
extension AppDelegate: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        if let token = fcmToken {
            // ✅ GUARDAR DIRECTAMENTE el token recibido (más confiable que esperar APNs)
            if let userId = Auth.auth().currentUser?.uid {
                FCMTokenService.shared.saveFCMTokenDirectly(token: token, userId: userId)
            }
        } else {
            // ✅ Si no hay token, intentar obtenerlo con el método normal
            FCMTokenService.shared.updateFCMToken()
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate
extension AppDelegate: UNUserNotificationCenterDelegate {
    // ✅ Mostrar notificaciones cuando la app está abierta + mark as delivered
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        
        let userInfo = notification.request.content.userInfo
        
        // ✅ Marcar mensaje como entregado cuando llegue la notificación (estilo WhatsApp)
        if let conversationId = userInfo["conversationId"] as? String,
           let messageId = userInfo["messageId"] as? String {
            ChatService.shared.markMessageAsDeliveredFromNotification(
                conversationId: conversationId,
                messageId: messageId
            )
        }
        
        // ✅ VERIFICAR si es notificación silenciosa para badge
        if userInfo["silent"] as? Bool == true {
            // Solo actualizar badge, sin mostrar banner
            completionHandler([.badge])
        } else {
            // Mostrar notificación normal (SOLO sonido y badge, el banner lo manejamos nosotros)
            completionHandler([.sound, .badge])
        }
        
        // ✅ Actualizar badge service cuando llegue notificación
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
