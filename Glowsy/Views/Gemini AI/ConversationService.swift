import Foundation
import FirebaseFirestore
import FirebaseVertexAI
import FirebaseAuth

class ConversationService {
    private let db = Firestore.firestore()
    private let vertexAI = VertexAI.vertexAI()
    private lazy var model = vertexAI.generativeModel(modelName: "gemini-2.5-flash-lite")
    private let encryptionService = EncryptionService.shared
    
    // MARK: - Colecciones de Firestore
    private var conversationTitlesCollection: CollectionReference {
        return db.collection("geminiConversationTitles")
    }
    
    private var conversationsCollection: CollectionReference {
        return db.collection("geminiConversations")
    }
    
    // MARK: - Cargar títulos de conversaciones
    func loadConversationTitles(for userId: String, completion: @escaping ([ConversationTitle]) -> Void) {
        conversationTitlesCollection
            .whereField("userId", isEqualTo: userId)
            .order(by: "lastUpdated", descending: true)
            .limit(to: 20) // Limitar a las últimas 20 conversaciones
            .addSnapshotListener { [weak self] snapshot, error in
                if let error = error {
                    print("Error loading Gemini conversation titles: \(error.localizedDescription)")
                    completion([])
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    completion([])
                    return
                }
                
                let titles = documents.compactMap { document -> ConversationTitle? in
                    guard var title = ConversationTitle(dictionary: document.data()) else {
                        return nil
                    }
                    
                    // 🔐 Decrypt title if encryption is enabled
                    if let encryptedTitle = title.title as String?,
                       let decryptedTitle = self?.encryptionService.decryptGeminiData(encryptedTitle, for: userId) {
                        // Create new title with decrypted content
                        return ConversationTitle(
                            id: title.id,
                            title: decryptedTitle,
                            lastUpdated: title.lastUpdated,
                            messageCount: title.messageCount,
                            userId: title.userId
                        )
                    }
                    
                    return title
                }
                
                completion(titles)
            }
    }
    
    // MARK: - Guardar nueva conversación
    func saveConversation(for userId: String, messages: [ChatMessage], completion: @escaping (String?) -> Void) {
        guard !messages.isEmpty else {
            completion(nil)
            return
        }
        
        let conversationId = UUID().uuidString
        let savedMessages = messages.toSavedMessages()
        
        // 🔐 Encrypt messages before storing
        let encryptedMessages = savedMessages.compactMap { message -> SavedChatMessage? in
            let encryptedText = self.encryptionService.encryptGeminiData(message.text, for: userId) ?? message.text
            
            return SavedChatMessage(
                id: message.id,
                text: encryptedText, // Store encrypted text
                isUser: message.isUser,
            )
        }
        
        // Generar título automáticamente
        generateConversationTitle(from: messages) { [weak self] title in
            guard let self = self else { return }
            
            // 🔐 Encrypt title before storing
            let encryptedTitle = self.encryptionService.encryptGeminiData(title, for: userId) ?? title
            
            let conversationTitle = ConversationTitle(
                id: conversationId,
                title: encryptedTitle, // Store encrypted title
                lastUpdated: Date(),
                messageCount: messages.count,
                userId: userId
            )
            
            // 🔐 Encrypt messages before storing
            let encryptedMessages = messages.compactMap { message -> SavedChatMessage? in
                let savedMessage = SavedChatMessage(from: message)
                
                // Create new saved message with encrypted content
                let encryptedText = self.encryptionService.encryptGeminiData(savedMessage.text, for: userId) ?? savedMessage.text
                
                return SavedChatMessage(
                    id: savedMessage.id,
                    text: encryptedText, // Store encrypted text
                    isUser: savedMessage.isUser,
                )
            }
            
            let savedConversation = SavedConversation(
                id: conversationId,
                title: encryptedTitle, // Store encrypted title
                messages: encryptedMessages, // Store encrypted messages
                createdAt: Date(),
                lastUpdated: Date(),
                userId: userId
            )
            
            // Guardar en batch para consistencia
            let batch = self.db.batch()
            
            // Guardar título
            let titleRef = self.conversationTitlesCollection.document(conversationId)
            batch.setData(conversationTitle.dictionary, forDocument: titleRef)
            
            // Guardar conversación completa
            let conversationRef = self.conversationsCollection.document(conversationId)
            batch.setData(savedConversation.dictionary, forDocument: conversationRef)
            
            batch.commit { error in
                if let error = error {
                    print("Error saving conversation: \(error.localizedDescription)")
                    completion(nil)
                } else {
                    print("Conversación de Gemini guardada exitosamente con ID: \(conversationId)")
                    completion(conversationId)
                }
            }
        }
    }
    
