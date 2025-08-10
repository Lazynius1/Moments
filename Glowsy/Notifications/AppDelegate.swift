import UIKit
import Firebase
import FirebaseMessaging
import UserNotifications
import FirebaseAuth
import FirebaseFirestore

class AppDelegate: NSObject, UIApplicationDelegate {
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        print("🚀 AppDelegate - didFinishLaunchingWithOptions iniciado")
        
        // ✅ CONFIGURAR PRIMERO el delegate de messaging
        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self
        
        // ✅ NUEVO: Configurar badge service
        NotificationBadgeService.shared.setupListeners()
        
        // ✅ SOLICITAR PERMISOS Y REGISTRAR para notificaciones remotas
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            print("🔐 AppDelegate - Permisos concedidos: \(granted)")
            if let error = error {
                print("❌ AppDelegate - Error en permisos: \(error)")
            }
            if granted {
                DispatchQueue.main.async {
                    print("📱 AppDelegate - Solicitando registro de notificaciones...")
                    application.registerForRemoteNotifications()
                    print("📱 AppDelegate - registerForRemoteNotifications() llamado")
                }
            } else {
                print("❌ AppDelegate - Permisos denegados")
            }
        }
        
        return true
    }
    
    // ✅ LOGS DETALLADOS: Registro exitoso de APNs
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        print("🎉 ====== APNs registration SUCCESS! ======")
        print("📱 Device token recibido: \(deviceToken.map { String(format: "%02.2hhx", $0) }.joined())")
        
        // ✅ PRIMERO: Configurar el token en Firebase Messaging
        Messaging.messaging().apnsToken = deviceToken
        print("✅ APNs token configurado en Firebase Messaging")
        
        // ✅ SEGUNDO: Esperar un poco y luego obtener FCM token
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            print("🔄 Solicitando FCM token después de configurar APNs...")
            FCMTokenService.shared.updateFCMToken()
        }
    }
    
    // ✅ LOGS DETALLADOS: Registro fallido de APNs
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("💥 ====== APNs registration FAILED! ======")
        print("❌ Error: \(error)")
        print("❌ Error code: \((error as NSError).code)")
        print("❌ Error domain: \((error as NSError).domain)")
        print("❌ Error localizedDescription: \(error.localizedDescription)")
    }
}

// MARK: - MessagingDelegate
extension AppDelegate: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        print("🔄 FCM Token actualizado")
        
        // ✅ USAR EL SERVICIO CENTRALIZADO mejorado
        FCMTokenService.shared.updateFCMToken()
    }
}

// MARK: - UNUserNotificationCenterDelegate
extension AppDelegate: UNUserNotificationCenterDelegate {
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
        
        print("🔔 Usuario tocó notificación: \(userInfo)")
        
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
                    print("❌ Error marcando notificación como leída: \(error)")
                } else {
                    print("✅ Notificación marcada como leída: \(notificationId)")
                }
            }
    }
}
