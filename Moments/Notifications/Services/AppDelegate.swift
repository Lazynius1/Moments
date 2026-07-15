import UIKit
import Firebase
import FirebaseMessaging
import UserNotifications
import FirebaseAuth
import FirebaseFirestore
import Kingfisher
import Intents

class AppDelegate: NSObject, UIApplicationDelegate {
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        
        // ✅ CONFIGURAR PRIMERO el delegate de messaging
        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self

        // ✅ Registrar la categoría de respuesta rápida (campo de texto al hacer
        // long-press en la notificación de mensaje).
        UNUserNotificationCenter.current().setNotificationCategories([
            ChatNotificationReply.makeCategory()
        ])

        // ✅ NUEVO: Configurar badge service
        NotificationBadgeService.shared.setupListeners()

        // ✅ Configurar cachés de imágenes ANTES de cualquier carga (splash → feed)
        configureImageCaches()

        // ✅ Liberar memoria bajo presión: purga cachés en memoria para evitar jetsam
        registerMemoryPressureHandler()
        
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

    // MARK: - Image Caches

    /// Configura Kingfisher y URLCache desde el primer frame para que las primeras
    /// imágenes (splash → feed) ya respeten los límites y opciones óptimas.
    private func configureImageCaches() {
        // URLCache mínimo: solo para respuestas JSON/API. Las imágenes remotas
        // las gestiona Kingfisher (evita duplicar ~1GB de disco en imágenes).
        let urlCache = URLCache(
            memoryCapacity: 8 * 1024 * 1024,
            diskCapacity: 50 * 1024 * 1024,
            diskPath: "apiCache"
        )
        URLCache.shared = urlCache

        let kingfisherCache = KingfisherManager.shared.cache
        kingfisherCache.memoryStorage.config.totalCostLimit = 20 * 1024 * 1024
        kingfisherCache.diskStorage.config.sizeLimit = 500 * 1024 * 1024
        kingfisherCache.diskStorage.config.expiration = .days(7)

        KingfisherManager.shared.defaultOptions = [
            .scaleFactor(UIApplication.shared.activeDisplayScale),
            .backgroundDecode,
            .asyncCacheTypeCheck
        ]
    }

    // MARK: - Memory Pressure

    /// Purga las cachés en memoria cuando iOS avisa de presión de memoria,
    /// reduciendo el riesgo de que el sistema mate la app (jetsam).
    private func registerMemoryPressureHandler() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { _ in
            KingfisherManager.shared.cache.clearMemoryCache()
            GIFCache.shared.clearCache()
            ChatGIFImageCache.shared.clearMemory()
            NotificationCenter.default.post(name: .momentsDidReceiveMemoryWarning, object: nil)
        }
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

            group.enter()
            Task { @MainActor in
                await MessageIngestService.shared.ingest(userInfo: userInfo)
                group.leave()
            }
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

        Task { @MainActor in
            NotificationPresentationCoordinator.shared.present(from: userInfo, source: .push)
        }

        if NotificationPresentationCoordinator.isSilentPush(userInfo) {
            completionHandler([.badge])
        } else {
            completionHandler([.sound, .badge])
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationBadgeService.shared.setupListeners()
        }
    }
    
    // ✅ MEJORADO: Usar el servicio de navegación con mejor logging
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo

        // ✅ Respuesta rápida desde la notificación (campo de texto inline).
        if let textResponse = response as? UNTextInputNotificationResponse,
           response.actionIdentifier == ChatNotificationReply.actionIdentifier {
            handleQuickReply(text: textResponse.userText, userInfo: userInfo, completion: completionHandler)
            return
        }

        // ✅ USAR EL SERVICIO DE NAVEGACIÓN
        NotificationNavigationService.shared.handleNotificationData(userInfo)
        
        // ✅ NUEVO: Marcar notificación como leída automáticamente
        if let notificationId = userInfo["notificationId"] as? String,
           let userId = Auth.auth().currentUser?.uid {
            markNotificationAsRead(userId: userId, notificationId: notificationId)
        }
        
        completionHandler()
    }

    func application(_ application: UIApplication, handlerFor intent: INIntent) -> Any? {
        if intent is INSendMessageIntent {
            return ChatSendMessageIntentHandler()
        }
        return nil
    }

    /// Envía el texto escrito en el campo de respuesta inline de la notificación.
    private func handleQuickReply(
        text: String,
        userInfo: [AnyHashable: Any],
        completion: @escaping () -> Void
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !trimmed.isEmpty,
            let conversationId = userInfo["conversationId"] as? String,
            let senderId = Auth.auth().currentUser?.uid
        else {
            completion()
            return
        }

        var backgroundTask: UIBackgroundTaskIdentifier = .invalid
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "QuickReply") {
            if backgroundTask != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTask)
                backgroundTask = .invalid
            }
        }

        let finish: () -> Void = {
            if backgroundTask != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTask)
                backgroundTask = .invalid
            }
            completion()
        }

        ChatService.shared.sendTextMessage(
            conversationId: conversationId,
            senderId: senderId,
            content: trimmed
        ) { _ in
            NotificationBadgeService.shared.setupListeners()
            finish()
        }
    }

    // ✅ NUEVO: Marcar notificación como leída
    private func markNotificationAsRead(userId: String, notificationId: String) {
        Firestore.firestore()
            .collection("users")
            .document(userId)
            .collection("notifications")
            .document(notificationId)
            .updateData(["isPending": false]) { _ in
            }
    }
}
