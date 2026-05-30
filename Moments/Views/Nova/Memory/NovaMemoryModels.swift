import Foundation
import FirebaseFirestore

enum NovaFactType: String, CaseIterable, Codable {
    case preference
    case personal
    case professional
    case interest
    case general

    var priority: Int {
        switch self {
        case .preference: return 5
        case .personal: return 4
        case .professional: return 3
        case .interest: return 2
        case .general: return 1
        }
    }

    var emoji: String {
        switch self {
        case .preference: return "⚙️"
        case .personal: return "👤"
        case .professional: return "💼"
        case .interest: return "❤️"
        case .general: return "💭"
        }
    }
}

struct NovaFact: Identifiable, Codable {
    let id: String
    let content: String
    let type: NovaFactType
    let timestamp: Date
    let importance: Int
    var lastVerified: Date
    var embedding: [Double]?

    init(
        id: String = UUID().uuidString,
        content: String,
        type: NovaFactType,
        timestamp: Date = Date(),
        importance: Int = 3,
        lastVerified: Date = Date(),
        embedding: [Double]? = nil
    ) {
        self.id = id
        self.content = content
        self.type = type
        self.timestamp = timestamp
        self.importance = max(1, min(5, importance))
        self.lastVerified = lastVerified
        self.embedding = embedding
    }

