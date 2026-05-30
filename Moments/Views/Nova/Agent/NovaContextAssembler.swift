import Foundation

enum NovaContextAssembler {
    static func systemInstruction(
        username: String,
        memory: NovaMemory?,
        context: NovaUserContext?,
        internalHistorySummary: String? = nil
    ) -> String {
        var blocks = [
            NovaPromptCatalog.systemInstruction,
            NovaPromptCatalog.sessionContext(
                username: username,
                preferredName: memory?.preferredName,
                appLocale: NovaLocaleContext.appLocaleIdentifier
            )
        ]

        if let factsBlock = memoryFactsBlock(memory) {
            blocks.append(factsBlock)
        }
        if let summariesBlock = conversationSummariesBlock(context) {
            blocks.append(summariesBlock)
        }
        if let internalHistoryBlock = NovaPromptCatalog.internalHistoryContext(internalHistorySummary) {
            blocks.append(internalHistoryBlock)
        }

        return blocks.joined(separator: "\n\n")
    }

    private static func memoryFactsBlock(_ memory: NovaMemory?) -> String? {
        guard let memory, !memory.facts.isEmpty else { return nil }
        let top = memory.facts
            .sorted { $0.relevanceScore > $1.relevanceScore }
            .prefix(10)
        let lines = top.map { "- [\($0.type.rawValue)] \($0.content)" }
        return """
        Known facts about this user (already in context — do not call remember_fact or update_user_preference for duplicates):
        \(lines.joined(separator: "\n"))
        """
    }

    private static func conversationSummariesBlock(_ context: NovaUserContext?) -> String? {
        guard let context, !context.conversationSummaries.isEmpty else { return nil }
        let lines = context.conversationSummaries
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(5)
            .map { "- \($0.summary)" }
        return """
        Recent summaries from past Nova chats:
        \(lines.joined(separator: "\n"))
        """
    }
}
