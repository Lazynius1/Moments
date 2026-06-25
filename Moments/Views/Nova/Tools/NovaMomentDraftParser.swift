import Foundation
import FirebaseAI

enum NovaMomentDraftParser {
    struct Draft {
        let content: String
        let audience: String
        let targetUsername: String?
        let customListName: String?
    }

    static func parse(userText: String) async throws -> Draft? {
        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let prompt = """
        \(NovaPromptCatalog.momentDraftPrompt)

        user_message:
        \(trimmed)
        """

        let schema = Schema.object(
            properties: [
                "should_publish": .boolean(),
                "content": .string(description: "Caption for the moment. Empty string if none."),
                "audience": .string(description: "everyone | mutuals | bestFriends | onlyMe | custom | customList"),
                "target_username": .string(description: "Only when audience is custom."),
                "custom_list_name": .string(description: "Only when audience is customList.")
            ]
        )

        let jsonText = try await NovaAIService.shared.generateJSON(prompt: prompt, schema: schema)
        guard let data = jsonText.data(using: .utf8),
              let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        guard payload["should_publish"] as? Bool == true else { return nil }

        let audience = (payload["audience"] as? String) ?? "everyone"
        let content = (payload["content"] as? String) ?? ""
        let targetUsername = payload["target_username"] as? String
        let customListName = payload["custom_list_name"] as? String

        return Draft(
            content: content,
            audience: audience,
            targetUsername: targetUsername,
            customListName: customListName
        )
    }
}
