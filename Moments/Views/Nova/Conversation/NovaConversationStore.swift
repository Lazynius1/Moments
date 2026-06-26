import Foundation
import FirebaseFirestore
import FirebaseAuth
import UIKit

@MainActor
final class NovaConversationStore: ObservableObject {
    static let shared = NovaConversationStore()

    private let db = Firestore.firestore()
    private let encryptionService = EncryptionService.shared
    private let ai = NovaAIService.shared
    private let storageService = StorageService()

    @Published var isLoading = false
    @Published var lastError: String?
    private var imageReferenceCache: [String: String] = [:]

    private var legacyTitlesCollection: CollectionReference { db.collection("geminiConversationTitles") }
    private var legacyConversationsCollection: CollectionReference { db.collection("geminiConversations") }

    private init() {}

    private func userConversationsCollection(for userId: String) -> CollectionReference {
        db.collection("users").document(userId).collection("novaConversations")
    }

    private func userConversationDocument(_ conversationId: String, for userId: String) -> DocumentReference {
        userConversationsCollection(for: userId).document(conversationId)
    }

    func loadConversationTitles(for userId: String) async -> [ConversationTitle] {
        isLoading = true
        defer { isLoading = false }

        do {
            async let newSnapshot = userConversationsCollection(for: userId)
                .order(by: "lastUpdated", descending: true)
                .limit(to: 20)
                .getDocuments()

            async let legacySnapshot = legacyTitlesCollection
                .whereField("userId", isEqualTo: userId)
                .order(by: "lastUpdated", descending: true)
                .limit(to: 20)
                .getDocuments()

            var merged: [String: ConversationTitle] = [:]

            let resolvedNewSnapshot = try await newSnapshot
            let resolvedLegacySnapshot = try await legacySnapshot

            for document in resolvedNewSnapshot.documents {
                if let title = await decryptConversationTitle(fromConversationData: document.data(), userId: userId) {
                    merged[title.id] = title
                }
            }

            for document in resolvedLegacySnapshot.documents {
                if let title = await decryptTitle(from: document.data(), userId: userId),
                   merged[title.id] == nil {
                    merged[title.id] = title
                }
            }

            return merged.values
                .sorted { $0.lastUpdated > $1.lastUpdated }
                .prefix(20)
                .map { $0 }
        } catch {
            lastError = error.localizedDescription
            return []
        }
    }

