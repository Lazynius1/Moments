import Foundation
import FirebaseFirestore

struct NovaConversationSummary: Identifiable, Codable, Equatable {
    let id: String
    let conversationId: String?
    let summary: String
    let createdAt: Date

    init(id: String = UUID().uuidString, conversationId: String?, summary: String, createdAt: Date = Date()) {
        self.id = id
        self.conversationId = conversationId
        self.summary = summary
        self.createdAt = createdAt
    }

    var dictionary: [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "summary": summary,
            "createdAt": Timestamp(date: createdAt)
        ]
        if let conversationId {
            dict["conversationId"] = conversationId
        }
        return dict
    }

    init?(dictionary: [String: Any]) {
        guard let id = dictionary["id"] as? String,
              let summary = dictionary["summary"] as? String,
              let createdAt = (dictionary["createdAt"] as? Timestamp)?.dateValue() else {
            return nil
        }
        self.id = id
        self.conversationId = dictionary["conversationId"] as? String
        self.summary = summary
        self.createdAt = createdAt
    }
}

struct NovaUserContext: Equatable {
    let userId: String
    var conversationSummaries: [NovaConversationSummary]

    static let maxSummaries = 5

    init(userId: String, conversationSummaries: [NovaConversationSummary] = []) {
        self.userId = userId
        self.conversationSummaries = conversationSummaries
    }

    var dictionary: [String: Any] {
        [
            "userId": userId,
            "conversationSummaries": conversationSummaries.map { $0.dictionary }
        ]
    }

    init?(dictionary: [String: Any]) {
        guard let userId = dictionary["userId"] as? String else { return nil }
        let raw = dictionary["conversationSummaries"] as? [[String: Any]] ?? []
        self.userId = userId
        self.conversationSummaries = raw.compactMap { NovaConversationSummary(dictionary: $0) }
    }

    func addingSummary(_ summary: NovaConversationSummary) -> NovaUserContext {
        let filtered = conversationSummaries.filter { existing in
            if let conversationId = summary.conversationId, existing.conversationId == conversationId {
                return false
            }
            return existing.summary != summary.summary
        }

        var next = ([summary] + filtered)
            .sorted { $0.createdAt > $1.createdAt }
        next = Array(next.prefix(Self.maxSummaries))
        return NovaUserContext(userId: userId, conversationSummaries: next)
    }
}

@MainActor
final class NovaContextStore: ObservableObject {
    static let shared = NovaContextStore()

    private let db = Firestore.firestore()
    private var cache: [String: NovaUserContext] = [:]

    private init() {}

    private func contextDocument(for userId: String) -> DocumentReference {
        db.collection("users").document(userId).collection("novaMemory").document("context")
    }

    func loadContext(userId: String) async -> NovaUserContext {
        if let cached = cache[userId] { return cached }

        do {
            let snapshot = try await contextDocument(for: userId).getDocument()
            if snapshot.exists, let data = snapshot.data(), let stored = NovaUserContext(dictionary: data) {
                let decrypted = await NovaMemoryCrypto.decryptContext(stored, userId: userId)
                cache[userId] = decrypted
                if NovaMemoryCrypto.contextNeedsEncryptionMigration(stored) {
                    try? await persistEncrypted(decrypted, userId: userId)
                }
                return decrypted
            }
        } catch {
            LogConfig.log("NovaContextStore load error: \(error.localizedDescription)", category: "Memory")
        }

        let empty = NovaUserContext(userId: userId)
        cache[userId] = empty
        return empty
    }

    func saveContext(_ context: NovaUserContext) async throws {
        try await persistEncrypted(context, userId: context.userId)
        cache[context.userId] = context
    }

    func invalidateCache(userId: String) {
        cache.removeValue(forKey: userId)
    }

    func clearContext(userId: String) async throws {
        let empty = NovaUserContext(userId: userId)
        try await persistEncrypted(empty, userId: userId)
        cache[userId] = empty
    }

    private func persistEncrypted(_ context: NovaUserContext, userId: String) async throws {
        let encrypted = await NovaMemoryCrypto.encryptContext(context, userId: userId)
        try await contextDocument(for: userId).setData(encrypted.dictionary, merge: true)
    }
}
