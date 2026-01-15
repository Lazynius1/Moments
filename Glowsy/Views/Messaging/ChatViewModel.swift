import Foundation
import FirebaseAuth
import Combine
import PhotosUI
import SwiftUI
import UIKit

class EnhancedChatViewModel: ObservableObject {
    @Published var messages: [EnhancedMessage] = []
    @Published var typingUsers: Set<String> = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var isTyping = false {
        didSet {
            handleTypingIndicator()
        }
    }
    
    // ✅ NUEVO: Diccionario para estados locales con prioridad
    private var localMessageStates: [String: MessageStatus] = [:]
    
    // ✅ NUEVO: Flag para bloquear listener temporalmente
    private var isUpdatingLocalMessage = false
    
    // ✅ NUEVO: Flag para saber si el chat está visible (para marcar como leído solo cuando está visible)
    var isChatVisible = false
    
    // ✅ PAGINACIÓN
    @Published var isLoadingMore = false
    @Published var canLoadMore = true
    private var historicalMessages: [EnhancedMessage] = []
    private var realTimeMessages: [EnhancedMessage] = []
    
    let conversation: Conversation
    let currentUserId: String
    private let chatService = ChatService()
    private let firestoreService = FirestoreService()
    private var cancellables = Set<AnyCancellable>()
    private var typingTimer: Timer?
    
    init(conversation: Conversation) {
        self.conversation = conversation
        self.currentUserId = Auth.auth().currentUser?.uid ?? ""
        
        // ✅ Configurar listener para actualizaciones de estado locales
        setupLocalStatusListener()
    }
    
    // ✅ NUEVA: Configurar listener para actualizaciones de estado locales
    private func setupLocalStatusListener() {
        NotificationCenter.default.addObserver(
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
            self?.updateMessageInArray(messageId: messageId, newStatus: status)
        }
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
        
        return mergedMessages.sorted { $0.timestamp < $1.timestamp }
    }
    