    var dictionary: [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "content": content,
            "type": type.rawValue,
            "timestamp": Timestamp(date: timestamp),
            "importance": importance,
            "lastVerified": Timestamp(date: lastVerified),
            "lastProbedAt": NSNull()
        ]
        if let embedding {
            dict["embedding"] = embedding
        }
        return dict
    }

    init?(dictionary: [String: Any]) {
        guard let id = dictionary["id"] as? String,
              let content = dictionary["content"] as? String,
              let typeString = dictionary["type"] as? String,
              let type = NovaFactType(rawValue: typeString),
              let timestamp = (dictionary["timestamp"] as? Timestamp)?.dateValue() else {
            return nil
        }

        self.id = id
        self.content = content
        self.type = type
        self.timestamp = timestamp
        self.importance = dictionary["importance"] as? Int ?? 3
        self.lastVerified = (dictionary["lastVerified"] as? Timestamp)?.dateValue() ?? timestamp
        self.embedding = dictionary["embedding"] as? [Double]
    }

    var relevanceScore: Int {
        (type.priority * 10) + importance
    }

    var normalizedContent: String {
        content.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct NovaMemory: Identifiable {
    let id: String
    let userId: String
    var facts: [NovaFact]
    var lastUpdated: Date
    let createdAt: Date

    init(
        id: String = UUID().uuidString,
        userId: String,
        facts: [NovaFact] = [],
        lastUpdated: Date = Date(),
        createdAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.facts = facts
        self.lastUpdated = lastUpdated
        self.createdAt = createdAt
    }

    init(userId: String) {
        self.init(id: UUID().uuidString, userId: userId)
    }

    var dictionary: [String: Any] {
        [
            "id": id,
            "userId": userId,
            "facts": facts.map { $0.dictionary },
            "lastUpdated": Timestamp(date: lastUpdated),
            "createdAt": Timestamp(date: createdAt)
        ]
    }

    init?(dictionary: [String: Any]) {
        guard let id = dictionary["id"] as? String,
              let userId = dictionary["userId"] as? String,
              let factsData = dictionary["facts"] as? [[String: Any]],
              let createdTimestamp = dictionary["createdAt"] as? Timestamp,
              let lastUpdatedTimestamp = dictionary["lastUpdated"] as? Timestamp else {
            return nil
        }

        self.id = id
        self.userId = userId
        self.facts = factsData.compactMap { NovaFact(dictionary: $0) }
        self.createdAt = createdTimestamp.dateValue()
        self.lastUpdated = lastUpdatedTimestamp.dateValue()
    }

    var preferredName: String? {
        let namePreferences = facts.filter { $0.type == .preference }
        let mostRecent = namePreferences.sorted { $0.timestamp > $1.timestamp }.first
        return NovaMemory.extractName(from: mostRecent?.content)
    }

    static func extractName(from preference: String?) -> String? {
        guard let preference else { return nil }
        let trimmed = preference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let separators = [":", " - ", " — "]
        for separator in separators {
            if let range = trimmed.range(of: separator) {
                let candidate = String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !candidate.isEmpty { return candidate }
            }
        }

        let words = trimmed.split(separator: " ")
        if words.count <= 3 { return trimmed }
        return words.suffix(2).joined(separator: " ")
    }

    func addingFacts(_ newFacts: [NovaFact]) -> NovaMemory {
        upsertingFacts(newFacts)
    }

    /// Merge new facts, replacing duplicates by normalized content.
    func upsertingFacts(_ newFacts: [NovaFact]) -> NovaMemory {
        var merged = facts

        for var incoming in newFacts {
            incoming = Self.normalizedFact(incoming)

            if Self.isPreferredNameFact(incoming) {
                merged.removeAll { Self.isPreferredNameFact($0) }
            }

            merged.removeAll { $0.normalizedContent == incoming.normalizedContent }
            merged.append(incoming)
        }

        let capped = merged
            .sorted { $0.relevanceScore > $1.relevanceScore }
            .prefix(20)

        return NovaMemory(
            id: id,
            userId: userId,
            facts: Array(capped),
            lastUpdated: Date(),
            createdAt: createdAt
        )
    }

    private static func normalizedFact(_ fact: NovaFact) -> NovaFact {
        if let name = extractPreferredName(from: fact.content) {
            return NovaFact(content: "Preferred name: \(name)", type: .preference, importance: 5)
        }
        return fact
    }

    private static func isPreferredNameFact(_ fact: NovaFact) -> Bool {
        let lower = fact.normalizedContent
        return lower.hasPrefix("preferred name:") || lower.hasPrefix("call me ")
    }

    private static func extractPreferredName(from content: String) -> String? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        let colonPrefixes = ["preferred name:", "nombre preferido:", "nombre:"]
        for prefix in colonPrefixes where lower.hasPrefix(prefix) {
            let name = trimmed.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { return String(name) }
        }

        let phrasePrefixes = ["call me ", "me llamo ", "my name is ", "i'm ", "soy "]
        for prefix in phrasePrefixes where lower.hasPrefix(prefix) {
            let name = trimmed.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty, name.split(separator: " ").count <= 3 { return String(name) }
        }

        return nil
    }

    /// Deduplicate existing stored facts (e.g. on load).
    func compacted() -> NovaMemory {
        guard facts.count > 1 else { return self }
        var working = NovaMemory(id: id, userId: userId, facts: [], createdAt: createdAt)
        for fact in facts.sorted(by: { $0.timestamp < $1.timestamp }) {
            working = working.upsertingFacts([fact])
        }
        return NovaMemory(
            id: id,
            userId: userId,
            facts: working.facts,
            lastUpdated: Date(),
            createdAt: createdAt
        )
    }

    func removingFact(withId id: String) -> NovaMemory {
        NovaMemory(
            id: self.id,
            userId: userId,
            facts: facts.filter { $0.id != id },
            lastUpdated: Date(),
            createdAt: createdAt
        )
    }

    func updatingFact(withId id: String, content: String? = nil, importance: Int? = nil) -> NovaMemory {
        let updatedFacts = facts.map { fact -> NovaFact in
            guard fact.id == id else { return fact }
            let resolvedContent = content ?? fact.content
            return NovaFact(
                id: fact.id,
                content: resolvedContent,
                type: fact.type,
                timestamp: fact.timestamp,
                importance: importance ?? fact.importance,
                lastVerified: Date(),
                embedding: resolvedContent == fact.content ? fact.embedding : nil
            )
        }
        return NovaMemory(
            id: self.id,
            userId: userId,
            facts: updatedFacts,
            lastUpdated: Date(),
            createdAt: createdAt
        )
    }

    func clearingFacts() -> NovaMemory {
        NovaMemory(id: id, userId: userId, facts: [], lastUpdated: Date(), createdAt: createdAt)
    }
}

private extension Array where Element == NovaFact {
    func removingDuplicatesByContent() -> [NovaFact] {
        var seen = Set<String>()
        return filter { fact in
            let key = fact.normalizedContent
            guard !key.isEmpty, !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }
}
