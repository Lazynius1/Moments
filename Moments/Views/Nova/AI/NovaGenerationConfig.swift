import FirebaseAI

enum NovaGenerationConfig {
    static let modelName = "gemini-3.1-flash-lite"
    static let location = "global"

    static var chat: GenerationConfig {
        GenerationConfig(
            temperature: 0.7,
            topP: 0.95,
            topK: 40,
            maxOutputTokens: 2048,
            thinkingConfig: ThinkingConfig(thinkingBudget: 512)
        )
    }

    static var structuredJSON: GenerationConfig {
        GenerationConfig(
            temperature: 0.2,
            maxOutputTokens: 1024,
            responseMIMEType: "application/json",
            thinkingConfig: ThinkingConfig(thinkingBudget: 0)
        )
    }

    static var titleGeneration: GenerationConfig {
        GenerationConfig(
            temperature: 0.3,
            maxOutputTokens: 32,
            thinkingConfig: ThinkingConfig(thinkingBudget: 0)
        )
    }

    static let safetySettings: [SafetySetting] = [
        SafetySetting(harmCategory: .harassment, threshold: .blockMediumAndAbove),
        SafetySetting(harmCategory: .hateSpeech, threshold: .blockMediumAndAbove),
        SafetySetting(harmCategory: .sexuallyExplicit, threshold: .blockMediumAndAbove),
        SafetySetting(harmCategory: .dangerousContent, threshold: .blockMediumAndAbove)
    ]
}
