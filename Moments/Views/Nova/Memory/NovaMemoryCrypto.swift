import Foundation

enum NovaMemoryCrypto {
    static func isProbablyEncrypted(_ text: String) -> Bool {
        guard let data = Data(base64Encoded: text), data.count >= 28 else { return false }
        return true
    }

    static func decryptMemory(_ memory: NovaMemory, userId: String) async -> NovaMemory {
        let facts = await decryptFacts(memory.facts, userId: userId)
        return NovaMemory(
            id: memory.id,
            userId: memory.userId,
            facts: facts,
            lastUpdated: memory.lastUpdated,
            createdAt: memory.createdAt
        )
    }

    static func encryptMemory(_ memory: NovaMemory, userId: String) async -> NovaMemory {
        let facts = await encryptFacts(memory.facts, userId: userId)
        return NovaMemory(
            id: memory.id,
            userId: memory.userId,
            facts: facts,
            lastUpdated: memory.lastUpdated,
            createdAt: memory.createdAt
        )
    }

    static func decryptContext(_ context: NovaUserContext, userId: String) async -> NovaUserContext {
        let encryptionService = await MainActor.run { EncryptionService.shared }
        var summaries: [NovaConversationSummary] = []
        for summary in context.conversationSummaries {
            let text = await encryptionService.decryptNovaData(summary.summary, for: userId) ?? summary.summary
            summaries.append(NovaConversationSummary(
                id: summary.id,
                conversationId: summary.conversationId,
                summary: text,
                createdAt: summary.createdAt
            ))
        }
        return NovaUserContext(userId: context.userId, conversationSummaries: summaries)
    }

    static func encryptContext(_ context: NovaUserContext, userId: String) async -> NovaUserContext {
        let encryptionService = await MainActor.run { EncryptionService.shared }
        var summaries: [NovaConversationSummary] = []
        for summary in context.conversationSummaries {
            let text = await encryptionService.encryptNovaData(summary.summary, for: userId) ?? summary.summary
            summaries.append(NovaConversationSummary(
                id: summary.id,
                conversationId: summary.conversationId,
                summary: text,
                createdAt: summary.createdAt
            ))
        }
        return NovaUserContext(userId: context.userId, conversationSummaries: summaries)
    }

    static func memoryNeedsEncryptionMigration(_ memory: NovaMemory) -> Bool {
        memory.facts.contains { !$0.content.isEmpty && !isProbablyEncrypted($0.content) }
    }

    static func contextNeedsEncryptionMigration(_ context: NovaUserContext) -> Bool {
        context.conversationSummaries.contains { !$0.summary.isEmpty && !isProbablyEncrypted($0.summary) }
    }

    private static func decryptFacts(_ facts: [NovaFact], userId: String) async -> [NovaFact] {
        let encryptionService = await MainActor.run { EncryptionService.shared }
        var decrypted: [NovaFact] = []
        for fact in facts {
            let content = await encryptionService.decryptNovaData(fact.content, for: userId) ?? fact.content
            decrypted.append(NovaFact(
                id: fact.id,
                content: content,
                type: fact.type,
                timestamp: fact.timestamp,
                importance: fact.importance,
                lastVerified: fact.lastVerified,
                embedding: fact.embedding
            ))
        }
        return decrypted
    }

    private static func encryptFacts(_ facts: [NovaFact], userId: String) async -> [NovaFact] {
        let encryptionService = await MainActor.run { EncryptionService.shared }
        var encrypted: [NovaFact] = []
        for fact in facts {
            let content = await encryptionService.encryptNovaData(fact.content, for: userId) ?? fact.content
            encrypted.append(NovaFact(
                id: fact.id,
                content: content,
                type: fact.type,
                timestamp: fact.timestamp,
                importance: fact.importance,
                lastVerified: fact.lastVerified,
                embedding: fact.embedding
            ))
        }
        return encrypted
    }
}
