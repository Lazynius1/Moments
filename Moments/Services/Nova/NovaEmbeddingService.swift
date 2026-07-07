import Foundation
import NaturalLanguage

// Embeddings on-device para dedup semántico y búsqueda de hechos de memoria.
final class NovaEmbeddingService {
    static let shared = NovaEmbeddingService()

    private var embeddingModel: NLEmbedding?
    private let modelQueue = DispatchQueue(label: "com.glowsy.embedding.model", qos: .userInitiated)

    private init() {
        modelQueue.async { [weak self] in
            self?.loadModelLocked()
        }
    }

    private func loadModelLocked() {
        guard embeddingModel == nil else { return }

        for language in Self.preferredEmbeddingLanguages() {
            if let model = NLEmbedding.sentenceEmbedding(for: language) {
                embeddingModel = model
                LogConfig.log("NovaEmbeddingService: modelo cargado (\(language.rawValue))", category: "Nova")
                return
            }
        }
        LogConfig.log("NovaEmbeddingService: sin modelo de embeddings disponible", category: "Nova")
    }

    private static func preferredEmbeddingLanguages() -> [NLLanguage] {
        let code = Locale.preferredLanguages.first
            .flatMap { Locale(identifier: $0).language.languageCode?.identifier } ?? "en"

        let primary: NLLanguage
        switch code {
        case "es", "ca": primary = .spanish
        case "de": primary = .german
        case "fr": primary = .french
        case "it": primary = .italian
        case "pt": primary = .portuguese
        default: primary = .english
        }
        return primary == .english ? [.english] : [primary, .english]
    }

    private func loadedModel() -> NLEmbedding? {
        if let embeddingModel { return embeddingModel }
        modelQueue.sync {
            loadModelLocked()
        }
        return embeddingModel
    }

    func generateEmbedding(for text: String) -> [Double]? {
        guard let model = loadedModel() else { return nil }

        let cleanText = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return nil }

        return model.vector(for: cleanText)
    }

    func findSimilarFacts(query: String, facts: [NovaFact], limit: Int = 5) -> [NovaFact] {
        guard let queryVector = generateEmbedding(for: query) else { return [] }

        let threshold = 0.5
        let scoredFacts = facts.compactMap { fact -> (NovaFact, Double)? in
            guard let factVector = fact.embedding ?? generateEmbedding(for: fact.content) else { return nil }
            let similarity = cosineSimilarity(queryVector, factVector)
            return (fact, similarity)
        }

        return scoredFacts
            .filter { $0.1 > threshold }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { $0.0 }
    }

    /// True when candidate is semantically redundant with any existing fact.
    func isNearDuplicate(_ candidate: NovaFact, existing: [NovaFact], threshold: Double = 0.82) -> Bool {
        let candidateKey = candidate.normalizedContent
        for fact in existing {
            if fact.normalizedContent == candidateKey { return true }
        }

        guard let candidateVector = candidate.embedding ?? generateEmbedding(for: candidate.content) else {
            return false
        }

        for fact in existing {
            guard let factVector = fact.embedding ?? generateEmbedding(for: fact.content) else { continue }
            if cosineSimilarity(candidateVector, factVector) >= threshold {
                return true
            }
        }
        return false
    }

    func cosineSimilarity(_ v1: [Double], _ v2: [Double]) -> Double {
        guard v1.count == v2.count else { return 0.0 }

        var dotProduct = 0.0
        var normA = 0.0
        var normB = 0.0

        for i in 0..<v1.count {
            dotProduct += v1[i] * v2[i]
            normA += v1[i] * v1[i]
            normB += v2[i] * v2[i]
        }

        if normA == 0 || normB == 0 { return 0.0 }

        return dotProduct / (sqrt(normA) * sqrt(normB))
    }
}
