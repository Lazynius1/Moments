import UIKit
import Firebase
import FirebaseMessaging
import UserNotifications
import FirebaseAuth
import FirebaseFirestore
import Kingfisher

class AppDelegate: NSObject, UIApplicationDelegate {
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        
        // ✅ CONFIGURAR PRIMERO el delegate de messaging
        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self

        // ✅ Acciones interactivas en notificaciones de mensaje (responder / marcar como leído)
        registerMessageNotificationCategories()
        
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
            .scaleFactor(UIScreen.main.scale),
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

        // ✅ Respuesta rápida en línea desde la notificación (estilo WhatsApp/iMessage)
        if response.actionIdentifier == "REPLY_ACTION",
           let textResponse = response as? UNTextInputNotificationResponse {
            handleInlineReply(userInfo: userInfo, text: textResponse.userText, completion: completionHandler)
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

    // MARK: - Acciones de notificación de mensaje

    private func registerMessageNotificationCategories() {
        // Igual que WhatsApp/iMessage: solo respuesta rápida en línea. No "marcar como leído".
        let replyAction = UNTextInputNotificationAction(
            identifier: "REPLY_ACTION",
            title: NSLocalizedString("notification.action.reply", comment: "Reply"),
            options: [],
            textInputButtonTitle: NSLocalizedString("notification.action.send", comment: "Send"),
            textInputPlaceholder: NSLocalizedString("notification.action.placeholder", comment: "Message")
        )

        let messageCategory = UNNotificationCategory(
            identifier: "MESSAGE_CATEGORY",
            actions: [replyAction],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([messageCategory])
    }

    private func handleInlineReply(userInfo: [AnyHashable: Any], text: String, completion: @escaping () -> Void) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !trimmed.isEmpty,
            let conversationId = userInfo["conversationId"] as? String,
            let senderId = Auth.auth().currentUser?.uid
        else {
            completion()
            return
        }

        // Mantener la app viva en segundo plano hasta terminar el envío.
        var backgroundTask: UIBackgroundTaskIdentifier = .invalid
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "InlineReply") {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }

        let finish: () -> Void = {
            if backgroundTask != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTask)
                backgroundTask = .invalid
            }
            completion()
        }

        // sendTextMessage cifra el contenido y actualiza la conversación internamente.
        // No marcamos la conversación como leída: igual que WhatsApp, responder desde
        // la notificación NO debe disparar el "visto" (deja los ticks en entregado).
        ChatService.shared.sendTextMessage(
            conversationId: conversationId,
            senderId: senderId,
            content: trimmed
        ) { _ in
            DispatchQueue.main.async {
                NotificationBadgeService.shared.setupListeners()
                finish()
            }
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
