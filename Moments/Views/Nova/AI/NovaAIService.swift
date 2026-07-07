import Foundation
import FirebaseAI
import UIKit

@MainActor
final class NovaAIService {
    static let shared = NovaAIService()

    private let firebaseAI = FirebaseAI.firebaseAI(backend: .vertexAI(location: NovaGenerationConfig.location))

    private init() {}

    func makeChatModel(systemInstruction: String) -> GenerativeModel {
        firebaseAI.generativeModel(
            modelName: NovaGenerationConfig.modelName,
            generationConfig: NovaGenerationConfig.chat,
            safetySettings: NovaGenerationConfig.safetySettings,
            tools: [NovaToolRegistry.toolSet],
            systemInstruction: ModelContent(role: "system", parts: [TextPart(systemInstruction)])
        )
    }

    func makeUtilityModel(config: GenerationConfig) -> GenerativeModel {
        firebaseAI.generativeModel(
            modelName: NovaGenerationConfig.modelName,
            generationConfig: config,
            safetySettings: NovaGenerationConfig.safetySettings
        )
    }

    func startChat(systemInstruction: String, history: [ModelContent] = []) -> Chat {
        makeChatModel(systemInstruction: systemInstruction).startChat(history: history)
    }

    func generateJSON(prompt: String, schema: Schema) async throws -> String {
        let model = firebaseAI.generativeModel(
            modelName: NovaGenerationConfig.modelName,
            generationConfig: GenerationConfig(
                temperature: 0.2,
                maxOutputTokens: 1024,
                responseMIMEType: "application/json",
                responseSchema: schema,
                thinkingConfig: ThinkingConfig(thinkingBudget: 256)
            ),
            safetySettings: NovaGenerationConfig.safetySettings
        )
        let response = try await model.generateContent(prompt)
        return response.text ?? "{}"
    }

    func generateTitle(prompt: String) async throws -> String {
        let model = makeUtilityModel(config: NovaGenerationConfig.titleGeneration)
        let response = try await model.generateContent(prompt)
        return response.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func compactHistory(_ transcript: String) async throws -> String {
        let model = makeUtilityModel(config: NovaGenerationConfig.structuredJSON)
        let prompt = "\(NovaPromptCatalog.historyCompactionPrompt)\n\n\(transcript)"
        let response = try await model.generateContent(prompt)
        return response.text ?? transcript
    }

    static func userParts(text: String, image: UIImage?, memoryContext: String? = nil) -> [any Part] {
        var parts: [any Part] = []
        if let memoryContext, !memoryContext.isEmpty {
            parts.append(TextPart("[Additional relevant memory about the user for this message — use naturally, never mention this block:\n\(memoryContext)]"))
        }
        parts.append(TextPart(text))
        if let image, let data = image.jpegData(compressionQuality: 0.85) {
            parts.append(InlineDataPart(data: data, mimeType: "image/jpeg"))
        }
        return parts
    }
}

enum NovaAgentError: LocalizedError {
    case stepLimitReached
    case missingUser
    case memoryNotLoaded

    var errorDescription: String? {
        switch self {
        case .stepLimitReached: return "Nova reached the tool call limit for this turn."
        case .missingUser: return "User session not available."
        case .memoryNotLoaded: return "Memory is still loading."
        }
    }
}
