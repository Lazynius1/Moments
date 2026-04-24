import Foundation
import NaturalLanguage

// MARK: - 🔍 SERVICIO DE EMBEDDINGS (RAG)
// Genera vectores semánticos y busca hechos relevantes
class NovaEmbeddingService {
    static let shared = NovaEmbeddingService()

    // Cache del embedding model para evitar recargarlo
    private var embeddingModel: NLEmbedding?
    private var isModelLoading = false
    private var modelLoadCompletion: [() -> Void] = []
    private let modelQueue = DispatchQueue(label: "com.glowsy.embedding.model", qos: .userInitiated)

    private init() {
        // Cargar modelo en background para no bloquear UI
        loadModelAsync()
    }

    private func loadModelAsync() {
        modelQueue.async { [weak self] in
            guard let self = self else { return }
            self.isModelLoading = true
            if let model = NLEmbedding.sentenceEmbedding(for: .spanish) {
                self.embeddingModel = model
                print("✅ NovaEmbeddingService: Modelo en ESPAÑOL cargado (async).")
            } else if let model = NLEmbedding.sentenceEmbedding(for: .english) {
                self.embeddingModel = model
                print("⚠️ NovaEmbeddingService: Modelo en ESPAÑOL no disponible. Usando INGLÉS.")
            } else {
                print("🚨 NovaEmbeddingService: No se pudo cargar ningún modelo de embedding.")
            }
            self.isModelLoading = false
        }
    }

    private func ensureModelLoaded() {
        guard embeddingModel == nil else { return }

        modelQueue.sync {
            guard self.embeddingModel == nil else { return }

            if let model = NLEmbedding.sentenceEmbedding(for: .spanish) {
                self.embeddingModel = model
                print("✅ NovaEmbeddingService: Modelo en ESPAÑOL cargado (sync fallback).")
            } else if let model = NLEmbedding.sentenceEmbedding(for: .english) {
                self.embeddingModel = model
                print("⚠️ NovaEmbeddingService: Modelo en ESPAÑOL no disponible. Usando INGLÉS (sync fallback).")
            } else {
                print("🚨 NovaEmbeddingService: No se pudo cargar ningún modelo de embedding (sync fallback).")
            }
        }
    }

    // MARK: - 🧬 Generación de Embeddings

    /// Genera un vector de 512 dimensiones para un texto dado
    func generateEmbedding(for text: String) -> [Double]? {
        if embeddingModel == nil {
            ensureModelLoaded()
        }
        guard let model = embeddingModel else { return nil }

        // Normalizar texto (opcional pero recomendado)
        let cleanText = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return nil }

        return model.vector(for: cleanText)
    }

    // MARK: - 🔎 Búsqueda Semántica

    /// Encuentra los hechos más similares a una query
    func findSimilarFacts(query: String, facts: [NovaFact], limit: Int = 5) -> [NovaFact] {
        guard let queryVector = generateEmbedding(for: query) else {
            print("⚠️ NovaEmbeddingService: No se pudo, generar embedding para query.")
            return []
        }

        // Calcular similitud coseno para cada hecho que tenga embedding
        let scoredFacts = facts.compactMap { fact -> (NovaFact, Double)? in
            guard let factVector = fact.embedding else { return nil }
            let similarity = cosineSimilarity(queryVector, factVector)
            return (fact, similarity)
        }

        // Ordenar por similitud descendente y tomar los top N
        // Umbral mínimo de 0.6 para evitar ruido irrelevante
        let threshold = 0.5
        let topFacts = scoredFacts
            .filter { $0.1 > threshold }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { $0.0 }

        return Array(topFacts)
    }

    // MARK: - 🧮 Matemáticas Vectoriales

    /// Calcula la similitud coseno entre dos vectores
    private func cosineSimilarity(_ v1: [Double], _ v2: [Double]) -> Double {
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