    // MARK: - Actualizar conversación existente
    func updateConversation(_ conversationId: String, for userId: String, messages: [ChatMessage], completion: @escaping (Bool) -> Void) {
        guard !messages.isEmpty else {
            completion(false)
            return
        }
        
        let savedMessages = messages.toSavedMessages()
        
        // 🔐 Encrypt messages before storing
        let encryptedMessages = savedMessages.compactMap { message -> SavedChatMessage? in
            let encryptedText = self.encryptionService.encryptGeminiData(message.text, for: userId) ?? message.text
            
            return SavedChatMessage(
                id: message.id,
                text: encryptedText, // Store encrypted text
                isUser: message.isUser
            )
        }
        
        // Obtener la conversación actual para mantener el título y fechas
        conversationsCollection.document(conversationId).getDocument { [weak self] document, error in
            guard let self = self,
                  let document = document,
                  document.exists,
                  let data = document.data(),
                  let savedConversation = SavedConversation(dictionary: data) else {
                print("Error obteniendo conversación de Gemini existente: \(error?.localizedDescription ?? "Documento no encontrado")")
                completion(false)
                return
            }
            
            let updatedConversation = SavedConversation(
                id: conversationId,
                title: savedConversation.title, // Keep existing encrypted title
                messages: encryptedMessages, // Store newly encrypted messages
                createdAt: savedConversation.createdAt,
                lastUpdated: Date(),
                userId: userId
            )
            
            let updatedTitle = ConversationTitle(
                id: conversationId,
                title: savedConversation.title, // Keep existing encrypted title
                lastUpdated: Date(),
                messageCount: messages.count,
                userId: userId
            )
            
            // Actualizar en batch
            let batch = self.db.batch()
            
            // Actualizar título
            let titleRef = self.conversationTitlesCollection.document(conversationId)
            batch.updateData(updatedTitle.dictionary, forDocument: titleRef)
            
            // Actualizar conversación
            let conversationRef = self.conversationsCollection.document(conversationId)
            batch.updateData(updatedConversation.dictionary, forDocument: conversationRef)
            
            batch.commit { error in
                if let error = error {
                    print("Error updating Gemini conversation: \(error.localizedDescription)")
                    completion(false)
                } else {
                    print("Conversación de Gemini actualizada exitosamente")
                    completion(true)
                }
            }
        }
    }
    // MARK: - Cargar conversación completa
    func loadConversation(_ conversationId: String, for userId: String, completion: @escaping ([ChatMessage]) -> Void) {
        print("🔍 Buscando conversación en Firestore: \(conversationId)")
        
        conversationsCollection.document(conversationId).getDocument { [weak self] document, error in
            if let error = error {
                print("❌ Error loading Gemini conversation: \(error.localizedDescription)")
                completion([])
                return
            }
            
            guard let document = document, document.exists else {
                print("❌ Documento de conversación no existe: \(conversationId)")
                completion([])
                return
            }
            
            guard let data = document.data() else {
                print("❌ No se pudieron obtener datos del documento")
                completion([])
                return
            }
            
            print("✅ Documento encontrado, parseando datos...")
            
            guard let savedConversation = SavedConversation(dictionary: data) else {
                print("❌ Error al parsear SavedConversation")
                completion([])
                return
            }
            
            // Verificar que el userId coincida
            guard savedConversation.userId == userId else {
                print("❌ Conversación no pertenece al usuario actual")
                completion([])
                return
            }
            
            print("📄 Conversación parseada: \(savedConversation.messages.count) mensajes")
            
            // 🔐 Decrypt messages before returning
            let decryptedMessages = savedConversation.messages.compactMap { savedMessage -> ChatMessage? in
                print("🔓 Desencriptando mensaje: \(savedMessage.id)")
                
                let decryptedText = self?.encryptionService.decryptGeminiData(savedMessage.text, for: userId) ?? savedMessage.text
                
                print("📝 Texto desencriptado: \(decryptedText.prefix(50))...")
                
                // ✅ CAMBIO AQUÍ: Añadir isHistorical: true
                return ChatMessage(text: decryptedText, isUser: savedMessage.isUser, isHistorical: true)
            }
            
            print("✅ \(decryptedMessages.count) mensajes desencriptados correctamente")
            completion(decryptedMessages)
        }
    }
    
