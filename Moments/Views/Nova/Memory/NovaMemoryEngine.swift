import Foundation
import FirebaseAI

/// Post-conversation memory: extract new facts + rolling chat summary (ChatGPT-style).
actor NovaMemoryEngine {
    static let shared = NovaMemoryEngine()

    private var inFlightKeys = Set<String>()

    private init() {}

    nonisolated func scheduleConversationFinalize(
        userId: String,
        conversationId: String?,
        messages: [ChatMessage]
    ) {
        Task {
            await self.finalizeConversation(
                userId: userId,
                conversationId: conversationId,
                messages: messages
            )
        }
    }

    func finalizeConversation(
        userId: String,
        conversationId: String?,
        messages: [ChatMessage]
    ) async {
        let memoryStore = await MainActor.run { NovaMemoryStore.shared }
        let contextStore = await MainActor.run { NovaContextStore.shared }
        let ai = await MainActor.run { NovaAIService.shared }

        let meaningful = messages.filter { !$0.isSystem && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard meaningful.contains(where: \.isUser),
              meaningful.contains(where: { !$0.isUser }) else {
            return
        }

        let key = "\(conversationId ?? "draft")-\(meaningful.count)-\(meaningful.last?.id.uuidString ?? "")"
        guard !inFlightKeys.contains(key) else { return }
        inFlightKeys.insert(key)
        defer { inFlightKeys.remove(key) }

        var memory = await memoryStore.loadMemory(userId: userId) ?? NovaMemory(userId: userId)
        let context = await contextStore.loadContext(userId: userId)
        let existingFacts = memory.facts

        let transcript = meaningful
            .map { "\($0.isUser ? "User" : "Nova"): \($0.text.prefix(800))" }
            .joined(separator: "\n")

        let existingList = existingFacts
            .map { "- [\($0.type.rawValue)] \($0.content)" }
            .joined(separator: "\n")

        let prompt = """
        \(NovaPromptCatalog.conversationFinalizePrompt)

        existing_facts:
        \(existingList.isEmpty ? "none" : existingList)

        transcript:
        \(transcript.prefix(6000))
        """

        let schema = Schema.object(
            properties: [
                "facts_to_add": .array(
                    items: .object(
                        properties: [
                            "content": .string(),
                            "type": .string(description: "preference|personal|professional|interest|general")
                        ]
                    )
                ),
                "conversation_summary": .string()
            ]
        )

        do {
            let jsonText = try await ai.generateJSON(prompt: prompt, schema: schema)
            guard let data = jsonText.data(using: .utf8),
                  let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }

            let rawFacts = payload["facts_to_add"] as? [[String: Any]] ?? []
            let extractedFacts: [NovaFact] = rawFacts.compactMap { item in
                guard let content = item["content"] as? String else { return nil }
                let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.count >= 3 else { return nil }
                let typeRaw = (item["type"] as? String) ?? "general"
                let type = NovaFactType(rawValue: typeRaw) ?? .general
                return NovaFact(content: trimmed, type: type)
            }

            let newFacts = sanitizeExtractedFacts(
                extractedFacts,
                existingFacts: existingFacts,
                transcript: transcript
            )

            if !newFacts.isEmpty {
                memory = memory.upsertingFacts(newFacts)
                try await memoryStore.saveMemory(memory)
            }

            if let summaryRaw = payload["conversation_summary"] as? String {
                let summary = summaryRaw.trimmingCharacters(in: .whitespacesAndNewlines)
                if summary.count >= 20 {
                    let entry = NovaConversationSummary(
                        conversationId: conversationId,
                        summary: summary
                    )
                    let updatedContext = context.addingSummary(entry)
                    try await contextStore.saveContext(updatedContext)
                }
            }

            await MainActor.run {
                NotificationCenter.default.post(name: .novaMemoryDidUpdate, object: userId)
            }
        } catch {
            LogConfig.log("NovaMemoryEngine finalize failed: \(error.localizedDescription)", category: "Memory")
        }
    }

    private func sanitizeExtractedFacts(
        _ facts: [NovaFact],
        existingFacts: [NovaFact],
        transcript: String
    ) -> [NovaFact] {
        let existing = Set(existingFacts.map(\.normalizedContent))
        var seen = Set<String>()

        return facts.compactMap { fact in
            let trimmed = fact.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let normalized = normalizedDurableContent(trimmed, type: fact.type, transcript: transcript) else {
                return nil
            }

            let normalizedKey = normalized.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !existing.contains(normalizedKey), !seen.contains(normalizedKey) else {
                return nil
            }
            seen.insert(normalizedKey)

            let resolvedType = refinedFactType(for: normalized, originalType: fact.type)
            let importance = inferredImportance(for: normalized, type: resolvedType)
            return NovaFact(content: normalized, type: resolvedType, importance: importance)
        }
    }

    private func normalizedDurableContent(_ content: String, type: NovaFactType, transcript: String) -> String? {
        let trimmed = content
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3, trimmed.count <= 180 else { return nil }

        let lower = trimmed.lowercased()
        let transientFragments = [
            "today", "tomorrow", "right now", "this morning", "this afternoon", "this evening",
            "hoy", "mañana", "ahora mismo", "esta mañana", "esta tarde", "esta noche",
            "failed", "cancelled", "canceled", "publish attempt", "intent to post", "draft caption",
            "acción fallida", "falló", "cancelado", "cancelada", "intento de publicar"
        ]
        if transientFragments.contains(where: { lower.contains($0) }) { return nil }
        if lower.hasPrefix("user asked") || lower.hasPrefix("the user asked") || lower.hasPrefix("nova:") {
            return nil
        }
        if trimmed.contains("?") { return nil }

        let sensitivePatterns = [
            #"\b\d{3}[-.\s]?\d{2,4}[-.\s]?\d{3,4}\b"#,
            #"[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}"#,
            #"\b\d{1,4}\s+\w+\s+(street|st|avenue|ave|road|rd|calle|plaza|paseo)\b"#
        ]
        if sensitivePatterns.contains(where: { lower.range(of: $0, options: [.regularExpression]) != nil }) {
            return nil
        }

        if lower.hasPrefix("preferred name:") {
            let value = String(trimmed.dropFirst("preferred name:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : "Preferred name: \(value)"
        }

        let pronounPrefixes = ["pronouns:", "my pronouns are ", "pronombres:", "mis pronombres son "]
        for prefix in pronounPrefixes where lower.hasPrefix(prefix) {
            let value = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return nil }
            return "Pronouns: \(value)"
        }

        if type == .general, looksLikeWeakGeneralFact(lower) {
            return nil
        }

        return trimmed
    }

    private func refinedFactType(for content: String, originalType: NovaFactType) -> NovaFactType {
        let lower = content.lowercased()
        if lower.hasPrefix("preferred name:") || lower.hasPrefix("pronouns:") {
            return .preference
        }
        if lower.contains("privacy") || lower.contains("profile") || lower.contains("posting") || lower.contains("stories") || lower.contains("moments") {
            return .preference
        }
        if lower.contains("goal") || lower.contains("studying") || lower.contains("working") || lower.contains("career") || lower.contains("exam") {
            return .professional
        }
        if lower.contains("partner") || lower.contains("girlfriend") || lower.contains("boyfriend") || lower.contains("family") || lower.contains("friend") {
            return .personal
        }
        return originalType
    }

    private func inferredImportance(for content: String, type: NovaFactType) -> Int {
        let lower = content.lowercased()
        if lower.hasPrefix("preferred name:") || lower.hasPrefix("pronouns:") {
            return 5
        }
        if lower.contains("privacy") || lower.contains("profile") || lower.contains("posting preference") || lower.contains("moments") {
            return 5
        }
        if lower.contains("goal") || lower.contains("important") || lower.contains("always") || lower.contains("never") {
            return 4
        }
        return max(3, type.priority)
    }

    private func looksLikeWeakGeneralFact(_ lower: String) -> Bool {
        let weakPrefixes = [
            "likes ", "wants ", "asked about ", "talked about ", "mentioned ", "is feeling ", "felt ",
            "le gusta ", "quiere ", "preguntó por ", "habló de ", "mencionó ", "se siente "
        ]
        return weakPrefixes.contains(where: { lower.hasPrefix($0) })
    }
}

extension Foundation.Notification.Name {
    static let novaMemoryDidUpdate = Foundation.Notification.Name("NovaMemoryDidUpdate")
}