    // ✅ NUEVA: Función para actualizar el array de manera que SwiftUI lo detecte
    private func updateMessageInArray(messageId: String, newStatus: MessageStatus) {
        // ✅ Bloquear listener temporalmente
        isUpdatingLocalMessage = true
        
        // ✅ Guardar estado local con prioridad
        localMessageStates[messageId] = newStatus
        
        if let index = messages.firstIndex(where: { $0.id == messageId }) {
            // ✅ FORZAR actualización de SwiftUI
            DispatchQueue.main.async {
                // Crear una copia completamente nueva del array
                var updatedMessages = Array(self.messages)
                updatedMessages[index].status = newStatus
                
                // Reemplazar el array completo
                self.messages = updatedMessages
                
                // ✅ FORZAR actualización de SwiftUI
                self.objectWillChange.send()
                
                // ✅ FORZAR actualización de groupedMessages si es InstagramChatViewModel
                if let instagramViewModel = self as? InstagramChatViewModel {
                    instagramViewModel.updateGroupedMessages()
                }
                
                // ✅ Desbloquear listener después de un delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.isUpdatingLocalMessage = false
                }
            }
        } else {
            // ✅ Desbloquear listener si no se encontró el mensaje
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.isUpdatingLocalMessage = false
            }
        }
    }
    
    // ✅ NUEVA: Función para limpiar estados locales después de un tiempo
    private func cleanupLocalStates() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
            self.localMessageStates.removeAll()
        }
    }
    
    // ✅ HELPER: Reconstruir lista completa de mensajes
    private func rebuildMessagesList() {
        // 1. Unir históricos + tiempo real
        let allMessages = historicalMessages + realTimeMessages
        
        // 2. Deduplicar por ID
        var seenIds = Set<String>()
        let uniqueMessages = allMessages.filter { seenIds.insert($0.id).inserted }
        
        // 3. Ordenar
        let sortedMessages = uniqueMessages.sorted { $0.timestamp < $1.timestamp }
        
        // 4. Preservar temporales y estados locales
        let finalMessages = preserveTemporaryMessages(sortedMessages)
        
        self.messages = finalMessages
        
        // ✅ Forzar actualización de groupedMessages
        if let instagramViewModel = self as? InstagramChatViewModel {
            instagramViewModel.updateGroupedMessages()
        }
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
        // ✅ Bloquear listener temporalmente
        isUpdatingLocalMessage = true
        
        // ✅ Limpiar estado local ya que el mensaje se ha enviado
        localMessageStates.removeValue(forKey: messageId)
        
        if let index = messages.firstIndex(where: { $0.id == messageId }) {
            
            // Crear una copia del array para forzar la actualización
            var updatedMessages = messages
            updatedMessages[index] = sentMessage
            
            // Actualizar el array completo
            DispatchQueue.main.async {
                self.messages = updatedMessages
                
                // ✅ Programar limpieza de estados locales
                self.cleanupLocalStates()
                
                // ✅ Desbloquear listener después de un delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    self.isUpdatingLocalMessage = false
                }
            }
        } else {
            // Agregar el mensaje enviado si no se encuentra el temporal
            DispatchQueue.main.async {
                self.messages.append(sentMessage)
                
                // ✅ Programar limpieza de estados locales
                self.cleanupLocalStates()
                
                // ✅ Desbloquear listener después de un delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.isUpdatingLocalMessage = false
                }
            }
        }
    }
    
    // MARK: - Lifecycle
    
    func startListening() {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            self.error = "ID de conversación no válido"
            return
        }
        
        
        // ✅ SOLO LLAMAR UNA VEZ
        if chatService.activeListeners[conversationId] == nil {
                    chatService.listenToMessages(conversationId: conversationId) { [weak self] result in
            DispatchQueue.main.async {
                // ✅ NO actualizar si estamos modificando mensajes locales
                guard let self = self, !self.isUpdatingLocalMessage else {
                    return
                }
                
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
                    
                    // ✅ SOLO marcar como leído si el chat está VISIBLE al usuario
                    if self.isChatVisible {
                        self.markUnreadMessagesAsRead(messages)
                    }
                case .failure(let error):
                    self.error = error.localizedDescription
                }
            }
        }
        }
        
        chatService.listenToTypingIndicators(conversationId: conversationId)
        
        chatService.$typingUsers
            .compactMap { $0[conversationId] }
            .sink { typingUsers in
                let filteredUsers = typingUsers.filter { $0 != self.currentUserId }
                self.typingUsers = filteredUsers
            }
            .store(in: &cancellables)
    }
    
    func stopListening() {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            return
        }
        chatService.removeListener(for: conversationId)
        chatService.stopTyping(conversationId: conversationId, userId: currentUserId)
        
        // ✅ Limpiar listener local
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name("MessageStatusUpdated"), object: nil)
    }
    
    // ✅ NUEVA: Cleanup cuando se destruye el ViewModel
    deinit {
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name("MessageStatusUpdated"), object: nil)
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
        DispatchQueue.main.async {
            self.messages.append(tempMessage)
            
            // ✅ FORZAR actualización de SwiftUI
            self.objectWillChange.send()
            
            // ✅ FORZAR actualización de groupedMessages si es InstagramChatViewModel
            if let instagramViewModel = self as? InstagramChatViewModel {
                instagramViewModel.updateGroupedMessages()
            }
        }
        
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
                    // ✅ SOLO cambiar el estado, no reemplazar
                    self?.updateMessageInArray(messageId: messageId, newStatus: .sent)
                case .failure(let error):
                    self?.error = error.localizedDescription
                    // Actualizar estado del mensaje temporal a fallido
                    self?.updateMessageInArray(messageId: messageId, newStatus: .failed)
                }
            }
        }
    }
    
    func sendImageMessage(_ image: UIImage) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            error = "No se puede enviar la imagen: ID de conversación no válido"
            return
        }
        
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            error = "No se puede enviar la imagen"
            return
        }
        
        // ✅ Crear mensaje local inmediatamente para feedback visual
        let messageId = UUID().uuidString
        let tempMessage = EnhancedMessage(
            id: messageId,
            conversationId: conversationId,
            senderId: currentUserId,
            type: .image,
            status: .sending
        )
        
        // Agregar mensaje temporal a la lista local
        DispatchQueue.main.async {
            self.messages.append(tempMessage)
            
            // ✅ FORZAR actualización de SwiftUI
            self.objectWillChange.send()
            
            // ✅ FORZAR actualización de groupedMessages si es InstagramChatViewModel
            if let instagramViewModel = self as? InstagramChatViewModel {
                instagramViewModel.updateGroupedMessages()
            }
        }
        
        chatService.sendMediaMessage(
            conversationId: conversationId,
            senderId: currentUserId,
            type: .image,
            mediaData: imageData,
            messageId: messageId // ✅ Pasar el mismo ID
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let sentMessage):
                    // ✅ SOLO cambiar el estado, no reemplazar
                    self?.updateMessageInArray(messageId: messageId, newStatus: .sent)
                case .failure(let error):
                    self?.error = error.localizedDescription
                    // Actualizar estado del mensaje temporal a fallido
                    self?.updateMessageInArray(messageId: messageId, newStatus: .failed)
                }
            }
        }
    }
    
    func handlePhotoPickerItem(_ item: PhotosPickerItem) {
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                if let image = UIImage(data: data) {
                    await MainActor.run {
                        sendImageMessage(image)
                    }
                } else {
                    await MainActor.run {
                        sendVideoMessage(data: data)
                    }
                }
            } else {
                await MainActor.run {
                    self.error = "Error al cargar la imagen o video"
                }
            }
        }
    }
    
     func sendVideoMessage(data: Data) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            error = "No se puede enviar el video: ID de conversación no válido"
            return
        }
        
        
        // ✅ Crear mensaje local inmediatamente para feedback visual
        let messageId = UUID().uuidString
        let tempMessage = EnhancedMessage(
            id: messageId,
            conversationId: conversationId,
            senderId: currentUserId,
            type: .video,
            status: .sending
        )
        
        // Agregar mensaje temporal a la lista local
        DispatchQueue.main.async {
            self.messages.append(tempMessage)
        }
        
        chatService.sendMediaMessage(
            conversationId: conversationId,
            senderId: currentUserId,
            type: .video,
            mediaData: data,
            messageId: messageId // ✅ Pasar el mismo ID
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let sentMessage):
                    // ✅ SOLO cambiar el estado, no reemplazar
                    self?.updateMessageInArray(messageId: messageId, newStatus: .sent)
                case .failure(let error):
                    self?.error = error.localizedDescription
                    // Actualizar estado del mensaje temporal a fallido
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
        DispatchQueue.main.async {
            self.messages.append(tempMessage)
        }
        
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
                    // ✅ SOLO cambiar el estado, no reemplazar
                    self?.updateMessageInArray(messageId: messageId, newStatus: .sent)
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
        let tempMessage = EnhancedMessage(
            id: messageId,
            conversationId: conversationId,
            senderId: currentUserId,
            type: .audio,
            duration: duration,
            status: .sending
        )
        
        // Agregar mensaje temporal a la lista local
        DispatchQueue.main.async {
            self.messages.append(tempMessage)
        }
        
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
                    // ✅ SOLO cambiar el estado, no reemplazar
                    self?.updateMessageInArray(messageId: messageId, newStatus: .sent)
                case .failure(let error):
                    self?.error = error.localizedDescription
                    // Actualizar estado del mensaje temporal a fallido
                    self?.updateMessageInArray(messageId: messageId, newStatus: .failed)
                }
            }
        }
    }
    
    // MARK: - Message Actions
    
    func deleteMessage(_ message: EnhancedMessage) {
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
    
    func editMessage(_ message: EnhancedMessage, newContent: String) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
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
    
    // MARK: - Read Status
    
    private func markUnreadMessagesAsRead(_ messages: [EnhancedMessage]) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            return
        }
        
        let unreadMessages = messages.filter {
            !$0.isRead && $0.senderId != currentUserId
        }
        
        guard !unreadMessages.isEmpty else { return }
        
        let messageIds = unreadMessages.map { $0.id }
        
        chatService.markMessagesAsRead(
            conversationId: conversationId,
            messageIds: messageIds,
            readerId: currentUserId
        ) { error in
            if let error = error {
                // Error marking messages as read
            }
        }
    }
    
    // MARK: - Typing Indicator
    
    private func handleTypingIndicator() {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            return
        }
        
        typingTimer?.invalidate()
        
        if isTyping {
            chatService.startTyping(conversationId: conversationId, userId: currentUserId)
            
            typingTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
                self?.isTyping = false
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
                case .success(let messages):
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
                case .success(_):
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
            if let error = error {
                // Error marking ephemeral as viewed
            }
        }
    }
}
