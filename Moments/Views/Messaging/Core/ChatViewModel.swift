import Foundation
import FirebaseAuth
import FirebaseFirestore
import Combine
import Photos
import PhotosUI
import AVFoundation
import SwiftUI
import UIKit

@MainActor
class EnhancedChatViewModel: ObservableObject {
    @Published var messages: [EnhancedMessage] = []
    @Published var typingUsers: Set<String> = []
    @Published var typingIndicatorEnabled = true
    @Published var isLoading = false
    @Published var error: String?
    @Published var uploadProgress: [String: Double] = [:] // ✅ Media upload progress (0.0 - 1.0)

    private func setUploadProgress(_ progress: Double, for messageId: String) {
        var updated = uploadProgress
        updated[messageId] = progress
        uploadProgress = updated
    }

    private func clearUploadProgress(for messageId: String) {
        guard uploadProgress[messageId] != nil else { return }
        var updated = uploadProgress
        updated.removeValue(forKey: messageId)
        uploadProgress = updated
    }

    private func pruneUploadProgress(for messages: [EnhancedMessage]) {
        let activeSendingIds = Set(messages.filter { $0.status == .sending }.map(\.id))
        var updated = uploadProgress
        for messageId in updated.keys where !activeSendingIds.contains(messageId) {
            updated.removeValue(forKey: messageId)
        }
        if updated != uploadProgress {
            uploadProgress = updated
        }
    }

    private func pruneLocalMessageStates(for messages: [EnhancedMessage]) {
        let statusPriority: [MessageStatus: Int] = [
            .sending: 0, .sent: 1, .delivered: 2, .read: 3, .failed: -1, .pending: -1
        ]
        for (messageId, localStatus) in localMessageStates {
            guard let remoteStatus = messages.first(where: { $0.id == messageId })?.status else { continue }
            let localPriority = statusPriority[localStatus] ?? 0
            let remotePriority = statusPriority[remoteStatus] ?? 0
            if remotePriority >= localPriority && localStatus != .failed {
                localMessageStates.removeValue(forKey: messageId)
            }
        }
    }

    private func commitMessagesPresentation(_ messages: [EnhancedMessage]) {
        self.messages = Array(messages)
        pruneUploadProgress(for: messages)
        pruneLocalMessageStates(for: messages)
        if let momentsViewModel = self as? MomentsChatViewModel {
            momentsViewModel.syncMessagePresentation()
        }
    }
    @Published var isTyping = false {
        didSet {
            handleTypingIndicator()
        }
    }

    // ✅ NUEVO: Diccionario para estados locales con prioridad
    private var localMessageStates: [String: MessageStatus] = [:]
    /// Mensajes salientes aún no reflejados en Firestore; sobreviven a `rebuildMessagesList`.
    private var outgoingTempMessages: [String: EnhancedMessage] = [:]
    private var hydratingMediaIds = Set<String>()
    private var refreshingMetadataIds = Set<String>()
    
    // ✅ NUEVO: Flag para bloquear listener temporalmente
    private var isUpdatingLocalMessage = false
    
    // ✅ NUEVO: Flag para saber si el chat está visible (para marcar como leído solo cuando está visible)
    var isChatVisible = false
    
    // ✅ PAGINACIÓN
    @Published var isLoadingMore = false
    @Published var canLoadMore = true
    @Published private(set) var forwardingPreferences: [String: Bool] = [:]
    @Published private(set) var buzzPreferences: [String: Bool] = [:]
    /// Fuente de verdad para pintar reacciones al instante (SwiftUI no siempre detecta cambios en `message.reactions`).
    @Published private(set) var liveReactionOverlays: [String: [String: [String]]] = [:]
    @Published var latestBuzzEvent: ChatBuzzEvent?
    @Published private(set) var buzzEvents: [ChatBuzzEvent] = []
    private var historicalMessages: [EnhancedMessage] = []
    private var realTimeMessages: [EnhancedMessage] = []
    private var seenBuzzEventIds = Set<String>()
    
    let conversation: Conversation
    let currentUserId: String
    private let chatService = ChatService.shared
    private let firestoreService = FirestoreService()
    private var cancellables = Set<AnyCancellable>()
    private var typingUsersCancellable: AnyCancellable?
    private var typingTimer: Timer?
    private var messageStatusObserver: NSObjectProtocol?
    private var mediaUploadObserver: NSObjectProtocol?
    
    // ✅ NUEVO: Flag para detectar la primera carga de Firestore (merge-first, sin wipe de caché)
    private var isFirstFetch = true

    enum ChatSessionMode: Equatable {
        case cold
        case warm
        case active
    }

    private(set) var chatSessionMode: ChatSessionMode = .cold
    private var sessionListenersAttached = false
    private var listenerPauseTask: Task<Void, Never>?
    private var didLoadCacheFromSwiftData = false
    private var requestedHighlightMessageIds = Set<String>()
    private static let listenerPauseTTL: UInt64 = 180_000_000_000
    
    init(conversation: Conversation) {
        self.conversation = conversation
        self.currentUserId = Auth.auth().currentUser?.uid ?? ""
        self.forwardingPreferences = conversation.forwardingPreferences ?? [:]
        self.buzzPreferences = conversation.buzzPreferences ?? [:]

        // ✅ Configurar listener para actualizaciones de estado locales
        setupLocalStatusListener()
        setupConversationPreferenceListener()
        refreshTypingIndicatorPreference()
    }
    
    // ✅ NUEVA: Configurar listener para actualizaciones de estado locales
    private func setupLocalStatusListener() {
        messageStatusObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("MessageStatusUpdated"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let conversationId = userInfo["conversationId"] as? String,
                  let messageId = userInfo["messageId"] as? String,
                  let statusString = userInfo["status"] as? String,
                  let status = MessageStatus(rawValue: statusString),
                  conversationId == self?.conversation.id else {
                return
            }
            
            
            // ✅ Usar la nueva función para actualizar el array
            Task { @MainActor [weak self] in
                self?.updateMessageInArray(messageId: messageId, newStatus: status)
            }
        }

        // ✅ Progress Listener
        mediaUploadObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("MediaUploadProgress"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let messageId = userInfo["messageId"] as? String,
                  let progress = userInfo["progress"] as? Double else {
                return
            }
            
            DispatchQueue.main.async {
                self?.setUploadProgress(progress, for: messageId)
            }
        }
    }

    private func setupConversationPreferenceListener() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ConversationForwardingPreferenceChanged"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let userInfo = notification.userInfo,
                  let conversationId = userInfo["conversationId"] as? String,
                  conversationId == self.conversation.id else { return }

