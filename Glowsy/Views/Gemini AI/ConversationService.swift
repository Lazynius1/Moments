import Foundation
import FirebaseFirestore
import FirebaseVertexAI
import FirebaseAuth

// MARK: - ConversationService ACTUALIZADO para Async Encryption 🚀
@MainActor
class ConversationService: ObservableObject {
    private let db = Firestore.firestore()
    private let vertexAI = VertexAI.vertexAI(location: "global")
    private lazy var model = vertexAI.generativeModel(modelName: "gemini-3.1-flash-lite-preview")
    private let encryptionService = EncryptionService.shared
    
    // MARK: - Published Properties for SwiftUI
    @Published var isLoading: Bool = false
    @Published var lastError: String?
    
    // MARK: - Colecciones de Firestore
    private var conversationTitlesCollection: CollectionReference {
        return db.collection("geminiConversationTitles")
    }
    
    private var conversationsCollection: CollectionReference {
        return db.collection("geminiConversations")
    }
    
    // MARK: - 🚀 ASYNC: Cargar títulos de conversaciones
    func loadConversationTitles(for userId: String) async -> [ConversationTitle] {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let snapshot = try await conversationTitlesCollection
                .whereField("userId", isEqualTo: userId)
                .order(by: "lastUpdated", descending: true)
                .limit(to: 20)
                .getDocuments()
            
            let titles = await withTaskGroup(of: ConversationTitle?.self, returning: [ConversationTitle].self) { group in
                for document in snapshot.documents {
                    group.addTask {
                        await self.decryptConversationTitle(from: document, userId: userId)
                    }
                }
                
                var results: [ConversationTitle] = []
                for await title in group {
                    if let title = title {
                        results.append(title)
                    }
                }
                
                // Mantener orden cronológico
                return results.sorted { $0.lastUpdated > $1.lastUpdated }
            }
            
            return titles
            
        } catch {
            lastError = "Error loading conversations: \(error.localizedDescription)"
            return []
        }
    }
    
    // MARK: - 🔓 Helper: Decrypt Conversation Title
    private func decryptConversationTitle(from document: QueryDocumentSnapshot, userId: String) async -> ConversationTitle? {
        guard var title = ConversationTitle(dictionary: document.data()) else {
            return nil
        }
        
        // 🔐 Decrypt title if encryption is enabled
        if let encryptedTitle = title.title as String? {
            let decryptedTitle = await encryptionService.decryptGeminiData(encryptedTitle, for: userId) ?? encryptedTitle
            
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
    
    // MARK: - 💾 ASYNC: Guardar nueva conversación
    func saveConversation(for userId: String, messages: [ChatMessage]) async -> String? {
        guard !messages.isEmpty else { return nil }
        
        isLoading = true
        defer { isLoading = false }
        
        let conversationId = UUID().uuidString
        
        do {
            // 1. Generate title asynchronously
            let title = await generateConversationTitle(from: messages)
            
            // 2. Encrypt title and messages in parallel
            async let encryptedTitle = encryptionService.encryptGeminiData(title, for: userId)
            async let encryptedMessages = encryptMessages(messages, for: userId)
            
            let finalEncryptedTitle = await encryptedTitle ?? title
            let finalEncryptedMessages = await encryptedMessages
            
            // 3. Create conversation objects
            let conversationTitle = ConversationTitle(
                id: conversationId,
                title: finalEncryptedTitle,
                lastUpdated: Date(),
                messageCount: messages.count,
                userId: userId
            )
            
            let savedConversation = SavedConversation(
                id: conversationId,
                title: finalEncryptedTitle,
                messages: finalEncryptedMessages,
                createdAt: Date(),
                lastUpdated: Date(),
                userId: userId
            )
            
            // 4. Save to Firestore in batch
            try await saveConversationBatch(
                conversationId: conversationId,
                title: conversationTitle,
                conversation: savedConversation
            )
            
            return conversationId
            
        } catch {
            lastError = "Error saving conversation: \(error.localizedDescription)"
            return nil
        }
    }
    
    // MARK: - 🔐 Helper: Encrypt Messages
    private func encryptMessages(_ messages: [ChatMessage], for userId: String) async -> [SavedChatMessage] {
        let savedMessages = messages.toSavedMessages()
        
        return await withTaskGroup(of: (Int, SavedChatMessage?).self, returning: [SavedChatMessage].self) { group in
            for (index, message) in savedMessages.enumerated() {
                group.addTask {
                    let encryptedText = await self.encryptionService.encryptGeminiData(message.text, for: userId) ?? message.text
                    let saved = SavedChatMessage(
                        id: message.id,
                        text: encryptedText,
                        isUser: message.isUser
                    )
                    return (index, saved)
                }
            }
            
            var results: [(Int, SavedChatMessage)] = []
            for await result in group {
                if let message = result.1 {
                    results.append((result.0, message))
                }
            }
            
            // Maintain original order
            return results.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
    }
    
    // MARK: - 🔄 Helper: Save Conversation Batch
    private func saveConversationBatch(
        conversationId: String,
        title: ConversationTitle,
        conversation: SavedConversation
    ) async throws {
        let batch = db.batch()
        
        // Save title
        let titleRef = conversationTitlesCollection.document(conversationId)
        batch.setData(title.dictionary, forDocument: titleRef)
        
        // Save full conversation
        let conversationRef = conversationsCollection.document(conversationId)
        batch.setData(conversation.dictionary, forDocument: conversationRef)
        
        try await batch.commit()
    }
    
    // MARK: - 🔄 ASYNC: Actualizar conversación existente
    func updateConversation(_ conversationId: String, for userId: String, messages: [ChatMessage]) async -> Bool {
        guard !messages.isEmpty else { return false }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            // 1. Get existing conversation
            let document = try await conversationsCollection.document(conversationId).getDocument()
            
            guard document.exists,
                  let data = document.data(),
                  let savedConversation = SavedConversation(dictionary: data) else {
                return false
            }
            
            // 2. Encrypt new messages
            let encryptedMessages = await encryptMessages(messages, for: userId)
            
            // 3. Create updated objects
            let updatedConversation = SavedConversation(
                id: conversationId,
                title: savedConversation.title, // Keep existing encrypted title
                messages: encryptedMessages,
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
            
            // 4. Update in batch
            try await updateConversationBatch(
                conversationId: conversationId,
                title: updatedTitle,
                conversation: updatedConversation
            )
            
            return true
            
        } catch {
            lastError = "Error updating conversation: \(error.localizedDescription)"
            return false
        }
    }
    
    // MARK: - 🔄 Helper: Update Conversation Batch
    private func updateConversationBatch(
        conversationId: String,
        title: ConversationTitle,
        conversation: SavedConversation
    ) async throws {
        let batch = db.batch()
        
        // Update title
        let titleRef = conversationTitlesCollection.document(conversationId)
        batch.updateData(title.dictionary, forDocument: titleRef)
        
        // Update conversation
        let conversationRef = conversationsCollection.document(conversationId)
        batch.updateData(conversation.dictionary, forDocument: conversationRef)
        
        try await batch.commit()
    }
    
    // MARK: - 📖 ASYNC: Cargar conversación completa
    func loadConversation(_ conversationId: String, for userId: String) async -> [ChatMessage] {
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            let document = try await conversationsCollection.document(conversationId).getDocument()
            
            guard document.exists,
                  let data = document.data(),
                  let savedConversation = SavedConversation(dictionary: data) else {
                return []
            }
            
            // Verify user ownership
            guard savedConversation.userId == userId else {
                return []
            }
            
            
            // 🔐 Decrypt messages in parallel
            let decryptedMessages = await withTaskGroup(of: (Int, ChatMessage?).self, returning: [ChatMessage].self) { group in
                
                for (index, savedMessage) in savedConversation.messages.enumerated() {
                    group.addTask {
                        
                        let decryptedText = await self.encryptionService.decryptGeminiData(savedMessage.text, for: userId) ?? savedMessage.text
                        
                        
                        let message = ChatMessage(
                            text: decryptedText,
                            isUser: savedMessage.isUser,
                            isHistorical: true // Mark as historical
                        )
                        
                        return (index, message)
                    }
                }
                
                var results: [(Int, ChatMessage)] = []
                for await (index, message) in group {
                    if let message = message {
                        results.append((index, message))
                    }
                }
                
                // Maintain original order
                return results.sorted { $0.0 < $1.0 }.map { $0.1 }
            }
            
            return decryptedMessages
            
        } catch {
            lastError = "Error loading conversation: \(error.localizedDescription)"
            return []
        }
    }
    
    // MARK: - 🗑️ ASYNC: Eliminar conversación
    func deleteConversation(_ conversationId: String, for userId: String) async -> Bool {
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Verify ownership first
            let document = try await conversationTitlesCollection.document(conversationId).getDocument()
            
            guard document.exists,
                  let data = document.data(),
                  let title = ConversationTitle(dictionary: data),
                  title.userId == userId else {
                return false
            }
            
            // Delete in batch
            let batch = db.batch()
            
            // Delete title
            let titleRef = conversationTitlesCollection.document(conversationId)
            batch.deleteDocument(titleRef)
            
            // Delete conversation
            let conversationRef = conversationsCollection.document(conversationId)
            batch.deleteDocument(conversationRef)
            
            try await batch.commit()
            
            return true
            
        } catch {
            lastError = "Error deleting conversation: \(error.localizedDescription)"
            return false
        }
    }
    
    // MARK: - 🎯 ASYNC: Generar título de conversación
    private func generateConversationTitle(from messages: [ChatMessage]) async -> String {
        // Take first messages for analysis
        let messagesToAnalyze = Array(messages.prefix(4))
        let lang = NovaLanguageService.getPreferredLanguage() ?? .es
        let conversationText = messagesToAnalyze.map { message in
            "\(message.isUser ? (lang == .en ? "User" : lang == .ca ? "Usuari" : "Usuario") : (lang == .en ? "Assistant" : lang == .ca ? "Assistent" : "Asistente")): \(message.text)"
        }.joined(separator: "\n")
        
        let prompt: String
        switch lang {
        case .es:
            prompt = """
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
        case .en:
            prompt = """
            Based on this conversation, generate a short, descriptive title (max 6 words) that captures the main topic. The title should be casual and friendly, like a personal note. Style examples:
            
            - "Study tips for exams"
            - "Chat about music interests"
            - "Help with creative writing"
            - "Express therapy with AI"
            - "Weekend planning"
            
            Conversation:
            \(conversationText)
            
            Respond ONLY with the title, without quotes or additional explanations.
            """
        case .ca:
            prompt = """
            Basant-te en aquesta conversa, genera un títol breu i descriptiu (màxim 6 paraules) que capti el tema principal. El títol ha de ser casual i amigable, com una nota personal. Exemples d'estil:
            
            - "Consells d'estudi per a exàmens"
            - "Xerrada sobre interessos musicals"
            - "Ajuda amb escriptura creativa"
            - "Teràpia exprés amb IA"
            - "Planificació de cap de setmana"
            
            Conversa:
            \(conversationText)
            
            Respon NOMÉS amb el títol, sense cometes ni explicacions addicionals.
            """
        }
        
        do {
            let response = try await model.generateContent(prompt)
            let fallbackTitle: String = {
                switch lang {
                case .es: return "Conversación \(DateFormatter.shortTime.string(from: Date()))"
                case .en: return "Conversation \(DateFormatter.shortTime.string(from: Date()))"
                case .ca: return "Conversa \(DateFormatter.shortTime.string(from: Date()))"
                }
            }()
            let title = response.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? fallbackTitle
            
            // Ensure title isn't too long
            let finalTitle = title.count > 50 ? String(title.prefix(47)) + "..." : title
            
            return finalTitle
            
        } catch {
            switch lang {
            case .es: return "Conversación \(DateFormatter.shortTime.string(from: Date()))"
            case .en: return "Conversation \(DateFormatter.shortTime.string(from: Date()))"
            case .ca: return "Conversa \(DateFormatter.shortTime.string(from: Date()))"
            }
        }
    }
    
    // MARK: - 🧹 ASYNC: Limpiar conversaciones antiguas
    func cleanupOldConversations(for userId: String, keepLast: Int = 50) async -> Bool {
        do {
            let snapshot = try await conversationTitlesCollection
                .whereField("userId", isEqualTo: userId)
                .order(by: "lastUpdated", descending: true)
                .limit(to: 100)
                .getDocuments()
            
            let documents = snapshot.documents
            guard documents.count > keepLast else {
                return true
            }
            
            // Delete oldest conversations
            let documentsToDelete = Array(documents.dropFirst(keepLast))
            let batch = db.batch()
            
            for document in documentsToDelete {
                // Delete title
                batch.deleteDocument(document.reference)
                
                // Delete full conversation
                let conversationRef = conversationsCollection.document(document.documentID)
                batch.deleteDocument(conversationRef)
            }
            
            try await batch.commit()
            
            return true
            
        } catch {
            lastError = "Error during cleanup: \(error.localizedDescription)"
            return false
        }
    }
    
    // MARK: - 📊 UTILITY: Get Conversation Statistics
    func getConversationStatistics(for userId: String) async -> ConversationStatistics {
        do {
            let snapshot = try await conversationTitlesCollection
                .whereField("userId", isEqualTo: userId)
                .getDocuments()
            
            let totalConversations = snapshot.documents.count
            let totalMessages = snapshot.documents.compactMap { doc -> Int? in
                ConversationTitle(dictionary: doc.data())?.messageCount
            }.reduce(0, +)
            
            let oldestConversation = snapshot.documents.compactMap { doc -> Date? in
                ConversationTitle(dictionary: doc.data())?.lastUpdated
            }.min()
            
            return ConversationStatistics(
                totalConversations: totalConversations,
                totalMessages: totalMessages,
                oldestConversation: oldestConversation,
                userId: userId
            )
            
        } catch {
            return ConversationStatistics(
                totalConversations: 0,
                totalMessages: 0,
                oldestConversation: nil,
                userId: userId
            )
        }
    }
    
    // MARK: - 🔄 PRELOAD: Optimize Performance
    func preloadRecentConversations(for userId: String) async {
        
        do {
            let snapshot = try await conversationTitlesCollection
                .whereField("userId", isEqualTo: userId)
                .order(by: "lastUpdated", descending: true)
                .limit(to: 5) // Preload 5 most recent
                .getDocuments()
            
            let conversationIds = snapshot.documents.map { $0.documentID }
            
            // Preload encryption keys for these conversations
            await encryptionService.preloadConversationKeys(for: conversationIds)
            
            
        } catch {
        }
    }
}

// MARK: - 📊 SUPPORTING TYPES
struct ConversationStatistics {
    let totalConversations: Int
    let totalMessages: Int
    let oldestConversation: Date?
    let userId: String
    
    var averageMessagesPerConversation: Double {
        guard totalConversations > 0 else { return 0.0 }
        return Double(totalMessages) / Double(totalConversations)
    }
    
    var formattedSummary: String {
        return """
        📊 Estadísticas de Conversaciones:
        • Total conversaciones: \(totalConversations)
        • Total mensajes: \(totalMessages)
        • Promedio por conversación: \(String(format: "%.1f", averageMessagesPerConversation))
        • Conversación más antigua: \(oldestConversation?.formatted(date: .abbreviated, time: .omitted) ?? "N/A")
        """
    }
}

// MARK: - 🔄 EXTENSIONS
extension DateFormatter {
    static let shortTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

// MARK: - 🚀 COMPATIBILITY BRIDGE (for gradual migration)
extension ConversationService {
    
    /// Legacy completion-based method for gradual migration
    func loadConversationTitles(for userId: String, completion: @escaping ([ConversationTitle]) -> Void) {
        Task {
            let titles = await loadConversationTitles(for: userId)
            await MainActor.run {
                completion(titles)
            }
        }
    }
    
    /// Legacy completion-based method for gradual migration
    func saveConversation(for userId: String, messages: [ChatMessage], completion: @escaping (String?) -> Void) {
        Task {
            let conversationId = await saveConversation(for: userId, messages: messages)
            await MainActor.run {
                completion(conversationId)
            }
        }
    }
    
    /// Legacy completion-based method for gradual migration
    func updateConversation(_ conversationId: String, for userId: String, messages: [ChatMessage], completion: @escaping (Bool) -> Void) {
        Task {
            let success = await updateConversation(conversationId, for: userId, messages: messages)
            await MainActor.run {
                completion(success)
            }
        }
    }
    
    /// Legacy completion-based method for gradual migration
    func loadConversation(_ conversationId: String, for userId: String, completion: @escaping ([ChatMessage]) -> Void) {
        Task {
            let messages = await loadConversation(conversationId, for: userId)
            await MainActor.run {
                completion(messages)
            }
        }
    }
    
    /// Legacy completion-based method for gradual migration
    func deleteConversation(_ conversationId: String, for userId: String, completion: @escaping (Bool) -> Void) {
        Task {
            let success = await deleteConversation(conversationId, for: userId)
            await MainActor.run {
                completion(success)
            }
        }
    }
}
