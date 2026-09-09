import UserNotifications
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import WidgetKit
import Intents

class NotificationService: UNNotificationServiceExtension {

    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?
    private var intentSenderImage: INImage?
    private var intentGroupImage: INImage?
    private let completionLock = NSLock()
    
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

        // ✅ Categoría de respuesta rápida lo antes posible: garantiza el campo de
        // texto inline (long-press) aunque la conversión a communication notification falle.
        if ChatNotificationThread.isChatMessagePush(userInfo["type"] as? String) {
            bestAttemptContent.categoryIdentifier = ChatNotificationReply.categoryIdentifier
            if let conversationId = ChatNotificationThread.conversationId(from: userInfo) {
                bestAttemptContent.threadIdentifier = ChatNotificationThread.threadIdentifier(conversationId: conversationId)
            }
        }

        if ChatNotificationThread.isChatMessagePush(userInfo["type"] as? String) {
            bestAttemptContent.body = ChatNotificationThread.previewLabel(messageType: userInfo["messageType"] as? String)
            if userInfo["isMention"] as? String == "1" || userInfo["isMention"] as? Bool == true {
                bestAttemptContent.body = String(format: localizedString("groups.notification.mention"), userInfo["senderUsername"] as? String ?? "")
            }
        }
        if ChatNotificationThread.isChatMessagePush(userInfo["type"] as? String),
           let conversationId = ChatNotificationThread.conversationId(from: userInfo),
           ChatNotificationThread.shouldRecycle(conversationId: conversationId, userInfo: userInfo) {
            bestAttemptContent.body = localizedString("notification.chatSummary.single")
            bestAttemptContent.attachments = []
        }
        if let groupName = ChatNotificationThread.resolvedGroupName(from: userInfo, contentTitle: bestAttemptContent.title) {
            bestAttemptContent.title = groupName
            bestAttemptContent.subtitle = userInfo["senderUsername"] as? String ?? ""
        }

        enqueueMessageIngestIfNeeded(userInfo: userInfo)
        let group = DispatchGroup()
        if ChatNotificationThread.isChatMessagePush(userInfo["type"] as? String) {
            group.enter()
            loadIntentImages(userInfo: userInfo) { sender, image in
                self.intentSenderImage = sender
                self.intentGroupImage = image
                group.leave()
            }
        }
        
        // 🔐 Vista previa E2E: resolver el texto real en el dispositivo (fast-path embebido
        // o fetch del mensaje + descifrado local). Entra en el group para que la
        // notificación no se entregue hasta tener el cuerpo definitivo.
        group.enter()
        resolveMessagePreview(userInfo: userInfo, content: bestAttemptContent) {
            group.leave()
        }

