import Foundation
import FirebaseFirestore
import FirebaseVertexAI
import FirebaseAuth

// MARK: - ConversationService ACTUALIZADO para Async Encryption 🚀
@MainActor
class ConversationService: ObservableObject {
    private let db = Firestore.firestore()
    private let vertexAI = VertexAI.vertexAI(location: "global")
    private lazy var model = vertexAI.generativeModel(modelName: "Gemini 3.1 Flash-Lite")
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
        guard let title = ConversationTitle(dictionary: document.data()) else {
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
            // 1. Generate title in two phases: provisional first, refined later
            let title = await generateInitialConversationTitle(from: messages)

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
                    let encryptedImageData = await self.encryptOptionalImageData(message.imageData, for: userId)
                    let saved = SavedChatMessage(
                        id: message.id,
                        text: encryptedText,
                        isUser: message.isUser,
                        imageData: encryptedImageData
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

    private func encryptOptionalImageData(_ imageData: String?, for userId: String) async -> String? {
        guard let imageData else { return nil }
        return await encryptionService.encryptGeminiData(imageData, for: userId) ?? imageData
    }

    private func decryptOptionalImageData(_ imageData: String?, for userId: String) async -> String? {
        guard let imageData else { return nil }
        return await encryptionService.decryptGeminiData(imageData, for: userId) ?? imageData
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

            // 2. Decide whether title should evolve now that the conversation has more shape
            let existingDecryptedTitle = await encryptionService.decryptGeminiData(savedConversation.title, for: userId) ?? savedConversation.title
            let shouldRefreshTitle = shouldRefreshConversationTitle(
                currentTitle: existingDecryptedTitle,
                previousMessageCount: savedConversation.messages.count,
                newMessageCount: messages.count
            )

            let resolvedTitle: String
            if shouldRefreshTitle {
                resolvedTitle = await generateRefinedConversationTitle(from: messages, currentTitle: existingDecryptedTitle)
            } else {
                resolvedTitle = existingDecryptedTitle
            }

            async let encryptedResolvedTitle = encryptionService.encryptGeminiData(resolvedTitle, for: userId)

            // 3. Encrypt new messages
            let encryptedMessages = await encryptMessages(messages, for: userId)
            let finalEncryptedTitle = await encryptedResolvedTitle ?? resolvedTitle

            // 4. Create updated objects
            let updatedConversation = SavedConversation(
                id: conversationId,
                title: finalEncryptedTitle,
                messages: encryptedMessages,
                createdAt: savedConversation.createdAt,
                lastUpdated: Date(),
                userId: userId
            )

            let updatedTitle = ConversationTitle(
                id: conversationId,
                title: finalEncryptedTitle,
                lastUpdated: Date(),
                messageCount: messages.count,
                userId: userId
            )

            // 5. Update in batch
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
                        let decryptedImageData = await self.decryptOptionalImageData(savedMessage.imageData, for: userId)

                        let message = SavedChatMessage(
                            id: savedMessage.id,
                            text: decryptedText,
                            isUser: savedMessage.isUser,
                            imageData: decryptedImageData
                        )

                        return (index, message.toChatMessage())
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
    private func generateInitialConversationTitle(from messages: [ChatMessage]) async -> String {
        let lang = NovaLanguageService.getPreferredLanguage() ?? .es
        let userMessages = messages.filter { $0.isUser && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        guard let firstUserMessage = userMessages.first?.text else {
            return fallbackTitle(for: lang)
        }

        if userMessages.count <= 2 {
            let snippet = makeSnippetTitle(from: firstUserMessage, lang: lang)
            return snippet.isEmpty ? fallbackTitle(for: lang) : snippet
        }

        return await generateRefinedConversationTitle(from: messages, currentTitle: nil)
    }

    private func generateRefinedConversationTitle(from messages: [ChatMessage], currentTitle: String?) async -> String {
        let meaningfulMessages = messages
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .filter { !$0.isSystem }

        let messagesToAnalyze = Array(meaningfulMessages.prefix(8))
        let lang = NovaLanguageService.getPreferredLanguage() ?? .es
        let conversationText = messagesToAnalyze.map { message in
            "\(message.isUser ? (lang == .en ? "User" : lang == .ca ? "Usuari" : "Usuario") : (lang == .en ? "Assistant" : lang == .ca ? "Assistent" : "Asistente")): \(message.text)"
        }.joined(separator: "\n")

        let prompt: String
        switch lang {
        case .es:
            prompt = """
            Basándote en esta conversación, genera un título breve y descriptivo (máximo 5 palabras) que capture el tema principal. Debe sonar limpio, natural y específico, como el nombre útil de un chat. Evita títulos genéricos o teatrales.

            Buen estilo:
            - "Consejos para estudiar mejor"
            - "Ideas para compartir hoy"
            - "Cambiar el tono de Nova"
            - "Ayuda con una bio"

            Conversación:
            \(conversationText)

            Título actual: \(currentTitle ?? "Ninguno")

            Reglas:
            - Prioriza el tema real, no la primera frase literal.
            - No uses comillas, emojis ni signos finales.
            - No empieces por "Conversación", "Chat", "Ayuda" o similares salvo que sea imprescindible.
            - Si el título actual ya es correcto, puedes devolver una versión muy parecida pero más precisa.

            Responde SOLO con el título, sin comillas ni explicaciones adicionales.
            """
        case .en:
            prompt = """
            Based on this conversation, generate a short, descriptive title (max 5 words) that captures the main topic. It should feel clean, natural, and specific, like a useful chat name. Avoid generic or overdramatic titles.

            Good style:
            - "Study tips for exams"
            - "Ideas to share today"
            - "Changing Nova's tone"
            - "Help with a bio"

            Conversation:
            \(conversationText)

            Current title: \(currentTitle ?? "None")

            Rules:
            - Prioritize the real topic, not the first literal sentence.
            - No quotes, emojis, or ending punctuation.
            - Do not start with "Conversation", "Chat", "Help", or similar unless truly necessary.
            - If the current title is already good, you may return a slightly more precise version.

            Respond ONLY with the title, without quotes or additional explanations.
            """
        case .ca:
            prompt = """
            Basant-te en aquesta conversa, genera un títol breu i descriptiu (màxim 5 paraules) que capti el tema principal. Ha de sonar net, natural i específic, com el nom útil d'un xat. Evita títols genèrics o teatrals.

            Bon estil:
            - "Consells per estudiar millor"
            - "Idees per compartir avui"
            - "Canviar el to de Nova"
            - "Ajuda amb una bio"

            Conversa:
            \(conversationText)

            Títol actual: \(currentTitle ?? "Cap")

            Regles:
            - Prioritza el tema real, no la primera frase literal.
            - No facis servir cometes, emojis ni puntuació final.
            - No comencis per "Conversa", "Xat", "Ajuda" o similars si no cal.
            - Si el títol actual ja és bo, pots tornar-ne una versió molt semblant però més precisa.

            Respon NOMÉS amb el títol, sense cometes ni explicacions addicionals.
            """
        }

        do {
            let response = try await model.generateContent(prompt)
            let title = response.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? fallbackTitle(for: lang)

            // Ensure title isn't too long
            let sanitized = sanitizeConversationTitle(title, lang: lang)
            let finalTitle = sanitized.count > 50 ? String(sanitized.prefix(47)) + "..." : sanitized

            return finalTitle

        } catch {
            return fallbackTitle(for: lang)
        }
    }

    private func shouldRefreshConversationTitle(currentTitle: String, previousMessageCount: Int, newMessageCount: Int) -> Bool {
        guard newMessageCount > previousMessageCount else { return false }

        let crossedFirstThreshold = previousMessageCount < 6 && newMessageCount >= 6
        let crossedSecondThreshold = previousMessageCount < 10 && newMessageCount >= 10
        let genericCurrentTitle = isGenericConversationTitle(currentTitle)

        return crossedFirstThreshold || crossedSecondThreshold || genericCurrentTitle
    }

    private func isGenericConversationTitle(_ title: String) -> Bool {
        let normalized = title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.hasPrefix("conversación ") ||
            normalized.hasPrefix("conversation ") ||
            normalized.hasPrefix("conversa ") ||
            normalized == "nueva conversación" ||
            normalized == "new conversation" ||
            normalized == "nova conversa"
    }

    private func makeSnippetTitle(from text: String, lang: NovaLanguage) -> String {
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "¿", with: "")
            .replacingOccurrences(of: "?", with: "")
            .replacingOccurrences(of: "!", with: "")

        let lowercased = cleaned.lowercased()
        let shortGreetingsES = ["hola", "holaa", "buenas", "qué tal", "que tal"]
        let shortGreetingsEN = ["hello", "hi", "hey"]
        let shortGreetingsCA = ["hola", "bon dia", "bona tarda"]
        let greetings: [String]
        switch lang {
        case .es: greetings = shortGreetingsES
        case .en: greetings = shortGreetingsEN
        case .ca: greetings = shortGreetingsCA
        }

        if greetings.contains(lowercased) {
            return fallbackTitle(for: lang)
        }

        let words = cleaned
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }

        let snippet = words.prefix(5).joined(separator: " ")
        return sanitizeConversationTitle(snippet, lang: lang)
    }

    private func sanitizeConversationTitle(_ title: String, lang: NovaLanguage) -> String {
        let trimmed = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "“", with: "")
            .replacingOccurrences(of: "”", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "!", with: "")
            .replacingOccurrences(of: "?", with: "")
            .replacingOccurrences(of: "##", with: "")

        if trimmed.isEmpty { return fallbackTitle(for: lang) }
        return trimmed
    }

    private func fallbackTitle(for lang: NovaLanguage) -> String {
        switch lang {
        case .es: return "Conversación \(DateFormatter.shortTime.string(from: Date()))"
        case .en: return "Conversation \(DateFormatter.shortTime.string(from: Date()))"
        case .ca: return "Conversa \(DateFormatter.shortTime.string(from: Date()))"
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


        } catch _ {
            // Silently ignore preloading errors
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
