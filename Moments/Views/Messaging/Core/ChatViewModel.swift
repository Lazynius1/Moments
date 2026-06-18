import Foundation
import FirebaseAuth
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
    
    // ✅ NUEVO: Flag para bloquear listener temporalmente
    private var isUpdatingLocalMessage = false
    
    // ✅ NUEVO: Flag para saber si el chat está visible (para marcar como leído solo cuando está visible)
    var isChatVisible = false
    
    // ✅ PAGINACIÓN
    @Published var isLoadingMore = false
    @Published var canLoadMore = true
    @Published private(set) var forwardingPreferences: [String: Bool] = [:]
    private var historicalMessages: [EnhancedMessage] = []
    private var realTimeMessages: [EnhancedMessage] = []
    
    let conversation: Conversation
    let currentUserId: String
    private let chatService = ChatService.shared
    private let firestoreService = FirestoreService()
    private var cancellables = Set<AnyCancellable>()
    private var typingUsersCancellable: AnyCancellable?
    private var typingTimer: Timer?
    private var messageStatusObserver: NSObjectProtocol?
    private var mediaUploadObserver: NSObjectProtocol?
    
    // ✅ NUEVO: Flag para detectar la primera carga de Firestore y limpiar el caché local (sync: true)
    private var isFirstFetch = true
    
    init(conversation: Conversation) {
        self.conversation = conversation
        self.currentUserId = Auth.auth().currentUser?.uid ?? ""
        self.forwardingPreferences = conversation.forwardingPreferences ?? [:]
        
        // ✅ Configurar listener para actualizaciones de estado locales
        setupLocalStatusListener()
        setupForwardingPreferenceListener()
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

    private func setupForwardingPreferenceListener() {
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
    }

    private func messageNeedsMediaHydration(_ message: EnhancedMessage) -> Bool {
        message.isMediaPendingResolution
    }

    func hydrateMediaIfNeeded(for message: EnhancedMessage) {
        guard messageNeedsMediaHydration(message) else { return }
        guard !hydratingMediaIds.contains(message.id) else { return }
        hydratingMediaIds.insert(message.id)
        prepareMediaForViewing(message) { [weak self] _ in
            self?.hydratingMediaIds.remove(message.id)
        }
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
        if message.mediaUrl != nil {
            completion(message)
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
                    messages[index].thumbnailUrl = thumbnailUrl
                }
                messages = Array(messages)
                objectWillChange.send()
                if let momentsViewModel = self as? MomentsChatViewModel {
                    momentsViewModel.syncMessagePresentation()
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
        let allMessages = realTimeMessages + historicalMessages
        
        // 2. Deduplicar por ID (se queda con el primero que encuentre, que ahora es el real-time)
        var seenIds = Set<String>()
        let uniqueMessages = allMessages.filter { seenIds.insert($0.id).inserted }
        
        // 3. Ordenar
        let sortedMessages = uniqueMessages.sorted { $0.timestamp < $1.timestamp }
        
        // 4. Preservar temporales y estados locales
        let finalMessages = preserveTemporaryMessages(sortedMessages)
        commitMessagesPresentation(finalMessages)

        for id in Array(outgoingTempMessages.keys) {
            if let msg = finalMessages.first(where: { $0.id == id }), msg.status != .sending {
                outgoingTempMessages.removeValue(forKey: id)
            }
        }
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

    private func applyReactionUpdate(_ update: MessageReactionUpdate, conversationId: String) {
        let affectedIds = update.changedMessageIds.union(update.reactionsByMessage.keys)
        guard !affectedIds.isEmpty else { return }

        for messageId in affectedIds {
            let liveReactions = update.reactionsByMessage[messageId]
            mutateReactionState(for: messageId) { message in
                message.reactions = liveReactions
            }
        }

        rebuildMessagesList()
        LocalPersistenceService.shared.saveMessages(messages, conversationId: conversationId)
    }
    
    // ✅ FUNCIÓN: Cargar más mensajes (Pull to refresh)
    func loadMoreMessages() {
        guard !isLoadingMore, canLoadMore, let firstMessage = messages.first, let conversationId = conversation.id else { return }
        
        isLoadingMore = true
        
        chatService.fetchOlderMessages(conversationId: conversationId, before: firstMessage.timestamp) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoadingMore = false
                
                switch result {
                case .success(let olderMessages):
                    if olderMessages.isEmpty {
                        self.canLoadMore = false
                    } else {
                        // Agregar al historial
                        self.historicalMessages.append(contentsOf: olderMessages)
                        self.rebuildMessagesList()
                    }
                case .failure(let error):
                    print("Error loading more messages: \(error)")
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
    
    func startListening() {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            self.error = "ID de conversación no válido"
            return
        }
        
        // Reiniciar suscripciones reactivas para evitar duplicados al re-entrar al chat
        cancellables.removeAll()
        typingUsersCancellable?.cancel()
        typingUsersCancellable = nil
        
        // ✅ SwiftData: carga síncrona en MainActor para que el primer frame ya tenga historial y scroll al fondo.
        let cachedMessages = LocalPersistenceService.shared.loadMessages(conversationId: conversationId)
        if !cachedMessages.isEmpty {
            historicalMessages = cachedMessages
            rebuildMessagesList()
            prefetchUnresolvedMediaIfNeeded()
        }
        
        // Re-registrar siempre el listener de mensajes para que el callback pertenezca
        // al ViewModel activo de este chat.
        chatService.listenToMessages(conversationId: conversationId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                switch result {
                case .success(let messages):
                    
                    // ✅ DETECTAR mensajes que caen fuera de la ventana de 50 (sliding window)
                    // y moverlos al histórico para no perderlos
                    let newSet = Set(messages.map { $0.id })
                    let droppedMessages = self.realTimeMessages.filter { !newSet.contains($0.id) }
                    
                    if !droppedMessages.isEmpty {
                        self.historicalMessages.append(contentsOf: droppedMessages)
                    }
                    
                    // ✅ Actualizar solo la parte de tiempo real
                    self.realTimeMessages = messages
                    self.rebuildMessagesList()
                    self.prefetchUnresolvedMediaIfNeeded()
                    
                    // ✅ SwiftData: Persistir historial actualizado
                    LocalPersistenceService.shared.saveMessages(messages, conversationId: conversationId, sync: self.isFirstFetch)
                    self.isFirstFetch = false
                    
                    // ✅ SOLO marcar como leído si el chat está VISIBLE al usuario
                    if self.isChatVisible {
                        self.markUnreadMessagesAsRead(messages)
                    }
                case .failure(let error):
                    self.error = error.localizedDescription
                }
            }
        }

        chatService.listenToMessageReactions(conversationId: conversationId) { [weak self] result in
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
        typingIndicatorEnabled = resolvedTypingIndicatorPreference(for: conversationId)
        applyTypingPreference(conversationId: conversationId)
    }
    
    func stopListening() {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            return
        }
        chatService.removeListener(for: conversationId)
        chatService.stopTyping(conversationId: conversationId, userId: currentUserId)
        typingTimer?.invalidate()
        typingUsersCancellable?.cancel()
        typingUsersCancellable = nil
        typingUsers = []
        cancellables.removeAll()
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
        let tempMessage = EnhancedMessage(
            id: messageId,
            conversationId: conversationId,
            senderId: currentUserId,
            type: .image,
            mediaUrl: localPreview,
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

        mutateReactionState(for: message.id) { currentMessage in
            currentMessage.reactions = MessageReactionMutation.apply(
                to: currentMessage.reactions,
                emoji: emoji,
                userId: currentUserId
            )
        }
        rebuildMessagesList()
        
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