            if let userId = userInfo["userId"] as? String,
               let allowsForwarding = userInfo["allowsForwarding"] as? Bool {
                var updated = self.forwardingPreferences
                updated[userId] = allowsForwarding
                self.forwardingPreferences = updated
            } else if let preferences = userInfo["forwardingPreferences"] as? [String: Bool] {
                self.forwardingPreferences = preferences
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ConversationBuzzPreferenceChanged"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let userInfo = notification.userInfo,
                  let conversationId = userInfo["conversationId"] as? String,
                  conversationId == self.conversation.id else { return }

            if let userId = userInfo["userId"] as? String,
               let allowsBuzz = userInfo["allowsBuzz"] as? Bool {
                var updated = self.buzzPreferences
                updated[userId] = allowsBuzz
                self.buzzPreferences = updated
            } else if let preferences = userInfo["buzzPreferences"] as? [String: Bool] {
                self.buzzPreferences = preferences
            }
        }
    }

    var canSendBuzz: Bool {
        ChatMessagePolicy.canSendBuzz(
            participants: conversation.participants,
            currentUserId: currentUserId,
            buzzPreferences: buzzPreferences
        )
    }

    func refreshForwardingPreference() {
        guard let conversationId = conversation.id, !conversationId.isEmpty else { return }
        let key = "chat_forwarding_enabled_\(conversationId)"
        if let stored = UserDefaults.standard.object(forKey: key) as? Bool {
            var updated = forwardingPreferences
            updated[currentUserId] = stored
            forwardingPreferences = updated
        }
    }
    
    private func typingIndicatorPreferenceKey(for conversationId: String) -> String {
        "chat_typing_indicator_enabled_\(conversationId)"
    }
    
    private func resolvedTypingIndicatorPreference(for conversationId: String) -> Bool {
        let defaults = UserDefaults.standard
        let perChatKey = typingIndicatorPreferenceKey(for: conversationId)
        
        if let perChatValue = defaults.object(forKey: perChatKey) as? Bool {
            return perChatValue
        }
        
        if let legacyGlobalValue = defaults.object(forKey: "chat_typing_indicator_enabled") as? Bool {
            return legacyGlobalValue
        }
        
        return true
    }
    
    private func setupTypingUsersSubscription(conversationId: String) {
        typingUsersCancellable?.cancel()
        typingUsersCancellable = chatService.$typingUsers
            .compactMap { $0[conversationId] }
            .sink { [weak self] typingUsers in
                guard let self = self else { return }
                
                guard self.typingIndicatorEnabled else {
                    self.typingUsers = []
                    return
                }
                
                let filteredUsers = typingUsers.filter { $0 != self.currentUserId }
                self.typingUsers = filteredUsers
            }
    }
    
    private func applyTypingPreference(conversationId: String) {
        if typingIndicatorEnabled {
            chatService.listenToTypingIndicators(conversationId: conversationId)
            setupTypingUsersSubscription(conversationId: conversationId)
        } else {
            typingUsers = []
            chatService.stopTyping(conversationId: conversationId, userId: currentUserId)
            chatService.removeTypingListener(for: conversationId)
            typingUsersCancellable?.cancel()
            typingUsersCancellable = nil
        }
    }
    
    func refreshTypingIndicatorPreference() {
        guard let conversationId = conversation.id, !conversationId.isEmpty else { return }
        typingIndicatorEnabled = resolvedTypingIndicatorPreference(for: conversationId)
        applyTypingPreference(conversationId: conversationId)
    }
    
    // ✅ NUEVA: Función para preservar mensajes temporales
    private func preserveTemporaryMessages(_ newMessages: [EnhancedMessage]) -> [EnhancedMessage] {
        let temporaryMessages = self.messages.filter { $0.status == .sending }
        
        var mergedMessages = newMessages
        
        for tempMessage in temporaryMessages {
            // Solo agregar si NO existe ya en Firestore
            if !mergedMessages.contains(where: { $0.id == tempMessage.id }) {
                mergedMessages.append(tempMessage)
            }
        }

        for (_, tempMessage) in outgoingTempMessages {
            if let index = mergedMessages.firstIndex(where: { $0.id == tempMessage.id }) {
                if let localUrl = tempMessage.mediaUrl,
                   let url = URL(string: localUrl),
                   url.isFileURL,
                   mergedMessages[index].mediaUrl == nil {
                    mergedMessages[index].mediaUrl = localUrl
                }
            } else {
                mergedMessages.append(tempMessage)
            }
        }
        
        // ✅ CORREGIDO: Solo aplicar estado local si es MÁS AVANZADO que el de Firestore
        // Orden de prioridad: sending < sent < delivered < read
        // No sobrescribir un estado más avanzado con uno menos avanzado
        let statusPriority: [MessageStatus: Int] = [
            .sending: 0,
            .sent: 1,
            .delivered: 2,
            .read: 3,
            .failed: -1
        ]
        
        for (messageId, localStatus) in localMessageStates {
            if let index = mergedMessages.firstIndex(where: { $0.id == messageId }) {
                let firestoreStatus = mergedMessages[index].status
                let localPriority = statusPriority[localStatus] ?? 0
                let firestorePriority = statusPriority[firestoreStatus] ?? 0
                
                // Solo aplicar local si es más avanzado O si es failed
                if localPriority > firestorePriority || localStatus == .failed {
                    mergedMessages[index].status = localStatus
                }
            }
        }

        // Conservar preview local file:// mientras Firestore aún no expone URL visible.
        for existing in messages where existing.senderId == currentUserId {
            guard let index = mergedMessages.firstIndex(where: { $0.id == existing.id }),
                  let localUrl = existing.mediaUrl,
                  let url = URL(string: localUrl),
                  url.isFileURL else { continue }
            if mergedMessages[index].mediaUrl == nil {
                mergedMessages[index].mediaUrl = localUrl
            }
        }

        // Conservar reacciones en memoria si el snapshot de mensajes llega sin hidratar subcolección.
        for existing in messages {
            guard let index = mergedMessages.firstIndex(where: { $0.id == existing.id }),
                  existing.reactions != nil else { continue }
            mergedMessages[index].reactions = chatService.mergeLegacyAndLiveReactions(
                legacy: existing.reactions,
                live: mergedMessages[index].reactions
            )
        }
        
        return mergedMessages.sorted { $0.timestamp < $1.timestamp }
    }
    
    // ✅ NUEVA: Función para actualizar el array de manera que SwiftUI lo detecte
    func updateMessageInArray(messageId: String, newStatus: MessageStatus) {
        applyOutgoingMessageUpdate(messageId: messageId, status: newStatus, mediaUrl: nil, thumbnailUrl: nil)
    }

    func applyOutgoingMessageUpdate(
        messageId: String,
        status: MessageStatus,
        mediaUrl: String?,
        thumbnailUrl: String?
    ) {
        localMessageStates[messageId] = status
        clearUploadProgress(for: messageId)
        outgoingTempMessages.removeValue(forKey: messageId)

        guard let index = messages.firstIndex(where: { $0.id == messageId }) else {
            if let momentsViewModel = self as? MomentsChatViewModel {
                momentsViewModel.syncMessagePresentation()
            }
            return
        }

        let apply = {
            let message = self.messages[index]
            message.status = status
            if let mediaUrl {
                message.mediaUrl = mediaUrl
            }
            if let thumbnailUrl {
                message.thumbnailUrl = thumbnailUrl
            }
            // Reasignar el array para que @Published notifique a SwiftUI (clases dentro del array).
            self.commitMessagesPresentation(self.messages)
        }

        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }

    func localOutgoingPreviewURL(data: Data, fileExtension: String) -> String? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("chat_outgoing_\(UUID().uuidString).\(fileExtension)")
        do {
            try data.write(to: url, options: .atomic)
            return url.absoluteString
        } catch {
            return nil
        }
    }

    func appendOutgoingMessage(_ message: EnhancedMessage) {
        outgoingTempMessages[message.id] = message
        messages.append(message)
        messages = Array(messages)
        objectWillChange.send()
        if let momentsViewModel = self as? MomentsChatViewModel {
            momentsViewModel.syncMessagePresentation()
        }
        if let conversationId = conversation.id,
           message.status == .sending || message.status == .pending || message.status == .failed {
            LocalPersistenceService.shared.saveMessages([message], conversationId: conversationId, sync: false)
        }
    }

    private func messageNeedsMediaHydration(_ message: EnhancedMessage) -> Bool {
        message.isMediaPendingResolution
    }

    /// Mensajes del cache antiguo pueden carecer de metadata de Storage; re-fetch puntual desde Firestore.
    func refreshMediaMetadataIfNeeded(for message: EnhancedMessage) {
        guard message.type == .image || message.type == .video else { return }
        guard let conversationId = conversation.id, !conversationId.isEmpty else { return }

        let missingMain = message.mediaObjectPath == nil || message.mediaEncryption == nil
        let needsThumb = message.type == .video && message.needsVideoThumbnailForDisplay
        let missingThumbMeta = message.thumbnailObjectPath == nil || message.thumbnailEncryption == nil

        if message.type == .image {
            guard missingMain else { return }
        } else if missingMain {
            // Falta metadata del vídeo principal.
        } else if needsThumb && missingThumbMeta {
            // Falta metadata de la miniatura cifrada (p. ej. cache viejo).
        } else {
            if needsThumb { hydrateVideoThumbnailIfNeeded(for: message) }
            return
        }

        let messageId = message.id
        guard refreshingMetadataIds.insert(messageId).inserted else { return }

        chatService.fetchMessage(conversationId: conversationId, messageId: messageId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.refreshingMetadataIds.remove(messageId)
                if case .success(let fresh?) = result {
                    self.applyRefreshedMediaMessage(fresh, conversationId: conversationId)
                }
            }
        }
    }

    private func applyRefreshedMediaMessage(_ fresh: EnhancedMessage, conversationId: String) {
        if let index = historicalMessages.firstIndex(where: { $0.id == fresh.id }) {
            historicalMessages[index] = fresh
        }
        if let index = realTimeMessages.firstIndex(where: { $0.id == fresh.id }) {
            realTimeMessages[index] = fresh
        }
        rebuildMessagesList()
        LocalPersistenceService.shared.saveMessages([fresh], conversationId: conversationId, sync: false)
        if let updated = messages.first(where: { $0.id == fresh.id }) {
            if updated.type == .video {
                hydrateVideoThumbnailIfNeeded(for: updated)
            } else {
                hydrateMediaIfNeeded(for: updated)
            }
        }
    }

    func hydrateMediaIfNeeded(for message: EnhancedMessage) {
        // Para vídeos resolvemos solo la miniatura (barato). El vídeo completo se
        // descarga al abrirlo, evitando bajar megas solo para mostrar la portada.
        if message.type == .video {
            hydrateVideoThumbnailIfNeeded(for: message)
            return
        }
        guard messageNeedsMediaHydration(message) else {
            if message.type == .image,
               message.mediaUrl == nil,
               message.mediaObjectPath == nil || message.mediaEncryption == nil {
                refreshMediaMetadataIfNeeded(for: message)
            }
            return
        }
        guard !hydratingMediaIds.contains(message.id) else { return }
        hydratingMediaIds.insert(message.id)
        prepareMediaForViewing(message) { [weak self] updated in
            self?.hydratingMediaIds.remove(message.id)
        }
    }

    func hydrateVideoThumbnailIfNeeded(for message: EnhancedMessage) {
        guard message.type == .video else { return }
        guard message.needsVideoThumbnailForDisplay else { return }

        // Caso 1: hay miniatura cifrada en Storage. Resolverla sola es barato.
        if message.thumbnailObjectPath != nil, message.thumbnailEncryption != nil {
            let thumbnailKey = "thumb_\(message.id)"
            guard !hydratingMediaIds.contains(thumbnailKey) else { return }
            hydratingMediaIds.insert(thumbnailKey)
            Task { [weak self] in
                guard let self else { return }
                let resolvedThumb = await self.chatService.resolveVideoThumbnail(for: message)
                await MainActor.run {
                    self.hydratingMediaIds.remove(thumbnailKey)
                    guard let resolvedThumb,
                          let index = self.messages.firstIndex(where: { $0.id == message.id }) else {
                        return
                    }
                    self.messages[index].thumbnailUrl = resolvedThumb
                    if let conversationId = self.conversation.id {
                        LocalPersistenceService.shared.saveMessages([self.messages[index]], conversationId: conversationId, sync: false)
                    }
                }
            }
            return
        }

        // Caso 2: vídeo ya disponible local/remoto → generar poster sin bajar el .mp4 completo.
        if let mediaUrl = message.mediaUrl, URL(string: mediaUrl) != nil {
            generateVideoPosterIfPossible(for: message)
            return
        }

        // Caso 3: solo tenemos el vídeo cifrado → descargar y luego generar poster.
        if message.mediaObjectPath != nil, message.mediaEncryption != nil {
            guard !hydratingMediaIds.contains(message.id) else { return }
            hydratingMediaIds.insert(message.id)
            prepareMediaForViewing(message) { [weak self] updated in
                self?.hydratingMediaIds.remove(message.id)
                self?.generateVideoPosterIfPossible(for: updated)
            }
            return
        }

        refreshMediaMetadataIfNeeded(for: message)
    }

    private func generateVideoPosterIfPossible(for message: EnhancedMessage) {
        guard message.needsVideoThumbnailForDisplay,
              let mediaUrl = message.mediaUrl,
              let url = URL(string: mediaUrl) else { return }
        let posterKey = "poster_\(message.id)"
        guard !hydratingMediaIds.contains(posterKey) else { return }
        hydratingMediaIds.insert(posterKey)
        Task { [weak self] in
            let poster = await ChatVideoPosterGenerator.poster(for: url, messageId: message.id)
            await MainActor.run {
                guard let self else { return }
                self.hydratingMediaIds.remove(posterKey)
                guard let poster,
                      let index = self.messages.firstIndex(where: { $0.id == message.id }) else {
                    return
                }
                self.messages[index].thumbnailUrl = poster
                if let conversationId = self.conversation.id {
                    LocalPersistenceService.shared.saveMessages([self.messages[index]], conversationId: conversationId, sync: false)
                }
            }
        }
    }

    /// Precalienta la galería del cluster: caché en disco → URLs locales al instante,
    /// hidratación en paralelo para lo que falte, y prefetch de Kingfisher.
    func prefetchClusterGalleryMedia(_ clusterMessages: [EnhancedMessage]) {
        var didUpdate = false

        for clusterMessage in clusterMessages {
            guard let index = messages.firstIndex(where: { $0.id == clusterMessage.id }) else {
                refreshMediaMetadataIfNeeded(for: clusterMessage)
                hydrateMediaIfNeeded(for: clusterMessage)
                continue
            }

            if messages[index].mediaObjectPath == nil || messages[index].mediaEncryption == nil {
                refreshMediaMetadataIfNeeded(for: messages[index])
            }

            let warmed = chatService.warmMessageURLsFromDiskCache(messages[index])
            if let mediaUrl = warmed.mediaUrl, messages[index].mediaUrl == nil {
                messages[index].mediaUrl = mediaUrl
                didUpdate = true
            }
            if let thumbnailUrl = warmed.thumbnailUrl, messages[index].thumbnailUrl == nil {
                messages[index].thumbnailUrl = thumbnailUrl
                didUpdate = true
            }
            if messages[index].type == .video {
                hydrateVideoThumbnailIfNeeded(for: messages[index])
            } else {
                hydrateMediaIfNeeded(for: messages[index])
            }
        }

        if didUpdate, let conversationId = conversation.id {
            LocalPersistenceService.shared.saveMessages(
                clusterMessages.compactMap { m in messages.first(where: { $0.id == m.id }) },
                conversationId: conversationId,
                sync: false
            )
        }

        ChatMediaGalleryPrefetcher.prefetch(messages: clusterMessages)
    }

    /// Hidrata media cifrada o pendiente de resolver (imagen, video, GIF/sticker legacy).
    func prefetchUnresolvedMediaIfNeeded() {
        for message in messages where messageNeedsMediaHydration(message) {
            hydrateMediaIfNeeded(for: message)
        }
        for message in messages where message.type == .gif || message.type == .sticker {
            guard let urlString = message.mediaUrl,
                  let url = URL(string: urlString),
                  !url.isFileURL else { continue }
            ChatGIFImageCache.shared.prefetch(url: url)
        }
    }

    /// Tras reinstalar o sin caché local: descarga el `.enc`, descifra y actualiza el mensaje en la lista.
    func prepareMediaForViewing(_ message: EnhancedMessage, completion: @escaping (EnhancedMessage) -> Void) {
        // Si ya hay una URL usable la devolvemos tal cual. Pero si es un `file://` cuyo archivo
        // fue purgado del directorio Caches, NO cortamos aquí: hay que re-descargar/descifrar.
        if message.mediaUrl != nil, !message.hasMissingLocalMedia {
            completion(message)
            return
        }

        if (message.type == .gif || message.type == .sticker),
           message.hasMissingLocalMedia,
           message.mediaObjectPath == nil {
            if let index = messages.firstIndex(where: { $0.id == message.id }) {
                messages[index].mediaUrl = nil
            }
            completion(messages.first(where: { $0.id == message.id }) ?? message)
            return
        }

        guard message.mediaObjectPath != nil, message.mediaEncryption != nil else {
            completion(message)
            return
        }

        Task {
            guard let (mediaUrl, thumbnailUrl) = await chatService.resolveEncryptedMediaForMessage(message) else {
                await MainActor.run { completion(message) }
                return
            }
            await MainActor.run {
                if let index = messages.firstIndex(where: { $0.id == message.id }) {
                    messages[index].mediaUrl = mediaUrl
                    if let thumbnailUrl {
                        messages[index].thumbnailUrl = thumbnailUrl
                    }
                    if let conversationId = conversation.id {
                        LocalPersistenceService.shared.saveMessages([messages[index]], conversationId: conversationId, sync: false)
                    }
                }
                let updated = messages.first(where: { $0.id == message.id }) ?? message
                completion(updated)
            }
        }
    }
    
    // ✅ NUEVA: Función para limpiar estados locales después de un tiempo
    private func cleanupLocalStates() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
            self.localMessageStates.removeAll()
            self.uploadProgress = [:]
        }
    }
    
    private func rebuildMessagesList() {
        // 1. Unir real-time + históricos (PRIORIDAD AL REAL-TIME para cambios de estado)
        let allMessages = messagesRespectingDeletionCutoff(realTimeMessages + historicalMessages)
        
        // 2. Deduplicar por ID (se queda con el primero que encuentre, que ahora es el real-time)
        var seenIds = Set<String>()
        let uniqueMessages = allMessages.filter { seenIds.insert($0.id).inserted }
        
        // 3. Ordenar
        let sortedMessages = uniqueMessages.sorted { $0.timestamp < $1.timestamp }
        
        // 4. Preservar temporales y estados locales
        let finalMessages = preserveTemporaryMessages(sortedMessages)
        commitMessagesPresentation(finalMessages)
        syncLiveReactionOverlays(from: finalMessages)

        for id in Array(outgoingTempMessages.keys) {
            if let msg = finalMessages.first(where: { $0.id == id }), msg.status != .sending {
                outgoingTempMessages.removeValue(forKey: id)
            }
        }
    }

    /// Punto de corte tras borrar conversación: modelo local o mapa en memoria de ChatService.
    private func effectiveDeletedAtCutoff() -> Date? {
        if let cutoff = conversation.deletedAtCutoff(for: currentUserId) {
            return cutoff
        }
        guard let conversationId = conversation.id else { return nil }
        return chatService.deletedAtCutoff(for: conversationId)
    }

    private func messagesRespectingDeletionCutoff(_ messages: [EnhancedMessage]) -> [EnhancedMessage] {
        guard let cutoff = effectiveDeletedAtCutoff() else { return messages }
        return messages.filter { $0.timestamp > cutoff }
    }

    private func commitReactionPresentation(conversationId: String? = nil) {
        messages = Array(messages)
        if let momentsViewModel = self as? MomentsChatViewModel {
            momentsViewModel.syncMessagePresentation()
        }
        if let conversationId = conversationId ?? conversation.id, !conversationId.isEmpty {
            LocalPersistenceService.shared.saveMessages(messages, conversationId: conversationId)
        }
    }

    func displayReactions(for messageId: String) -> [String: [String]]? {
        if let overlay = liveReactionOverlays[messageId] {
            return overlay
        }
        return messages.first(where: { $0.id == messageId })?.reactions
    }

    private func syncLiveReactionOverlays(from messages: [EnhancedMessage]) {
        var overlays = liveReactionOverlays
        for message in messages {
            guard let reactions = message.reactions, !reactions.isEmpty else { continue }
            overlays[message.id] = chatService.mergeLegacyAndLiveReactions(
                legacy: overlays[message.id],
                live: reactions
            ) ?? reactions
        }
        liveReactionOverlays = overlays
    }

    private func setLiveReactions(_ reactions: [String: [String]]?, for messageId: String) {
        var overlays = liveReactionOverlays
        if let reactions, !reactions.isEmpty {
            overlays[messageId] = reactions
        } else {
            overlays.removeValue(forKey: messageId)
        }
        liveReactionOverlays = overlays

        mutateReactionState(for: messageId) { message in
            message.reactions = reactions
        }
        commitReactionPresentation()
    }

    private func mutateReactionState(
        for messageId: String,
        _ transform: (EnhancedMessage) -> Void
    ) {
        for message in realTimeMessages where message.id == messageId {
            transform(message)
        }
        for message in historicalMessages where message.id == messageId {
            transform(message)
        }
        if let outgoingMessage = outgoingTempMessages[messageId] {
            transform(outgoingMessage)
            outgoingTempMessages[messageId] = outgoingMessage
        }
        for message in messages where message.id == messageId {
            transform(message)
        }
    }

    private var hasReceivedInitialReactionSnapshot = false

    private func applyReactionUpdate(_ update: MessageReactionUpdate, conversationId: String) {
        let affectedIds = update.changedMessageIds.union(update.reactionsByMessage.keys)
        guard !affectedIds.isEmpty else { return }

        var overlays = liveReactionOverlays
        for messageId in affectedIds {
            let liveReactions = update.reactionsByMessage[messageId]
            mutateReactionState(for: messageId) { message in
                message.reactions = liveReactions
            }
            if let liveReactions, !liveReactions.isEmpty {
                overlays[messageId] = liveReactions
            } else {
                overlays.removeValue(forKey: messageId)
            }
        }

        if hasReceivedInitialReactionSnapshot {
            for messageId in update.changedMessageIds {
                guard
                    let message = messages.first(where: { $0.id == messageId }),
                    message.senderId == currentUserId,
                    let liveReactions = update.reactionsByMessage[messageId],
                    !liveReactions.isEmpty,
                    reactionIncludesOtherParticipant(liveReactions)
                else { continue }

                NotificationCenter.default.post(
                    name: .chatMessageReactionHighlight,
                    object: nil,
                    userInfo: [
                        "conversationId": conversationId,
                        "messageId": messageId
                    ]
                )
            }
        }
        hasReceivedInitialReactionSnapshot = true
        liveReactionOverlays = overlays

        commitReactionPresentation(conversationId: conversationId)
    }

    private func reactionIncludesOtherParticipant(_ reactions: [String: [String]]) -> Bool {
        reactions.values.contains { userIds in
            userIds.contains { $0 != currentUserId }
        }
    }

    /// Mensaje propio con reacción de otra persona; solo si hay exactamente uno (apertura sin push).
    func soleOwnMessageWithExternalReactionId() -> String? {
        let matching = messages.filter { message in
            guard message.senderId == currentUserId else { return false }
            let reactions = liveReactionOverlays[message.id] ?? message.reactions
            guard let reactions, !reactions.isEmpty else { return false }
            return reactionIncludesOtherParticipant(reactions)
        }
        guard matching.count == 1, let id = matching.last?.id else { return nil }
        return id
    }

    func preferredHighlightMessageIdForOpen(intentHighlightIds: Set<String>) -> String? {
        if let intentId = intentHighlightIds.first { return intentId }
        return soleOwnMessageWithExternalReactionId()
    }
    
    // ✅ FUNCIÓN: Cargar más mensajes (Pull to refresh)
    func loadMoreMessages() {
        guard !isLoadingMore, canLoadMore, let firstMessage = messages.first, let conversationId = conversation.id else { return }
        
        isLoadingMore = true
        
        let cutoff = effectiveDeletedAtCutoff()
        chatService.fetchOlderMessages(
            conversationId: conversationId,
            before: firstMessage.timestamp,
            cutoffDate: cutoff
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoadingMore = false
                
                switch result {
                case .success(let olderMessages):
                    if olderMessages.isEmpty {
                        self.canLoadMore = false
                    } else {
                        self.historicalMessages.append(contentsOf: olderMessages)
                        self.rebuildMessagesList()
                        if let conversationId = self.conversation.id {
                            LocalPersistenceService.shared.appendMessages(olderMessages, conversationId: conversationId)
                        }
                    }
                case .failure(let error):
                    print("Error loading more messages: \(error)")
                }
            }
        }
    }

    func loadMessageForHighlightIfNeeded(messageId: String) {
        guard !messageId.isEmpty else { return }
        guard !messages.contains(where: { $0.id == messageId }) else { return }
        guard let conversationId = conversation.id else { return }
        guard requestedHighlightMessageIds.insert(messageId).inserted else { return }

        chatService.fetchMessage(conversationId: conversationId, messageId: messageId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let message):
                    guard let message else { return }
                    guard !self.messages.contains(where: { $0.id == message.id }) else { return }
                    self.historicalMessages.append(message)
                    self.rebuildMessagesList()
                    LocalPersistenceService.shared.appendMessages([message], conversationId: conversationId)
                case .failure(let error):
                    print("Error loading highlighted message: \(error)")
                }
            }
        }
    }
    
    // ✅ NUEVA: Función para reemplazar mensaje temporal
    private func replaceTemporaryMessage(messageId: String, with sentMessage: EnhancedMessage) {
        // ✅ Limpiar estado local ya que el mensaje se ha enviado
        localMessageStates.removeValue(forKey: messageId)
        
        if let index = messages.firstIndex(where: { $0.id == messageId }) {
            DispatchQueue.main.async {
                self.messages[index] = sentMessage
                self.cleanupLocalStates()
                self.objectWillChange.send()
            }
        } else {
            DispatchQueue.main.async {
                self.messages.append(sentMessage)
                self.cleanupLocalStates()
                self.objectWillChange.send()
            }
        }
    }
    
    // MARK: - Lifecycle

    func loadCachedMessagesIfNeeded() {
        guard let conversationId = conversation.id, !conversationId.isEmpty else { return }
        guard !didLoadCacheFromSwiftData else { return }
        didLoadCacheFromSwiftData = true

        var cachedMessages = LocalPersistenceService.shared.loadMessages(conversationId: conversationId)
        
        // Filtrar mensajes locales usando el punto de corte (lastDeletedAt)
        if let cutoff = effectiveDeletedAtCutoff() {
            cachedMessages = cachedMessages.filter { $0.timestamp > cutoff }
        }

        guard !cachedMessages.isEmpty else { return }

        for message in cachedMessages where message.senderId == currentUserId {
            switch message.status {
            case .sending, .pending, .failed:
                outgoingTempMessages[message.id] = message
            default:
                break
            }
        }

        historicalMessages = cachedMessages
        rebuildMessagesList()
        syncLiveReactionOverlays(from: messages)
        prefetchUnresolvedMediaIfNeeded()
        if let momentsViewModel = self as? MomentsChatViewModel {
            momentsViewModel.syncMessagePresentation()
        }
    }

    func attachChatListenersIfNeeded() {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            self.error = "ID de conversación no válido"
            return
        }
        guard !sessionListenersAttached else { return }
        sessionListenersAttached = true

        cancellables.removeAll()
        typingUsersCancellable?.cancel()
        typingUsersCancellable = nil

        let cutoff = effectiveDeletedAtCutoff()
        chatService.listenToMessages(
            conversationId: conversationId,
            cutoffDate: cutoff,
            replaceExisting: false
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }

                switch result {
                case .success(let messages):
                    let newSet = Set(messages.map { $0.id })
                    let droppedMessages = self.realTimeMessages.filter { !newSet.contains($0.id) }

                    if !droppedMessages.isEmpty {
                        // No promover al histórico mensajes anteriores al punto de corte del borrado
                        let promotable = self.messagesRespectingDeletionCutoff(droppedMessages)
                        self.historicalMessages.append(contentsOf: promotable)
                    }

                    self.realTimeMessages = messages
                    self.rebuildMessagesList()
                    self.prefetchUnresolvedMediaIfNeeded()

                    LocalPersistenceService.shared.reconcileMessages(messages, conversationId: conversationId)
                    self.isFirstFetch = false
                case .failure(let error):
                    self.error = error.localizedDescription
                }
            }
        }

        chatService.listenToMessageReactions(conversationId: conversationId, replaceExisting: false) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }

                switch result {
                case .success(let update):
                    self.applyReactionUpdate(update, conversationId: conversationId)
                case .failure(let error):
                    self.error = error.localizedDescription
                }
            }
        }

        chatService.listenToConversationForwardingPreferences(conversationId: conversationId, replaceExisting: false) { [weak self] forwarding, buzz in
            DispatchQueue.main.async {
                self?.forwardingPreferences = forwarding
                self?.buzzPreferences = buzz
            }
        }

        chatService.listenToBuzzEvents(
            conversationId: conversationId,
            cutoffDate: effectiveDeletedAtCutoff(),
            replaceExisting: false
        ) { [weak self] event, isInitialSnapshot in
            Task { @MainActor in
                guard let self else { return }
                guard self.seenBuzzEventIds.insert(event.id).inserted else { return }
                self.buzzEvents.append(event)
                self.buzzEvents.sort { $0.createdAt < $1.createdAt }
                if let momentsViewModel = self as? MomentsChatViewModel {
                    momentsViewModel.syncMessagePresentation()
                }
                if !isInitialSnapshot {
                    self.latestBuzzEvent = event
                }
            }
        }

        typingIndicatorEnabled = resolvedTypingIndicatorPreference(for: conversationId)
        applyTypingPreference(conversationId: conversationId)
    }

    func activateChatSession() {
        listenerPauseTask?.cancel()
        listenerPauseTask = nil
        chatSessionMode = .active
        isChatVisible = true
        loadCachedMessagesIfNeeded()
        attachChatListenersIfNeeded()

        if let conversationId = conversation.id {
            Task {
                await EncryptionService.shared.preloadConversationKeys(for: [conversationId])
            }
        }
    }

    func deactivateChatSession() {
        isChatVisible = false
        if chatSessionMode == .active {
            chatSessionMode = .warm
        }
        listenerPauseTask?.cancel()
        listenerPauseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.listenerPauseTTL)
            guard let self, !self.isChatVisible, self.chatSessionMode != .active else { return }
            self.pauseChatListenersImmediately()
        }
    }

    func warmChatSession() {
        guard chatSessionMode != .active else { return }
        chatSessionMode = .warm
        loadCachedMessagesIfNeeded()
        attachChatListenersIfNeeded()

        if let conversationId = conversation.id {
            Task {
                await EncryptionService.shared.preloadConversationKeys(for: [conversationId])
            }
        }
    }

    func pauseChatListenersImmediately() {
        listenerPauseTask?.cancel()
        listenerPauseTask = nil
        guard sessionListenersAttached else {
            chatSessionMode = .cold
            return
        }
        sessionListenersAttached = false
        chatSessionMode = .cold
        detachChatListeners()
    }

    private func detachChatListeners() {
        guard let conversationId = conversation.id, !conversationId.isEmpty else { return }
        chatService.removeListener(for: conversationId)
        chatService.stopTyping(conversationId: conversationId, userId: currentUserId)
        typingTimer?.invalidate()
        typingUsersCancellable?.cancel()
        typingUsersCancellable = nil
        typingUsers = []
        cancellables.removeAll()
    }

    func startListening() {
        activateChatSession()
    }
    func stopListening() {
        pauseChatListenersImmediately()
        isChatVisible = false
    }

    func sendBuzz(completion: @escaping (Result<Void, Error>) -> Void) {
        guard canSendBuzz else {
            completion(.failure(NSError(
                domain: "ChatBuzz",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("chat.buzz.blocked", comment: "Buzz blocked by recipient")]
            )))
            return
        }

        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            completion(.failure(NSError(
                domain: "ChatBuzz",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "ID de conversación no válido"]
            )))
            return
        }

        chatService.sendBuzz(
            conversationId: conversationId,
            senderId: currentUserId,
            completion: completion
        )
    }
    
    // ✅ NUEVA: Cleanup cuando se destruye el ViewModel
    deinit {
        if let messageStatusObserver {
            NotificationCenter.default.removeObserver(messageStatusObserver)
        }
        if let mediaUploadObserver {
            NotificationCenter.default.removeObserver(mediaUploadObserver)
        }
        typingUsersCancellable?.cancel()
    }
    
    // MARK: - Send Messages
    
    func sendTextMessage(_ text: String, replyTo: String? = nil) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            error = "No se puede enviar el mensaje: ID de conversación no válido"
            return
        }
        
        // ✅ Crear mensaje local inmediatamente para feedback visual
        let messageId = UUID().uuidString
        let tempMessage = EnhancedMessage(
            id: messageId,
            conversationId: conversationId,
            senderId: currentUserId,
            type: .text,
            content: text,
            status: .sending,
            replyTo: replyTo
        )
        
        // Agregar mensaje temporal a la lista local
        appendOutgoingMessage(tempMessage)
        
        chatService.sendTextMessage(
            conversationId: conversationId,
            senderId: currentUserId,
            content: text,
            replyTo: replyTo,
            messageId: messageId // ✅ Pasar el mismo ID
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let sentMessage):
                    // ✅ Usar el estado devuelto (puede ser .pending si es offline)
                    self?.updateMessageInArray(messageId: messageId, newStatus: sentMessage.status)
                    self?.trackSuccessfulDirectMessage()
                case .failure(let error):
                    self?.error = error.localizedDescription
                    // Actualizar estado del mensaje temporal a fallido
                    self?.updateMessageInArray(messageId: messageId, newStatus: .failed)
                }
            }
        }
    }
    
    func sendImageMessage(_ image: UIImage) {
        sendImageMessage(image, mediaBatchId: nil)
    }

    func sendImageMessage(_ image: UIImage, mediaBatchId: String?) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            error = "No se puede enviar la imagen: ID de conversación no válido"
            return
        }
        
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            error = "No se puede enviar la imagen"
            return
        }
        
        let messageId = UUID().uuidString
        let localPreview = localOutgoingPreviewURL(data: imageData, fileExtension: "jpg")
        // Reservar dimensiones desde el origen: la burbuja calcula su altura sin esperar a descargar
        // la imagen, evitando el reflujo/padding al renderizar.
        let pixelWidth = Int(image.size.width * image.scale)
        let pixelHeight = Int(image.size.height * image.scale)
        let tempMessage = EnhancedMessage(
            id: messageId,
            conversationId: conversationId,
            senderId: currentUserId,
            type: .image,
            mediaUrl: localPreview,
            mediaWidth: pixelWidth > 0 ? pixelWidth : nil,
            mediaHeight: pixelHeight > 0 ? pixelHeight : nil,
            status: .sending,
            mediaBatchId: mediaBatchId
        )
        
        // Agregar mensaje temporal a la lista local
        appendOutgoingMessage(tempMessage)
        
        chatService.sendMediaMessage(
            conversationId: conversationId,
            senderId: currentUserId,
            type: .image,
            mediaData: imageData,
            messageId: messageId, // ✅ Pasar el mismo ID
            mediaBatchId: mediaBatchId
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let sentMessage):
                    self?.applyOutgoingMessageUpdate(
                        messageId: messageId,
                        status: sentMessage.status,
                        mediaUrl: sentMessage.mediaUrl ?? localPreview,
                        thumbnailUrl: sentMessage.thumbnailUrl
                    )
                    self?.trackSuccessfulDirectMessage()
                case .failure(let error):
                    self?.error = error.localizedDescription
                    self?.updateMessageInArray(messageId: messageId, newStatus: .failed)
                }
            }
        }
    }
    
    func handlePhotoPickerItem(_ item: PhotosPickerItem, mediaBatchId: String? = nil) {
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                if let image = UIImage(data: data) {
                    await MainActor.run {
                        sendImageMessage(image, mediaBatchId: mediaBatchId)
                    }
                } else {
                    await MainActor.run {
                        sendVideoMessage(data: data, mediaBatchId: mediaBatchId)
                    }
                }
            } else {
                await MainActor.run {
                    self.error = "Error al cargar la imagen o video"
                }
            }
        }
    }

    func handlePhotoPickerItems(_ items: [PhotosPickerItem]) {
        let mediaBatchId = items.count > 1 ? UUID().uuidString : nil
        for item in items {
            handlePhotoPickerItem(item, mediaBatchId: mediaBatchId)
        }
    }

    func sendSelectedPHAssets(_ assets: [PHAsset], completion: (() -> Void)? = nil) {
        let mediaBatchId = assets.count > 1 ? UUID().uuidString : nil
        Task {
            for asset in assets {
                await sendPHAsset(asset, mediaBatchId: mediaBatchId)
            }
            await MainActor.run {
                completion?()
            }
        }
    }

    private func sendPHAsset(_ asset: PHAsset, mediaBatchId: String?) async {
        switch asset.mediaType {
        case .image:
            if let image = await loadFullImage(from: asset) {
                sendImageMessage(image, mediaBatchId: mediaBatchId)
            }
        case .video:
            if let data = await loadVideoData(from: asset) {
                sendVideoMessage(data: data, mediaBatchId: mediaBatchId)
            }
        default:
            break
        }
    }

    private func loadFullImage(from asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                if let isDegraded = info?[PHImageResultIsDegradedKey] as? Bool, isDegraded {
                    return
                }
                continuation.resume(returning: image)
            }
        }
    }

    private func loadVideoData(from asset: PHAsset) async -> Data? {
        await withCheckedContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            options.version = .current

            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, info in
                if let isDegraded = info?[PHImageResultIsDegradedKey] as? Bool, isDegraded {
                    return
                }

                guard let urlAsset = avAsset as? AVURLAsset else {
                    continuation.resume(returning: nil)
                    return
                }

                do {
                    let data = try Data(contentsOf: urlAsset.url)
                    continuation.resume(returning: data)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    func sendVideoMessage(data: Data) {
        sendVideoMessage(data: data, mediaBatchId: nil)
    }

    func sendVideoMessage(data: Data, mediaBatchId: String?) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            error = "No se puede enviar el video: ID de conversación no válido"
            return
        }
        
        
        let messageId = UUID().uuidString
        let localPreview = localOutgoingPreviewURL(data: data, fileExtension: "mp4")
        let tempMessage = EnhancedMessage(
            id: messageId,
            conversationId: conversationId,
            senderId: currentUserId,
            type: .video,
            mediaUrl: localPreview,
            status: .sending,
            mediaBatchId: mediaBatchId
        )
        
        // Agregar mensaje temporal a la lista local
        appendOutgoingMessage(tempMessage)
        
        chatService.sendMediaMessage(
            conversationId: conversationId,
            senderId: currentUserId,
            type: .video,
            mediaData: data,
            messageId: messageId, // ✅ Pasar el mismo ID
            mediaBatchId: mediaBatchId
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let sentMessage):
                    self?.applyOutgoingMessageUpdate(
                        messageId: messageId,
                        status: sentMessage.status,
                        mediaUrl: sentMessage.mediaUrl ?? localPreview,
                        thumbnailUrl: sentMessage.thumbnailUrl
                    )
                    self?.trackSuccessfulDirectMessage()
                case .failure(let error):
                    self?.error = error.localizedDescription
                    self?.updateMessageInArray(messageId: messageId, newStatus: .failed)
                }
            }
        }
    }
    
    func sendLocationMessage(latitude: Double, longitude: Double) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            error = "No se puede enviar la ubicación: ID de conversación no válido"
            return
        }
        
        
        // ✅ Crear mensaje local inmediatamente para feedback visual
        let messageId = UUID().uuidString
        let tempMessage = EnhancedMessage(
            id: messageId,
            conversationId: conversationId,
            senderId: currentUserId,
            type: .location,
            latitude: latitude,
            longitude: longitude,
            status: .sending
        )
        
        // Agregar mensaje temporal a la lista local
        appendOutgoingMessage(tempMessage)
        
        chatService.sendLocationMessage(
            conversationId: conversationId,
            senderId: currentUserId,
            latitude: latitude,
            longitude: longitude,
            messageId: messageId // ✅ Pasar el mismo ID
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let sentMessage):
                    // ✅ Usar el estado devuelto (puede ser .pending si es offline)
                    self?.updateMessageInArray(messageId: messageId, newStatus: sentMessage.status)
                    self?.trackSuccessfulDirectMessage()
                case .failure(let error):
                    self?.error = error.localizedDescription
                    // Actualizar estado del mensaje temporal a fallido
                    self?.updateMessageInArray(messageId: messageId, newStatus: .failed)
                }
            }
        }
    }
    
    // MARK: - Audio Messages
    
    func sendAudioMessage(audioData: Data, duration: Double) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            error = "No se puede enviar el audio: ID de conversación no válido"
            return
        }
        
        
        // ✅ Crear mensaje local inmediatamente para feedback visual
        let messageId = UUID().uuidString
        let localPreview = localOutgoingPreviewURL(data: audioData, fileExtension: "m4a")
        let tempMessage = EnhancedMessage(
            id: messageId,
            conversationId: conversationId,
            senderId: currentUserId,
            type: .audio,
            mediaUrl: localPreview,
            duration: duration,
            status: .sending
        )
        
        // Agregar mensaje temporal a la lista local
        appendOutgoingMessage(tempMessage)
        
        chatService.sendAudioMessage(
            conversationId: conversationId,
            senderId: currentUserId,
            audioData: audioData,
            duration: duration,
            messageId: messageId // ✅ Pasar el mismo ID
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let sentMessage):
                    self?.applyOutgoingMessageUpdate(
                        messageId: messageId,
                        status: sentMessage.status,
                        mediaUrl: sentMessage.mediaUrl ?? localPreview,
                        thumbnailUrl: sentMessage.thumbnailUrl
                    )
                    self?.trackSuccessfulDirectMessage()
                case .failure(let error):
                    self?.error = error.localizedDescription
                    self?.updateMessageInArray(messageId: messageId, newStatus: .failed)
                }
            }
        }
    }
    
    private func trackSuccessfulDirectMessage() {
        let targetUserId = conversation.otherParticipantId
        guard !targetUserId.isEmpty else { return }
        Task { @MainActor in
            AffinityTracker.shared.trackInteraction(type: .directMessage, with: targetUserId)
        }
    }
    
    // MARK: - Message Actions
    
    func deleteMessageForEveryone(_ message: EnhancedMessage) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            return
        }
        
        chatService.deleteMessage(
            conversationId: conversationId,
            messageId: message.id
        ) { [weak self] error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.error = error.localizedDescription
                }
            }
        }
    }
    
    func deleteMessageForMe(_ message: EnhancedMessage) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            return
        }
        
        chatService.deleteMessageForMe(
            conversationId: conversationId,
            messageId: message.id,
            userId: currentUserId
        ) { [weak self] error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.error = error.localizedDescription
                }
            } else {
                // Locally remove the message immediately for better UX
                DispatchQueue.main.async {
                    self?.messages.removeAll { $0.id == message.id }
                    if let momentsVM = self as? MomentsChatViewModel {
                        momentsVM.syncMessagePresentation()
                    }
                    self?.objectWillChange.send()
                }
            }
        }
    }
    
    func editMessage(_ message: EnhancedMessage, newContent: String) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            return
        }
        guard ChatMessagePolicy.canEdit(message, userId: currentUserId) else {
            error = NSLocalizedString("chat.error.editWindowExpired", comment: "")
            return
        }
        
        chatService.editMessage(
            conversationId: conversationId,
            messageId: message.id,
            newContent: newContent
        ) { [weak self] error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.error = error.localizedDescription
                }
            }
        }
    }
    
    func addReaction(to message: EnhancedMessage, emoji: String) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            return
        }

        EmojiUsageStore.increment(emoji, userId: currentUserId)

        let updated = MessageReactionMutation.apply(
            to: message.reactions,
            emoji: emoji,
            userId: currentUserId
        )
        setLiveReactions(updated, for: message.id)
        
        chatService.addReaction(
            conversationId: conversationId,
            messageId: message.id,
            emoji: emoji,
            userId: currentUserId
        ) { [weak self] error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.error = error.localizedDescription
                }
            }
        }
    }

    func forwardTextMessage(_ message: EnhancedMessage, toUserIds: Set<String>) {
        guard let sourceConversationId = conversation.id, !sourceConversationId.isEmpty else { return }
        guard ChatMessagePolicy.canForward(
            message,
            currentUserId: currentUserId,
            forwardingPreferences: forwardingPreferences
        ), let rawContent = message.content else { return }

        Task {
            let plaintext = await chatService.decryptMessageContent(rawContent, for: sourceConversationId)
            chatService.forwardTextMessage(
                plaintext: plaintext,
                toUserIds: toUserIds,
                senderId: currentUserId
            ) { [weak self] result in
                DispatchQueue.main.async {
                    if case .failure(let error) = result {
                        self?.error = error.localizedDescription
                    }
                }
            }
        }
    }

    func toggleStar(for message: EnhancedMessage) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else { return }
        let isStarred = message.isStarred(by: currentUserId)
        let newStarred = !isStarred

        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            var starredBy = messages[index].starredBy ?? []
            if newStarred {
                if !starredBy.contains(currentUserId) { starredBy.append(currentUserId) }
            } else {
                starredBy.removeAll { $0 == currentUserId }
            }
            messages[index].starredBy = starredBy.isEmpty ? nil : starredBy
        }

        chatService.toggleMessageStar(
            conversationId: conversationId,
            messageId: message.id,
            userId: currentUserId,
            isStarred: newStarred
        ) { [weak self] error in
            if let error {
                DispatchQueue.main.async {
                    self?.error = error.localizedDescription
                }
            }
        }
    }
    
    // MARK: - Read Status

    func markVisibleConversationAsRead() {
        guard isChatVisible else { return }
        applyOptimisticReadLocally()
        markUnreadMessagesAsRead(messages)
    }

    private func applyOptimisticReadLocally() {
        var didChange = false
        for index in realTimeMessages.indices {
            guard realTimeMessages[index].senderId != currentUserId,
                  !realTimeMessages[index].isRead else { continue }
            realTimeMessages[index].isRead = true
            didChange = true
        }
        guard didChange else { return }
        rebuildMessagesList()
    }
    
    private func markUnreadMessagesAsRead(_ messages: [EnhancedMessage]) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            return
        }
        
        let unreadMessages = messages.filter {
            !$0.isRead && $0.senderId != currentUserId
        }
        
        if unreadMessages.isEmpty {
            // Si no hay mensajes individuales sin leer, de todos modos marcamos el documento de la conversación como leído (útil si se marcó como no leído manualmente).
            chatService.markConversationAsRead(conversationId: conversationId, userId: currentUserId)
        } else {
            let messageIds = unreadMessages.map { $0.id }
            chatService.markMessagesAsRead(
                conversationId: conversationId,
                messageIds: messageIds,
                readerId: currentUserId
            ) { error in
                if error != nil {
                    // Error marking messages as read
                }
            }
        }
    }
    
    // MARK: - Typing Indicator
    
    private func handleTypingIndicator() {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            return
        }
        
        guard typingIndicatorEnabled else {
            chatService.stopTyping(conversationId: conversationId, userId: currentUserId)
            return
        }
        
        typingTimer?.invalidate()
        
        if isTyping {
            chatService.startTyping(conversationId: conversationId, userId: currentUserId)
            
            typingTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.isTyping = false
                }
            }
        } else {
            chatService.stopTyping(conversationId: conversationId, userId: currentUserId)
        }
    }
    
    // MARK: - Search
    
    func searchMessages(query: String) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            return
        }
        
        chatService.searchMessages(conversationId: conversationId, query: query) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    // Messages found successfully
                    break
                case .failure(let error):
                    self?.error = error.localizedDescription
                }
            }
        }
    }
    
    // MARK: - Ephemeral Messages
    
    func sendEphemeralMessage(content: String?, mediaUrl: String?, duration: Int = 24) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            error = "No se puede enviar mensaje efímero: ID de conversación no válido"
            return
        }
        
        chatService.sendEphemeralMessage(
            conversationId: conversationId,
            senderId: currentUserId,
            content: content,
            mediaUrl: mediaUrl,
            expirationHours: duration
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    // Ephemeral message sent successfully
                    break
                case .failure(let error):
                    self?.error = error.localizedDescription
                }
            }
        }
    }
    
    func markEphemeralAsViewed(_ message: EnhancedMessage) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            return
        }
        
        chatService.markEphemeralAsViewed(
            conversationId: conversationId,
            messageId: message.id
        ) { error in
            if error != nil {
                // Error marking ephemeral as viewed
            }
        }
    }
}
