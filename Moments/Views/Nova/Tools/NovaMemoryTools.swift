import Foundation
import FirebaseAI

actor NovaMemoryTools {
    private let store: NovaMemoryStore

    init(store: NovaMemoryStore) {
        self.store = store
    }

    func rememberFact(userId: String, content: String, type: NovaFactType?) async -> JSONObject {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ["success": .bool(false), "error": .string("Empty fact.")]
        }

        var memory = await store.loadMemory(userId: userId) ?? NovaMemory(userId: userId)
        let factType = type ?? .general
        let fact = NovaFact(content: trimmed, type: factType, importance: factType == .preference ? 5 : 3)

        memory = memory.upsertingFacts([fact])
        do {
            try await store.saveMemory(memory)
            return [
                "success": .bool(true),
                "fact_id": .string(fact.id)
            ]
        } catch {
            return [
                "success": .bool(false),
                "error": .string(error.localizedDescription)
            ]
        }
    }

    func updatePreference(userId: String, key: String, value: String) async -> JSONObject {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return ["success": .bool(false), "error": .string("Empty value.")]
        }

        let normalizedKey = key.lowercased()
        if normalizedKey.contains("name") {
            return await rememberFact(userId: userId, content: "Preferred name: \(trimmedValue)", type: .preference)
        }
        if normalizedKey.contains("pronoun") || normalizedKey.contains("pronombre") {
            return await rememberFact(userId: userId, content: "Pronouns: \(trimmedValue)", type: .preference)
        }

        return await rememberFact(userId: userId, content: "\(key): \(trimmedValue)", type: .preference)
    }
}
