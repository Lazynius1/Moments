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
        print("Initialized EnhancedChatViewModel with conversation ID: \(conversation.id ?? "nil")")
        
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
            
            print("📊 Local status update received for message \(messageId): \(status.rawValue)")
            
            // ✅ Usar la nueva función para actualizar el array
            self?.updateMessageInArray(messageId: messageId, newStatus: status)
        }
    }
    
    // ✅ NUEVA: Función para preservar mensajes temporales
    private func preserveTemporaryMessages(_ newMessages: [EnhancedMessage]) -> [EnhancedMessage] {
        let temporaryMessages = self.messages.filter { $0.status == .sending }
        print("🔍 Preservando \(temporaryMessages.count) mensajes temporales")
        
        var mergedMessages = newMessages
        
        for tempMessage in temporaryMessages {
            if !mergedMessages.contains(where: { $0.id == tempMessage.id }) {
                print("✅ Agregando mensaje temporal preservado: \(tempMessage.id)")
                mergedMessages.append(tempMessage)
            } else {
                // Si el mensaje ya existe en Firestore, preservar el estado temporal si es más reciente
                if let existingIndex = mergedMessages.firstIndex(where: { $0.id == tempMessage.id }) {
                    let existingMessage = mergedMessages[existingIndex]
                    if existingMessage.status == .sent && tempMessage.status == .sending {
                        print("🔄 Preservando estado temporal para mensaje: \(tempMessage.id)")
                        mergedMessages[existingIndex].status = .sending
                    }
                }
            }
        }
        
        // ✅ Aplicar estados locales con prioridad
        for (messageId, localStatus) in localMessageStates {
            if let index = mergedMessages.firstIndex(where: { $0.id == messageId }) {
                print("🔄 Aplicando estado local \(localStatus.rawValue) a mensaje: \(messageId)")
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
            print("🧹 Limpiando estados locales antiguos")
            self.localMessageStates.removeAll()
        }
    }
    
    // ✅ NUEVA: Función para reemplazar mensaje temporal
    private func replaceTemporaryMessage(messageId: String, with sentMessage: EnhancedMessage) {
        // ✅ Bloquear listener temporalmente
        isUpdatingLocalMessage = true
        print("🔒 Bloqueando listener para reemplazo de mensaje")
        print("🔍 Buscando mensaje temporal con ID: \(messageId)")
        print("🔍 Mensaje enviado tiene ID: \(sentMessage.id)")
        print("🔍 Total de mensajes en la lista: \(messages.count)")
        print("🔍 Mensajes temporales: \(messages.filter { $0.status == .sending }.map { $0.id })")
        
        // ✅ Limpiar estado local ya que el mensaje se ha enviado
        localMessageStates.removeValue(forKey: messageId)
        print("🧹 Estado local limpiado para \(messageId)")
        
        if let index = messages.firstIndex(where: { $0.id == messageId }) {
            print("✅ Reemplazando mensaje temporal en índice: \(index)")
            print("🔍 Mensaje temporal: \(messages[index].id) - \(messages[index].status.rawValue)")
            print("🔍 Mensaje enviado: \(sentMessage.id) - \(sentMessage.status.rawValue)")
            
            // Crear una copia del array para forzar la actualización
            var updatedMessages = messages
            updatedMessages[index] = sentMessage
            
            // Actualizar el array completo
            DispatchQueue.main.async {
                self.messages = updatedMessages
                print("✅ Mensaje temporal reemplazado, SwiftUI debería detectar el cambio")
                print("🔍 Estado final del mensaje: \(self.messages[index].status.rawValue)")
                
                // ✅ Programar limpieza de estados locales
                self.cleanupLocalStates()
                
                // ✅ Desbloquear listener después de un delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    self.isUpdatingLocalMessage = false
                    print("🔓 Listener desbloqueado después de reemplazo")
                }
            }
        } else {
            print("❌ NO se encontró el mensaje temporal con ID: \(messageId)")
            print("🔍 IDs de mensajes en la lista: \(messages.map { $0.id })")
            // Agregar el mensaje enviado si no se encuentra el temporal
            DispatchQueue.main.async {
                self.messages.append(sentMessage)
                print("✅ Mensaje enviado agregado a la lista")
                
                // ✅ Programar limpieza de estados locales
                self.cleanupLocalStates()
                
                // ✅ Desbloquear listener después de un delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.isUpdatingLocalMessage = false
                    print("🔓 Listener desbloqueado después de agregar mensaje")
                }
            }
        }
    }
    
    // MARK: - Lifecycle
    
    func startListening() {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            print("Cannot start listening: No valid conversation ID")
            self.error = "ID de conversación no válido"
            return
        }
        
        print("Starting to listen for messages in conversation: \(conversationId)")
        
        // ✅ SOLO LLAMAR UNA VEZ
        if chatService.activeListeners[conversationId] == nil {
                    chatService.listenToMessages(conversationId: conversationId) { [weak self] result in
            DispatchQueue.main.async {
                // ✅ NO actualizar si estamos modificando mensajes locales
                guard let self = self, !self.isUpdatingLocalMessage else {
                    print("🛑 Listener bloqueado - actualización local en progreso")
                    return
                }
                
                switch result {
                case .success(let messages):
                    print("Received \(messages.count) messages")
                    // ✅ Preservar mensajes temporales al actualizar la lista
                    let mergedMessages = self.preserveTemporaryMessages(messages)
                    self.messages = mergedMessages
                    self.markUnreadMessagesAsRead(messages)
                case .failure(let error):
                    print("Error listening to messages: \(error.localizedDescription)")
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
            print("Cannot stop listening: No valid conversation ID")
            return
        }
        print("Stopping listeners for conversation: \(conversationId)")
        chatService.removeListener(for: conversationId)
        chatService.stopTyping(conversationId: conversationId, userId: currentUserId)
        
        // ✅ Limpiar listener local
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name("MessageStatusUpdated"), object: nil)
    }
    
    // ✅ NUEVA: Cleanup cuando se destruye el ViewModel
    deinit {
        print("🧹 EnhancedChatViewModel deinit - cleaning up listeners")
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name("MessageStatusUpdated"), object: nil)
    }
    
    // MARK: - Send Messages
    
    func sendTextMessage(_ text: String, replyTo: String? = nil) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            print("No valid conversation ID for sending message")
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
                    print("Error sending text message: \(error.localizedDescription)")
                    self?.error = error.localizedDescription
                    // Actualizar estado del mensaje temporal a fallido
                    self?.updateMessageInArray(messageId: messageId, newStatus: .failed)
                }
            }
        }
    }
    
    func sendImageMessage(_ image: UIImage) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            print("No valid conversation ID for sending image")
            error = "No se puede enviar la imagen: ID de conversación no válido"
            return
        }
        
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            print("Invalid image data")
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
                    print("Error sending image message: \(error.localizedDescription)")
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
                    print("Failed to load photo picker item")
                    self.error = "Error al cargar la imagen o video"
                }
            }
        }
    }
    
     func sendVideoMessage(data: Data) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            print("No valid conversation ID for sending video")
            error = "No se puede enviar el video: ID de conversación no válido"
            return
        }
        
        print("Sending video message in conversation \(conversationId)")
        
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
            print("✅ Mensaje temporal agregado: \(messageId) - \(tempMessage.status.rawValue)")
            print("🔍 Total mensajes después de agregar temporal: \(self.messages.count)")
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
                    print("Video message sent successfully")
                    // ✅ SOLO cambiar el estado, no reemplazar
                    self?.updateMessageInArray(messageId: messageId, newStatus: .sent)
                case .failure(let error):
                    print("Error sending video message: \(error.localizedDescription)")
                    self?.error = error.localizedDescription
                    // Actualizar estado del mensaje temporal a fallido
                    self?.updateMessageInArray(messageId: messageId, newStatus: .failed)
                }
            }
        }
    }
    
    func sendLocationMessage(latitude: Double, longitude: Double) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            print("No valid conversation ID for sending location")
            error = "No se puede enviar la ubicación: ID de conversación no válido"
            return
        }
        
        print("Sending location message in conversation \(conversationId)")
        
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
            print("✅ Mensaje temporal agregado: \(messageId) - \(tempMessage.status.rawValue)")
            print("🔍 Total mensajes después de agregar temporal: \(self.messages.count)")
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
                    print("Location message sent successfully")
                    // ✅ SOLO cambiar el estado, no reemplazar
                    self?.updateMessageInArray(messageId: messageId, newStatus: .sent)
                case .failure(let error):
                    print("Error sending location message: \(error.localizedDescription)")
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
            print("No valid conversation ID for sending audio")
            error = "No se puede enviar el audio: ID de conversación no válido"
            return
        }
        
        print("Sending audio message in conversation \(conversationId)")
        
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
            print("✅ Mensaje temporal agregado: \(messageId) - \(tempMessage.status.rawValue)")
            print("🔍 Total mensajes después de agregar temporal: \(self.messages.count)")
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
                    print("Audio message sent successfully")
                    // ✅ SOLO cambiar el estado, no reemplazar
                    self?.updateMessageInArray(messageId: messageId, newStatus: .sent)
                case .failure(let error):
                    print("Error sending audio message: \(error.localizedDescription)")
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
            print("No valid conversation ID for deleting message")
            return
        }
        
        print("Deleting message \(message.id) in conversation \(conversationId)")
        chatService.deleteMessage(
            conversationId: conversationId,
            messageId: message.id
        ) { [weak self] error in
            if let error = error {
                print("Error deleting message: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self?.error = error.localizedDescription
                }
            }
        }
    }
    
    func editMessage(_ message: EnhancedMessage, newContent: String) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            print("No valid conversation ID for editing message")
            return
        }
        
        print("Editing message \(message.id) in conversation \(conversationId)")
        chatService.editMessage(
            conversationId: conversationId,
            messageId: message.id,
            newContent: newContent
        ) { [weak self] error in
            if let error = error {
                print("Error editing message: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self?.error = error.localizedDescription
                }
            }
        }
    }
    
    func addReaction(to message: EnhancedMessage, emoji: String) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            print("No valid conversation ID for adding reaction")
            return
        }
        
        print("Adding reaction \(emoji) to message \(message.id)")
        chatService.addReaction(
            conversationId: conversationId,
            messageId: message.id,
            emoji: emoji,
            userId: currentUserId
        ) { [weak self] error in
            if let error = error {
                print("Error adding reaction: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self?.error = error.localizedDescription
                }
            }
        }
    }
    
    // MARK: - Read Status
    
    private func markUnreadMessagesAsRead(_ messages: [EnhancedMessage]) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            print("No valid conversation ID for marking messages as read")
            return
        }
        
        let unreadMessages = messages.filter {
            !$0.isRead && $0.senderId != currentUserId
        }
        
        guard !unreadMessages.isEmpty else { return }
        
        let messageIds = unreadMessages.map { $0.id }
        
        print("Marking \(messageIds.count) messages as read in conversation \(conversationId)")
        chatService.markMessagesAsRead(
            conversationId: conversationId,
            messageIds: messageIds,
            readerId: currentUserId
        ) { error in
            if let error = error {
                print("Error marking messages as read: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Typing Indicator
    
    private func handleTypingIndicator() {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            print("No valid conversation ID for typing indicator")
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
            print("No valid conversation ID for searching messages")
            return
        }
        
        print("Searching messages with query: \(query)")
        chatService.searchMessages(conversationId: conversationId, query: query) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let messages):
                    print("Found \(messages.count) messages matching query")
                case .failure(let error):
                    print("Error searching messages: \(error.localizedDescription)")
                    self?.error = error.localizedDescription
                }
            }
        }
    }
    
    // MARK: - Ephemeral Messages
    
    func sendEphemeralMessage(content: String?, mediaUrl: String?, duration: Int = 24) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            print("No valid conversation ID for sending ephemeral message")
            error = "No se puede enviar mensaje efímero: ID de conversación no válido"
            return
        }
        
        print("Sending ephemeral message in conversation \(conversationId)")
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
                    print("Ephemeral message sent successfully")
                case .failure(let error):
                    print("Error sending ephemeral message: \(error.localizedDescription)")
                    self?.error = error.localizedDescription
                }
            }
        }
    }
    
    func markEphemeralAsViewed(_ message: EnhancedMessage) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            print("No valid conversation ID for marking ephemeral as viewed")
            return
        }
        
        print("Marking ephemeral message \(message.id) as viewed")
        chatService.markEphemeralAsViewed(
            conversationId: conversationId,
            messageId: message.id
        ) { error in
            if let error = error {
                print("Error marking ephemeral as viewed: \(error.localizedDescription)")
            }
        }
    }
}