        // 🖼️ Adjunto de la notificación (rich media). Una sola fuente de verdad para
        // evitar que el avatar pise a la media: la media SIEMPRE gana, y solo se cae al
        // avatar si no hay media adjuntable. Respeta el toggle y excluye view-once.
        group.enter()
        resolveNotificationAttachment(userInfo: userInfo, content: bestAttemptContent) {
            group.leave()
        }

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
            } else if type == "group_message" {
                if handledByServer, let conversationId = ChatNotificationThread.conversationId(from: userInfo),
                   let messageId = userInfo["messageId"] as? String {
                    markMessageAsDelivered(conversationId: conversationId, messageId: messageId) { group.leave() }
                } else {
                    handleNewMessage(userInfo: userInfo) { group.leave() }
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
        
        // ✅ 3. Entregar notificación SOLO cuando TODO esté listo
        group.notify(queue: .main) {
            self.deliverChatNotification(userInfo: userInfo, content: bestAttemptContent)
        }
    }

    private func deliverChatNotification(
        userInfo: [AnyHashable: Any],
        content: UNMutableNotificationContent
    ) {
        guard contentHandler != nil else { return }
        guard ChatNotificationThread.isChatMessagePush(userInfo["type"] as? String),
              let conversationId = ChatNotificationThread.conversationId(from: userInfo) else {
            complete(content)
            return
        }

        let threadId = ChatNotificationThread.threadIdentifier(conversationId: conversationId)
        content.threadIdentifier = threadId

        let finish: () -> Void = { [weak self] in
            guard let self, self.contentHandler != nil else { return }
            self.donateCommunicationNotificationContent(
                userInfo: userInfo,
                content: content,
                senderImage: self.intentSenderImage,
                groupImage: self.intentGroupImage,
                completion: { self.complete($0) }
            )
        }

        if ChatNotificationThread.shouldRecycle(conversationId: conversationId, userInfo: userInfo) {
            recycleDelivered(matching: threadId, conversationId: conversationId, content: content, finish: finish)
        } else {
            finish()
        }
    }

    private func recycleDelivered(matching threadId: String, conversationId: String, content: UNMutableNotificationContent, finish: @escaping () -> Void) {
        let legacyGroupThread = "group-\(conversationId)"
        UNUserNotificationCenter.current().getDeliveredNotifications { delivered in
            var messageCount = 1
            let incomingId = content.userInfo["messageId"] as? String
            let ids = delivered.compactMap { note -> String? in
                let existing = note.request.content.threadIdentifier
                if (existing == threadId || existing == legacyGroupThread),
                   ChatNotificationThread.isChatMessagePush(note.request.content.userInfo["type"] as? String) {
                    let previous = note.request.content.userInfo
                    messageCount += max(1, previous["chatSummaryCount"] as? Int ?? 1)
                    if let incomingId, previous["messageId"] as? String == incomingId { messageCount -= 1 }
                    return note.request.identifier
                }
                return nil
            }
            if !ids.isEmpty {
                UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
            }
            DispatchQueue.main.async {
                content.userInfo["chatSummaryCount"] = messageCount
                content.body = messageCount > 1
                    ? String(format: self.localizedString("notification.chatSummary.multiple"), String(messageCount))
                    : self.localizedString("notification.chatSummary.single")
                if content.userInfo["isMention"] as? String == "1" || content.userInfo["isMention"] as? Bool == true {
                    content.body += "\n" + String(format: self.localizedString("groups.notification.mention"), content.userInfo["senderUsername"] as? String ?? "")
                }
                content.attachments = []
                finish()
            }
        }
    }

    private func loadIntentImages(
        userInfo: [AnyHashable: Any],
        completion: @escaping (INImage?, INImage?) -> Void
    ) {
        let senderPath = (userInfo["senderProfileImage"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let groupPath = ChatNotificationThread.isGroupPush(userInfo)
            ? (userInfo["groupImage"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            : nil
        let group = DispatchGroup()
        var senderImage: INImage?
        var groupImage: INImage?
        if let senderPath, !senderPath.isEmpty {
            group.enter()
            loadNotificationImageData(pathOrURL: senderPath) { data in
                if let data { senderImage = INImage(imageData: data) }
                group.leave()
            }
        }
        if let groupPath, !groupPath.isEmpty {
            group.enter()
            loadNotificationImageData(pathOrURL: groupPath) { data in
                if let data { groupImage = INImage(imageData: data) }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            completion(senderImage, groupImage)
        }
    }

    /// HTTP(S) o ruta de Storage — profileImagePath/groupImagePath a menudo no son URL.
    private func loadNotificationImageData(pathOrURL: String, completion: @escaping (Data?) -> Void) {
        let cleaned = pathOrURL.replacingOccurrences(of: ":443", with: "")
        if cleaned.hasPrefix("http://") || cleaned.hasPrefix("https://"),
           let url = URL(string: cleaned) {
            downloadImageData(from: url, completion: completion)
            return
        }
        downloadStorageObject(path: cleaned, maxSize: 2 * 1024 * 1024, completion: completion)
    }

    private func donateCommunicationNotificationContent(
        userInfo: [AnyHashable: Any],
        content: UNMutableNotificationContent,
        senderImage: INImage?,
        groupImage: INImage?,
        completion: @escaping (UNNotificationContent) -> Void
    ) {
        guard ChatNotificationThread.isChatMessagePush(userInfo["type"] as? String) else { completion(content); return }
        guard let conversationId = ChatNotificationThread.conversationId(from: userInfo),
              let messageId = userInfo["messageId"] as? String,
              let senderId = userInfo["senderId"] as? String else { completion(content); return }

        let senderUsername = (userInfo["senderUsername"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? content.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let preview = content.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let groupName = ChatNotificationThread.resolvedGroupName(
            from: userInfo,
            contentTitle: content.title,
            senderUsername: senderUsername
        )

        ChatCommunicationIntentDonor.donateAndApplyCommunicationIntent(
            to: content,
            conversationId: conversationId,
            messageId: messageId,
            senderId: senderId,
            senderUsername: senderUsername.isEmpty ? "Moments" : senderUsername,
            senderImage: senderImage,
            messagePreview: preview.isEmpty ? nil : preview,
            groupName: groupName,
            groupImage: groupImage,
            recipientCount: Int(userInfo["recipientCount"] as? String ?? "") ?? 1,
            otherRecipientId: (userInfo["otherRecipientId"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            mentionsCurrentUser: userInfo["isMention"] as? String == "1" || userInfo["isMention"] as? Bool == true,
            completion: completion
        )
    }

    private func applyCommunicationNotificationContent(
        userInfo: [AnyHashable: Any],
        content: UNMutableNotificationContent,
        senderImage: INImage?,
        groupImage: INImage?
    ) -> UNNotificationContent {
        guard ChatNotificationThread.isChatMessagePush(userInfo["type"] as? String) else { return content }
        guard let conversationId = ChatNotificationThread.conversationId(from: userInfo),
              let messageId = userInfo["messageId"] as? String,
              let senderId = userInfo["senderId"] as? String else { return content }

        let senderUsername = (userInfo["senderUsername"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? content.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let preview = content.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let groupName = ChatNotificationThread.resolvedGroupName(
            from: userInfo,
            contentTitle: content.title,
            senderUsername: senderUsername
        )

        return ChatCommunicationIntentDonor.applyCommunicationIntent(
            to: content,
            conversationId: conversationId,
            messageId: messageId,
            senderId: senderId,
            senderUsername: senderUsername.isEmpty ? "Moments" : senderUsername,
            senderImage: senderImage,
            messagePreview: preview.isEmpty ? nil : preview,
            groupName: groupName,
            groupImage: groupImage,
            recipientCount: Int(userInfo["recipientCount"] as? String ?? "") ?? 1,
            otherRecipientId: (userInfo["otherRecipientId"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            mentionsCurrentUser: userInfo["isMention"] as? String == "1" || userInfo["isMention"] as? Bool == true
        )
    }
    
    // MARK: - Local-first ingest queue

    private func enqueueMessageIngestIfNeeded(userInfo: [AnyHashable: Any]) {
        let type = (userInfo["type"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard ChatNotificationThread.isChatMessagePush(type) else { return }
        guard let conversationId = ChatNotificationThread.conversationId(from: userInfo),
              let messageId = userInfo["messageId"] as? String else { return }
        MessageIngestQueue.enqueue(conversationId: conversationId, messageId: messageId)
    }

    // MARK: - 🔐 Vista previa de mensajes (descifrado E2E en el dispositivo)
    /// Reemplaza el cuerpo genérico ("Te envió un mensaje") por el texto real.
    /// Dos caminos, ambos con descifrado local con la clave de la conversación:
    ///   1. Fast-path: `encryptedContent` embebido en el payload (solo textos cortos
    ///      que caben bajo el límite real de APNs; lo decide la Cloud Function).
    ///   2. Fetch: si no viene embebido, se lee el mensaje cifrado de Firestore
    ///      (`conversations/{cid}/messages/{mid}`) y se descifra en el dispositivo.
    /// Solo para texto y respetando el toggle de privacidad. Si algo falla (toggle
    /// off, clave ausente, device bloqueado, sin red) se conserva el cuerpo genérico.
    private func resolveMessagePreview(
        userInfo: [AnyHashable: Any],
        content: UNMutableNotificationContent,
        completion: @escaping () -> Void
    ) {
        if userInfo["type"] as? String == "message_reaction" {
            resolveChatReactionPreview(userInfo: userInfo, content: content, completion: completion)
            return
        }

        // Solo mensajes de texto: la media mantiene su descripción genérica localizada.
        guard let messageType = userInfo["messageType"] as? String, messageType == "text",
              let conversationId = ChatNotificationThread.conversationId(from: userInfo) else {
            completion()
            return
        }

        // Respetar el ajuste de privacidad "Mostrar vista previa" POR CONVERSACIÓN (default: ON).
        // Los mensajes vanish se tratan como previews desactivadas.
        let previewEnabled = ChatPreviewPrivacy.shouldRevealPreview(
            for: conversationId,
            isVanishModeMessage: ChatPreviewPrivacy.isVanishModeMessage(in: userInfo)
        )
        guard previewEnabled else {
            completion()
            return
        }

        // 1. Fast-path: contenido cifrado embebido en el payload.
        if let embedded = userInfo["encryptedContent"] as? String, !embedded.isEmpty,
           let decrypted = SharedChatDecryptor.decrypt(embedded, conversationId: conversationId) {
            applyPreviewText(decrypted, userInfo: userInfo, content: content)
            completion()
            return
        }

        // 2. Fetch del mensaje cifrado y descifrado local (payload solo trae metadatos).
        guard let messageId = userInfo["messageId"] as? String else {
            completion()
            return
        }

        let messageRef: DocumentReference
        if ChatNotificationThread.isGroupPush(userInfo) {
            messageRef = Firestore.firestore()
                .collection("groupConversations").document(conversationId)
                .collection("groupMessages").document(messageId)
        } else {
            messageRef = Firestore.firestore()
                .collection("conversations").document(conversationId)
                .collection("messages").document(messageId)
        }

        messageRef.getDocument { [weak self] snapshot, _ in
            defer { completion() }
            guard let self,
                  let data = snapshot?.data(),
                  !ChatPreviewPrivacy.isVanishModeMessage(in: data),
                  let cipher = data["content"] as? String, !cipher.isEmpty,
                  let decrypted = SharedChatDecryptor.decrypt(cipher, conversationId: conversationId) else {
                return
            }
            self.applyPreviewText(decrypted, userInfo: userInfo, content: content)
        }
    }

    /// Fija el título (remitente o grupo) y el cuerpo (texto descifrado, truncado).
    private func applyPreviewText(
        _ text: String,
        userInfo: [AnyHashable: Any],
        content: UNMutableNotificationContent
    ) {
        let trimmed = notificationPlainText(text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if ChatNotificationThread.isGroupPush(userInfo) {
            if let groupName = ChatNotificationThread.resolvedGroupName(
                from: userInfo,
                contentTitle: content.title,
                senderUsername: userInfo["senderUsername"] as? String
            ) {
                content.title = groupName
            }
            if let senderUsername = userInfo["senderUsername"] as? String, !senderUsername.isEmpty {
                content.subtitle = senderUsername
            }
        } else if let senderUsername = userInfo["senderUsername"] as? String, !senderUsername.isEmpty {
            content.title = senderUsername
        }

        // Truncar para que la notificación no muestre textos enormes.
        let maxLength = 200
        if trimmed.count > maxLength {
            content.body = String(trimmed.prefix(maxLength - 1)) + "…"
        } else {
            content.body = trimmed
        }
    }

    /// Reacción singular con texto visible: "Reaccionó con ❤️ a tu mensaje \"hola\"".
    /// Solo texto; media nunca incluye preview. Plural conserva el loc-key del servidor.
    private func resolveChatReactionPreview(
        userInfo: [AnyHashable: Any],
        content: UNMutableNotificationContent,
        completion: @escaping () -> Void
    ) {
        guard userInfo["isReactionPlural"] as? String != "1",
              userInfo["messageType"] as? String == "text",
              let conversationId = userInfo["conversationId"] as? String,
              let emoji = userInfo["reactionEmoji"] as? String,
              !emoji.isEmpty else {
            completion()
            return
        }

        let previewEnabled = ChatPreviewPrivacy.shouldRevealPreview(
            for: conversationId,
            isVanishModeMessage: ChatPreviewPrivacy.isVanishModeMessage(in: userInfo)
        )
        guard previewEnabled else {
            completion()
            return
        }

        if let senderUsername = userInfo["senderUsername"] as? String, !senderUsername.isEmpty {
            content.title = senderUsername
        }

        if let embedded = userInfo["encryptedContent"] as? String, !embedded.isEmpty,
           let decrypted = SharedChatDecryptor.decrypt(embedded, conversationId: conversationId) {
            applyReactionQuotedPreview(decrypted, emoji: emoji, content: content)
            completion()
            return
        }

        guard let messageId = userInfo["messageId"] as? String else {
            completion()
            return
        }

        Firestore.firestore()
            .collection("conversations").document(conversationId)
            .collection("messages").document(messageId)
            .getDocument { [weak self] snapshot, _ in
                defer { completion() }
                guard let self,
                      let data = snapshot?.data(),
                      !ChatPreviewPrivacy.isVanishModeMessage(in: data),
                      let cipher = data["content"] as? String, !cipher.isEmpty,
                      let decrypted = SharedChatDecryptor.decrypt(cipher, conversationId: conversationId) else {
                    return
                }
                self.applyReactionQuotedPreview(decrypted, emoji: emoji, content: content)
            }
    }

    private func applyReactionQuotedPreview(
        _ text: String,
        emoji: String,
        content: UNMutableNotificationContent
    ) {
        let trimmed = notificationPlainText(text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let maxLength = 120
        let quoted: String
        if trimmed.count > maxLength {
            quoted = String(trimmed.prefix(maxLength - 1)) + "…"
        } else {
            quoted = trimmed
        }

        let format = localizedString("notification.chatReaction.singleQuoted")
        content.body = String(format: format, locale: Locale.current, arguments: [emoji, quoted])
    }

    /// Las notificaciones muestran el significado del mensaje, no la sintaxis del
    /// editor. El spoiler nunca se revela fuera del chat.
    private func notificationPlainText(_ input: String) -> String {
        var result = input
        let replacements: [(String, String)] = [
            (#"\|\|([^|]+)\|\|"#, "••••"),
            (#"\*\*([^*]+)\*\*"#, "$1"),
            (#"(?<!\*)\*([^*]+)\*(?!\*)"#, "$1"),
            (#"~~([^~]+)~~"#, "$1"),
            (#"`([^`]+)`"#, "$1"),
            (#"(?m)^> ?"#, "")
        ]
        for (pattern, template) in replacements {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: template
            )
        }
        return result
    }

    /// Localiza desde el bundle de la app host (el NSE vive en App.app/PlugIns/…).
    private func localizedString(_ key: String) -> String {
        let bundle = hostAppBundle() ?? Bundle.main
        let value = bundle.localizedString(forKey: key, value: nil, table: nil)
        if value != key, !value.isEmpty {
            return value
        }
        return NSLocalizedString(key, bundle: bundle, comment: "")
    }

    private func hostAppBundle() -> Bundle? {
        // …/Moments.app/PlugIns/MomentsNotificationService.appex → …/Moments.app
        let appURL = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        if let host = Bundle(url: appURL), host.bundlePath.hasSuffix(".app") {
            return host
        }
        return Bundle(identifier: "com.glowsyapp")
    }

    // MARK: - Media previews

    /// Tipos que NUNCA muestran media en la notificación (privacidad):
    /// solo el texto genérico ("📷 Foto").
    private static let viewOnceMessageTypes: Set<String> = ["viewOnceImage", "viewOnceVideo", "ephemeral"]

    /// Decide y adjunta UNA sola imagen a la notificación (rich media).
    /// Mensajes de chat: solo media del mensaje (sin avatar fallback). Otros tipos: mediaUrl o avatar.
    private func resolveNotificationAttachment(
        userInfo: [AnyHashable: Any],
        content: UNMutableNotificationContent,
        completion: @escaping () -> Void
    ) {
        let notificationType = userInfo["type"] as? String
        let isChatMessage = ChatNotificationThread.isChatMessagePush(notificationType)
        let messageType = userInfo["messageType"] as? String

        if isChatMessage, let messageType,
           !Self.viewOnceMessageTypes.contains(messageType),
           let conversationId = ChatNotificationThread.conversationId(from: userInfo) {

            let previewEnabled = ChatPreviewPrivacy.shouldRevealPreview(
                for: conversationId,
                isVanishModeMessage: ChatPreviewPrivacy.isVanishModeMessage(in: userInfo)
            )

            if previewEnabled {
                // image/video → media cifrado. Vídeo usa la miniatura/poster cifrado;
                // imagen no tiene miniatura aparte, así que se descifra el media completo (con tope).
                if (messageType == "image" || messageType == "video"),
                   let messageId = userInfo["messageId"] as? String {
                    resolveEncryptedMediaAttachment(
                        userInfo: userInfo,
                        conversationId: conversationId,
                        messageId: messageId,
                        allowFullMediaFallback: messageType == "image",
                        content: content
                    ) { _ in
                        completion()
                    }
                    return
                }

                // gif/sticker → URL pública (Giphy), descarga directa preservando extensión (GIF animado).
                if messageType == "gif" || messageType == "sticker",
                   let mediaUrlString = userInfo["mediaUrl"] as? String,
                   let url = URL(string: mediaUrlString) {
                    downloadAttachment(from: url) { attachment in
                        if let attachment {
                            content.attachments = [attachment]
                        }
                        completion()
                    }
                    return
                }
            }

            completion()
            return
        }

        if isChatMessage {
            completion()
            return
        }

        // Notificación que no es de chat: usar mediaUrl de preview (moment/story) o avatar.
        if let mediaUrlString = userInfo["mediaUrl"] as? String, !mediaUrlString.isEmpty,
           let url = URL(string: mediaUrlString) {
            downloadImage(from: url) { [weak self] attachment in
                if let attachment {
                    content.attachments = [attachment]
                    completion()
                } else {
                    self?.attachSenderAvatar(userInfo: userInfo, content: content, completion: completion)
                }
            }
            return
        }

        attachSenderAvatar(userInfo: userInfo, content: content, completion: completion)
    }

    /// Descarga el avatar del remitente como adjunto (icono grande de respaldo).
    private func attachSenderAvatar(
        userInfo: [AnyHashable: Any],
        content: UNMutableNotificationContent,
        completion: @escaping () -> Void
    ) {
        guard let avatarString = userInfo["senderProfileImage"] as? String, !avatarString.isEmpty,
              let url = URL(string: avatarString) else {
            completion()
            return
        }
        downloadImage(from: url) { attachment in
            if let attachment {
                content.attachments = [attachment]
            }
            completion()
        }
    }

    /// Tope de tamaño para el media descifrado en la notificación. APNs permite hasta
    /// ~10 MB en adjuntos de imagen; nos quedamos por debajo por memoria/tiempo del NSE.
    private static let maxAttachmentBytes: Int64 = 8 * 1024 * 1024

    /// Resuelve el media CIFRADO de un mensaje image/video. Intenta primero la miniatura
    /// (poster de vídeo) y, si no existe y se permite, el media completo (imágenes).
    private func resolveEncryptedMediaAttachment(
        userInfo: [AnyHashable: Any],
        conversationId: String,
        messageId: String,
        allowFullMediaFallback: Bool,
        content: UNMutableNotificationContent,
        completion: @escaping (Bool) -> Void
    ) {
        let messageRef: DocumentReference
        if ChatNotificationThread.isGroupPush(userInfo) {
            messageRef = Firestore.firestore()
                .collection("groupConversations").document(conversationId)
                .collection("groupMessages").document(messageId)
        } else {
            messageRef = Firestore.firestore()
                .collection("conversations").document(conversationId)
                .collection("messages").document(messageId)
        }
        messageRef.getDocument { [weak self] snapshot, _ in
                guard let self, let data = snapshot?.data() else {
                    completion(false)
                    return
                }

                // 1. Miniatura/poster cifrado (existe para vídeo).
                if let thumbnailObjectPath = data["thumbnailObjectPath"] as? String,
                   !thumbnailObjectPath.isEmpty,
                   let metadataMap = data["thumbnailEncryption"] as? [String: Any],
                   let metadata = SharedChatDecryptor.MediaMetadata(map: metadataMap) {
                    self.downloadAndAttachEncryptedObject(
                        objectPath: thumbnailObjectPath,
                        metadata: metadata,
                        conversationId: conversationId,
                        messageId: messageId,
                        content: content,
                        completion: completion
                    )
                    return
                }

                // 2. Fallback (solo imágenes): media completo cifrado, si cabe en el tope.
                if allowFullMediaFallback,
                   let mediaObjectPath = data["mediaObjectPath"] as? String,
                   !mediaObjectPath.isEmpty,
                   let metadataMap = data["mediaEncryption"] as? [String: Any],
                   let metadata = SharedChatDecryptor.MediaMetadata(map: metadataMap),
                   metadata.plaintextSize <= Self.maxAttachmentBytes {
                    self.downloadAndAttachEncryptedObject(
                        objectPath: mediaObjectPath,
                        metadata: metadata,
                        conversationId: conversationId,
                        messageId: messageId,
                        content: content,
                        completion: completion
                    )
                    return
                }

                completion(false)
            }
    }

    private func downloadAndAttachEncryptedObject(
        objectPath: String,
        metadata: SharedChatDecryptor.MediaMetadata,
        conversationId: String,
        messageId: String,
        content: UNMutableNotificationContent,
        completion: @escaping (Bool) -> Void
    ) {
        let maxSize = min(
            max(metadata.plaintextSize + Int64(256 * 1024), Int64(2 * 1024 * 1024)),
            Self.maxAttachmentBytes + Int64(256 * 1024)
        )
        downloadStorageObject(path: objectPath, maxSize: maxSize) { encryptedData in
            guard
                let encryptedData,
                let decrypted = SharedChatDecryptor.decryptMedia(
                    encryptedData,
                    metadata: metadata,
                    conversationId: conversationId,
                    messageId: messageId
                )
            else {
                completion(false)
                return
            }

            let fileURL = self.temporaryAttachmentURL(
                messageId: messageId,
                fileExtension: metadata.fileExtension
            )

            do {
                try decrypted.write(to: fileURL, options: .atomic)
                let attachment = try UNNotificationAttachment(
                    identifier: "chat-media-\(messageId)",
                    url: fileURL,
                    options: nil
                )
                content.attachments = [attachment]
                completion(true)
            } catch {
                completion(false)
            }
        }
    }

    private func downloadStorageObject(path: String, maxSize: Int64, completion: @escaping (Data?) -> Void) {
        guard
            let bucket = FirebaseApp.app()?.options.storageBucket,
            let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)?
                .replacingOccurrences(of: "/", with: "%2F"),
            let url = URL(string: "https://firebasestorage.googleapis.com/v0/b/\(bucket)/o/\(encodedPath)?alt=media")
        else {
            completion(nil)
            return
        }

        guard let currentUser = Auth.auth().currentUser else {
            downloadStorageObject(url: url, bearerToken: nil, maxSize: maxSize, completion: completion)
            return
        }

        currentUser.getIDToken { token, _ in
            self.downloadStorageObject(url: url, bearerToken: token, maxSize: maxSize, completion: completion)
        }
    }

    private func downloadStorageObject(
        url: URL,
        bearerToken token: String?,
        maxSize: Int64,
        completion: @escaping (Data?) -> Void
    ) {
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            if let token {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }

            URLSession.shared.dataTask(with: request) { data, response, _ in
                guard
                    let httpResponse = response as? HTTPURLResponse,
                    (200..<300).contains(httpResponse.statusCode),
                    let data,
                    Int64(data.count) <= maxSize
                else {
                    completion(nil)
                    return
                }
                completion(data)
            }.resume()
    }

    private func temporaryAttachmentURL(messageId: String, fileExtension: String) -> URL {
        let safeMessageId = messageId.replacingOccurrences(of: "/", with: "_")
        let normalizedExtension = fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("chat_preview_\(safeMessageId).\(normalizedExtension.isEmpty ? "jpg" : normalizedExtension)")
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
            return false
        }
        
        let echoes = parseCount("unreadEchoes") ?? 0
        let tags = parseCount("unreadTags") ?? 0
        
        if let defaults = UserDefaults(suiteName: "group.com.glowsyapp") {
            // Guardar con persistencia forzada para App Groups
            defaults.set(messages + (parseCount("unreadGroupMessages") ?? 0), forKey: "widget_unread_messages")
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
                content.badge = (messages + (parseCount("unreadGroupMessages") ?? 0) + notifications) as NSNumber
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
        
        if let conversationId = ChatNotificationThread.conversationId(from: userInfo),
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
        
        let group = DispatchGroup()
        var count = 0
        var failed = false
        for collection in ["conversations", "groupConversations"] {
            group.enter()
            Firestore.firestore().collection(collection)
                .whereField("participants", arrayContains: userId)
                .getDocuments { snapshot, _ in
                    DispatchQueue.main.async {
                        if let documents = snapshot?.documents {
                            count += documents.filter {
                                ($0.data()["readStatus"] as? [String: Bool])?[userId] == false
                            }.count
                        } else { failed = true }
                        group.leave()
                    }
                }
        }
        group.notify(queue: .main) {
            if !failed, let defaults = UserDefaults(suiteName: "group.com.glowsyapp") {
                defaults.set(count, forKey: "widget_unread_messages")
                self.bestAttemptContent?.badge = NSNumber(value: count + defaults.integer(forKey: "widget_unread_notifications"))
                WidgetCenter.shared.reloadTimelines(ofKind: "GlowsyWidgetExtension")
            }
            completion()
        }
    }
    
    private func markMessageAsDelivered(conversationId: String, messageId: String, completion: @escaping () -> Void) {
        guard let userId = Auth.auth().currentUser?.uid else { 
            completion()
            return 
        }
        
        let db = Firestore.firestore()
        let isGroup = ChatNotificationThread.isGroupConversationId(conversationId)
        let messageRef = db.collection(isGroup ? "groupConversations" : "conversations").document(conversationId)
            .collection(isGroup ? "groupMessages" : "messages").document(messageId)
        
        messageRef.getDocument { snapshot, _ in
            guard let data = snapshot?.data(), let senderId = data["senderId"] as? String, senderId != userId else {
                completion()
                return
            }
            if isGroup {
                guard !(data["deliveredTo"] as? [String] ?? []).contains(userId) else { completion(); return }
                messageRef.updateData([
                    "deliveredTo": FieldValue.arrayUnion([userId]),
                    "deliveredAtBy.\(userId)": FieldValue.serverTimestamp()
                ]) { _ in completion() }
            } else if data["status"] as? String == "sent" {
                messageRef.updateData(["status": "delivered"]) { _ in completion() }
            } else { completion() }
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
    
    private func complete(_ content: UNNotificationContent) {
        completionLock.lock()
        let handler = contentHandler
        contentHandler = nil
        completionLock.unlock()
        handler?(content)
    }

    override func serviceExtensionTimeWillExpire() {
        // Called just before the extension will be terminated by the system.
        // Use this as an opportunity to deliver your "best attempt" at modified content, otherwise the original push payload will be used.
        if contentHandler != nil, let bestAttemptContent = bestAttemptContent {
            complete(applyCommunicationNotificationContent(
                userInfo: bestAttemptContent.userInfo, content: bestAttemptContent, senderImage: intentSenderImage, groupImage: intentGroupImage
            ))
        }
    }

    private func downloadImageData(from url: URL, completion: @escaping (Data?) -> Void) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        URLSession.shared.dataTask(with: request) { data, response, _ in
            guard let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode),
                  let data, data.count <= 2 * 1024 * 1024 else { completion(nil); return }
            completion(data)
        }.resume()
    }
    
    // Helper para descargar imagen (avatar / preview estático → JPG).
    private func downloadImage(from url: URL, completion: @escaping (UNNotificationAttachment?) -> Void) {
        downloadAttachment(from: url, forcedExtension: "jpg", completion: completion)
    }

    /// Descarga y adjunta preservando la extensión real (GIF/WebP/PNG animados de Giphy
    /// deben conservar su extensión para que iOS valide y anime el adjunto correctamente).
    private func downloadAttachment(
        from url: URL,
        forcedExtension: String? = nil,
        completion: @escaping (UNNotificationAttachment?) -> Void
    ) {
        let task = URLSession.shared.downloadTask(with: url) { (downloadedUrl, response, _) in
            guard let downloadedUrl = downloadedUrl else {
                completion(nil)
                return
            }

            let resolvedExtension = forcedExtension
                ?? Self.fileExtension(for: url, response: response)
            let fileName = ProcessInfo.processInfo.globallyUniqueString + "." + resolvedExtension
            let destination = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent(fileName)

            try? FileManager.default.moveItem(at: downloadedUrl, to: destination)

            do {
                let attachment = try UNNotificationAttachment(identifier: "media", url: destination, options: nil)
                completion(attachment)
            } catch {
                completion(nil)
            }
        }
        task.resume()
    }

    /// Determina la extensión del adjunto a partir de la URL o el MIME de la respuesta.
    private static func fileExtension(for url: URL, response: URLResponse?) -> String {
        let pathExtension = url.pathExtension.lowercased()
        let knownExtensions: Set<String> = ["gif", "jpg", "jpeg", "png", "webp", "heic", "mp4", "mov"]
        if knownExtensions.contains(pathExtension) {
            return pathExtension
        }

        switch response?.mimeType?.lowercased() {
        case "image/gif": return "gif"
        case "image/png": return "png"
        case "image/webp": return "webp"
        case "image/heic": return "heic"
        case "video/mp4": return "mp4"
        case "video/quicktime": return "mov"
        default: return "jpg"
        }
    }
}
