import Foundation
import FirebaseFirestore

@MainActor
final class NovaMemoryStore: ObservableObject {
    static let shared = NovaMemoryStore()

    private let db = Firestore.firestore()
    private var memoryCache: [String: NovaMemory] = [:]

    private init() {}

    private func memoryDocument(for userId: String) -> DocumentReference {
        db.collection("users").document(userId).collection("novaMemory").document("memory")
    }

    func loadMemory(userId: String) async -> NovaMemory? {
        if let cached = memoryCache[userId] {
            return cached
        }

        do {
            let snapshot = try await memoryDocument(for: userId).getDocument()
            guard snapshot.exists, let data = snapshot.data(), let stored = NovaMemory(dictionary: data) else {
                let empty = NovaMemory(userId: userId)
                memoryCache[userId] = empty
                return empty
            }

            let decrypted = await NovaMemoryCrypto.decryptMemory(stored, userId: userId)
            let compacted = decrypted.compacted()
            memoryCache[userId] = compacted

            if compacted.facts.count != decrypted.facts.count || NovaMemoryCrypto.memoryNeedsEncryptionMigration(stored) {
                try? await persistEncrypted(compacted, userId: userId)
            }
            return compacted
        } catch {
            LogConfig.log("NovaMemoryStore load error: \(error.localizedDescription)", category: "Memory")
            return NovaMemory(userId: userId)
        }
    }

    func saveMemory(_ memory: NovaMemory) async throws {
        try await persistEncrypted(memory, userId: memory.userId)
        memoryCache[memory.userId] = memory
    }

    func invalidateCache(userId: String) {
        memoryCache.removeValue(forKey: userId)
    }

    func memory(for userId: String) -> NovaMemory? {
        memoryCache[userId]
    }

    private func persistEncrypted(_ memory: NovaMemory, userId: String) async throws {
        let encrypted = await NovaMemoryCrypto.encryptMemory(memory, userId: userId)
        try await memoryDocument(for: userId).setData(encrypted.dictionary, merge: true)
    }
}
