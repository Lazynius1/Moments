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
            if !mergedMessages.contains(where: { $0.id == tempMessage.id }) {
                mergedMessages.append(tempMessage)
            } else {
                // Si el mensaje ya existe en Firestore, preservar el estado temporal si es más reciente
                if let existingIndex = mergedMessages.firstIndex(where: { $0.id == tempMessage.id }) {
                    let existingMessage = mergedMessages[existingIndex]
                    if existingMessage.status == .sent && tempMessage.status == .sending {
                        mergedMessages[existingIndex].status = .sending
                    }
                }
            }
        }
        
        // ✅ Aplicar estados locales con prioridad
        for (messageId, localStatus) in localMessageStates {
            if let index = mergedMessages.firstIndex(where: { $0.id == messageId }) {
                mergedMessages[index].status = localStatus
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
                    // ✅ Preservar mensajes temporales al actualizar la lista
                    let mergedMessages = self.preserveTemporaryMessages(messages)
                    self.messages = mergedMessages
                    self.markUnreadMessagesAsRead(messages)
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
