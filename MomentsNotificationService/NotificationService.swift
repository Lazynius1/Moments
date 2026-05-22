import UserNotifications
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import WidgetKit

class NotificationService: UNNotificationServiceExtension {

    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?
    
    // ✅ 1. Inicializar Firebase lo antes posible (Constructor)
    override init() {
        super.init()
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
    }

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)
        
        guard let bestAttemptContent = bestAttemptContent else {
            contentHandler(request.content)
            return
        }
        
        let userInfo = bestAttemptContent.userInfo
        let group = DispatchGroup()
        
        // ✅ 2. NUEVO: Intentar usar los conteos que vienen del servidor (SÍ funcionan con la app cerrada)
        let handledByServer = handleServerCounts(userInfo: userInfo)
        
        // Procesar lógica de Firebase
        if let type = userInfo["type"] as? String {
            group.enter()
            // Soportamos ambos por si acaso
            if type == "message" || type == "new_message" {
                // Si ya tenemos los conteos del servidor, solo marcamos como entregado (si hay Auth)
                if handledByServer {
                    if let conversationId = userInfo["conversationId"] as? String,
                       let messageId = userInfo["messageId"] as? String {
                        markMessageAsDelivered(conversationId: conversationId, messageId: messageId) {
                            group.leave()
                        }
                    } else {
                        group.leave()
                    }
                } else {
                    // Fallback: Calcularlo nosotros (requiere Auth funcional)
                    handleNewMessage(userInfo: userInfo) {
                        group.leave()
                    }
                }
            } else {
                // Si ya gestionamos los conteos, no hace falta entrar en Firestore
                if handledByServer {
                    group.leave()
                } else {
                    handleNewNotification(userInfo: userInfo) {
                        group.leave()
                    }
                }
            }
        }
        
        // Descargar imágenes (Rich Media)
        // Prioridad: mediaUrl (foto enviada) > senderProfileImage (avatar)
        let mediaUrlString = userInfo["mediaUrl"] as? String
        let profileImageString = userInfo["senderProfileImage"] as? String
        
        if let urlString = mediaUrlString ?? profileImageString, 
           let url = URL(string: urlString) {
            
            group.enter()
            downloadImage(from: url) { attachment in
                if let attachment = attachment {
                    bestAttemptContent.attachments = [attachment]
                }
                group.leave()
            }
        }
        
        // ✅ 3. Entregar notificación SOLO cuando TODO esté listo
        group.notify(queue: .main) {
            contentHandler(bestAttemptContent)
        }
    }
    
    // ✅ NUEVO: Leer conteos del servidor y actualizar Widget instantáneamente
    private func handleServerCounts(userInfo: [AnyHashable: Any]) -> Bool {
        
        func parseCount(_ key: String) -> Int? {
            if let str = userInfo[key] as? String {
                return Int(str)
            }
            if let num = userInfo[key] as? Int {
                return num
            }
            return nil
        }
        
        guard let messages = parseCount("unreadMessages"),
              let notifications = parseCount("unreadNotifications") else {
            // Si falla el guard, añadimos un marcador de error al título
            if let content = bestAttemptContent {
                content.title = "⚠️ " + content.title
            }
            return false
        }
        
        let echoes = parseCount("unreadEchoes") ?? 0
        let tags = parseCount("unreadTags") ?? 0
        
        if let defaults = UserDefaults(suiteName: "group.com.glowsyapp") {
            // Guardar con persistencia forzada para App Groups
            defaults.set(messages, forKey: "widget_unread_messages")
            defaults.set(notifications, forKey: "widget_unread_notifications")
            defaults.set(echoes, forKey: "widget_unread_echoes")
            defaults.set(tags, forKey: "widget_unread_tags")
            defaults.synchronize() // Forzar escritura inmediata
            
            // Forzar recarga de los widgets del app (Kind específico es más fiable)
            // Lo hacemos en el main queue para asegurar ejecución
            DispatchQueue.main.async {
                WidgetCenter.shared.reloadTimelines(ofKind: "GlowsyWidgetExtension")
            }
            
            // Marcador de éxito en el título y CUERPO para ver los datos recibidos
            if let content = bestAttemptContent {
                // Forzar el badge de la notificación al total correcto
                content.badge = (messages + notifications) as NSNumber
            }
            
            return true
        }
        
        return false
    }
    
    // MARK: - Manejo de Mensajes
    private func handleNewMessage(userInfo: [AnyHashable: Any], completion: @escaping () -> Void) {
        // Marcamos un grupo interno para las dos tareas de mensajes
        let internalGroup = DispatchGroup()
        
        internalGroup.enter()
        updateUnreadMessageCount { 
            internalGroup.leave() 
        }
        
        if let conversationId = userInfo["conversationId"] as? String,
           let messageId = userInfo["messageId"] as? String {
            internalGroup.enter()
            markMessageAsDelivered(conversationId: conversationId, messageId: messageId) {
                internalGroup.leave()
            }
        }
        
        internalGroup.notify(queue: .main) {
            completion()
        }
    }
    
    // MARK: - Manejo de Notificaciones
    private func handleNewNotification(userInfo: [AnyHashable: Any], completion: @escaping () -> Void) {
        updateUnreadNotificationCounts {
            completion()
        }
    }
    
    // MARK: - Lógica de Firebase (Auth Compartido Requerido)
    
    private func updateUnreadMessageCount(completion: @escaping () -> Void) {
        guard let userId = Auth.auth().currentUser?.uid else { 
            completion()
            return 
        }
        
        Firestore.firestore().collection("conversations")
            .whereField("participants", arrayContains: userId)
            .getDocuments { snapshot, error in
                defer { completion() } // ✅ Siempre llamar completion
                guard let documents = snapshot?.documents else { return }
                
                var unreadCount = 0
                for doc in documents {
                    let data = doc.data()
                    let readStatus = data["readStatus"] as? [String: Bool] ?? [:]
                    if let isRead = readStatus[userId], !isRead {
                        unreadCount += 1
                    }
                }
                
                if let defaults = UserDefaults(suiteName: "group.com.glowsyapp") {
                    defaults.set(unreadCount, forKey: "widget_unread_messages")
                    WidgetCenter.shared.reloadTimelines(ofKind: "GlowsyWidgetExtension")
                }
            }
    }
    
    private func markMessageAsDelivered(conversationId: String, messageId: String, completion: @escaping () -> Void) {
        guard let userId = Auth.auth().currentUser?.uid else { 
            completion()
            return 
        }
        
        let db = Firestore.firestore()
        let messageRef = db.collection("conversations").document(conversationId).collection("messages").document(messageId)
        
        messageRef.getDocument { snapshot, _ in
            if let data = snapshot?.data(),
               let senderId = data["senderId"] as? String,
               senderId != userId,
               let status = data["status"] as? String,
               status == "sent" {
                
                messageRef.updateData(["status": "delivered"]) { _ in
                    completion()
                }
            } else {
                completion()
            }
        }
    }
    
    private func updateUnreadNotificationCounts(completion: @escaping () -> Void) {
        guard let userId = Auth.auth().currentUser?.uid else { 
            completion()
            return 
        }
        
        Firestore.firestore().collection("users").document(userId).collection("notifications")
            .whereField("isPending", isEqualTo: true)
            .getDocuments { snapshot, _ in
                defer { completion() }
                guard let documents = snapshot?.documents else { return }
                
                let totalCount = documents.count
                let echoes = documents.filter { ($0.data()["type"] as? String) == "echoSuggestion" }.count
                let tags = documents.filter { ($0.data()["type"] as? String) == "photoTag" }.count
                
                if let defaults = UserDefaults(suiteName: "group.com.glowsyapp") {
                    defaults.set(totalCount, forKey: "widget_unread_notifications")
                    defaults.set(echoes, forKey: "widget_unread_echoes")
                    defaults.set(tags, forKey: "widget_unread_tags")
                    WidgetCenter.shared.reloadTimelines(ofKind: "GlowsyWidgetExtension")
                }
            }
    }
    
    override func serviceExtensionTimeWillExpire() {
        // Called just before the extension will be terminated by the system.
        // Use this as an opportunity to deliver your "best attempt" at modified content, otherwise the original push payload will be used.
        if let contentHandler = contentHandler, let bestAttemptContent =  bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }
    
    // Helper para descargar imagen
    private func downloadImage(from url: URL, completion: @escaping (UNNotificationAttachment?) -> Void) {
        let task = URLSession.shared.downloadTask(with: url) { (downloadedUrl, response, error) in
            guard let downloadedUrl = downloadedUrl else {
                completion(nil)
                return
            }
            
            var urlPath = URL(fileURLWithPath: NSTemporaryDirectory())
            let uniqueURLEnding = ProcessInfo.processInfo.globallyUniqueString + ".jpg"
            urlPath = urlPath.appendingPathComponent(uniqueURLEnding)
            
            try? FileManager.default.moveItem(at: downloadedUrl, to: urlPath)
            
            do {
                let attachment = try UNNotificationAttachment(identifier: "picture", url: urlPath, options: nil)
                completion(attachment)
            } catch {
                completion(nil)
            }
        }
        task.resume()
    }
}