    // MARK: - Eliminar conversación
    func deleteConversation(_ conversationId: String, for userId: String, completion: @escaping (Bool) -> Void) {
        // Verificar que la conversación pertenece al usuario
        conversationTitlesCollection.document(conversationId).getDocument { [weak self] document, error in
            guard let self = self,
                  let document = document,
                  document.exists,
                  let data = document.data(),
                  let title = ConversationTitle(dictionary: data),
                  title.userId == userId else {
                print("Error: Conversación de Gemini no encontrada o acceso denegado")
                completion(false)
                return
            }
            
            // Eliminar en batch
            let batch = self.db.batch()
            
            // Eliminar título
            let titleRef = self.conversationTitlesCollection.document(conversationId)
            batch.deleteDocument(titleRef)
            
            // Eliminar conversación
            let conversationRef = self.conversationsCollection.document(conversationId)
            batch.deleteDocument(conversationRef)
            
            batch.commit { error in
                if let error = error {
                    print("Error deleting Gemini conversation: \(error.localizedDescription)")
                    completion(false)
                } else {
                    print("Conversación de Gemini eliminada exitosamente")
                    completion(true)
                }
            }
        }
    }
    
    // MARK: - Generar título de conversación
    private func generateConversationTitle(from messages: [ChatMessage], completion: @escaping (String) -> Void) {
        // Tomar los primeros mensajes para generar el título
        let messagesToAnalyze = Array(messages.prefix(4))
        let conversationText = messagesToAnalyze.map { message in
            "\(message.isUser ? "Usuario" : "Asistente"): \(message.text)"
        }.joined(separator: "\n")
        
        let prompt = """
        Basándote en esta conversación, genera un título breve y descriptivo (máximo 6 palabras) que capture el tema principal. El título debe ser casual y amigable, como si fuera una nota personal. Algunos ejemplos de estilo:
        
        - "Consejos de estudio para exámenes"
        - "Charla sobre intereses musicales"
        - "Ayuda con escritura creativa"
        - "Terapia express con IA"
        - "Planificación de fin de semana"
        
        Conversación:
        \(conversationText)
        
        Responde SOLO con el título, sin comillas ni explicaciones adicionales.
        """
        
        Task {
            do {
                let response = try await model.generateContent(prompt)
                let title = response.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Conversación \(DateFormatter.shortTime.string(from: Date()))"
                
                // Asegurar que el título no sea demasiado largo
                let finalTitle = title.count > 50 ? String(title.prefix(47)) + "..." : title
                
                DispatchQueue.main.async {
                    completion(finalTitle)
                }
            } catch {
                print("Error generando título: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion("Conversación \(DateFormatter.shortTime.string(from: Date()))")
                }
            }
        }
    }
    
    // MARK: - Limpiar conversaciones antiguas (opcional)
    func cleanupOldConversations(for userId: String, keepLast: Int = 50) {
        conversationTitlesCollection
            .whereField("userId", isEqualTo: userId)
            .order(by: "lastUpdated", descending: true)
            .limit(to: 100) // Obtener más de las que queremos mantener
            .getDocuments { [weak self] snapshot, error in
                guard let self = self,
                      let documents = snapshot?.documents,
                      documents.count > keepLast else {
                    return
                }
                
                // Eliminar las conversaciones más antiguas
                let documentsToDelete = Array(documents.dropFirst(keepLast))
                let batch = self.db.batch()
                
                for document in documentsToDelete {
                    // Eliminar título
                    batch.deleteDocument(document.reference)
                    
                    // Eliminar conversación completa
                    let conversationRef = self.conversationsCollection.document(document.documentID)
                    batch.deleteDocument(conversationRef)
                }
                
                batch.commit { error in
                    if let error = error {
                        print("Error cleaning up old Gemini conversations: \(error.localizedDescription)")
                    } else {
                        print("Limpieza de conversaciones de Gemini completada")
                    }
                }
            }
    }
}

// MARK: - Extensions
extension DateFormatter {
    static let shortTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