    func saveConversation(for userId: String, messages: [ChatMessage]) async -> String? {
        guard !messages.isEmpty else { return nil }
        isLoading = true
        defer { isLoading = false }

        let conversationId = UUID().uuidString
        do {
            let title = await generateTitle(from: messages)
            let encryptedTitle = await encryptionService.encryptNovaData(title, for: userId) ?? title
            let encryptedMessages = try await encryptMessages(messages, for: userId, conversationId: conversationId)

            let savedConversation = SavedConversation(
                id: conversationId,
                title: encryptedTitle,
                messages: encryptedMessages,
                createdAt: Date(),
                lastUpdated: Date(),
                userId: userId
            )

            try await saveUserConversation(savedConversation, for: userId)
            return conversationId
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func updateConversation(_ conversationId: String, for userId: String, messages: [ChatMessage]) async -> Bool {
        guard !messages.isEmpty else { return false }
        isLoading = true
        defer { isLoading = false }

        do {
            guard let source = try await loadConversationSource(conversationId, for: userId) else { return false }
            let savedConversation = source.conversation

            let existingTitle = await encryptionService.decryptNovaData(savedConversation.title, for: userId) ?? savedConversation.title
            let shouldRefresh = savedConversation.messages.count < 6 && messages.count >= 6
            let resolvedTitle: String
            if shouldRefresh {
                resolvedTitle = await generateTitle(from: messages, currentTitle: existingTitle)
            } else {
                resolvedTitle = existingTitle
            }

            let encryptedTitle = await encryptionService.encryptNovaData(resolvedTitle, for: userId) ?? resolvedTitle
            let encryptedMessages = try await encryptMessages(messages, for: userId, conversationId: conversationId)

            let updatedConversation = SavedConversation(
                id: conversationId,
                title: encryptedTitle,
                messages: encryptedMessages,
                createdAt: savedConversation.createdAt,
                lastUpdated: Date(),
                userId: userId
            )
            switch source.location {
            case .userScoped:
                try await updateUserConversation(updatedConversation, for: userId)
            case .legacy:
                let updatedTitle = ConversationTitle(
                    id: conversationId,
                    title: encryptedTitle,
                    lastUpdated: Date(),
                    messageCount: messages.count,
                    userId: userId
                )
                try await updateLegacyBatch(conversationId: conversationId, title: updatedTitle, conversation: updatedConversation)
            }
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func loadConversation(_ conversationId: String, for userId: String) async -> [ChatMessage] {
        isLoading = true
        defer { isLoading = false }

        do {
            guard let source = try await loadConversationSource(conversationId, for: userId) else { return [] }
            let savedConversation = source.conversation

            var messages: [ChatMessage] = []
            for savedMessage in savedConversation.messages {
                let decryptedText = await encryptionService.decryptNovaData(savedMessage.text, for: userId) ?? savedMessage.text
                let decryptedImagePayload = await decryptImageData(savedMessage.imageData, for: userId)
                let resolvedImage = await resolveHistoricalImage(
                    from: decryptedImagePayload,
                    messageId: savedMessage.id,
                    conversationId: savedConversation.id,
                    userId: userId
                )

                let restored = SavedChatMessage(
                    id: savedMessage.id,
                    text: decryptedText,
                    isUser: savedMessage.isUser,
                    imageData: decryptedImagePayload
                )
                if let storagePath = resolvedImage.storagePath {
                    imageReferenceCache[cacheKey(conversationId: savedConversation.id, messageId: savedMessage.id)] = storagePath
                }
                messages.append(
                    restored.toChatMessage(
                        image: resolvedImage.image,
                        imageStoragePath: resolvedImage.storagePath
                    )
                )
            }
            return messages
        } catch {
            lastError = error.localizedDescription
            return []
        }
    }

    func deleteConversation(_ conversationId: String, for userId: String) async -> Bool {
        isLoading = true
        defer { isLoading = false }

        do {
            let userDocument = try await userConversationDocument(conversationId, for: userId).getDocument()
            if userDocument.exists {
                if let data = userDocument.data(),
                   let conversation = SavedConversation(dictionary: data) {
                    await deleteStoredImages(for: conversation, userId: userId)
                }
                try await userConversationDocument(conversationId, for: userId).delete()
                imageReferenceCache = imageReferenceCache.filter { !$0.key.hasPrefix("\(conversationId)|") }
                return true
            }

            let document = try await legacyTitlesCollection.document(conversationId).getDocument()
            guard document.exists,
                  let data = document.data(),
                  let title = ConversationTitle(dictionary: data),
                  title.userId == userId else {
                return false
            }

            let legacyConversationDocument = try await legacyConversationsCollection.document(conversationId).getDocument()
            if let legacyData = legacyConversationDocument.data(),
               let conversation = SavedConversation(dictionary: legacyData) {
                await deleteStoredImages(for: conversation, userId: userId)
            }

            let batch = db.batch()
            batch.deleteDocument(legacyTitlesCollection.document(conversationId))
            batch.deleteDocument(legacyConversationsCollection.document(conversationId))
            try await batch.commit()
            imageReferenceCache = imageReferenceCache.filter { !$0.key.hasPrefix("\(conversationId)|") }
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    // MARK: - Private

    private func decryptTitle(from data: [String: Any], userId: String) async -> ConversationTitle? {
        guard let title = ConversationTitle(dictionary: data) else { return nil }
        let decrypted = await encryptionService.decryptNovaData(title.title, for: userId) ?? title.title
        return ConversationTitle(
            id: title.id,
            title: decrypted,
            lastUpdated: title.lastUpdated,
            messageCount: title.messageCount,
            userId: title.userId
        )
    }

    private func decryptConversationTitle(fromConversationData data: [String: Any], userId: String) async -> ConversationTitle? {
        guard let conversation = SavedConversation(dictionary: data) else { return nil }
        let decrypted = await encryptionService.decryptNovaData(conversation.title, for: userId) ?? conversation.title
        return ConversationTitle(
            id: conversation.id,
            title: decrypted,
            lastUpdated: conversation.lastUpdated,
            messageCount: conversation.messages.count,
            userId: conversation.userId
        )
    }

    private func encryptMessages(_ messages: [ChatMessage], for userId: String, conversationId: String) async throws -> [SavedChatMessage] {
        var saved: [SavedChatMessage] = []
        for message in messages where !message.isSystem {
            let encryptedText = await encryptionService.encryptNovaData(message.text, for: userId) ?? message.text
            let imageReference = try await resolveImageReference(for: message, userId: userId, conversationId: conversationId)
            let encryptedImage = await encryptImageData(imageReference, for: userId)
            saved.append(
                SavedChatMessage(
                    id: message.id.uuidString,
                    text: encryptedText,
                    isUser: message.isUser,
                    imageData: encryptedImage
                )
            )
        }
        return saved
    }

    private func encryptImageData(_ imageData: String?, for userId: String) async -> String? {
        guard let imageData else { return nil }
        return await encryptionService.encryptNovaData(imageData, for: userId) ?? imageData
    }

    private func decryptImageData(_ imageData: String?, for userId: String) async -> String? {
        guard let imageData else { return nil }
        return await encryptionService.decryptNovaData(imageData, for: userId) ?? imageData
    }

    private func resolveImageReference(
        for message: ChatMessage,
        userId: String,
        conversationId: String
    ) async throws -> String? {
        let key = cacheKey(conversationId: conversationId, messageId: message.id.uuidString)
        if let cached = imageReferenceCache[key], !cached.isEmpty {
            return cached
        }

        if let existingPath = message.imageStoragePath, !existingPath.isEmpty {
            imageReferenceCache[key] = existingPath
            return existingPath
        }

        guard let image = message.image else { return nil }
        let uploadedPath = try await storageService.uploadNovaConversationImage(
            userId: userId,
            conversationId: conversationId,
            messageId: message.id.uuidString,
            image: image
        )
        imageReferenceCache[key] = uploadedPath
        return uploadedPath
    }

    private func resolveHistoricalImage(
        from decryptedPayload: String?,
        messageId: String,
        conversationId: String,
        userId: String
    ) async -> (image: UIImage?, storagePath: String?) {
        guard let decryptedPayload, !decryptedPayload.isEmpty else {
            return (nil, nil)
        }

        if SavedChatMessage.looksLikeStorageReference(decryptedPayload) {
            do {
                let image = try await storageService.downloadNovaConversationImage(
                    userId: userId,
                    conversationId: conversationId,
                    messageId: messageId,
                    storedPath: decryptedPayload
                )
                return (image, decryptedPayload)
            } catch {
                return (nil, decryptedPayload)
            }
        }

        return (SavedChatMessage.decodeLegacyInlineImage(decryptedPayload), nil)
    }

    private func deleteStoredImages(for conversation: SavedConversation, userId: String) async {
        for savedMessage in conversation.messages {
            guard let decryptedPayload = await decryptImageData(savedMessage.imageData, for: userId),
                  SavedChatMessage.looksLikeStorageReference(decryptedPayload) else {
                continue
            }
            try? await storageService.deleteMedia(path: decryptedPayload)
        }
    }

    private func cacheKey(conversationId: String, messageId: String) -> String {
        "\(conversationId)|\(messageId)"
    }

    private func saveUserConversation(_ conversation: SavedConversation, for userId: String) async throws {
        try await userConversationDocument(conversation.id, for: userId).setData(conversation.dictionary, merge: true)
    }

    private func updateUserConversation(_ conversation: SavedConversation, for userId: String) async throws {
        try await userConversationDocument(conversation.id, for: userId).setData(conversation.dictionary, merge: true)
    }

    private func updateLegacyBatch(conversationId: String, title: ConversationTitle, conversation: SavedConversation) async throws {
        let batch = db.batch()
        batch.updateData(title.dictionary, forDocument: legacyTitlesCollection.document(conversationId))
        batch.updateData(conversation.dictionary, forDocument: legacyConversationsCollection.document(conversationId))
        try await batch.commit()
    }

    private func loadConversationSource(_ conversationId: String, for userId: String) async throws -> LoadedConversation? {
        let userDocument = try await userConversationDocument(conversationId, for: userId).getDocument()
        if userDocument.exists,
           let data = userDocument.data(),
           let conversation = SavedConversation(dictionary: data),
           conversation.userId == userId {
            return LoadedConversation(location: .userScoped, conversation: conversation)
        }

        let legacyDocument = try await legacyConversationsCollection.document(conversationId).getDocument()
        if legacyDocument.exists,
           let data = legacyDocument.data(),
           let conversation = SavedConversation(dictionary: data),
           conversation.userId == userId {
            return LoadedConversation(location: .legacy, conversation: conversation)
        }

        return nil
    }

    private func generateTitle(from messages: [ChatMessage], currentTitle: String? = nil) async -> String {
        let userMessages = messages.filter { $0.isUser && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard let first = userMessages.first?.text else {
            return fallbackTitle()
        }

        if userMessages.count <= 2 {
            let snippet = makeSnippet(from: first)
            return snippet.isEmpty ? fallbackTitle() : snippet
        }

        let transcript = messages
            .filter { !$0.isSystem && !$0.text.isEmpty }
            .prefix(8)
            .map { "\($0.isUser ? "User" : "Nova"): \($0.text)" }
            .joined(separator: "\n")

        let prompt = """
        \(NovaPromptCatalog.conversationTitlePrompt)
        Conversation:
        \(transcript)
        Current title: \(currentTitle ?? "none")
        """

        do {
            let title = try await ai.generateTitle(prompt: prompt)
            let sanitized = sanitize(title)
            return sanitized.isEmpty ? fallbackTitle() : String(sanitized.prefix(50))
        } catch {
            return fallbackTitle()
        }
    }

    private func makeSnippet(from text: String) -> String {
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        let words = cleaned.split(separator: " ").prefix(5)
        return sanitize(words.joined(separator: " "))
    }

    private func sanitize(_ title: String) -> String {
        title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
    }

    private func fallbackTitle() -> String {
        "Chat \(MomentsFormat.smartDate(from: Date(), context: .timeOnly))"
    }
}

private struct LoadedConversation {
    enum Location {
        case userScoped
        case legacy
    }

    let location: Location
    let conversation: SavedConversation
}
